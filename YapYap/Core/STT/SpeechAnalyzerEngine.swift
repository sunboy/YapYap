// SpeechAnalyzerEngine.swift
// YapYap — Apple SpeechAnalyzer STT backend (macOS 26+)
// Zero-setup, fastest option — uses Apple's on-device Neural Engine model.
// Trade-off: ~8% WER vs Whisper's ~1%, but 2x faster and no model download.
//
// SpeechTranscriber/AssetInventory/AnalyzerInput are macOS 26 SDK only (Swift 6.2+).
// Wrap entire implementation so it compiles cleanly on Xcode 16 / macOS 15 runners.

import AVFoundation

#if compiler(>=6.2)
import Speech

@available(macOS 26, *)
class SpeechAnalyzerEngine: STTEngine {
    let modelInfo: STTModelInfo
    private var isReady = false

    var isLoaded: Bool { isReady }

    init(modelInfo: STTModelInfo) {
        self.modelInfo = modelInfo
    }

    func loadModel(progressHandler: @escaping (Double) -> Void) async throws {
        // Request speech recognition authorization
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard status == .authorized else {
            throw YapYapError.transcriptionFailed(
                NSError(domain: "SpeechAnalyzer", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied"])
            )
        }

        // Create a probe transcriber to check locale support and trigger model download
        let locale = Locale(identifier: "en-US")
        let probe = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // Download the on-device model if needed
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
            NSLog("[SpeechAnalyzerEngine] Downloading speech model...")
            progressHandler(0.3)
            try await request.downloadAndInstall()
        }

        // Reserve the locale so the model stays available
        try await AssetInventory.reserve(locale: locale)

        isReady = true
        progressHandler(1.0)
        NSLog("[SpeechAnalyzerEngine] Ready")
    }

    func unloadModel() {
        isReady = false
    }

    func warmup() async {
        // System framework manages its own caching — no warmup needed
    }

    func transcribe(audioBuffer: AVAudioPCMBuffer, language: String) async throws -> TranscriptionResult {
        guard isReady else {
            throw YapYapError.modelNotLoaded
        }

        let startTime = Date()

        // Use SpeechTranscriber (not DictationTranscriber) to get raw text
        // without auto-punctuation — YapYap's LLM handles formatting
        let locale = Locale(identifier: language)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Get the optimal audio format for the analyzer
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw YapYapError.transcriptionFailed(
                NSError(domain: "SpeechAnalyzer", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "No compatible audio format"])
            )
        }

        // Convert buffer to analyzer's preferred format if needed
        let inputBuffer: AVAudioPCMBuffer
        if audioBuffer.format == analyzerFormat {
            inputBuffer = audioBuffer
        } else {
            guard let converter = AVAudioConverter(from: audioBuffer.format, to: analyzerFormat),
                  let converted = AVAudioPCMBuffer(
                    pcmFormat: analyzerFormat,
                    frameCapacity: AVAudioFrameCount(
                        Double(audioBuffer.frameLength) * analyzerFormat.sampleRate / audioBuffer.format.sampleRate
                    )
                  ) else {
                throw YapYapError.transcriptionFailed(
                    NSError(domain: "SpeechAnalyzer", code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "Audio format conversion failed"])
                )
            }
            try converter.convert(to: converted, from: audioBuffer)
            inputBuffer = converted
        }

        // Create async stream to feed audio to the analyzer
        let (inputStream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        // Feed the entire buffer as a single chunk then finish
        continuation.yield(AnalyzerInput(buffer: inputBuffer))
        continuation.finish()

        // Start collecting results in a task before we begin analysis
        let resultsTask = Task<String, Error> {
            var accumulated = AttributedString("")
            for try await result in transcriber.results {
                accumulated.append(result.text)
            }
            return String(accumulated.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Start the analyzer with our input stream
        try await analyzer.start(inputSequence: inputStream)

        // Signal end of audio and wait for finalization
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        // Wait for all results to be collected
        let plainText = try await resultsTask.value

        let processingTime = Date().timeIntervalSince(startTime)

        NSLog("[SpeechAnalyzerEngine] Transcribed in %.0fms: %d chars",
              processingTime * 1000, plainText.count)

        return TranscriptionResult(
            text: plainText,
            language: language,
            segments: [],
            processingTime: processingTime
        )
    }
}
#endif
