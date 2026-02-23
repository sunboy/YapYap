// LLMModelRegistry.swift
// YapYap — Catalog of available LLM cleanup models
import Foundation

enum LLMModelFamily: String {
    case llama
    case qwen
    case gemma

    /// Recommended inference temperature for this model family
    var temperature: Float { 0.0 }

    /// Recommended top-p for this model family
    var topP: Float { 1.0 }

    /// Repetition penalty to prevent degenerate loops
    var repetitionPenalty: Float {
        switch self {
        case .llama: return 1.1
        case .qwen: return 1.1
        case .gemma: return 1.1
        }
    }

    /// Context window used for repetition penalty
    var repetitionContextSize: Int { 20 }
}

/// Model size tier determines prompt complexity.
/// Small models (<=2B params) need ultra-minimal prompts.
/// Medium/large models (3B+) handle detailed prompts well.
enum LLMModelSize {
    case small  // <=2B — ultra-minimal prompts
    case medium // 3B+ — detailed prompts with full rules
}

struct LLMModelInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let huggingFaceId: String
    let sizeBytes: Int64
    let sizeDescription: String
    let description: String
    let isRecommended: Bool
    let family: LLMModelFamily
    let size: LLMModelSize
    let languages: [String]

    static func == (lhs: LLMModelInfo, rhs: LLMModelInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct LLMModelRegistry {
    static let allModels: [LLMModelInfo] = [
        LLMModelInfo(
            id: "qwen-2.5-1.5b",
            name: "Qwen 2.5 1.5B",
            huggingFaceId: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            sizeBytes: 986_000_000,
            sizeDescription: "~1.0GB",
            description: "Best balance of speed and quality. Recommended.",
            isRecommended: true,
            family: .qwen,
            size: .small,
            languages: ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "hi"]
        ),
        LLMModelInfo(
            id: "llama-3.2-1b",
            name: "Llama 3.2 1B",
            huggingFaceId: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            sizeBytes: 700_000_000,
            sizeDescription: "~700MB",
            description: "Fastest, English-only.",
            isRecommended: false,
            family: .llama,
            size: .small,
            languages: ["en"]
        ),
        LLMModelInfo(
            id: "qwen-2.5-3b",
            name: "Qwen 2.5 3B",
            huggingFaceId: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            sizeBytes: 2_147_483_648,
            sizeDescription: "~2.0GB",
            description: "Higher quality, multilingual. Slower.",
            isRecommended: false,
            family: .qwen,
            size: .medium,
            languages: ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "hi"]
        ),
        LLMModelInfo(
            id: "qwen-2.5-7b",
            name: "Qwen 2.5 7B",
            huggingFaceId: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            sizeBytes: 5_016_021_811,
            sizeDescription: "~4.7GB",
            description: "Higher quality rewrites. 16GB+ RAM.",
            isRecommended: false,
            family: .qwen,
            size: .medium,
            languages: ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "hi"]
        ),
        LLMModelInfo(
            id: "llama-3.2-3b",
            name: "Llama 3.2 3B",
            huggingFaceId: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            sizeBytes: 2_147_483_648,
            sizeDescription: "~2.0GB",
            description: "Great for English. Fast.",
            isRecommended: false,
            family: .llama,
            size: .medium,
            languages: ["en"]
        ),
        LLMModelInfo(
            id: "llama-3.1-8b",
            name: "Llama 3.1 8B",
            huggingFaceId: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            sizeBytes: 5_016_021_811,
            sizeDescription: "~4.7GB",
            description: "Best rewrite quality. 16GB+ RAM.",
            isRecommended: false,
            family: .llama,
            size: .medium,
            languages: ["en"]
        ),
    ]

    static func model(for id: String) -> LLMModelInfo? {
        allModels.first { $0.id == id }
    }

    static var recommendedModel: LLMModelInfo {
        allModels.first { $0.isRecommended } ?? allModels[0]
    }
}
