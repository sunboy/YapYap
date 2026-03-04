// ModelDownloadService.swift
// YapYap — Unified model download actor for STT, LLM, and GGUF models
import Foundation
import WhisperKit
import FluidAudio
import MLXLLM
import MLXLMCommon
import Hub

/// Centralized model download service.
///
/// Owns the pre-download step for all model types. Engines (`WhisperKitEngine`,
/// `FluidAudioEngine`, `MLXEngine`) still own `loadModel()` (load into memory);
/// this actor owns explicit downloads with progress feedback.
///
/// All models are stored under ~/Library/Application Support/YapYap/models/
/// which is never iCloud-synced, preventing eviction hangs on iCloud-backed paths.
actor ModelDownloadService {
    static let shared = ModelDownloadService()
    private init() {}

    // MARK: - Canonical storage paths (all App Support, never iCloud)

    static let modelsBase: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("YapYap/models")
    }()

    /// WhisperKit model cache: HubApi stores at {whisperDir}/models/argmaxinc/whisperkit-coreml/
    static var whisperDir: URL { modelsBase.appendingPathComponent("whisperkit") }

    /// Parent directory for FluidAudio/Parakeet models.
    /// AsrModels.download(to:) creates its own versioned subfolder (parakeet-tdt-0.6b-v3-coreml) inside.
    static var fluidAudioParentDir: URL { modelsBase.appendingPathComponent("STT") }

    /// LLM model cache: HubApi stores at {llmDir}/models/{huggingFaceId}/
    static var llmDir: URL { modelsBase.appendingPathComponent("llm") }

    /// Known Parakeet repo folder name used by FluidAudio's DownloadUtils
    static let parakeetRepoFolderName = "parakeet-tdt-0.6b-v3-coreml"

    // MARK: - isDownloaded

    /// Returns true if a model is locally available (no network needed).
    /// Thread-safe — runs synchronous filesystem checks; call from a background queue.
    func isDownloaded(modelId: String) -> Bool {
        if let stt = STTModelRegistry.model(for: modelId) {
            return isSTTDownloaded(stt)
        }
        if let llm = LLMModelRegistry.model(for: modelId) {
            let modelDir = Self.llmDir.appendingPathComponent("models/\(llm.huggingFaceId)")
            return FileManager.default.fileExists(atPath: modelDir.path)
        }
        if let gguf = GGUFModelRegistry.model(for: modelId) {
            return FileManager.default.fileExists(atPath: GGUFModelRegistry.localPath(for: gguf).path)
        }
        return false
    }

    private func isSTTDownloaded(_ model: STTModelInfo) -> Bool {
        switch model.backend {
        case .whisperKit:
            let whiskerKitModel = model.id.replacingOccurrences(of: "whisper-", with: "")
            // HubApi stores at {whisperDir}/models/argmaxinc/whisperkit-coreml/
            let hubSubdir = Self.whisperDir.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            return findWhisperFolder(variant: whiskerKitModel, in: hubSubdir) != nil
                || findWhisperFolder(variant: whiskerKitModel, in: Self.whisperDir) != nil
        case .fluidAudio:
            let repoDir = Self.fluidAudioParentDir.appendingPathComponent(Self.parakeetRepoFolderName)
            return AsrModels.modelsExist(at: repoDir)
        case .whisperCpp, .speechAnalyzer:
            return false
        }
    }

    // MARK: - download

    /// Download a model to its canonical location with fractional progress (0.0–1.0).
    /// Idempotent — safe to call if already downloaded (returns immediately after progress(1.0)).
    func download(modelId: String, progress: @escaping (Double) -> Void) async throws {
        if let stt = STTModelRegistry.model(for: modelId) {
            try await downloadSTT(stt, progress: progress)
        } else if let llm = LLMModelRegistry.model(for: modelId) {
            try await downloadLLM(llm, progress: progress)
        } else if let gguf = GGUFModelRegistry.model(for: modelId) {
            try await downloadGGUF(gguf, progress: progress)
        }
    }

    // MARK: - Private STT download

    private func downloadSTT(_ model: STTModelInfo, progress: @escaping (Double) -> Void) async throws {
        switch model.backend {
        case .whisperKit:
            progress(0.0)
            let whiskerKitModel = model.id.replacingOccurrences(of: "whisper-", with: "")
            try? FileManager.default.createDirectory(at: Self.whisperDir, withIntermediateDirectories: true)
            // WhisperKit.download() returns the local folder URL; no fractional progress in the public API.
            // We emit 0→1 to signal indeterminate download (at least the spinner is explicit).
            _ = try await WhisperKit.download(
                variant: whiskerKitModel,
                downloadBase: Self.whisperDir,
                useBackgroundSession: false
            )
            progress(1.0)
        case .fluidAudio:
            progress(0.0)
            try? FileManager.default.createDirectory(at: Self.fluidAudioParentDir, withIntermediateDirectories: true)
            // AsrModels.download(to:) downloads FluidAudio's repo files into its own versioned subfolder.
            // No file-level progress is exposed; emit 0→1 as indeterminate.
            let repoDir = Self.fluidAudioParentDir.appendingPathComponent(Self.parakeetRepoFolderName)
            _ = try await AsrModels.download(to: repoDir)
            progress(1.0)
        case .whisperCpp, .speechAnalyzer:
            break
        }
    }

    // MARK: - Private LLM download

    private func downloadLLM(_ model: LLMModelInfo, progress: @escaping (Double) -> Void) async throws {
        try? FileManager.default.createDirectory(at: Self.llmDir, withIntermediateDirectories: true)
        let hub = HubApi(downloadBase: Self.llmDir)
        let config = ModelConfiguration(id: model.huggingFaceId)
        _ = try await LLMModelFactory.shared.load(hub: hub, configuration: config) { p in
            progress(p.fractionCompleted)
        }
    }

    // MARK: - Private GGUF download

    private func downloadGGUF(_ model: GGUFModelInfo, progress: @escaping (Double) -> Void) async throws {
        progress(0.0)
        let destination = GGUFModelRegistry.localPath(for: model)
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let (tempURL, response) = try await URLSession.shared.download(from: model.downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LlamaCppError.downloadFailed(model.downloadURL.absoluteString)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        progress(1.0)
    }

    // MARK: - Helpers

    /// Find a locally cached WhisperKit model folder for the given variant.
    /// Mirrors the logic in WhisperKitEngine.findLocalWhisperFolder().
    private func findWhisperFolder(variant: String, in cacheDir: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        let prefix = "openai_whisper-\(variant)"
        let candidates = contents.filter { url in
            let name = url.lastPathComponent.lowercased()
            let targetPrefix = prefix.lowercased()
            guard name.hasPrefix(targetPrefix) else { return false }
            let remainder = name.dropFirst(targetPrefix.count)
            return remainder.isEmpty || remainder.hasPrefix("_") || remainder.first?.isNumber == true
        }

        guard !candidates.isEmpty else { return nil }
        return candidates.first
    }
}
