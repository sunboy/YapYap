// FluidAudioEngine.swift
// YapYap — FluidAudio/Parakeet TDT STT backend
import FluidAudio
import AVFoundation

class FluidAudioEngine: STTEngine {
    let modelInfo: STTModelInfo
    private var recognizer: FluidRecognizer?

    var isLoaded: Bool { recognizer != nil }

    init(modelInfo: STTModelInfo) {
        self.modelInfo = modelInfo
    }

    func loadModel(progressHandler: @escaping (Double) -> Void) async throws {
        let modelPath = ModelStorage.shared.path(for: modelInfo.id, type: .stt)
        recognizer = try FluidRecognizer(modelPath: modelPath.path)
        progressHandler(1.0)
    }

    func unloadModel() {
        recognizer = nil
    }

    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        guard let recognizer = recognizer else {
            throw YapYapError.modelNotLoaded
        }

        let startTime = Date()
        let floatArray = bufferToFloatArray(audioBuffer)

        let result = try await recognizer.transcribe(
            audioSamples: floatArray,
            sampleRate: Int(audioBuffer.format.sampleRate)
        )

        let processingTime = Date().timeIntervalSince(startTime)

        return TranscriptionResult(
            text: result.text,
            language: result.language,
            segments: result.segments?.map { seg in
                TranscriptionSegment(
                    text: seg.text,
                    start: seg.startTime,
                    end: seg.endTime
                )
            } ?? [],
            processingTime: processingTime
        )
    }

    private func bufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }
}
