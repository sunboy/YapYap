// LLMModelRegistry.swift
// YapYap — Catalog of available LLM cleanup models
import Foundation

struct LLMModelInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let huggingFaceId: String
    let sizeBytes: Int64
    let sizeDescription: String
    let description: String
    let isRecommended: Bool

    static func == (lhs: LLMModelInfo, rhs: LLMModelInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct LLMModelRegistry {
    static let allModels: [LLMModelInfo] = [
        LLMModelInfo(
            id: "qwen-2.5-3b",
            name: "Qwen 2.5 3B",
            huggingFaceId: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            sizeBytes: 2_147_483_648,
            sizeDescription: "~2.0GB",
            description: "Fast, multilingual. Recommended.",
            isRecommended: true
        ),
        LLMModelInfo(
            id: "qwen-2.5-7b",
            name: "Qwen 2.5 7B",
            huggingFaceId: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            sizeBytes: 5_016_021_811,
            sizeDescription: "~4.7GB",
            description: "Higher quality rewrites. 16GB+ RAM.",
            isRecommended: false
        ),
        LLMModelInfo(
            id: "llama-3.2-3b",
            name: "Llama 3.2 3B",
            huggingFaceId: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            sizeBytes: 2_147_483_648,
            sizeDescription: "~2.0GB",
            description: "Great for English. Fast.",
            isRecommended: false
        ),
        LLMModelInfo(
            id: "llama-3.1-8b",
            name: "Llama 3.1 8B",
            huggingFaceId: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            sizeBytes: 5_016_021_811,
            sizeDescription: "~4.7GB",
            description: "Best rewrite quality. 16GB+ RAM.",
            isRecommended: false
        ),
    ]

    static func model(for id: String) -> LLMModelInfo? {
        allModels.first { $0.id == id }
    }

    static var recommendedModel: LLMModelInfo {
        allModels.first { $0.isRecommended } ?? allModels[0]
    }
}
