import Foundation

enum ModelType {
    case stt
    case llm
}

/// Manages local storage of ML models in ~/Library/Application Support/YapYap/Models/
class ModelStorage {
    static let shared = ModelStorage()

    private let baseDirectory: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDirectory = appSupport.appendingPathComponent("YapYap/Models")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    /// Get the storage path for a model
    func path(for modelId: String, type: ModelType) -> URL {
        let subdirectory = type == .stt ? "STT" : "LLM"
        let modelDir = baseDirectory.appendingPathComponent("\(subdirectory)/\(modelId)")

        // Create subdirectory if it doesn't exist
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        return modelDir
    }

    /// Check if a model exists locally
    func exists(modelId: String, type: ModelType) -> Bool {
        let modelPath = path(for: modelId, type: type)
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    /// Delete a model from local storage
    func delete(modelId: String, type: ModelType) throws {
        let modelPath = path(for: modelId, type: type)
        try FileManager.default.removeItem(at: modelPath)
    }

    /// Get the size of a model in bytes
    func size(modelId: String, type: ModelType) -> Int64? {
        let modelPath = path(for: modelId, type: type)
        guard let enumerator = FileManager.default.enumerator(at: modelPath, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    /// Get total disk usage of all models
    func totalDiskUsage() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: baseDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }

        return totalSize
    }
}
