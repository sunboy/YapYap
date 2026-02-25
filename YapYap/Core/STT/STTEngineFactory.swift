// STTEngineFactory.swift
// YapYap — Factory to create STT engines by model ID
import Foundation

struct STTEngineFactory {
    static func create(modelId: String) -> any STTEngine {
        guard let modelInfo = STTModelRegistry.model(for: modelId) else {
            // Default to first available model
            let defaultModel = STTModelRegistry.allModels.first!
            return createEngine(for: defaultModel)
        }
        return createEngine(for: modelInfo)
    }

    private static func createEngine(for model: STTModelInfo) -> any STTEngine {
        switch model.backend {
        case .whisperKit:
            return WhisperKitEngine(modelInfo: model)
        case .fluidAudio:
            return FluidAudioEngine(modelInfo: model)
        case .whisperCpp:
            return WhisperCppEngine(modelInfo: model)
        case .speechAnalyzer:
            if #available(macOS 26, *) {
                return SpeechAnalyzerEngine(modelInfo: model)
            } else {
                // Fall back to recommended model on older macOS
                let fallback = STTModelRegistry.recommendedModel
                return createEngine(for: fallback)
            }
        }
    }
}
