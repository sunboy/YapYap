// AudioCaptureManager.swift
// YapYap — Audio capture via AVAudioEngine
import AVFoundation
import Combine

@Observable
class AudioCaptureManager {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: AVAudioPCMBuffer?
    private var accumulatedFrames: [Float] = []
    private var rmsCallback: ((Float) -> Void)?

    let sampleRate: Double = 16000
    let channelCount: AVAudioChannelCount = 1
    let bufferSize: AVAudioFrameCount = 1024

    var isCapturing: Bool = false

    // MARK: - Microphone Permission

    static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static var hasMicrophonePermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // MARK: - Available Microphones

    static func availableMicrophones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    // MARK: - Capture

    func startCapture(microphoneId: String? = nil, rmsHandler: @escaping (Float) -> Void) async throws {
        guard !isCapturing else { return }
        guard Self.hasMicrophonePermission else {
            throw YapYapError.microphonePermissionDenied
        }

        accumulatedFrames = []
        rmsCallback = rmsHandler

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono Float32
        guard let convertFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw YapYapError.audioCaptureFailed(
                NSError(domain: "YapYap", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"])
            )
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: convertFormat) else {
            throw YapYapError.audioCaptureFailed(
                NSError(domain: "YapYap", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
            )
        }

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * self.sampleRate / buffer.format.sampleRate
            )
            guard frameCount > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: convertFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else { return }

            // Accumulate frames
            if let channelData = convertedBuffer.floatChannelData?[0] {
                let frames = Array(UnsafeBufferPointer(start: channelData, count: Int(convertedBuffer.frameLength)))
                self.accumulatedFrames.append(contentsOf: frames)

                // Calculate RMS for waveform visualization
                let rms = Self.calculateRMS(frames)
                DispatchQueue.main.async {
                    self.rmsCallback?(rms)
                }
            }
        }

        try engine.start()
        audioEngine = engine
        isCapturing = true
    }

    func stopCapture() -> AVAudioPCMBuffer? {
        guard isCapturing, let engine = audioEngine else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        audioEngine = nil

        // Create final buffer from accumulated frames
        guard !accumulatedFrames.isEmpty else { return nil }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else { return nil }

        let frameCount = AVAudioFrameCount(accumulatedFrames.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<accumulatedFrames.count {
                channelData[i] = accumulatedFrames[i]
            }
        }

        accumulatedFrames = []
        return buffer
    }

    func cancelCapture() {
        guard isCapturing, let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        audioEngine = nil
        accumulatedFrames = []
    }

    // MARK: - RMS Calculation

    static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}
