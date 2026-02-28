// OllamaEngine.swift
// YapYap — Ollama-based LLM inference engine via local HTTP API
import Foundation

class OllamaEngine: LLMEngine {
    static let defaultEndpoint = "http://localhost:11434"

    private let endpoint: String
    private let session: URLSession
    private(set) var modelId: String?
    private var _isLoaded: Bool = false

    /// MLX model registry ID used for prompt selection. When set, the prompt builder
    /// uses the same family/size tier as the MLX model, ensuring identical prompts
    /// regardless of inference framework.
    var promptModelId: String?

    var isLoaded: Bool { _isLoaded }

    init(endpoint: String = OllamaEngine.defaultEndpoint) {
        self.endpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - LLMEngine Protocol

    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws {
        NSLog("[OllamaEngine] Loading model '\(id)' via Ollama at \(endpoint)")

        // Resolve Ollama model tag: use the user-provided id directly.
        // Users configure the Ollama model name in settings (e.g., "qwen2.5:1.5b").
        let modelTag = id

        // First, verify the Ollama server is reachable
        try await verifyServerReachable()

        // Check if the model is available locally, pull if needed
        let isAvailable = try await isModelAvailable(modelTag)
        if !isAvailable {
            NSLog("[OllamaEngine] Model '\(modelTag)' not found locally, pulling...")
            try await pullModel(modelTag, progressHandler: progressHandler)
        } else {
            progressHandler(1.0)
        }

        // Warm up: send a minimal request to pre-load weights into memory
        try await preloadModel(modelTag)

        self.modelId = id
        self._isLoaded = true
        NSLog("[OllamaEngine] Model '\(id)' loaded successfully via Ollama")
    }

    func unloadModel() {
        // Tell Ollama to unload the model from memory by setting keep_alive to 0
        if let tag = modelId {
            Task {
                try? await sendGenerateRequest(model: tag, prompt: "", keepAlive: 0)
            }
        }
        modelId = nil
        _isLoaded = false
    }

    func warmup() async {
        guard let tag = modelId, _isLoaded else { return }
        do {
            let startTime = Date()
            _ = try await chatCompletion(
                model: tag,
                messages: [["role": "user", "content": "Hi"]],
                maxTokens: 1
            )
            let elapsed = Date().timeIntervalSince(startTime) * 1000
            NSLog("[OllamaEngine] Keep-alive warmup complete (\(String(format: "%.0f", elapsed))ms)")
        } catch {
            NSLog("[OllamaEngine] Keep-alive warmup failed: \(error)")
        }
    }

    func cleanup(rawText: String, context: CleanupContext) async throws -> String {
        guard let tag = modelId, _isLoaded else {
            throw YapYapError.modelNotLoaded
        }

        // Build prompts using the same CleanupPromptBuilder as MLXEngine.
        // Use promptModelId (the MLX registry ID) so the prompt builder selects
        // the same family/size tier, producing identical prompts across frameworks.
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: rawText, context: context,
            modelId: promptModelId
        )

        NSLog("[OllamaEngine] System prompt (\(messages.system.count) chars): \"\(String(messages.system.prefix(200)))\"")
        NSLog("[OllamaEngine] User prompt (\(messages.user.count) chars): \"\(String(messages.user.prefix(200)))\"")

        var chatMessages: [[String: String]] = []
        if !messages.system.isEmpty {
            chatMessages.append(["role": "system", "content": messages.system])
        }
        chatMessages.append(["role": "user", "content": messages.user])

        let userTokenEstimate = rawText.split(separator: " ").count
        let maxTokens = max(32, min(userTokenEstimate * 4, 512))

        let startTime = Date()
        let result = try await chatCompletion(
            model: tag,
            messages: chatMessages,
            maxTokens: maxTokens,
            temperature: 0.0
        )
        let elapsed = Date().timeIntervalSince(startTime)
        NSLog("[OllamaEngine] Cleanup completed in \(String(format: "%.1f", elapsed))s, result: \(result.count) chars")

        let sanitized = sanitizeOutput(result)
        NSLog("[OllamaEngine] Cleanup result (\(sanitized.count) chars): \"\(String(sanitized.prefix(80)))...\"")
        return sanitized
    }

    // MARK: - Ollama HTTP API

    /// Verify the Ollama server is reachable
    private func verifyServerReachable() async throws {
        let url = URL(string: "\(endpoint)/api/tags")!
        let request = URLRequest(url: url)
        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw OllamaError.serverUnreachable(endpoint)
            }
        } catch let error as OllamaError {
            throw error
        } catch {
            throw OllamaError.serverUnreachable(endpoint)
        }
    }

    /// Check if a model is available locally in Ollama
    private func isModelAvailable(_ model: String) async throws -> Bool {
        let url = URL(string: "\(endpoint)/api/tags")!
        let request = URLRequest(url: url)
        let (data, _) = try await session.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return false
        }

        // Check if the model name matches (with or without :latest tag)
        return models.contains { modelInfo in
            guard let name = modelInfo["name"] as? String else { return false }
            return name == model || name == "\(model):latest" || model == name.replacingOccurrences(of: ":latest", with: "")
        }
    }

    /// Pull a model from the Ollama registry
    private func pullModel(_ model: String, progressHandler: @escaping (Double) -> Void) async throws {
        let url = URL(string: "\(endpoint)/api/pull")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3600 // Model downloads can take a long time

        let body: [String: Any] = ["name": model, "stream": true]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.pullFailed(model)
        }

        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let total = json["total"] as? Int64, let completed = json["completed"] as? Int64, total > 0 {
                let progress = Double(completed) / Double(total)
                await MainActor.run { progressHandler(progress) }
            }

            if let error = json["error"] as? String {
                throw OllamaError.pullError(model, error)
            }
        }
        await MainActor.run { progressHandler(1.0) }
    }

    /// Pre-load model weights into Ollama's memory
    private func preloadModel(_ model: String) async throws {
        _ = try await sendGenerateRequest(model: model, prompt: "", keepAlive: nil)
    }

    /// Send a chat completion request to Ollama
    private func chatCompletion(
        model: String,
        messages: [[String: String]],
        maxTokens: Int,
        temperature: Float = 0.0
    ) async throws -> String {
        let url = URL(string: "\(endpoint)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "options": [
                "temperature": temperature,
                "top_p": 1.0,
                "repeat_penalty": 1.1,
                "num_predict": maxTokens
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaError.httpError(httpResponse.statusCode, errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OllamaError.invalidResponse
        }

        return content
    }

    /// Low-level generate request (used for preload and unload)
    @discardableResult
    private func sendGenerateRequest(model: String, prompt: String, keepAlive: Int?) async throws -> String {
        let url = URL(string: "\(endpoint)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]
        if let keepAlive = keepAlive {
            body["keep_alive"] = keepAlive
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? String else {
            return ""
        }
        return response
    }

    // MARK: - Output Sanitization

    /// Reuses similar sanitization logic as MLXEngine for consistency.
    private func sanitizeOutput(_ text: String) -> String {
        var cleaned = text

        // Remove common special tokens that Ollama models might emit
        let specialTokens = [
            "<|endoftext|>", "<|im_end|>", "<|im_start|>",
            "<|eot_id|>", "<|end|>", "</s>", "<s>",
            "<|assistant|>", "<|user|>", "<|system|>",
            "</output>", "<output>", "<input>", "</input>"
        ]
        for token in specialTokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }

        // Remove common LLM preambles
        let preamblePatterns = [
            "(?i)^\\s*(the\\s+)?cleaned\\s+(text|version)\\s*(is)?\\s*:?\\s*",
            "(?i)^\\s*here\\s+(is|are)\\s+(the\\s+)?.*?:\\s*",
            "(?i)^\\s*here'?s\\s+the\\s+.*?:\\s*",
            "(?i)^\\s*(cleaned|corrected|fixed)\\s+(text|version)\\s*:?\\s*",
            "(?i)^\\s*output\\s*:\\s*",
            "(?i)^\\s*result\\s*:\\s*",
        ]
        for pattern in preamblePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
            }
        }

        // Remove markdown code fences
        if cleaned.contains("```") {
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        }

        // Remove wrapping quotes
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Ollama Errors

enum OllamaError: LocalizedError {
    case serverUnreachable(String)
    case pullFailed(String)
    case pullError(String, String)
    case invalidResponse
    case httpError(Int, String)
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .serverUnreachable(let endpoint):
            return "Cannot connect to Ollama at \(endpoint). Make sure Ollama is running."
        case .pullFailed(let model):
            return "Failed to pull model '\(model)' from Ollama."
        case .pullError(let model, let message):
            return "Error pulling model '\(model)': \(message)"
        case .invalidResponse:
            return "Invalid response from Ollama server."
        case .httpError(let code, let body):
            return "Ollama HTTP error \(code): \(body)"
        case .modelNotFound(let model):
            return "Model '\(model)' not found in Ollama. Run: ollama pull \(model)"
        }
    }
}
