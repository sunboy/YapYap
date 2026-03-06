// STTEngineFactory.swift
// YapYap — Factory to create STT engines by model ID
import Foundation

struct STTEngineFactory {
    static func create(modelId: String) -> any STTEngine {
        guard let modelInfo = STTModelRegistry.model(for: modelId) else {
            // Fall back to recommended model (Parakeet)
            return createEngine(for: STTModelRegistry.recommendedModel)
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
            #if compiler(>=6.2)
            if #available(macOS 26, *) {
                return SpeechAnalyzerEngine(modelInfo: model)
            }
            #endif
            // Fall back to recommended model on older macOS / older SDK
            let fallback = STTModelRegistry.recommendedModel
            return createEngine(for: fallback)
        }
    }
}
