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
            description: "Fast and light. Good for 8GB machines. Auto-downloads on first use.",
            isRecommended: true
        ),
        STTModelInfo(
            id: "parakeet-tdt-v3",
            name: "Parakeet TDT v3",
            backend: .fluidAudio,
            sizeBytes: 629_145_600,
            sizeDescription: "~600MB",
            languages: ["en", "es", "fr", "de", "it", "pt"],
            description: "Fastest. Runs on Neural Engine. Must download manually in Settings.",
            isRecommended: false
        ),
        STTModelInfo(
            id: "voxtral-mini-3b",
            name: "Voxtral Mini 3B",
            backend: .whisperCpp,
            sizeBytes: 9_500_000_000,
            sizeDescription: "~9.5GB",
            languages: ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "hi", "ar", "ru", "nl"],
            description: "Mistral's SOTA model. 13 languages. Coming soon.",
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
