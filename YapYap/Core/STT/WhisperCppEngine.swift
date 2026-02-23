// WhisperCppEngine.swift
// YapYap — Placeholder for future Voxtral/whisper.cpp support
import AVFoundation

class WhisperCppEngine: STTEngine {
    let modelInfo: STTModelInfo
    private var isModelLoaded = false

    var isLoaded: Bool { isModelLoaded }

    init(modelInfo: STTModelInfo) {
        self.modelInfo = modelInfo
    }

    func loadModel(progressHandler: @escaping (Double) -> Void) async throws {
        // Voxtral requires a dedicated C bridge (voxtral.c) or vLLM.
        // This backend is not yet integrated.
        NSLog("[WhisperCppEngine] Voxtral/whisper.cpp backend not yet available")
        throw YapYapError.modelNotLoaded
    }

    func unloadModel() {
        isModelLoaded = false
    }

    func warmup() async {
        // No-op: backend not yet implemented
    }

    func transcribe(audioBuffer: AVAudioPCMBuffer, language: String = "en") async throws -> TranscriptionResult {
        throw YapYapError.modelNotLoaded
    }
}
