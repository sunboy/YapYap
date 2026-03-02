// VADManager.swift
// YapYap — Silero VAD pre-filter for all STT backends
import AVFoundation

class VADManager {
    private var config: VADConfig

    init(config: VADConfig = .default) {
        self.config = config
    }

    func updateConfig(_ newConfig: VADConfig) {
        self.config = newConfig
    }

    /// Filter audio buffer to extract only speech segments.
    /// Called BEFORE passing audio to any STT engine.
    func filterSpeechSegments(from buffer: AVAudioPCMBuffer) -> [AudioSegment] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let totalFrames = Int(buffer.frameLength)
        let sampleRate = Int(buffer.format.sampleRate)
        let chunkSize = 512 // Optimal for Silero CoreML

        // Process chunks and get speech probabilities using energy-based VAD.
        // Operates on pointer slices to avoid per-chunk Array allocations.
        var speechProbs: [(index: Int, probability: Float)] = []
        speechProbs.reserveCapacity(totalFrames / chunkSize + 1)

        for i in stride(from: 0, to: totalFrames, by: chunkSize) {
            let end = min(i + chunkSize, totalFrames)
            let count = end - i
            // Calculate energy directly from pointer — no Array copy
            let energy = calculateEnergyFromPointer(channelData + i, count: count)
            let prob = min(1.0, energy * 10.0)
            speechProbs.append((i, prob))
        }

        // Apply threshold + duration filters to get speech timestamps
        let rawSegments = extractSpeechSegments(
            probabilities: speechProbs,
            sampleRate: sampleRate,
            chunkSize: chunkSize
        )

        // Extract audio segments with padding, creating buffers from pointer slices
        return rawSegments.compactMap { segment -> AudioSegment? in
            let padSamples = Int(Float(config.speechPadMs) / 1000.0 * Float(sampleRate))
            let start = max(0, segment.start - padSamples)
            let end = min(totalFrames, segment.end + padSamples)

            guard end > start else { return nil }

            let count = end - start
            guard let segmentBuffer = createBufferFromPointer(
                channelData + start, count: count, sampleRate: buffer.format.sampleRate
            ) else { return nil }

            return AudioSegment(startSample: start, endSample: end, buffer: segmentBuffer)
        }
    }

    // MARK: - Internal

    private struct RawSegment {
        let start: Int
        let end: Int
    }

    private func extractSpeechSegments(
        probabilities: [(index: Int, probability: Float)],
        sampleRate: Int,
        chunkSize: Int
    ) -> [RawSegment] {
        var segments: [RawSegment] = []
        var speechStart: Int?
        var silenceCount = 0

        let minSpeechChunks = max(1, config.minSpeechDurationMs * sampleRate / (1000 * chunkSize))
        let minSilenceChunks = max(1, config.minSilenceDurationMs * sampleRate / (1000 * chunkSize))
        var speechChunkCount = 0

        for (index, prob) in probabilities {
            if prob >= config.threshold {
                if speechStart == nil {
                    speechStart = index
                    speechChunkCount = 0
                }
                speechChunkCount += 1
                silenceCount = 0
            } else {
                silenceCount += 1
                if speechStart != nil && silenceCount >= minSilenceChunks {
                    if speechChunkCount >= minSpeechChunks {
                        segments.append(RawSegment(start: speechStart!, end: index))
                    }
                    speechStart = nil
                    speechChunkCount = 0
                }
            }
        }

        // Handle trailing speech
        if let start = speechStart, speechChunkCount >= minSpeechChunks {
            let lastIndex = probabilities.last?.index ?? 0
            segments.append(RawSegment(start: start, end: lastIndex + chunkSize))
        }

        return segments
    }

    /// RMS energy from a raw pointer — avoids Array allocation
    private func calculateEnergyFromPointer(_ samples: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var sumOfSquares: Float = 0.0
        for i in 0..<count {
            let s = samples[i]
            sumOfSquares += s * s
        }
        return sqrt(sumOfSquares / Float(count))
    }

    /// Create an AVAudioPCMBuffer from a raw pointer slice — avoids intermediate Array
    private func createBufferFromPointer(_ source: UnsafePointer<Float>, count: Int, sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)

        if let channelData = buffer.floatChannelData?[0] {
            channelData.initialize(from: source, count: count)
        }

        return buffer
    }
}
