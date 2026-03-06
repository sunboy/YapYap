// LlamaCppEngine.swift
// YapYap — Embedded llama.cpp inference engine via LlamaSwift (no external server)
import Foundation
import LlamaSwift

class LlamaCppEngine: LLMEngine {
    private var model: OpaquePointer?   // llama_model *
    private var context: OpaquePointer? // llama_context *
    /// Serializes all llama_decode / llama_memory_clear calls.
    /// The keep-alive timer can fire warmup() concurrently with cleanup(),
    /// and llama.cpp contexts are not thread-safe — concurrent decode calls
    /// corrupt the KV cache and trigger ggml_abort.
    private let inferenceLock = NSLock()
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
        ctxParams.n_batch = 2048     // Must match n_ctx so full prompts can decode in one call
        ctxParams.n_threads = Int32(max(1, ProcessInfo.processInfo.processorCount - 2))

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
        guard model != nil, let context = context else { return }
        let startTime = Date()
        // Tokenize a minimal prompt and run one decode step
        let tokens = tokenize("Hello", addSpecial: true)
        guard !tokens.isEmpty else { return }

        // Skip warmup if cleanup is already running — warmup is best-effort
        guard inferenceLock.try() else {
            NSLog("[LlamaCppEngine] Warmup skipped — inference in progress")
            return
        }
        defer { inferenceLock.unlock() }

        let batch = llama_batch_get_one(UnsafeMutablePointer(mutating: tokens), Int32(tokens.count))
        let result = llama_decode(context, batch)
        if result != 0 {
            NSLog("[LlamaCppEngine] Warmup decode failed with code \(result)")
        }
        llama_memory_clear(llama_get_memory(context), true)

        let elapsed = Date().timeIntervalSince(startTime) * 1000
        NSLog("[LlamaCppEngine] Keep-alive warmup complete (\(String(format: "%.0f", elapsed))ms)")
    }

    func cleanup(rawText: String, context cleanupContext: CleanupContext) async throws -> String {
        guard let model = model, let context = context else {
            throw YapYapError.modelNotLoaded
        }

        let userContext = UserPromptContextManager.shared.context(
            for: cleanupContext.appContext?.appName,
            transcript: rawText
        )

        let prompt: String

        if cleanupContext.useV2Prompts {
            // V2: multi-turn chat-style messages
            let v2Messages = CleanupPromptBuilderV2.buildMessages(
                rawText: rawText, context: cleanupContext, modelId: promptModelId, userContext: userContext
            )
            prompt = applyChatTemplateMultiTurn(v2Messages)
            NSLog("[LlamaCppEngine] V2 prompt: %d messages", v2Messages.count)
        } else {
            // V1: classic system + user message
            let messages = CleanupPromptBuilder.buildMessages(
                rawText: rawText, context: cleanupContext,
                modelId: promptModelId, userContext: userContext
            )
            NSLog("[LlamaCppEngine] V1 system prompt (\(messages.system.count) chars), user prompt (\(messages.user.count) chars)")
            prompt = applyChatTemplate(system: messages.system, user: messages.user)
        }
        var tokens = tokenize(prompt, addSpecial: false)

        guard !tokens.isEmpty else {
            throw LlamaCppError.tokenizationFailed
        }

        // Guard against prompts that would overflow the context window.
        // Reserve at least 256 tokens for generation output.
        let contextSize = Int(llama_n_ctx(context))
        let maxPromptTokens = contextSize - 256
        if tokens.count > maxPromptTokens {
            NSLog("[LlamaCppEngine] Prompt too long (%d tokens), truncating to %d to leave room for generation", tokens.count, maxPromptTokens)
            tokens = Array(tokens.prefix(maxPromptTokens))
        }

        NSLog("[LlamaCppEngine] Prompt: \(tokens.count) tokens (context: \(contextSize))")

        // Lock the context for the entire inference pass (prefill + generation).
        // The keep-alive timer can fire warmup() concurrently, and llama.cpp
        // contexts are not thread-safe.
        inferenceLock.lock()
        defer { inferenceLock.unlock() }

        // Clear KV cache for fresh inference
        llama_memory_clear(llama_get_memory(context), true)

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

        // Generate tokens (cap at remaining context to avoid decode crash)
        let eosToken = llama_vocab_eos(llama_model_get_vocab(model))
        let maxGenTokens = contextSize - tokens.count
        var outputTokens: [llama_token] = []
        var outputText = ""

        // Hoist stop sequences outside the loop to avoid per-token allocation
        let stopSequences = ["<end_of_turn>", "<|im_end|>", "<|eot_id|>", "<|end|>", "</s>", "</output>"]
        let maxStopLen = stopSequences.map(\.count).max() ?? 0

        while outputTokens.count < maxGenTokens {
            let newToken = llama_sampler_sample(sampler, context, -1)

            // Stop on EOS
            if newToken == eosToken { break }

            // Decode token to text
            let piece = tokenToPiece(newToken)
            outputText += piece

            // Only scan the tail of outputText for stop sequences (O(1) per token)
            let tailStart = outputText.index(outputText.endIndex, offsetBy: -(maxStopLen + piece.count), limitedBy: outputText.startIndex) ?? outputText.startIndex
            let tail = String(outputText[tailStart...])
            var stopped = false
            for stop in stopSequences {
                if let range = tail.range(of: stop) {
                    let offset = outputText.distance(from: outputText.startIndex, to: tailStart)
                    let fullStart = outputText.index(outputText.startIndex, offsetBy: offset + tail.distance(from: tail.startIndex, to: range.lowerBound))
                    outputText = String(outputText[..<fullStart])
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
        let memWarning = tokPerSec < 5 ? " ⚠️ MEMORY PRESSURE — model likely swapped to disk" :
                         tokPerSec < 20 ? " ⚠️ SLOW — possible memory pressure" : ""
        NSLog("[LlamaCppEngine] Generation: %d tokens in %.0fms (%.0f tok/s), total %.1fs%@",
              outputTokens.count, genMs, tokPerSec, elapsed, memWarning)

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
                llama_model_chat_template(model, nil),
                messagesPtr.baseAddress,
                messagesPtr.count,
                true,  // add generation prompt
                &buf,
                Int32(buf.count)
            )
        }

        if result > 0 && Int(result) < buf.count {
            return String(cString: buf.prefix(Int(result)) + [0])
        }

        // Fallback: ChatML format (Qwen-compatible)
        NSLog("[LlamaCppEngine] Built-in template failed, using ChatML fallback")
        let systemBlock = system.isEmpty ? "" : "<|im_start|>system\n\(system)<|im_end|>\n"
        return "\(systemBlock)<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
    }

    /// Apply the model's built-in chat template with multi-turn ChatMessages (V2).
    private func applyChatTemplateMultiTurn(_ messages: [ChatMessage]) -> String {
        guard let model = model else {
            return messages.last?.content ?? ""
        }

        var chatMessages: [llama_chat_message] = []
        var allocations: [(UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CChar>)] = []

        for msg in messages {
            let roleCStr = strdup(msg.role.rawValue)!
            let contentCStr = strdup(msg.content)!
            chatMessages.append(llama_chat_message(role: roleCStr, content: contentCStr))
            allocations.append((roleCStr, contentCStr))
        }

        defer {
            for (role, content) in allocations {
                free(role)
                free(content)
            }
        }

        var buf = [CChar](repeating: 0, count: 16384)
        let result = chatMessages.withUnsafeBufferPointer { messagesPtr in
            llama_chat_apply_template(
                llama_model_chat_template(model, nil),
                messagesPtr.baseAddress,
                messagesPtr.count,
                true,
                &buf,
                Int32(buf.count)
            )
        }

        if result > 0 && Int(result) < buf.count {
            return String(cString: buf.prefix(Int(result)) + [0])
        }

        // Fallback: ChatML format with multi-turn
        NSLog("[LlamaCppEngine] Built-in template failed for multi-turn, using ChatML fallback")
        var prompt = ""
        for msg in messages {
            prompt += "<|im_start|>\(msg.role.rawValue)\n\(msg.content)<|im_end|>\n"
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }

    // MARK: - GGUF Download

    private func downloadGGUF(from url: URL, to destination: URL, progressHandler: @escaping (Double) -> Void) async throws {
        // Use bytes(from:) for streaming download with progress tracking
        let (bytes, response) = try await URLSession.shared.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LlamaCppError.downloadFailed(url.absoluteString)
        }

        let expectedLength = httpResponse.expectedContentLength  // -1 if unknown
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")

        // Stream bytes to a temp file, reporting progress
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        defer { try? fileHandle.close() }

        var bytesReceived: Int64 = 0
        let chunkSize = 1024 * 256  // 256KB buffer
        var buffer = Data()
        buffer.reserveCapacity(chunkSize)

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= chunkSize {
                fileHandle.write(buffer)
                bytesReceived += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expectedLength > 0 {
                    progressHandler(Double(bytesReceived) / Double(expectedLength))
                }
            }
        }

        // Write remaining bytes
        if !buffer.isEmpty {
            fileHandle.write(buffer)
            bytesReceived += Int64(buffer.count)
        }
        try fileHandle.close()
        progressHandler(1.0)

        // Move to final destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        NSLog("[LlamaCppEngine] Downloaded GGUF to \(destination.path) (\(bytesReceived) bytes)")
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
