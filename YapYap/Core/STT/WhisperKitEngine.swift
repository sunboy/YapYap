// WhisperKitEngine.swift
// YapYap — WhisperKit STT backend for Whisper models
import WhisperKit
import AVFoundation

class WhisperKitEngine: STTEngine {
    let modelInfo: STTModelInfo
    private var pipe: WhisperKit?

    var isLoaded: Bool { pipe != nil }

    init(modelInfo: STTModelInfo) {
        self.modelInfo = modelInfo
    }

    func loadModel(progressHandler: @escaping (Double) -> Void) async throws {
        print("[WhisperKitEngine] Loading model '\(modelInfo.id)'")

        // Convert our model ID to WhisperKit's expected format
        // "whisper-small" -> "small", "whisper-large-v3-turbo" -> "large-v3-turbo"
        let whisperKitModel = modelInfo.id.replacingOccurrences(of: "whisper-", with: "")

        // Ensure the download cache directory exists
        let cacheURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

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
        do {
            pipe = try await WhisperKit(config)
        } catch {
            print("[WhisperKitEngine] First attempt failed: \(error). Retrying after cleaning cache...")
            // Clean incomplete downloads
            let incompletePath = cacheURL.appendingPathComponent(".cache", isDirectory: true)
            try? FileManager.default.removeItem(at: incompletePath)
            // Retry
            pipe = try await WhisperKit(config)
        }

        progressHandler(1.0)
        print("[WhisperKitEngine] Model '\(whisperKitModel)' loaded successfully")
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

    private func bufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }
}
