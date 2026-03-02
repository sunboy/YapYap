// VADConfigTests.swift
// YapYapTests
import XCTest
import AVFoundation
@testable import YapYap

final class VADConfigTests: XCTestCase {

    func testDefaultConfig() {
        let config = VADConfig.default
        // Threshold is calibrated for energy-based VAD: prob = min(1, rms * 10).
        // Normal speech RMS ~0.01-0.10 → threshold must be << 0.35 (Silero scale).
        XCTAssertEqual(config.threshold, 0.10)
        XCTAssertEqual(config.minSpeechDurationMs, 200)
        XCTAssertEqual(config.minSilenceDurationMs, 300)
        XCTAssertEqual(config.speechPadMs, 100)
        XCTAssertEqual(config.maxSpeechDurationS, 30)
    }

    func testNoisyPreset() {
        let config = VADConfig.noisyPreset
        XCTAssertGreaterThan(config.threshold, VADConfig.default.threshold)
        XCTAssertGreaterThan(config.minSpeechDurationMs, VADConfig.default.minSpeechDurationMs)
    }

    func testQuietPreset() {
        let config = VADConfig.quietPreset
        XCTAssertLessThan(config.threshold, VADConfig.default.threshold)
        XCTAssertLessThan(config.minSpeechDurationMs, VADConfig.default.minSpeechDurationMs)
    }

    func testNoisyHasHigherThresholdThanQuiet() {
        XCTAssertGreaterThan(VADConfig.noisyPreset.threshold, VADConfig.quietPreset.threshold)
    }
}

// MARK: - VADManager detection tests

final class VADManagerTests: XCTestCase {

    // MARK: - Helpers

    /// Build a 16kHz mono float32 AVAudioPCMBuffer filled with a sine wave at `amplitude`.
    private func makeSineBuffer(sampleRate: Double = 16000, durationSeconds: Double, amplitude: Float, frequency: Float = 440) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            data[i] = amplitude * sin(2.0 * Float.pi * frequency * Float(i) / Float(sampleRate))
        }
        return buffer
    }

    /// Build a buffer of pure silence (all zeros).
    private func makeSilenceBuffer(sampleRate: Double = 16000, durationSeconds: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        // floatChannelData is zero-initialised by AVAudioPCMBuffer
        return buffer
    }

    /// Build a buffer: `silenceSec` of silence followed by `speechSec` of sine, then `silenceSec` more silence.
    private func makeSpeechInSilenceBuffer(
        sampleRate: Double = 16000,
        silenceSec: Double = 0.5,
        speechSec: Double = 1.0,
        amplitude: Float = 0.05
    ) -> AVAudioPCMBuffer {
        let silenceFrames = Int(sampleRate * silenceSec)
        let speechFrames  = Int(sampleRate * speechSec)
        let totalFrames   = silenceFrames + speechFrames + silenceFrames

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
        buffer.frameLength = AVAudioFrameCount(totalFrames)
        let data = buffer.floatChannelData![0]

        // Leading silence (already zero)
        // Speech segment
        let speechStart = silenceFrames
        for i in 0..<speechFrames {
            data[speechStart + i] = amplitude * sin(2.0 * Float.pi * 440 * Float(i) / Float(sampleRate))
        }
        // Trailing silence (already zero)
        return buffer
    }

    // MARK: - Tests

    /// Silence-only buffer must produce no speech segments.
    func testSilenceProducesNoSegments() {
        let vad = VADManager(config: .default)
        let buffer = makeSilenceBuffer(durationSeconds: 2.0)
        let segments = vad.filterSpeechSegments(from: buffer)
        XCTAssertTrue(segments.isEmpty, "Pure silence should yield no speech segments")
    }

    /// A 1-second sine wave at amplitude 0.05 (typical quiet-mic speech RMS) must be detected.
    /// This is the regression test for the bug: threshold 0.35 with energy*10 never triggered
    /// because typical speech RMS ~0.035 → prob ~0.35 which was right at (or just below) threshold.
    func testNormalSpeechAmplitudeIsDetected() {
        let vad = VADManager(config: .default)
        // Sine wave at amplitude 0.05 has RMS = 0.05/sqrt(2) ≈ 0.0354
        // With the fixed threshold of 0.10: prob = 0.0354 * 10 = 0.354 > 0.10 ✓
        // With the old threshold of 0.35:   prob = 0.354 which was borderline / often missed ✗
        let buffer = makeSineBuffer(durationSeconds: 1.0, amplitude: 0.05)
        let segments = vad.filterSpeechSegments(from: buffer)
        XCTAssertFalse(segments.isEmpty, "Speech at amplitude 0.05 (RMS ~0.035) must be detected with default threshold")
    }

    /// Very quiet speech (amplitude 0.02, RMS ~0.014) should be detected with default threshold.
    func testQuietSpeechIsDetectedWithDefaultConfig() {
        let vad = VADManager(config: .default)
        // Sine at 0.02 amplitude: RMS = 0.02/sqrt(2) ≈ 0.0141 → prob = 0.141 > threshold(0.10) ✓
        let buffer = makeSineBuffer(durationSeconds: 1.0, amplitude: 0.02)
        let segments = vad.filterSpeechSegments(from: buffer)
        XCTAssertFalse(segments.isEmpty, "Speech at amplitude 0.02 should be detected with default threshold 0.10")
    }

    /// Background noise level (amplitude 0.002, RMS ~0.0014) should NOT be detected.
    func testBackgroundNoiseIsNotDetected() {
        let vad = VADManager(config: .default)
        // RMS = 0.002/sqrt(2) ≈ 0.0014 → prob = 0.014 < threshold(0.10) ✓
        let buffer = makeSineBuffer(durationSeconds: 2.0, amplitude: 0.002)
        let segments = vad.filterSpeechSegments(from: buffer)
        XCTAssertTrue(segments.isEmpty, "Background noise at amplitude 0.002 should not be detected as speech")
    }

    /// Speech embedded in silence: VAD should extract only the speech portion.
    func testSpeechExtractedFromSilence() {
        let vad = VADManager(config: .default)
        // 0.5s silence + 1.0s speech (amplitude 0.05) + 0.5s silence
        let buffer = makeSpeechInSilenceBuffer(silenceSec: 0.5, speechSec: 1.0, amplitude: 0.05)
        let segments = vad.filterSpeechSegments(from: buffer)
        XCTAssertFalse(segments.isEmpty, "VAD must find speech segment in silence+speech+silence buffer")
        // The concatenated speech should be significantly shorter than the full buffer
        let totalFrames = Int(buffer.frameLength)
        let speechFrames = segments.reduce(0) { $0 + Int($1.buffer.frameLength) }
        XCTAssertLessThan(Double(speechFrames), Double(totalFrames) * 0.85,
            "VAD should have stripped at least some silence; speech frames (\(speechFrames)) should be < 85% of total (\(totalFrames))")
    }

    /// Noisy preset has higher threshold — requires louder signal than default.
    func testNoisyPresetRequiresLouderSignal() {
        let quietSpeech = makeSineBuffer(durationSeconds: 1.0, amplitude: 0.015)
        // With default threshold 0.10: RMS ≈ 0.0106 → prob ≈ 0.106 > 0.10, detected
        let defaultVAD = VADManager(config: .default)
        let defaultSegments = defaultVAD.filterSpeechSegments(from: quietSpeech)
        // With noisy threshold 0.20: RMS ≈ 0.0106 → prob ≈ 0.106 < 0.20, NOT detected
        let noisyVAD = VADManager(config: .noisyPreset)
        let noisySegments = noisyVAD.filterSpeechSegments(from: quietSpeech)
        XCTAssertFalse(defaultSegments.isEmpty, "Default VAD should detect marginal speech")
        XCTAssertTrue(noisySegments.isEmpty, "Noisy preset should reject the same marginal speech")
    }

    /// Empty buffer returns no segments without crashing.
    func testEmptyBufferReturnsNoSegments() {
        let vad = VADManager(config: .default)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 0)!
        buffer.frameLength = 0
        let segments = vad.filterSpeechSegments(from: buffer)
        XCTAssertTrue(segments.isEmpty, "Empty buffer should return no segments")
    }
}
