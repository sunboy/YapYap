// LLMInferenceFramework.swift
// YapYap — Defines the available inference backends for LLM cleanup
import Foundation

/// Which framework to use for running the LLM cleanup model.
/// MLX runs models on-device via Apple's MLX framework.
/// Ollama delegates inference to a locally-running Ollama server.
enum LLMInferenceFramework: String, CaseIterable, Codable {
    case mlx = "mlx"
    case ollama = "ollama"

    var displayName: String {
        switch self {
        case .mlx: return "MLX (On-Device)"
        case .ollama: return "Ollama (Local Server)"
        }
    }

    var description: String {
        switch self {
        case .mlx:
            return "Runs quantized models directly on Apple GPU/CPU via MLX. No extra software needed."
        case .ollama:
            return "Delegates inference to a locally-running Ollama server. Install Ollama separately."
        }
    }
}
