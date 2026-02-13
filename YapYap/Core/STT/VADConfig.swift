// VADConfig.swift
// YapYap — Voice Activity Detection configuration
import Foundation

struct VADConfig {
    /// Speech detection sensitivity (0.0 = everything is speech, 1.0 = very selective)
    var threshold: Float = 0.35
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

    /// Noisy environment (café, open office)
    static let noisyPreset = VADConfig(
        threshold: 0.5,
        minSpeechDurationMs: 300,
        minSilenceDurationMs: 200,
        speechPadMs: 150,
        maxSpeechDurationS: 30
    )

    /// Quiet environment (home, private office)
    static let quietPreset = VADConfig(
        threshold: 0.25,
        minSpeechDurationMs: 150,
        minSilenceDurationMs: 400,
        speechPadMs: 80,
        maxSpeechDurationS: 30
    )
}
