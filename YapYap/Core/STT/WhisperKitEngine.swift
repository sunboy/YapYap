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
    private var audioSampleCountProvider: (() -> Int)?
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

        // ~/Library/Application Support/YapYap/models/whisperkit/
        // Application Support is never touched by iCloud, so large mlmodelc blobs
        // are never evicted. Accessing evicted iCloud files causes stat() to hang
        // indefinitely as the FileProvider tries to re-materialize them.
        let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("YapYap/models/whisperkit", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        // Report indeterminate progress so the UI shows a spinner immediately
        progressHandler(0.0)

        // Use GPU for encoder/decoder — avoids ANE compilation which can take 5-10+ min
        // on first launch or after code signature changes (dev.sh build cycles).
        // ANE is faster at runtime but requires a one-time compilation step per signature.
        // GPU (Metal) loads instantly and gives good performance for development.
        let computeOptions = ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndGPU,
            textDecoderCompute: .cpuAndGPU,
            prefillCompute: .cpuOnly
        )

        // Check if the model is already downloaded locally.
        // HubApi (used by WhisperKit) stores models at {downloadBase}/models/argmaxinc/whisperkit-coreml/
        // So we search there first, then fall back to the root cacheURL (legacy flat layout).
        let hubApiSubdir = cacheURL.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
        let localFolder = findLocalWhisperFolder(variant: whisperKitModel, in: hubApiSubdir)
            ?? findLocalWhisperFolder(variant: whisperKitModel, in: cacheURL)
        let isLocallyAvailable = localFolder != nil
        NSLog("[WhisperKitEngine] Model locally available: \(isLocallyAvailable) → \(isLocallyAvailable ? "offline mode (no HF network call)" : "online mode (will download)")")

        let config: WhisperKitConfig
        if let folder = localFolder {
            // Offline mode: load directly from local path, no HF metadata call.
            // prewarm: false — WhisperKit's prewarm triggers synchronous Metal/ANE shader
            // compilation inside WhisperKit(config), which can take 2-10 min on first use
            // of a new model folder. The existing warmup() call in TranscriptionPipeline
            // handles the actual warm-up after load, which compiles shaders lazily.
            //
            // CRITICAL: downloadBase must be set even in offline mode.
            // WhisperKit sets tokenizerFolder = config.tokenizerFolder ?? config.downloadBase.
            // Without downloadBase, tokenizerFolder is nil and HubApi defaults to
            // ~/Documents/huggingface — which is iCloud-backed and can hang in read()
            // indefinitely while iCloud FileProvider tries to re-materialize evicted files.
            // By passing downloadBase: cacheURL, the tokenizer is resolved from App Support
            // at {cacheURL}/models/openai/whisper-{variant}/ which is never iCloud-evicted.
            config = WhisperKitConfig(
                downloadBase: cacheURL,
                modelFolder: folder.path,
                computeOptions: computeOptions,
                verbose: false,
                prewarm: false,
                load: true,
                download: false
            )
        } else {
            // Online mode: download from HuggingFace into cacheURL (App Support).
            // downloadBase must be explicit — without it WhisperKit defaults to
            // ~/Documents/huggingface which is iCloud-synced and causes eviction hangs.
            config = WhisperKitConfig(
                model: whisperKitModel,
                downloadBase: cacheURL,
                computeOptions: computeOptions,
                verbose: false,
                prewarm: false,
                load: true,
                download: true
            )
        }

        // WhisperKit will auto-download the model if it doesn't exist.
        // verbose: false suppresses WhisperKit's internal logging — no need for
        // StderrSuppressor (which dup2()/fd redirects can interfere with NSLog on
        // other threads when WhisperKit suspends across cooperative concurrency hops).
        // Retry once if download fails.
        NSLog("[WhisperKitEngine] Initializing WhisperKit for '\(whisperKitModel)'...")
        do {
            pipe = try await WhisperKit(config)
        } catch {
            NSLog("[WhisperKitEngine] First attempt failed: \(error). Retrying after cleaning cache...")
            // Clean incomplete downloads and retry with online mode
            let incompletePath = cacheURL.appendingPathComponent(".cache", isDirectory: true)
            try? FileManager.default.removeItem(at: incompletePath)
            let retryConfig = WhisperKitConfig(
                model: whisperKitModel,
                downloadBase: cacheURL,
                computeOptions: computeOptions,
                verbose: false,
                prewarm: true,
                load: true,
                download: true
            )
            pipe = try await WhisperKit(retryConfig)
        }

        progressHandler(1.0)
        NSLog("[WhisperKitEngine] Model '\(whisperKitModel)' loaded successfully")
    }

    /// Find a locally cached WhisperKit model folder for the given variant.
    /// WhisperKit uses folder names like "openai_whisper-small" or "openai_whisper-small_216MB".
    /// Returns the folder with the most files (largest/most complete download) if multiple exist.
    private func findLocalWhisperFolder(variant: String, in cacheDir: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        // Match folders that start with "openai_whisper-{variant}" (exact prefix, not partial)
        let prefix = "openai_whisper-\(variant)"
        let candidates = contents.filter { url in
            let name = url.lastPathComponent.lowercased()
            let targetPrefix = prefix.lowercased()
            // Must start with the exact prefix, followed by end-of-string, "_", or a digit
            guard name.hasPrefix(targetPrefix) else { return false }
            let remainder = name.dropFirst(targetPrefix.count)
            return remainder.isEmpty || remainder.hasPrefix("_") || remainder.first?.isNumber == true
        }

        guard !candidates.isEmpty else { return nil }

        // Keep only folders that have all required model files (complete downloads)
        let requiredFiles = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"]
        let complete = candidates.filter { url in
            requiredFiles.allSatisfy { file in
                FileManager.default.fileExists(atPath: url.appendingPathComponent(file).path)
            }
        }
        let pool = complete.isEmpty ? candidates : complete

        // WhisperKit prefers quantized variants (e.g. "_216MB") over unquantized base folders.
        // Sort: folders with size suffix (quantized) before plain name (unquantized).
        let sorted = pool.sorted { a, b in
            let aHasSuffix = a.lastPathComponent.contains("_") && a.lastPathComponent.last?.isNumber == true
            let bHasSuffix = b.lastPathComponent.contains("_") && b.lastPathComponent.last?.isNumber == true
            if aHasSuffix != bHasSuffix { return aHasSuffix }
            // Among same type, prefer longer name (more specific variant)
            return a.lastPathComponent.count > b.lastPathComponent.count
        }

        return sorted.first
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
        audioSampleCountProvider: (() -> Int)? = nil,
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
        self.audioSampleCountProvider = audioSampleCountProvider
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
        audioSampleCountProvider = nil
        updateCallback = nil
        confirmedSegments = []
        unconfirmedSegments = []
        lastBufferSize = 0
        lastConfirmedSegmentEndSeconds = 0

        return result
    }

    private func transcribeCurrentBuffer(isFinal: Bool) async throws {
        guard let pipe = pipe, let audioProvider = audioProvider else { return }

        // Check sample count first via the lightweight accessor to avoid
        // a full array copy when we're just going to skip transcription.
        let sampleCount = audioSampleCountProvider?() ?? 0
        let newSamples = sampleCount - lastBufferSize

        // Skip if less than 0.3 seconds of new audio (unless finalizing).
        // Previous 1s threshold added perceptible latency for short utterances.
        if !isFinal && newSamples < Int(4800) {
            return
        }

        // Skip if no audio at all
        guard sampleCount > 0 else { return }

        // Only now fetch the full sample array for actual transcription
        let samples = audioProvider()
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
