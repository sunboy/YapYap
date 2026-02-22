// FluidAudioEngine.swift
// YapYap — FluidAudio/Parakeet TDT STT backend
import FluidAudio
import AVFoundation
import CoreML

class FluidAudioEngine: STTEngine {
    let modelInfo: STTModelInfo
    private var asrManager: AsrManager?

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
            // Buffer is zero-initialized by default (silence)
            _ = try await asrManager.transcribe(silenceBuffer, source: .microphone)
            NSLog("[FluidAudioEngine] Keep-alive warmup complete")
        } catch {
            NSLog("[FluidAudioEngine] Keep-alive warmup failed: \(error)")
        }
    }

    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        guard let asrManager = asrManager else {
            throw YapYapError.modelNotLoaded
        }

        let startTime = Date()

        // Transcribe using the audio buffer directly
        let result = try await asrManager.transcribe(audioBuffer, source: .microphone)

        let processingTime = Date().timeIntervalSince(startTime)

        return TranscriptionResult(
            text: result.text,
            language: "en", // FluidAudio doesn't expose language detection yet
            segments: [],   // Simplified for now - can add segment support later
            processingTime: processingTime
        )
    }
}
