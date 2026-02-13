// WhisperCppEngine.swift
// YapYap — whisper.cpp bridge for Voxtral/GGML models
import AVFoundation

class WhisperCppEngine: STTEngine {
    let modelInfo: STTModelInfo
    private var isModelLoaded = false

    var isLoaded: Bool { isModelLoaded }

    init(modelInfo: STTModelInfo) {
        self.modelInfo = modelInfo
    }

    func loadModel(progressHandler: @escaping (Double) -> Void) async throws {
        let modelPath = ModelStorage.shared.path(for: modelInfo.id, type: .stt)

        // TODO: Initialize whisper.cpp context with model file
        // let ctx = whisper_init_from_file(modelPath.path)

        // Verify model file exists
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw YapYapError.modelNotLoaded
        }

        isModelLoaded = true
        progressHandler(1.0)
    }

    func unloadModel() {
        // TODO: whisper_free(ctx)
        isModelLoaded = false
    }

    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        guard isModelLoaded else {
            throw YapYapError.modelNotLoaded
        }

        let startTime = Date()
        let floatArray = bufferToFloatArray(audioBuffer)

        // TODO: Full whisper.cpp integration
        // For now, return a placeholder result
        // In production, this would use the whisper.cpp C API via a Swift bridge:
        //
        // var params = whisper_full_default_params(.greedy)
        // params.language = "auto"
        // params.no_timestamps = true
        // params.suppress_blank = true
        // params.temperature = 0.0
        // params.entropy_thold = 2.4
        // params.logprob_thold = -0.8
        // params.no_speech_thold = 0.5
        //
        // whisper_full(ctx, params, floatArray, Int32(floatArray.count))
        // let nSegments = whisper_full_n_segments(ctx)
        // var text = ""
        // for i in 0..<nSegments {
        //     text += String(cString: whisper_full_get_segment_text(ctx, i))
        // }

        let processingTime = Date().timeIntervalSince(startTime)

        return TranscriptionResult(
            text: "[whisper.cpp backend not yet integrated — install whisper.cpp and rebuild]",
            language: nil,
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
