// LlamaCppEngine.swift
// YapYap — Embedded llama.cpp inference engine via LlamaSwift (no external server)
import Foundation
import LlamaSwift

class LlamaCppEngine: LLMEngine {
    private var model: OpaquePointer?   // llama_model *
    private var context: OpaquePointer? // llama_context *
    private(set) var modelId: String?

    /// MLX model registry ID used for prompt selection. Maps the GGUF model
    /// to the corresponding MLX family/size tier so CleanupPromptBuilder
    /// generates identical prompts regardless of inference framework.
    var promptModelId: String?

    var isLoaded: Bool { model != nil && context != nil }

    // MARK: - LLMEngine Protocol

    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws {
        guard let modelInfo = GGUFModelRegistry.model(for: id) else {
            throw YapYapError.modelNotLoaded
        }

        NSLog("[LlamaCppEngine] Loading model '\(id)' from GGUF file: \(modelInfo.ggufFilename)")

        // Ensure GGUF models directory exists
        let ggufDir = GGUFModelRegistry.ggufModelsDir
        try? FileManager.default.createDirectory(at: ggufDir, withIntermediateDirectories: true)

        // Download if not present
        let localPath = GGUFModelRegistry.localPath(for: modelInfo)
        if !FileManager.default.fileExists(atPath: localPath.path) {
            NSLog("[LlamaCppEngine] GGUF file not found locally, downloading from \(modelInfo.downloadURL)")
            try await downloadGGUF(from: modelInfo.downloadURL, to: localPath, progressHandler: progressHandler)
        } else {
            NSLog("[LlamaCppEngine] GGUF file found locally at \(localPath.path)")
            progressHandler(1.0)
        }

        // Initialize llama.cpp backend (safe to call multiple times)
        llama_backend_init()

        // Load model from file
        var modelParams = llama_model_default_params()
        // Use GPU offloading on Apple Silicon (Metal)
        modelParams.n_gpu_layers = 99  // Offload all layers to GPU

        guard let loadedModel = llama_model_load_from_file(localPath.path, modelParams) else {
            throw LlamaCppError.modelLoadFailed(localPath.path)
        }

        // Create inference context
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 2048       // Context window sufficient for cleanup
        ctxParams.n_batch = 512      // Batch size for prompt processing
        ctxParams.n_threads = UInt32(max(1, ProcessInfo.processInfo.processorCount - 2))

        guard let ctx = llama_init_from_model(loadedModel, ctxParams) else {
            llama_model_free(loadedModel)
            throw LlamaCppError.contextCreationFailed
        }

        // Clean up previous model if any
        if let oldCtx = self.context { llama_free(oldCtx) }
        if let oldModel = self.model { llama_model_free(oldModel) }

        self.model = loadedModel
        self.context = ctx
        self.modelId = id

        NSLog("[LlamaCppEngine] Model '\(id)' loaded successfully (\(modelInfo.sizeDescription))")
    }

    func unloadModel() {
        if let ctx = context { llama_free(ctx) }
        if let mdl = model { llama_model_free(mdl) }
        context = nil
        model = nil
        modelId = nil
    }

    func warmup() async {
        guard let model = model, let context = context else { return }
        do {
            let startTime = Date()
            // Tokenize a minimal prompt and run one decode step
            let tokens = tokenize("Hello", addSpecial: true)
            guard !tokens.isEmpty else { return }

            let batch = llama_batch_get_one(UnsafeMutablePointer(mutating: tokens), Int32(tokens.count))
            llama_decode(context, batch)
            llama_kv_cache_clear(context)

            let elapsed = Date().timeIntervalSince(startTime) * 1000
            NSLog("[LlamaCppEngine] Keep-alive warmup complete (\(String(format: "%.0f", elapsed))ms)")
        }
    }

    func cleanup(rawText: String, context cleanupContext: CleanupContext) async throws -> String {
        guard let model = model, let context = context else {
            throw YapYapError.modelNotLoaded
        }

        // Build prompts using the same CleanupPromptBuilder as other engines.
        // Use promptModelId to select the correct family/size tier prompts.
        let userContext = UserPromptContextManager.shared.context(
            for: cleanupContext.appContext?.appName,
            transcript: rawText
        )
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: rawText, context: cleanupContext,
            modelId: promptModelId, userContext: userContext
        )

        NSLog("[LlamaCppEngine] System prompt (\(messages.system.count) chars), user prompt (\(messages.user.count) chars)")

        // Apply chat template via llama.cpp's built-in template support
        let prompt = applyChatTemplate(system: messages.system, user: messages.user)
        let tokens = tokenize(prompt, addSpecial: false)

        guard !tokens.isEmpty else {
            throw LlamaCppError.tokenizationFailed
        }

        // Cap output: cleanup output should be roughly the same length as input
        let userTokenCount = tokenize(rawText, addSpecial: false).count
        let maxOutputTokens = max(32, min(userTokenCount * 2, 512))

        NSLog("[LlamaCppEngine] Prompt: \(tokens.count) tokens, maxOutput: \(maxOutputTokens)")

        // Clear KV cache for fresh inference
        llama_kv_cache_clear(context)

        // Decode prompt (prefill)
        let startTime = Date()
        let batch = llama_batch_get_one(UnsafeMutablePointer(mutating: tokens), Int32(tokens.count))
        let decodeResult = llama_decode(context, batch)
        guard decodeResult == 0 else {
            throw LlamaCppError.decodeFailed(Int(decodeResult))
        }

        let prefillTime = Date()
        let prefillMs = prefillTime.timeIntervalSince(startTime) * 1000
        NSLog("[LlamaCppEngine] Prefill: \(String(format: "%.0f", prefillMs))ms (\(tokens.count) tokens)")

        // Set up sampler chain: greedy (temperature 0) for deterministic cleanup
        let samplerChainParams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(samplerChainParams) else {
            throw LlamaCppError.samplerInitFailed
        }
        defer { llama_sampler_free(sampler) }

        // Temperature 0 = greedy decoding (best for text cleanup)
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        // Generate tokens
        let eosToken = llama_vocab_eos(llama_model_get_vocab(model))
        var outputTokens: [llama_token] = []
        var outputText = ""

        for _ in 0..<maxOutputTokens {
            let newToken = llama_sampler_sample(sampler, context, -1)

            // Stop on EOS
            if newToken == eosToken { break }

            // Decode token to text
            let piece = tokenToPiece(newToken)
            outputText += piece

            // Check for stop sequences in the tail
            let stopSequences = ["<end_of_turn>", "<|im_end|>", "<|eot_id|>", "<|end|>", "</s>", "</output>"]
            var stopped = false
            for stop in stopSequences {
                if let range = outputText.range(of: stop) {
                    outputText = String(outputText[..<range.lowerBound])
                    stopped = true
                    break
                }
            }
            if stopped { break }

            outputTokens.append(newToken)

            // Prepare next token for decoding
            let nextBatch = llama_batch_get_one(&outputTokens[outputTokens.count - 1], 1)
            let nextResult = llama_decode(context, nextBatch)
            if nextResult != 0 { break }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let genMs = Date().timeIntervalSince(prefillTime) * 1000
        let tokPerSec = outputTokens.count > 0 ? Double(outputTokens.count) / (genMs / 1000) : 0
        NSLog("[LlamaCppEngine] Generation: \(outputTokens.count) tokens in \(String(format: "%.0f", genMs))ms (\(String(format: "%.0f", tokPerSec)) tok/s), total \(String(format: "%.1f", elapsed))s")

        let result = LLMOutputSanitizer.sanitize(outputText)
        NSLog("[LlamaCppEngine] Cleanup result (\(result.count) chars): \"\(String(result.prefix(80)))...\"")
        return result
    }

    // MARK: - Tokenization Helpers

    private func tokenize(_ text: String, addSpecial: Bool) -> [llama_token] {
        guard let model = model else { return [] }
        let vocab = llama_model_get_vocab(model)
        let utf8 = text.utf8CString
        let maxTokens = Int32(utf8.count + (addSpecial ? 1 : 0))

        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        let nTokens = utf8.withUnsafeBufferPointer { buf in
            llama_tokenize(vocab, buf.baseAddress, Int32(text.utf8.count), &tokens, maxTokens, addSpecial, true)
        }

        guard nTokens >= 0 else { return [] }
        return Array(tokens.prefix(Int(nTokens)))
    }

    private func tokenToPiece(_ token: llama_token) -> String {
        guard let model = model else { return "" }
        let vocab = llama_model_get_vocab(model)
        var buf = [CChar](repeating: 0, count: 256)
        let len = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
        guard len > 0 else { return "" }
        return String(cString: buf.prefix(Int(len)) + [0])
    }

    // MARK: - Chat Template

    /// Apply the model's built-in chat template, or fall back to ChatML format.
    private func applyChatTemplate(system: String, user: String) -> String {
        guard let model = model else { return user }

        // Build chat messages for llama_chat_apply_template
        var chatMessages: [llama_chat_message] = []

        // System message (if non-empty)
        if !system.isEmpty {
            let systemCStr = strdup(system)!
            let roleCStr = strdup("system")!
            chatMessages.append(llama_chat_message(role: roleCStr, content: systemCStr))
        }

        // User message
        let userCStr = strdup(user)!
        let userRoleCStr = strdup("user")!
        chatMessages.append(llama_chat_message(role: userRoleCStr, content: userCStr))

        defer {
            for msg in chatMessages {
                free(UnsafeMutablePointer(mutating: msg.role))
                free(UnsafeMutablePointer(mutating: msg.content))
            }
        }

        // Try applying the model's built-in template
        var buf = [CChar](repeating: 0, count: 8192)
        let result = chatMessages.withUnsafeBufferPointer { messagesPtr in
            llama_chat_apply_template(
                llama_model_get_template(model),
                messagesPtr.baseAddress,
                messagesPtr.count,
                true,  // add generation prompt
                &buf,
                Int32(buf.count)
            )
        }

        if result > 0 && result < buf.count {
            return String(cString: buf.prefix(Int(result)) + [0])
        }

        // Fallback: ChatML format (Qwen-compatible)
        NSLog("[LlamaCppEngine] Built-in template failed, using ChatML fallback")
        let systemBlock = system.isEmpty ? "" : "<|im_start|>system\n\(system)<|im_end|>\n"
        return "\(systemBlock)<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
    }

    // MARK: - GGUF Download

    private func downloadGGUF(from url: URL, to destination: URL, progressHandler: @escaping (Double) -> Void) async throws {
        let (tempURL, response) = try await URLSession.shared.download(from: url, delegate: DownloadProgressDelegate(handler: progressHandler))

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LlamaCppError.downloadFailed(url.absoluteString)
        }

        // Move downloaded file to destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        NSLog("[LlamaCppEngine] Downloaded GGUF to \(destination.path)")
    }
}

// MARK: - Download Progress Delegate

private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let handler: (Double) -> Void

    init(handler: @escaping (Double) -> Void) {
        self.handler = handler
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        // This delegate method is for uploads, not downloads.
        // Download progress is reported via URLSessionDownloadDelegate.
    }
}

// MARK: - Errors

enum LlamaCppError: LocalizedError {
    case modelLoadFailed(String)
    case contextCreationFailed
    case tokenizationFailed
    case decodeFailed(Int)
    case samplerInitFailed
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load GGUF model from \(path)"
        case .contextCreationFailed:
            return "Failed to create llama.cpp inference context"
        case .tokenizationFailed:
            return "Failed to tokenize input text"
        case .decodeFailed(let code):
            return "llama.cpp decode failed with code \(code)"
        case .samplerInitFailed:
            return "Failed to initialize llama.cpp sampler"
        case .downloadFailed(let url):
            return "Failed to download GGUF model from \(url)"
        }
    }
}
