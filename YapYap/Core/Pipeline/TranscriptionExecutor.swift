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
        // Determine what needs reloading BEFORE launching any async work
        let needsSTTReload = sttEngine == nil || !sttEngine!.isLoaded
            || sttEngine!.modelInfo.id != sttModelId

        // LLM — read inference framework from settings
        let settings = await MainActor.run { DataManager.shared.fetchSettings() }
        let framework = LLMInferenceFramework(rawValue: settings.llmInferenceFramework) ?? .mlx
        let ollamaEndpoint = settings.ollamaEndpoint
        let ollamaModelName = settings.ollamaModelName
        let llamacppModelId = settings.llamacppModelId

        let effectiveLLMId: String
        switch framework {
        case .mlx:      effectiveLLMId = llmModelId
        case .llamacpp: effectiveLLMId = llamacppModelId
        case .ollama:   effectiveLLMId = ollamaModelName
        }

        let currentFramework: LLMInferenceFramework? = {
            if llmEngine is MLXEngine { return .mlx }
            if llmEngine is LlamaCppEngine { return .llamacpp }
            if llmEngine is OllamaEngine { return .ollama }
            return nil
        }()
        let frameworkChanged = currentFramework != framework
        let needsLLMReload = llmEngine == nil || !llmEngine!.isLoaded
            || llmEngine!.modelId != effectiveLLMId || frameworkChanged

        // Prepare engines that need reloading (unload old ones, create new instances)
        var newSTTEngine: (any STTEngine)?
        if needsSTTReload {
            if let existing = sttEngine, existing.isLoaded {
                NSLog("[TranscriptionExecutor] STT model changed: \(existing.modelInfo.id) → \(sttModelId)")
                existing.unloadModel()
            }
            newSTTEngine = STTEngineFactory.create(modelId: sttModelId)
            sttEngine = newSTTEngine
        }

        var newLLMEngine: (any LLMEngine)?
        if needsLLMReload {
            if let existing = llmEngine, existing.isLoaded {
                NSLog("[TranscriptionExecutor] LLM model changed: \(existing.modelId ?? "?") → \(effectiveLLMId) (framework: \(framework.rawValue))")
                existing.unloadModel()
            }
            let engine = LLMEngineFactory.create(framework: framework, ollamaEndpoint: ollamaEndpoint)
            if let ollamaEngine = engine as? OllamaEngine {
                ollamaEngine.promptModelId = llmModelId
            } else if let llamaCppEngine = engine as? LlamaCppEngine {
                llamaCppEngine.promptModelId = llmModelId
            }
            newLLMEngine = engine
        }

        // Launch both model loads in parallel when both need reloading.
        // STT uses ANE/GPU, LLM uses GPU — they can load concurrently.
        if let sttEng = newSTTEngine, let llmEng = newLLMEngine {
            await onStatus("Loading models...")
            NSLog("[TranscriptionExecutor] Loading STT + LLM in parallel: \(sttModelId), \(effectiveLLMId)")

            async let sttLoad: Void = sttEng.loadModel(progressHandler: onSTTProgress)
            async let llmLoad: Result<Void, Error> = {
                do {
                    try await llmEng.loadModel(id: effectiveLLMId, progressHandler: onLLMProgress)
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }()

            // STT is critical — let it throw
            try await sttLoad
            NSLog("[TranscriptionExecutor] ✅ STT loaded")

            // LLM failure is non-fatal — recording works without cleanup
            switch await llmLoad {
            case .success:
                llmEngine = llmEng
                NSLog("[TranscriptionExecutor] ✅ LLM loaded via \(framework.rawValue)")
            case .failure(let error):
                llmEngine = nil
                NSLog("[TranscriptionExecutor] ⚠️ LLM failed: \(error)")
                let errorHint: String
                switch framework {
                case .ollama: errorHint = "Is Ollama running?"
                case .llamacpp: errorHint = "GGUF model download may have failed."
                case .mlx: errorHint = "Recording still works without cleanup."
                }
                await onStatus("Cleanup model unavailable — \(errorHint)")
            }
        } else if let sttEng = newSTTEngine {
            // Only STT needs reloading
            await onStatus("Loading speech model...")
            NSLog("[TranscriptionExecutor] Loading STT: \(sttModelId)")
            try await sttEng.loadModel(progressHandler: onSTTProgress)
            NSLog("[TranscriptionExecutor] ✅ STT loaded")
        } else if let llmEng = newLLMEngine {
            // Only LLM needs reloading
            await onStatus("Loading language model...")
            NSLog("[TranscriptionExecutor] Loading LLM: \(effectiveLLMId) via \(framework.rawValue)")
            do {
                try await llmEng.loadModel(id: effectiveLLMId, progressHandler: onLLMProgress)
                llmEngine = llmEng
                NSLog("[TranscriptionExecutor] ✅ LLM loaded via \(framework.rawValue)")
            } catch {
                llmEngine = nil
                NSLog("[TranscriptionExecutor] ⚠️ LLM failed: \(error)")
                let errorHint: String
                switch framework {
                case .ollama: errorHint = "Is Ollama running?"
                case .llamacpp: errorHint = "GGUF model download may have failed."
                case .mlx: errorHint = "Recording still works without cleanup."
                }
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
        audioSampleCountProvider: (() -> Int)? = nil,
        language: String,
        onUpdate: @escaping (StreamingTranscriptionUpdate) -> Void
    ) async throws {
        guard let streaming = streamingEngine else {
            NSLog("[TranscriptionExecutor] STT engine does not support streaming")
            return
        }
        try await streaming.startStreaming(
            audioSamplesProvider: audioSamplesProvider,
            audioSampleCountProvider: audioSampleCountProvider,
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
