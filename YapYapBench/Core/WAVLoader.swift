// WAVLoader.swift
// YapYapBench — WAV file → 16kHz mono AVAudioPCMBuffer
import AVFoundation

struct WAVLoader {

    /// Load a WAV/AIFF/CAF file and convert to 16kHz mono float32 PCM buffer.
    /// This matches the format AudioCaptureManager produces for the STT engines.
    static func load(url: URL) throws -> (buffer: AVAudioPCMBuffer, duration: TimeInterval) {
        let audioFile = try AVAudioFile(forReading: url)
        let sourceFormat = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        // Target format: 16kHz, mono, float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw BenchError.audioFormatError("Failed to create target audio format")
        }

        // If source is already 16kHz mono, read directly
        if sourceFormat.sampleRate == 16000 && sourceFormat.channelCount == 1 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
                throw BenchError.audioFormatError("Failed to allocate buffer")
            }
            try audioFile.read(into: buffer)
            let duration = Double(buffer.frameLength) / sourceFormat.sampleRate
            return (buffer, duration)
        }

        // Read source audio
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw BenchError.audioFormatError("Failed to allocate source buffer")
        }
        try audioFile.read(into: sourceBuffer)

        // Convert to 16kHz mono
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw BenchError.audioFormatError("Failed to create audio converter from \(sourceFormat) to \(targetFormat)")
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else {
            throw BenchError.audioFormatError("Failed to allocate target buffer")
        }

        var conversionError: NSError?
        converter.convert(to: targetBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let error = conversionError {
            throw BenchError.audioFormatError("Audio conversion failed: \(error.localizedDescription)")
        }

        let duration = Double(targetBuffer.frameLength) / targetFormat.sampleRate
        return (targetBuffer, duration)
    }
}

enum BenchError: LocalizedError {
    case audioFormatError(String)
    case noWAVFiles(String)
    case sttFailed(String)
    case llmFailed(String)
    case invalidModel(String)
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .audioFormatError(let msg): return "Audio format error: \(msg)"
        case .noWAVFiles(let msg): return "No WAV files found: \(msg)"
        case .sttFailed(let msg): return "STT failed: \(msg)"
        case .llmFailed(let msg): return "LLM failed: \(msg)"
        case .invalidModel(let msg): return "Invalid model: \(msg)"
        case .recordingFailed(let msg): return "Recording failed: \(msg)"
        }
    }
}
