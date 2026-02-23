// WAVRecorder.swift
// YapYapBench — Record from microphone to WAV file
import AVFoundation

class WAVRecorder {
    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?

    /// Record from the default input device to a WAV file.
    /// Blocks until the user presses Enter.
    func record(to url: URL) throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target: 16kHz mono (matches STT pipeline input)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw BenchError.recordingFailed("Failed to create target format")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw BenchError.recordingFailed("Failed to create audio converter")
        }

        // Create WAV output file at 16kHz mono
        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        outputFile = try AVAudioFile(forWriting: url, settings: wavSettings)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let outFile = self.outputFile else { return }

            let ratio = 16000.0 / inputFormat.sampleRate
            let targetFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil && convertedBuffer.frameLength > 0 {
                try? outFile.write(from: convertedBuffer)
            }
        }

        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        outputFile = nil
    }
}
