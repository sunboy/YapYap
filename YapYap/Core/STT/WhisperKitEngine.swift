// WhisperKitEngine.swift
// YapYap — WhisperKit STT backend for Whisper models
import WhisperKit
import AVFoundation

/// Lightweight segment storage to avoid referencing WhisperKit's TranscriptionSegment
/// by module-qualified name (module and class are both named "WhisperKit").
private struct StreamSegment {
    let text: String
    let start: Float
    let end: Float
}

class WhisperKitEngine: STTEngine, StreamingSTTEngine {
    let modelInfo: STTModelInfo
    private var pipe: WhisperKit?

    var isLoaded: Bool { pipe != nil }

    // MARK: - Streaming State

    private(set) var isStreaming: Bool = false
    private var streamingTask: Task<Void, Never>?
    private var lastBufferSize: Int = 0
    private var lastConfirmedSegmentEndSeconds: Float = 0
    private var confirmedSegments: [StreamSegment] = []
    private var unconfirmedSegments: [StreamSegment] = []
    private var audioProvider: (() -> [Float])?
    private var updateCallback: ((StreamingTranscriptionUpdate) -> Void)?
    private var streamingLanguage: String = "en"
    private let requiredSegmentsForConfirmation = 2

    init(modelInfo: STTModelInfo) {
        self.modelInfo = modelInfo
    }

    func loadModel(progressHandler: @escaping (Double) -> Void) async throws {
        NSLog("[WhisperKitEngine] Loading model '\(modelInfo.id)'")

        // Convert our model ID to WhisperKit's expected format
        // "whisper-small" -> "small", "whisper-large-v3-turbo" -> "large-v3-turbo"
        let whisperKitModel = modelInfo.id.replacingOccurrences(of: "whisper-", with: "")

        // Ensure the download cache directory exists
        let cacheURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        // Report indeterminate progress so the UI shows a spinner immediately
        progressHandler(0.0)

        // Use ANE for encoder/decoder — fastest inference on Apple Silicon.
        // First launch triggers ANE compilation (~2 min), but the ANE cache
        // persists across launches via CoreML's internal cache.
        // prewarm: true ensures compilation happens during load, not first transcribe.
        let computeOptions = ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine,
            prefillCompute: .cpuOnly
        )

        let config = WhisperKitConfig(
            model: whisperKitModel,
            computeOptions: computeOptions,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )

        // WhisperKit will auto-download the model if it doesn't exist
        // Retry once if download fails
        NSLog("[WhisperKitEngine] Downloading/compiling '\(whisperKitModel)' (this may take a few minutes on first use)...")
        do {
            pipe = try await WhisperKit(config)
        } catch {
            NSLog("[WhisperKitEngine] First attempt failed: \(error). Retrying after cleaning cache...")
            // Clean incomplete downloads
            let incompletePath = cacheURL.appendingPathComponent(".cache", isDirectory: true)
            try? FileManager.default.removeItem(at: incompletePath)
            // Retry
            pipe = try await WhisperKit(config)
        }

        progressHandler(1.0)
        NSLog("[WhisperKitEngine] Model '\(whisperKitModel)' loaded successfully")
    }

    func unloadModel() {
        pipe = nil
    }

    func warmup() async {
        guard let pipe = pipe else { return }
        do {
            // Transcribe 1 second of silence to keep ANE/GPU contexts warm
            let silenceBuffer = [Float](repeating: 0.0, count: 16000)
            let options = DecodingOptions(
                task: .transcribe,
                language: "en",
                temperature: 0.0,
                withoutTimestamps: true,
                suppressBlank: true,
                noSpeechThreshold: 0.6
            )
            _ = try await pipe.transcribe(audioArray: silenceBuffer, decodeOptions: options)
            NSLog("[WhisperKitEngine] Keep-alive warmup complete")
        } catch {
            NSLog("[WhisperKitEngine] Keep-alive warmup failed: \(error)")
        }
    }

    func transcribe(audioBuffer: AVAudioPCMBuffer, language: String = "en") async throws -> TranscriptionResult {
        guard let pipe = pipe else {
            throw YapYapError.modelNotLoaded
        }

        let startTime = Date()
        let floatArray = bufferToFloatArray(audioBuffer)

        // Enable timestamps for audio longer than 30s so the decoder properly
        // seeks through multiple windows. Without timestamps on long audio,
        // Whisper loses track and truncates the transcription.
        let audioDuration = Double(audioBuffer.frameLength) / 16000.0
        let needsTimestamps = audioDuration > 28.0

        // Map language code to Whisper's expected format (strip region suffixes like "en-GB" → "en")
        let whisperLang = language.components(separatedBy: "-").first ?? "en"
        NSLog("[WhisperKitEngine] Transcribing with language: \(whisperLang)")

        // Build vocabulary prompt from personal dictionary to bias decoder
        // toward user's expected terminology (e.g., names, technical terms)
        let vocabPrompt = VocabularyBooster.whisperPrompt(from: PersonalDictionary.shared)

        // Speed-optimized decoding options — no temperature fallback retries
        let options = DecodingOptions(
            task: .transcribe,
            language: whisperLang,
            temperature: 0.0,
            temperatureFallbackCount: 2,
            usePrefillPrompt: true,
            usePrefillCache: true,
            detectLanguage: false,
            withoutTimestamps: !needsTimestamps,
            wordTimestamps: false,
            promptTokens: vocabPrompt.flatMap { pipe.tokenizer?.encode(text: $0) },
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.6
        )

        let result = try await pipe.transcribe(audioArray: floatArray, decodeOptions: options)
        let processingTime = Date().timeIntervalSince(startTime)

        // For now, return simple transcription without detailed segments
        return TranscriptionResult(
            text: result.map { $0.text }.joined(separator: " "),
            language: result.first?.language ?? "en",
            segments: [],
            processingTime: processingTime
        )
    }

    // MARK: - Streaming STT

    func startStreaming(
        audioSamplesProvider: @escaping () -> [Float],
        language: String,
        onUpdate: @escaping (StreamingTranscriptionUpdate) -> Void
    ) async throws {
        guard pipe != nil else { throw YapYapError.modelNotLoaded }

        // Reset streaming state
        isStreaming = true
        lastBufferSize = 0
        lastConfirmedSegmentEndSeconds = 0
        confirmedSegments = []
        unconfirmedSegments = []
        audioProvider = audioSamplesProvider
        updateCallback = onUpdate
        streamingLanguage = language.components(separatedBy: "-").first ?? "en"

        NSLog("[WhisperKitEngine] Streaming started (language: \(streamingLanguage))")

        // Launch background transcription loop
        streamingTask = Task { [weak self] in
            while let self = self, self.isStreaming, !Task.isCancelled {
                do {
                    try await self.transcribeCurrentBuffer(isFinal: false)
                } catch {
                    NSLog("[WhisperKitEngine] Streaming loop error: \(error)")
                }
                // Small yield to avoid tight-looping; actual throttle is inside
                // transcribeCurrentBuffer (skips if <1s new audio)
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
    }

    func stopStreaming() async throws -> TranscriptionResult {
        let stopStart = Date()
        NSLog("[WhisperKitEngine] Stopping streaming...")

        // Signal the loop to stop
        isStreaming = false
        streamingTask?.cancel()
        streamingTask = nil

        // One final pass to catch tail-end audio
        try await transcribeCurrentBuffer(isFinal: true)

        // Promote all remaining unconfirmed → confirmed
        confirmedSegments.append(contentsOf: unconfirmedSegments)
        unconfirmedSegments = []

        // Build final text — Whisper segments often have leading spaces,
        // so join without separator and just trim
        let fullText = confirmedSegments.map { $0.text }.joined()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let processingTime = Date().timeIntervalSince(stopStart)

        NSLog("[WhisperKitEngine] Streaming finalized in \(String(format: "%.0f", processingTime * 1000))ms, segments: \(confirmedSegments.count)")

        let result = TranscriptionResult(
            text: fullText,
            language: streamingLanguage,
            segments: confirmedSegments.map {
                TranscriptionSegment(text: $0.text, start: TimeInterval($0.start), end: TimeInterval($0.end))
            },
            processingTime: processingTime
        )

        // Clean up
        audioProvider = nil
        updateCallback = nil
        confirmedSegments = []
        unconfirmedSegments = []
        lastBufferSize = 0
        lastConfirmedSegmentEndSeconds = 0

        return result
    }

    private func transcribeCurrentBuffer(isFinal: Bool) async throws {
        guard let pipe = pipe, let audioProvider = audioProvider else { return }

        let samples = audioProvider()
        let sampleCount = samples.count
        let newSamples = sampleCount - lastBufferSize

        // Skip if less than 1 second of new audio (unless finalizing)
        if !isFinal && newSamples < Int(16000) {
            return
        }

        // Skip if no audio at all
        guard sampleCount > 0 else { return }

        lastBufferSize = sampleCount

        // Speed-optimized options for streaming — fewer retries, timestamps enabled
        // clipTimestamps tells Whisper to only decode audio after the confirmed point
        // skipSpecialTokens strips <|startoftranscript|>, <|en|>, <|0.00|> etc. from output
        let options = DecodingOptions(
            task: .transcribe,
            language: streamingLanguage,
            temperature: 0.0,
            temperatureFallbackCount: 1,
            usePrefillPrompt: true,
            usePrefillCache: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: false,
            clipTimestamps: [lastConfirmedSegmentEndSeconds],
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.6
        )

        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)

        // Collect all segments from all result chunks, converting to local type.
        // Strip any Whisper special tokens that leak through (e.g. <|startoftranscript|>).
        let newSegments = results.flatMap { $0.segments }.map {
            StreamSegment(
                text: Self.stripSpecialTokens($0.text),
                start: $0.start,
                end: $0.end
            )
        }

        guard !newSegments.isEmpty else { return }

        if isFinal {
            // On final pass, everything is confirmed
            unconfirmedSegments = newSegments
        } else {
            // Segment confirmation: segments that have appeared consistently across
            // multiple iterations get promoted to "confirmed" and won't be re-processed.
            // Only the trailing segments remain "unconfirmed" (may change with more audio).
            let segmentCount = newSegments.count
            if segmentCount > requiredSegmentsForConfirmation {
                let confirmCount = segmentCount - requiredSegmentsForConfirmation
                let newlyConfirmed = Array(newSegments.prefix(confirmCount))
                confirmedSegments.append(contentsOf: newlyConfirmed)

                // Advance the seek point past confirmed audio
                if let lastConfirmed = newlyConfirmed.last {
                    lastConfirmedSegmentEndSeconds = lastConfirmed.end
                }

                unconfirmedSegments = Array(newSegments.suffix(requiredSegmentsForConfirmation))
            } else {
                unconfirmedSegments = newSegments
            }
        }

        // Publish update to UI — Whisper segments have leading spaces, join without separator
        let confirmedText = confirmedSegments.map { $0.text }.joined()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let unconfirmedText = unconfirmedSegments.map { $0.text }.joined()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let update = StreamingTranscriptionUpdate(
            confirmedText: confirmedText,
            unconfirmedText: unconfirmedText
        )

        let callback = self.updateCallback
        await MainActor.run {
            callback?(update)
        }

        NSLog("[WhisperKitEngine] Streaming: confirmed=\(confirmedSegments.count) unconfirmed=\(unconfirmedSegments.count) seek=\(String(format: "%.1f", lastConfirmedSegmentEndSeconds))s")
    }

    // MARK: - Helpers

    /// Strip Whisper special tokens like <|startoftranscript|>, <|en|>, <|0.00|>, <|endoftext|>
    private static func stripSpecialTokens(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
    }

    private func bufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }
}
