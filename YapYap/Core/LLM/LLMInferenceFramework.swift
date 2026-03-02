// LLMInferenceFramework.swift
// YapYap — Defines the available inference backends for LLM cleanup
import Foundation

/// Which framework to use for running the LLM cleanup model.
/// - MLX: On-device via Apple's MLX framework (safetensors format)
/// - llama.cpp: Embedded llama.cpp engine (GGUF format, no external deps)
/// - Ollama: Delegates to a locally-running Ollama server (user-managed)
enum LLMInferenceFramework: String, CaseIterable, Codable {
    case mlx = "mlx"
    case llamacpp = "llamacpp"
    case ollama = "ollama"

    var displayName: String {
        switch self {
        case .mlx: return "MLX"
        case .llamacpp: return "llama.cpp"
        case .ollama: return "Ollama"
        }
    }

    var description: String {
        switch self {
        case .mlx:
            return "Apple GPU via MLX. Fastest on M-series. No extra software."
        case .llamacpp:
            return "Embedded llama.cpp. Broad GGUF model support. No extra software."
        case .ollama:
            return "External Ollama server. Bring any model. Install separately."
        }
    }

    var iconName: String {
        switch self {
        case .mlx: return "cpu"
        case .llamacpp: return "terminal"
        case .ollama: return "server.rack"
        }
    }

    /// Whether this framework uses the MLX model registry
    var usesMLXModels: Bool { self == .mlx }
    /// Whether this framework uses the GGUF model registry
    var usesGGUFModels: Bool { self == .llamacpp }
    /// Whether this framework uses a free-text Ollama model name
    var usesOllamaModels: Bool { self == .ollama }
}
