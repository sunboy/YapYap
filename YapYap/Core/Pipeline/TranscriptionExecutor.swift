// TranscriptionExecutor.swift
// YapYap — Actor-isolated engine management for STT and LLM
import AVFoundation
import Foundation

actor TranscriptionExecutor {
    private var sttEngine: (any STTEngine)?
    private var llmEngine: (any LLMEngine)?
    private var modelLoadingTask: Task<Void, Error>?

    var sttModelId: String? { sttEngine?.modelInfo.id }
    var llmModelId: String? { llmEngine?.modelId }
    var isSTTLoaded: Bool { sttEngine?.isLoaded ?? false }
    var isLLMLoaded: Bool { llmEngine?.isLoaded ?? false }
    var activeLLMModelId: String? { llmEngine?.isLoaded == true ? llmEngine?.modelId : nil }

    /// Access the streaming engine if the current STT supports it.
    var streamingEngine: (any StreamingSTTEngine)? {
        sttEngine as? (any StreamingSTTEngine)
    }

    // MARK: - Model Loading

    func ensureModelsLoaded(
        sttModelId: String,
        llmModelId: String,
        onSTTProgress: @escaping (Double) -> Void,
        onLLMProgress: @escaping (Double) -> Void,
        onStatus: @escaping (String) async -> Void
    ) async throws {
        // Await in-flight load if any
        if let existing = modelLoadingTask {
            try await existing.value
            return
        }

        let task = Task<Void, Error> { [weak self] in
            guard let self = self else { return }
            defer { Task { await self.clearModelLoadingTask() } }
            try await self.loadModelsImpl(
                sttModelId: sttModelId, llmModelId: llmModelId,
                onSTTProgress: onSTTProgress, onLLMProgress: onLLMProgress,
                onStatus: onStatus
            )
        }
        modelLoadingTask = task
        try await task.value
    }

    private func clearModelLoadingTask() {
        modelLoadingTask = nil
    }

    private func loadModelsImpl(
        sttModelId: String,
        llmModelId: String,
        onSTTProgress: @escaping (Double) -> Void,
        onLLMProgress: @escaping (Double) -> Void,
        onStatus: @escaping (String) async -> Void
    ) async throws {
        // STT
        let needsSTTReload = sttEngine == nil || !sttEngine!.isLoaded
            || sttEngine!.modelInfo.id != sttModelId
        if needsSTTReload {
            if let existing = sttEngine, existing.isLoaded {
                NSLog("[TranscriptionExecutor] STT model changed: \(existing.modelInfo.id) → \(sttModelId)")
                existing.unloadModel()
            }
            await onStatus("Loading speech model...")
            NSLog("[TranscriptionExecutor] Loading STT: \(sttModelId)")

            let newEngine = STTEngineFactory.create(modelId: sttModelId)
            sttEngine = newEngine
            try await newEngine.loadModel(progressHandler: onSTTProgress)
            NSLog("[TranscriptionExecutor] ✅ STT loaded")
        }

        // LLM — read inference framework from settings
        let settings = await MainActor.run { DataManager.shared.fetchSettings() }
        let framework = LLMInferenceFramework(rawValue: settings.llmInferenceFramework) ?? .mlx
        let ollamaEndpoint = settings.ollamaEndpoint
        let ollamaModelName = settings.ollamaModelName
        let effectiveLLMId = framework == .ollama ? ollamaModelName : llmModelId

        // Reload if: no engine, not loaded, model changed, or framework changed
        let currentIsOllama = llmEngine is OllamaEngine
        let frameworkChanged = (framework == .ollama) != currentIsOllama
        let needsLLMReload = llmEngine == nil || !llmEngine!.isLoaded
            || llmEngine!.modelId != effectiveLLMId || frameworkChanged
        if needsLLMReload {
            if let existing = llmEngine, existing.isLoaded {
                NSLog("[TranscriptionExecutor] LLM model changed: \(existing.modelId ?? "?") → \(effectiveLLMId) (framework: \(framework.rawValue))")
                existing.unloadModel()
            }
            await onStatus("Loading language model...")
            NSLog("[TranscriptionExecutor] Loading LLM: \(effectiveLLMId) via \(framework.rawValue)")

            let engine = LLMEngineFactory.create(framework: framework, ollamaEndpoint: ollamaEndpoint)
            // For Ollama: set the MLX registry model ID so the prompt builder
            // uses the same family/size tier as MLX, producing identical prompts.
            if let ollamaEngine = engine as? OllamaEngine {
                ollamaEngine.promptModelId = llmModelId
            }
            do {
                try await engine.loadModel(id: effectiveLLMId, progressHandler: onLLMProgress)
                llmEngine = engine
                NSLog("[TranscriptionExecutor] ✅ LLM loaded via \(framework.rawValue)")
            } catch {
                llmEngine = nil
                NSLog("[TranscriptionExecutor] ⚠️ LLM failed: \(error)")
                let errorHint = framework == .ollama ? "Is Ollama running?" : "Recording still works without cleanup."
                await onStatus("Cleanup model unavailable — \(errorHint)")
            }
        }
    }

    // MARK: - Transcription

    func transcribe(audioBuffer: AVAudioPCMBuffer, language: String) async throws -> TranscriptionResult {
        guard let engine = sttEngine, engine.isLoaded else {
            throw YapYapError.modelNotLoaded
        }
        return try await engine.transcribe(audioBuffer: audioBuffer, language: language)
    }

    // MARK: - Cleanup

    func cleanup(rawText: String, context: CleanupContext) async throws -> String {
        guard let engine = llmEngine, engine.isLoaded else {
            throw YapYapError.modelNotLoaded
        }
        return try await engine.cleanup(rawText: rawText, context: context)
    }

    // MARK: - Streaming

    func startStreaming(
        audioSamplesProvider: @escaping () -> [Float],
        language: String,
        onUpdate: @escaping (StreamingTranscriptionUpdate) -> Void
    ) async throws {
        guard let streaming = streamingEngine else {
            NSLog("[TranscriptionExecutor] STT engine does not support streaming")
            return
        }
        try await streaming.startStreaming(
            audioSamplesProvider: audioSamplesProvider,
            language: language,
            onUpdate: onUpdate
        )
    }

    func stopStreaming() async throws -> TranscriptionResult? {
        guard let streaming = streamingEngine, streaming.isStreaming else {
            return nil
        }
        return try await streaming.stopStreaming()
    }

    var isStreaming: Bool {
        (sttEngine as? (any StreamingSTTEngine))?.isStreaming ?? false
    }

    // MARK: - Warmup

    func warmupEngines() async {
        // Run STT and LLM warmups concurrently — they use different hardware
        // (STT may use ANE, LLM uses GPU) and are completely independent.
        async let sttWarmup: Void = sttEngine?.warmup() ?? ()
        async let llmWarmup: Void = llmEngine?.warmup() ?? ()
        _ = await (sttWarmup, llmWarmup)
    }

    func unloadAll() {
        sttEngine?.unloadModel()
        sttEngine = nil
        llmEngine?.unloadModel()
        llmEngine = nil
    }
}
