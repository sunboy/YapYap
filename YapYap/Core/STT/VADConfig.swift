// VADConfig.swift
// YapYap — Voice Activity Detection configuration
import Foundation

struct VADConfig {
    /// Speech detection sensitivity threshold, applied to energy-based probability.
    /// The VADManager computes prob = min(1.0, rms * 10.0) per 512-sample chunk.
    /// Normal speech on macOS produces RMS ~0.01-0.10, so threshold must be calibrated
    /// for this scale — NOT for a Silero neural network's 0-1 probability output.
    /// At threshold=0.10, speech with RMS >= 0.01 is detected; background noise
    /// (RMS < 0.003) produces prob < 0.03 and is correctly suppressed.
    var threshold: Float = 0.10
    /// Ignore speech bursts shorter than this (filters coughs, clicks)
    var minSpeechDurationMs: Int = 200
    /// Need this much silence to split segments
    var minSilenceDurationMs: Int = 300
    /// Pad speech segments with this much extra audio to avoid clipping
    var speechPadMs: Int = 100
    /// Auto-split very long segments at silence points
    var maxSpeechDurationS: Float = 30

    // MARK: - Presets

    /// Default balanced preset
    static let `default` = VADConfig()

    /// Noisy environment (café, open office): higher threshold filters background noise
    static let noisyPreset = VADConfig(
        threshold: 0.20,
        minSpeechDurationMs: 300,
        minSilenceDurationMs: 200,
        speechPadMs: 150,
        maxSpeechDurationS: 30
    )

    /// Quiet environment (home, private office): lower threshold catches quiet speech
    static let quietPreset = VADConfig(
        threshold: 0.05,
        minSpeechDurationMs: 150,
        minSilenceDurationMs: 400,
        speechPadMs: 80,
        maxSpeechDurationS: 30
    )
}
