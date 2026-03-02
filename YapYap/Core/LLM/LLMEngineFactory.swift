// LLMEngineFactory.swift
// YapYap — Factory for creating the appropriate LLM engine based on user settings
import Foundation

struct LLMEngineFactory {
    /// Creates an LLM engine for the given inference framework.
    /// - Parameters:
    ///   - framework: Which inference backend to use (.mlx, .llamacpp, or .ollama)
    ///   - ollamaEndpoint: The Ollama server URL (only used when framework is .ollama)
    /// - Returns: An engine conforming to LLMEngine
    static func create(framework: LLMInferenceFramework, ollamaEndpoint: String = OllamaEngine.defaultEndpoint) -> any LLMEngine {
        switch framework {
        case .mlx:
            return MLXEngine()
        case .llamacpp:
            return LlamaCppEngine()
        case .ollama:
            return OllamaEngine(endpoint: ollamaEndpoint)
        }
    }
}
