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
        let modelPath = ModelStorage.shared.path(for: modelInfo.id, type: .stt)
        let config = WhisperKitConfig(
            model: modelInfo.id,
            modelFolder: modelPath.path
        )
        pipe = try await WhisperKit(config)
        progressHandler(1.0)
    }

    func unloadModel() {
        pipe = nil
    }

    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        guard let pipe = pipe else {
            throw YapYapError.modelNotLoaded
        }

        let startTime = Date()
        let floatArray = bufferToFloatArray(audioBuffer)

        // YapYap-optimized decoding options for robust dictation
        let options = DecodingOptions(
            task: .transcribe,
            temperature: 0.0,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            usePrefillCache: true,
            detectLanguage: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -0.8,
            firstTokenLogProbThreshold: -1.0,
            noSpeechThreshold: 0.5
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
