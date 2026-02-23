// BenchmarkRunner.swift
// YapYapBench — Orchestrator: STT once, then LLM matrix across models/contexts/levels
import Foundation
import MLX

struct BenchmarkConfig {
    let sttModelId: String
    let llmModelIds: [String]
    let contextNames: [String]
    let cleanupLevels: [CleanupContext.CleanupLevel]
    let experimentalPrompts: Bool
    let language: String
}

class BenchmarkRunner {

    /// Run the full benchmark for a single WAV file.
    /// Returns a RecordingResult with STT output + all LLM runs.
    func runSingle(
        wavURL: URL,
        transcript: String?,
        config: BenchmarkConfig
    ) async throws -> RecordingResult {
        let fileName = wavURL.lastPathComponent

        // STT phase
        let sttResult: STTResult?
        let transcriptText: String
        let duration: Double?

        if let providedTranscript = transcript {
            // Skip STT, use provided transcript
            transcriptText = providedTranscript
            sttResult = nil
            duration = nil
            log("Using provided transcript: \"\(truncate(transcriptText, to: 60))\"")
        } else {
            // Load WAV
            log("Loading \(fileName)...")
            let (buffer, dur) = try WAVLoader.load(url: wavURL)
            duration = dur
            log(String(format: "Audio: %.1fs, %d frames", dur, buffer.frameLength))

            // STT
            log("Loading STT model '\(config.sttModelId)'...")
            let engine = STTEngineFactory.create(modelId: config.sttModelId)
            try await engine.loadModel { progress in
                let pct = Int(progress * 100)
                if pct % 25 == 0 { self.log("STT loading: \(pct)%") }
            }

            log("Transcribing...")
            let result = try await engine.transcribe(audioBuffer: buffer, language: config.language)
            let latencyMs = Int(result.processingTime * 1000)
            sttResult = STTResult(transcript: result.text, latencyMs: latencyMs, language: result.language)
            transcriptText = result.text
            log("STT result (\(latencyMs)ms): \"\(truncate(transcriptText, to: 60))\"")

            engine.unloadModel()
        }

        // LLM phase — sequential model loading, all combos per model
        var runs: [LLMRunResult] = []
        let llmRunner = BenchmarkLLMRunner()

        for llmModelId in config.llmModelIds {
            guard let modelInfo = LLMModelRegistry.model(for: llmModelId) else {
                log("WARNING: Unknown LLM model '\(llmModelId)', skipping")
                continue
            }

            log("Loading LLM model '\(llmModelId)'...")
            try await llmRunner.loadModel(id: llmModelId) { progress in
                let pct = Int(progress * 100)
                if pct % 25 == 0 { self.log("LLM loading: \(pct)%") }
            }

            // Run all (context, cleanupLevel) combos against this model
            for contextName in config.contextNames {
                let appContext = ContextFactory.makeAppContext(for: contextName)

                for level in config.cleanupLevels {
                    let cleanupContext = ContextFactory.makeCleanupContext(
                        appContext: appContext,
                        cleanupLevel: level,
                        experimentalPrompts: config.experimentalPrompts
                    )

                    log("  \(llmModelId) × \(contextName) × \(level.rawValue)...")

                    let prompt = llmRunner.getPrompt(rawText: transcriptText, context: cleanupContext)

                    do {
                        let metrics = try await llmRunner.run(rawText: transcriptText, context: cleanupContext)

                        // Post-processing pipeline (mirrors YapYap)
                        let outputFormatterStart = Date()
                        let afterFormatter = OutputFormatter.format(metrics.sanitizedOutput, for: appContext)
                        let outputFormatterMs = Int(Date().timeIntervalSince(outputFormatterStart) * 1000)

                        let fillerFilterStart = Date()
                        let afterFillerFilter = cleanupContext.removeFillers
                            ? FillerFilter.removeFillers(from: afterFormatter, aggressive: level == .heavy)
                            : afterFormatter
                        let fillerFilterMs = Int(Date().timeIntervalSince(fillerFilterStart) * 1000)

                        let finalOutput = afterFillerFilter

                        // Validation: check overlap with input
                        let overlapRatio = computeOverlap(input: transcriptText, output: finalOutput)
                        let isValid = !finalOutput.isEmpty && overlapRatio > 0.2

                        let sizeLabel = modelInfo.size == .small ? "small" : "medium"
                        let run = LLMRunResult(
                            llmModelId: llmModelId,
                            llmModelFamily: modelInfo.family.rawValue,
                            llmModelSize: sizeLabel,
                            context: ContextInfo(category: appContext.category.rawValue, appName: appContext.appName),
                            cleanupLevel: level.rawValue,
                            experimentalPrompts: config.experimentalPrompts,
                            prompt: PromptInfo(system: prompt.system, user: prompt.user),
                            output: OutputStages(
                                rawLLM: metrics.rawOutput,
                                afterSanitization: metrics.sanitizedOutput,
                                afterOutputFormatter: afterFormatter,
                                afterFillerFilter: afterFillerFilter,
                                final_: finalOutput
                            ),
                            timing: TimingInfo(
                                prefillMs: metrics.prefillMs,
                                generationMs: metrics.generationMs,
                                totalLLMMs: metrics.totalMs,
                                outputFormatterMs: outputFormatterMs,
                                fillerFilterMs: fillerFilterMs
                            ),
                            tokens: TokenInfo(
                                promptTokens: metrics.promptTokens,
                                generationTokens: metrics.generationTokens,
                                tokensPerSecond: metrics.tokensPerSecond
                            ),
                            validation: ValidationInfo(
                                isValid: isValid,
                                overlapRatio: overlapRatio
                            )
                        )
                        runs.append(run)
                        log("    → \"\(truncate(finalOutput, to: 50))\" (\(metrics.totalMs)ms, \(String(format: "%.0f", metrics.tokensPerSecond)) tok/s)")
                    } catch {
                        log("    ERROR: \(error.localizedDescription)")
                    }
                }
            }

            // Unload model and flush GPU memory
            llmRunner.unloadModel()
            GPU.set(cacheLimit: 0)
            try? await Task.sleep(for: .milliseconds(500))
            GPU.set(cacheLimit: GPU.cacheLimit)
            log("Unloaded '\(llmModelId)', GPU cache flushed")
        }

        return RecordingResult(
            file: fileName,
            durationSeconds: duration,
            stt: sttResult,
            runs: runs
        )
    }

    // MARK: - Helpers

    /// Compute word overlap ratio between input and output.
    private func computeOverlap(input: String, output: String) -> Double {
        let inputWords = Set(input.lowercased().split(separator: " ").map(String.init))
        let outputWords = Set(output.lowercased().split(separator: " ").map(String.init))
        guard !inputWords.isEmpty else { return 0 }
        let intersection = inputWords.intersection(outputWords)
        return Double(intersection.count) / Double(inputWords.count)
    }

    private func truncate(_ text: String, to maxLen: Int) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        if cleaned.count <= maxLen { return cleaned }
        return String(cleaned.prefix(maxLen - 3)) + "..."
    }

    private func log(_ message: String) {
        FileHandle.standardError.write("[\(timestamp())] \(message)\n".data(using: .utf8)!)
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
