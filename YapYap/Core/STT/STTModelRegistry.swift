// STTModelRegistry.swift
// YapYap — Catalog of available STT models
import Foundation

struct STTModelRegistry {
    static let allModels: [STTModelInfo] = [
        STTModelInfo(
            id: "whisper-large-v3-turbo",
            name: "Whisper Large v3",
            backend: .whisperKit,
            sizeBytes: 1_610_612_736,
            sizeDescription: "~1.5GB",
            languages: ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "hi"],
            description: "Best accuracy, multilingual. CoreML optimized.",
            isRecommended: false
        ),
        STTModelInfo(
            id: "whisper-medium",
            name: "Whisper Medium",
            backend: .whisperKit,
            sizeBytes: 805_306_368,
            sizeDescription: "~769MB",
            languages: ["en", "es", "fr", "de", "it", "pt", "zh", "ja"],
            description: "Good balance of speed and accuracy.",
            isRecommended: false
        ),
        STTModelInfo(
            id: "whisper-small",
            name: "Whisper Small",
            backend: .whisperKit,
            sizeBytes: 255_852_544,
            sizeDescription: "~244MB",
            languages: ["en", "es", "fr", "de"],
            description: "Fast and light. Good for 8GB machines.",
            isRecommended: false
        ),
        STTModelInfo(
            id: "parakeet-tdt-v3",
            name: "Parakeet TDT v3",
            backend: .fluidAudio,
            sizeBytes: 629_145_600,
            sizeDescription: "~600MB",
            languages: ["en", "es", "fr", "de", "it", "pt"],
            description: "Fastest. Runs on Neural Engine. Recommended.",
            isRecommended: true
        ),
        STTModelInfo(
            id: "voxtral",
            name: "Voxtral",
            backend: .whisperCpp,
            sizeBytes: 681_574_400,
            sizeDescription: "~650MB",
            languages: ["en", "es", "fr", "de", "it", "pt", "zh"],
            description: "Mistral's STT model. Good multilingual.",
            isRecommended: false
        ),
    ]

    static func model(for id: String) -> STTModelInfo? {
        allModels.first { $0.id == id }
    }

    static var recommendedModel: STTModelInfo {
        allModels.first { $0.isRecommended } ?? allModels[0]
    }
}
