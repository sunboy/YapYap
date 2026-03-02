// FluidAudioEngine.swift
// YapYap — FluidAudio/Parakeet TDT STT backend with streaming support
import FluidAudio
import AVFoundation
import CoreML

class FluidAudioEngine: STTEngine, StreamingSTTEngine {
    let modelInfo: STTModelInfo
    private var asrManager: AsrManager?

    // MARK: - Streaming State

    private(set) var isStreaming: Bool = false
    private var streamingTask: Task<Void, Never>?
    private var audioProvider: (() -> [Float])?
    private var audioSampleCountProvider: (() -> Int)?
    private var updateCallback: ((StreamingTranscriptionUpdate) -> Void)?
    private var lastTranscribedSampleCount: Int = 0
    private var lastTranscribedText: String = ""

    var isLoaded: Bool { asrManager != nil }

    init(modelInfo: STTModelInfo) {
        self.modelInfo = modelInfo
    }

    func loadModel(progressHandler: @escaping (Double) -> Void) async throws {
        let modelPath = ModelStorage.shared.path(for: modelInfo.id, type: .stt)

        print("[FluidAudioEngine] Loading model '\(modelInfo.id)' from path: \(modelPath.path)")

        // Load the models from the model directory
        let models = try await AsrModels.load(from: modelPath)

        // Initialize AsrManager with default config
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)

        asrManager = manager
        progressHandler(1.0)

        print("[FluidAudioEngine] Model '\(modelInfo.id)' loaded successfully")
    }

    func unloadModel() {
        asrManager?.cleanup()
        asrManager = nil
    }

    func warmup() async {
        guard let asrManager = asrManager else { return }
        do {
            // Create a 1-second silence buffer at 16kHz to keep model warm
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            let frameCount = AVAudioFrameCount(16000)
            guard let silenceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
            silenceBuffer.frameLength = frameCount
            _ = try await asrManager.transcribe(silenceBuffer, source: .microphone)
            NSLog("[FluidAudioEngine] Keep-alive warmup complete")
        } catch {
            NSLog("[FluidAudioEngine] Keep-alive warmup failed: \(error)")
        }
    }

    func transcribe(audioBuffer: AVAudioPCMBuffer, language: String = "en") async throws -> TranscriptionResult {
        guard let asrManager = asrManager else {
            throw YapYapError.modelNotLoaded
        }

        let startTime = Date()
        let result = try await asrManager.transcribe(audioBuffer, source: .microphone)
        let processingTime = Date().timeIntervalSince(startTime)

        return TranscriptionResult(
            text: result.text,
            language: "en",
            segments: [],
            processingTime: processingTime
        )
    }

    // MARK: - Streaming STT
    //
    // Uses a lightweight polling approach: periodically runs batch transcription
    // on accumulated audio using the already-loaded AsrManager. This avoids
    // creating a new StreamingAsrManager (which re-initializes ASR models each
    // dictation, causing memory pressure that evicts LLM weights from RAM).

    func startStreaming(
        audioSamplesProvider: @escaping () -> [Float],
        audioSampleCountProvider: (() -> Int)? = nil,
        language: String,
        onUpdate: @escaping (StreamingTranscriptionUpdate) -> Void
    ) async throws {
        guard asrManager != nil else { throw YapYapError.modelNotLoaded }

        isStreaming = true
        lastTranscribedSampleCount = 0
        lastTranscribedText = ""
        audioProvider = audioSamplesProvider
        self.audioSampleCountProvider = audioSampleCountProvider
        updateCallback = onUpdate

        NSLog("[FluidAudioEngine] Streaming started (poll-based, reusing loaded AsrManager)")

        // Poll audio buffer every ~300ms and run batch transcription for partial results.
        // Previous 2s interval caused perceptible latency for short utterances.
        streamingTask = Task { [weak self] in
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            ) else { return }

            while let self = self, self.isStreaming, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                guard self.isStreaming, !Task.isCancelled else { break }

                guard let provider = self.audioProvider,
                      let asr = self.asrManager else { break }

                // Use lightweight count check to avoid full array copy when skipping
                let sampleCount = self.audioSampleCountProvider?() ?? 0

                // Need at least 0.5s of audio and 0.3s of new audio since last run.
                // Previous thresholds (1.5s total, 0.5s new) caused excessive latency.
                guard sampleCount >= 8000,
                      sampleCount - self.lastTranscribedSampleCount >= 4800 else { continue }

                // Only fetch full sample array when we're actually going to transcribe
                let allSamples = provider()

                // Convert [Float] to AVAudioPCMBuffer
                let frameCount = AVAudioFrameCount(allSamples.count)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { continue }
                buffer.frameLength = frameCount
                if let channelData = buffer.floatChannelData?[0] {
                    allSamples.withUnsafeBufferPointer { src in
                        channelData.initialize(from: src.baseAddress!, count: allSamples.count)
                    }
                }

                // Run batch transcription on accumulated audio
                do {
                    let result = try await asr.transcribe(buffer, source: .microphone)
                    self.lastTranscribedSampleCount = sampleCount
                    self.lastTranscribedText = result.text

                    let update = StreamingTranscriptionUpdate(
                        confirmedText: "",
                        unconfirmedText: result.text
                    )
                    let callback = self.updateCallback
                    await MainActor.run {
                        callback?(update)
                    }
                } catch {
                    NSLog("[FluidAudioEngine] Streaming poll error: \(error)")
                }
            }
        }
    }

    func stopStreaming() async throws -> TranscriptionResult {
        NSLog("[FluidAudioEngine] Stopping streaming...")

        isStreaming = false
        streamingTask?.cancel()
        streamingTask = nil

        // Clean up — final transcription is handled by the batch path in
        // TranscriptionPipeline (stopRecordingAndProcess runs on the full buffer)
        let text = lastTranscribedText
        audioProvider = nil
        audioSampleCountProvider = nil
        updateCallback = nil
        lastTranscribedSampleCount = 0
        lastTranscribedText = ""

        NSLog("[FluidAudioEngine] Streaming stopped")

        return TranscriptionResult(
            text: text,
            language: "en",
            segments: [],
            processingTime: 0
        )
    }
}
