// STTEngine.swift
// YapYap — Speech-to-text engine protocol
import AVFoundation

struct TranscriptionResult {
    let text: String
    let language: String?
    let segments: [TranscriptionSegment]
    let processingTime: TimeInterval
}

struct TranscriptionSegment {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct STTModelInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let backend: STTBackend
    let sizeBytes: Int64
    let sizeDescription: String
    let languages: [String]
    let description: String
    let isRecommended: Bool

    static func == (lhs: STTModelInfo, rhs: STTModelInfo) -> Bool {
        lhs.id == rhs.id
    }
}

enum STTBackend: String, Codable {
    case whisperKit
    case fluidAudio
    case whisperCpp
}

protocol STTEngine: AnyObject {
    var modelInfo: STTModelInfo { get }
    var isLoaded: Bool { get }
    func loadModel(progressHandler: @escaping (Double) -> Void) async throws
    func unloadModel()
    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> TranscriptionResult
    /// Run a minimal inference to keep model weights resident in memory
    func warmup() async
}
