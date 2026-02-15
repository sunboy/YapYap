// AudioCaptureManager.swift
// YapYap — Audio capture via AVAudioEngine
import AVFoundation
import Combine

@Observable
class AudioCaptureManager {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: AVAudioPCMBuffer?
    private var accumulatedFrames: [Float] = []
    private let audioLock = NSLock()
    private var rmsCallback: ((Float) -> Void)?
    private var converter: AVAudioConverter?
    private var convertFormat: AVAudioFormat?

    let sampleRate: Double = 16000
    let channelCount: AVAudioChannelCount = 1
    let bufferSize: AVAudioFrameCount = 1024

    /// No minimum recording duration — the app should transcribe any length

    var isCapturing: Bool = false
    private(set) var isEngineWarmed: Bool = false

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

    // MARK: - Engine Pre-warming

    /// Pre-warm the audio engine at app startup so recording starts instantly.
    /// This creates the engine, configures the converter, but does NOT install a tap yet.
    func warmUp() {
        guard !isEngineWarmed else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        NSLog("[AudioCaptureManager] Warm-up: input format \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        // Pre-create the target format and converter
        let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )
        self.convertFormat = fmt

        if let fmt = fmt {
            self.converter = AVAudioConverter(from: inputFormat, to: fmt)
        }

        self.audioEngine = engine
        self.isEngineWarmed = true
        NSLog("[AudioCaptureManager] Engine pre-warmed")
    }

    // MARK: - Capture

    func startCapture(microphoneId: String? = nil, rmsHandler: @escaping (Float) -> Void) async throws {
        // If already capturing, stop first to avoid tap conflicts
        if isCapturing {
            NSLog("[AudioCaptureManager] Already capturing, stopping first")
            _ = stopCapture()
        }

        var status = AVCaptureDevice.authorizationStatus(for: .audio)
        NSLog("[AudioCaptureManager] Microphone permission status=\(status.rawValue)")

        // If not determined, request permission inline
        if status == .notDetermined {
            NSLog("[AudioCaptureManager] Requesting microphone permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            status = AVCaptureDevice.authorizationStatus(for: .audio)
            NSLog("[AudioCaptureManager] Permission result: granted=\(granted), status=\(status.rawValue)")
        }

        guard status == .authorized else {
            NSLog("[AudioCaptureManager] ERROR: Microphone permission denied (status=\(status.rawValue))")
            throw YapYapError.microphonePermissionDenied
        }

        audioLock.lock()
        accumulatedFrames = []
        // Pre-allocate for ~30 seconds of audio at 16kHz to reduce reallocations
        accumulatedFrames.reserveCapacity(Int(sampleRate) * 30)
        audioLock.unlock()
        rmsCallback = rmsHandler

        // Always create a fresh engine to avoid stale tap state
        let engine = AVAudioEngine()
        self.audioEngine = engine
        self.isEngineWarmed = false

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create converter for this engine's input format
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw YapYapError.audioCaptureFailed(
                NSError(domain: "YapYap", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"])
            )
        }
        let targetFormat = fmt
        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw YapYapError.audioCaptureFailed(
                NSError(domain: "YapYap", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
            )
        }
        self.convertFormat = targetFormat
        self.converter = conv

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * self.sampleRate / buffer.format.sampleRate
            )
            guard frameCount > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            let convStatus = conv.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard convStatus != .error, error == nil else { return }

            if let channelData = convertedBuffer.floatChannelData?[0] {
                let count = Int(convertedBuffer.frameLength)
                let bufferPointer = UnsafeBufferPointer(start: channelData, count: count)

                self.audioLock.lock()
                self.accumulatedFrames.append(contentsOf: bufferPointer)
                self.audioLock.unlock()

                let rms = Self.calculateRMSFromPointer(bufferPointer)
                DispatchQueue.main.async {
                    self.rmsCallback?(rms)
                }
            }
        }

        try engine.start()
        isCapturing = true
        NSLog("[AudioCaptureManager] Capture started")
    }

    func stopCapture() -> AVAudioPCMBuffer? {
        guard let engine = audioEngine else { return nil }

        // Always clean up tap and engine, even if isCapturing is false
        // (handles race condition where stop is called before start finishes)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false

        // Thread-safe read of accumulated frames
        audioLock.lock()
        let frames = accumulatedFrames
        accumulatedFrames = []
        audioLock.unlock()

        guard !frames.isEmpty else {
            NSLog("[AudioCaptureManager] No frames captured")
            return nil
        }

        let duration = Double(frames.count) / sampleRate
        NSLog("[AudioCaptureManager] Captured \(frames.count) frames (\(String(format: "%.1f", duration))s)")

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else { return nil }

        let frameCount = AVAudioFrameCount(frames.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData?[0] {
            frames.withUnsafeBufferPointer { ptr in
                channelData.update(from: ptr.baseAddress!, count: frames.count)
            }
        }

        // Re-warm engine for next use
        reWarm()

        return buffer
    }

    func cancelCapture() {
        guard let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false

        audioLock.lock()
        accumulatedFrames = []
        audioLock.unlock()

        // Re-warm engine for next use
        reWarm()
    }

    /// Re-create engine after stopping so it's ready for the next recording
    private func reWarm() {
        isEngineWarmed = false
        audioEngine = nil
        converter = nil
        convertFormat = nil
        // Warm up asynchronously to not block the caller
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.warmUp()
        }
    }

    // MARK: - RMS Calculation

    static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }

    /// RMS from UnsafeBufferPointer — avoids Array allocation in audio tap callback
    static func calculateRMSFromPointer(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumOfSquares: Float = 0.0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}
