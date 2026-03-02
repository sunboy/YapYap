// GGUFModelRegistry.swift
// YapYap — Catalog of available GGUF models for llama.cpp inference
import Foundation

struct GGUFModelInfo: Identifiable, Equatable {
    let id: String
    let name: String
    /// HuggingFace repo containing the GGUF file
    let ggufRepo: String
    /// Filename of the .gguf file within the repo
    let ggufFilename: String
    /// Corresponding MLX model ID for prompt building (family/size tier selection)
    let mlxEquivalentId: String
    let sizeBytes: Int64
    let sizeDescription: String
    let description: String
    let isRecommended: Bool
    let family: LLMModelFamily
    let size: LLMModelSize
    let languages: [String]

    /// Full HuggingFace download URL for the GGUF file
    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(ggufRepo)/resolve/main/\(ggufFilename)")!
    }

    static func == (lhs: GGUFModelInfo, rhs: GGUFModelInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct GGUFModelRegistry {
    static let allModels: [GGUFModelInfo] = [
        // Small tier (<=2B)
        GGUFModelInfo(
            id: "gguf-qwen-2.5-1.5b",
            name: "Qwen 2.5 1.5B",
            ggufRepo: "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
            ggufFilename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            mlxEquivalentId: "qwen-2.5-1.5b",
            sizeBytes: 1_100_000_000,
            sizeDescription: "~1.1GB",
            description: "Lightweight multilingual option.",
            isRecommended: false,
            family: .qwen,
            size: .small,
            languages: ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "hi"]
        ),
        GGUFModelInfo(
            id: "gguf-llama-3.2-1b",
            name: "Llama 3.2 1B",
            ggufRepo: "bartowski/Llama-3.2-1B-Instruct-GGUF",
            ggufFilename: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
            mlxEquivalentId: "llama-3.2-1b",
            sizeBytes: 800_000_000,
            sizeDescription: "~800MB",
            description: "Fastest, English-only.",
            isRecommended: false,
            family: .llama,
            size: .small,
            languages: ["en"]
        ),
        GGUFModelInfo(
            id: "gguf-gemma-3-1b",
            name: "Gemma 3 1B",
            ggufRepo: "bartowski/google_gemma-3-1b-it-GGUF",
            ggufFilename: "google_gemma-3-1b-it-Q4_K_M.gguf",
            mlxEquivalentId: "gemma-3-1b",
            sizeBytes: 800_000_000,
            sizeDescription: "~800MB",
            description: "Ultra-fast, 140+ languages.",
            isRecommended: false,
            family: .gemma,
            size: .small,
            languages: ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "hi", "ar", "ru"]
        ),

        // Medium tier (3B-4B)
        GGUFModelInfo(
            id: "gguf-qwen-2.5-3b",
            name: "Qwen 2.5 3B",
            ggufRepo: "Qwen/Qwen2.5-3B-Instruct-GGUF",
            ggufFilename: "qwen2.5-3b-instruct-q4_k_m.gguf",
            mlxEquivalentId: "qwen-2.5-3b",
            sizeBytes: 2_200_000_000,
            sizeDescription: "~2.2GB",
            description: "Higher quality, multilingual.",
            isRecommended: false,
            family: .qwen,
            size: .medium,
            languages: ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "hi"]
        ),
        GGUFModelInfo(
            id: "gguf-llama-3.2-3b",
            name: "Llama 3.2 3B",
            ggufRepo: "bartowski/Llama-3.2-3B-Instruct-GGUF",
            ggufFilename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            mlxEquivalentId: "llama-3.2-3b",
            sizeBytes: 2_000_000_000,
            sizeDescription: "~2.0GB",
            description: "Great for English. Fast.",
            isRecommended: false,
            family: .llama,
            size: .medium,
            languages: ["en"]
        ),
        GGUFModelInfo(
            id: "gguf-gemma-3-4b",
            name: "Gemma 3 4B",
            ggufRepo: "bartowski/google_gemma-3-4b-it-GGUF",
            ggufFilename: "google_gemma-3-4b-it-Q4_K_M.gguf",
            mlxEquivalentId: "gemma-3-4b",
            sizeBytes: 3_000_000_000,
            sizeDescription: "~3.0GB",
            description: "Best quality. Recommended. 140+ languages.",
            isRecommended: true,
            family: .gemma,
            size: .medium,
            languages: ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "hi", "ar", "ru"]
        ),

        // Large tier (7B+)
        GGUFModelInfo(
            id: "gguf-qwen-2.5-7b",
            name: "Qwen 2.5 7B",
            ggufRepo: "Qwen/Qwen2.5-7B-Instruct-GGUF",
            ggufFilename: "qwen2.5-7b-instruct-q4_k_m.gguf",
            mlxEquivalentId: "qwen-2.5-7b",
            sizeBytes: 4_700_000_000,
            sizeDescription: "~4.7GB",
            description: "Higher quality rewrites. 16GB+ RAM.",
            isRecommended: false,
            family: .qwen,
            size: .large,
            languages: ["en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "hi"]
        ),
        GGUFModelInfo(
            id: "gguf-llama-3.1-8b",
            name: "Llama 3.1 8B",
            ggufRepo: "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF",
            ggufFilename: "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
            mlxEquivalentId: "llama-3.1-8b",
            sizeBytes: 4_900_000_000,
            sizeDescription: "~4.9GB",
            description: "Best rewrite quality. 16GB+ RAM.",
            isRecommended: false,
            family: .llama,
            size: .large,
            languages: ["en"]
        ),
    ]

    static func model(for id: String) -> GGUFModelInfo? {
        allModels.first { $0.id == id }
    }

    static var recommendedModel: GGUFModelInfo {
        allModels.first { $0.isRecommended } ?? allModels[0]
    }

    /// Local directory for GGUF model files
    static var ggufModelsDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("YapYap/models/gguf")
    }

    /// Local file path for a downloaded GGUF model
    static func localPath(for model: GGUFModelInfo) -> URL {
        ggufModelsDir.appendingPathComponent(model.ggufFilename)
    }

    /// Check if a GGUF model is downloaded locally
    static func isDownloaded(_ model: GGUFModelInfo) -> Bool {
        FileManager.default.fileExists(atPath: localPath(for: model).path)
    }
}
