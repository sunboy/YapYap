// AudioCaptureManager.swift
// YapYap — Audio capture via AVAudioEngine
import AVFoundation
import Combine
import CoreAudio

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

    // MARK: - Engine Recovery

    private var consecutiveErrors: Int = 0
    private let maxConsecutiveErrors = 10
    var onEngineFailure: (() -> Void)?

    /// Callback when the default audio device changes (mic plugged/unplugged)
    var onDeviceChanged: (() -> Void)?
    private var deviceChangeListenerRegistered = false

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

    // MARK: - Device Selection

    /// Set a specific audio input device on the engine by CoreAudio device ID.
    /// Returns true if the device was set, false if the device wasn't found.
    private func setInputDevice(_ microphoneId: String, on engine: AVAudioEngine) -> Bool {
        // Find the CoreAudio device matching the AVCaptureDevice unique ID
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddress, 0, nil, &dataSize) == noErr else {
            return false
        }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddress, 0, nil, &dataSize, &devices) == noErr else {
            return false
        }

        for deviceID in devices {
            // Get the device UID to match against AVCaptureDevice.uniqueID
            var uidPropAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(deviceID, &uidPropAddress, 0, nil, &uidSize, &uid) == noErr else {
                continue
            }
            if (uid as String) == microphoneId {
                // Check if this device has input channels
                var inputPropAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyStreamConfiguration,
                    mScope: kAudioObjectPropertyScopeInput,
                    mElement: kAudioObjectPropertyElementMain
                )
                var inputSize: UInt32 = 0
                guard AudioObjectGetPropertyDataSize(deviceID, &inputPropAddress, 0, nil, &inputSize) == noErr,
                      inputSize > 0 else {
                    continue
                }

                // Set this device as the engine's input
                var deviceIDValue = deviceID
                let status = AudioUnitSetProperty(
                    engine.inputNode.audioUnit!,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &deviceIDValue,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if status == noErr {
                    NSLog("[AudioCaptureManager] Set input device: %@ (ID: %d)", microphoneId, deviceID)
                    return true
                } else {
                    NSLog("[AudioCaptureManager] Failed to set input device: OSStatus %d", status)
                    return false
                }
            }
        }
        NSLog("[AudioCaptureManager] Device not found: %@, using system default", microphoneId)
        return false
    }

    // MARK: - Device Change Monitoring

    /// Start listening for default audio input device changes.
    func startDeviceChangeMonitoring() {
        guard !deviceChangeListenerRegistered else { return }

        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            NSLog("[AudioCaptureManager] Default input device changed")
            self?.onDeviceChanged?()
        }

        if status == noErr {
            deviceChangeListenerRegistered = true
            NSLog("[AudioCaptureManager] Device change monitoring started")
        } else {
            NSLog("[AudioCaptureManager] Failed to register device listener: %d", status)
        }
    }

    // MARK: - Tap Installation with Format Retry

    /// Try multiple audio formats when tap installation fails.
    /// Returns the converter that successfully connected.
    private func installTapWithRetry(
        on engine: AVAudioEngine,
        targetFormat: AVAudioFormat,
        handler: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) throws -> AVAudioConverter {
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        // Try native format first, then common alternatives
        let candidates: [AVAudioFormat] = [
            nativeFormat,
            AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1),
            AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1),
            AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2),
            AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2),
        ].compactMap { $0 }

        var lastError: Error?
        for format in candidates {
            guard let conv = AVAudioConverter(from: format, to: targetFormat) else { continue }
            do {
                inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: handler)
                try engine.start()
                NSLog("[AudioCaptureManager] Tap installed: %.0fHz, %dch", format.sampleRate, format.channelCount)
                return conv
            } catch {
                NSLog("[AudioCaptureManager] Format %.0fHz/%dch failed: %@", format.sampleRate, format.channelCount, error.localizedDescription)
                inputNode.removeTap(onBus: 0)
                engine.stop()
                lastError = error
            }
        }

        throw YapYapError.audioCaptureFailed(
            lastError ?? NSError(domain: "YapYap", code: -3,
                userInfo: [NSLocalizedDescriptionKey: "No compatible audio format found"])
        )
    }

    // MARK: - Capture

    func startCapture(microphoneId: String? = nil, preserveFrames: Bool = false, rmsHandler: @escaping (Float) -> Void) async throws {
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
        if !preserveFrames {
            accumulatedFrames = []
            // Pre-allocate for ~30 seconds of audio at 16kHz to reduce reallocations
            accumulatedFrames.reserveCapacity(Int(sampleRate) * 30)
        }
        audioLock.unlock()
        rmsCallback = rmsHandler

        // Always create a fresh engine to avoid stale tap state
        let engine = AVAudioEngine()
        self.audioEngine = engine
        self.isEngineWarmed = false

        // Set specific input device if requested
        if let micId = microphoneId, !micId.isEmpty {
            _ = setInputDevice(micId, on: engine)
        }

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
        self.convertFormat = targetFormat

        // Tap callback — references conv via the converter returned by installTapWithRetry
        // We use a placeholder that gets replaced after the converter is created
        var conv: AVAudioConverter?

        let tapHandler: (AVAudioPCMBuffer, AVAudioTime) -> Void = { [weak self] buffer, _ in
            guard let self = self, let conv = conv else { return }

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

            guard convStatus != .error, error == nil else {
                self.consecutiveErrors += 1
                if self.consecutiveErrors >= self.maxConsecutiveErrors {
                    NSLog("[AudioCaptureManager] %d consecutive errors, triggering recovery", self.maxConsecutiveErrors)
                    DispatchQueue.main.async { self.onEngineFailure?() }
                    self.consecutiveErrors = 0
                }
                return
            }
            self.consecutiveErrors = 0

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

        // Install tap with format retry — sets conv via the returned converter
        let installedConv = try installTapWithRetry(on: engine, targetFormat: targetFormat, handler: tapHandler)
        conv = installedConv
        self.converter = installedConv

        isCapturing = true
        NSLog("[AudioCaptureManager] Capture started")
    }

    // Convenience overload matching existing call sites that don't use preserveFrames
    func startCapture(microphoneId: String? = nil, rmsHandler: @escaping (Float) -> Void) async throws {
        try await startCapture(microphoneId: microphoneId, preserveFrames: false, rmsHandler: rmsHandler)
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

    // MARK: - Engine Recovery

    /// Recreate the audio engine mid-recording, preserving accumulated frames.
    func recreateEngine() async throws {
        guard isCapturing else { return }
        NSLog("[AudioCaptureManager] Recreating AVAudioEngine...")

        let savedCallback = rmsCallback

        // Tear down current engine but keep accumulated frames
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        converter = nil
        isCapturing = false

        // Restart capture, preserving accumulated frames
        try await startCapture(preserveFrames: true, rmsHandler: savedCallback ?? { _ in })
        NSLog("[AudioCaptureManager] Engine recreated successfully")
    }

    // MARK: - Audio Sample Access

    /// Thread-safe snapshot of accumulated audio frames for streaming STT.
    func currentAudioSamples() -> [Float] {
        audioLock.lock()
        let copy = accumulatedFrames
        audioLock.unlock()
        return copy
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
