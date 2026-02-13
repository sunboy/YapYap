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
    func filterSpeechSegments(from buffer: AVAudioPCMBuffer) async throws -> [AudioSegment] {
        let floatArray = bufferToFloatArray(buffer)
        let sampleRate = Int(buffer.format.sampleRate)
        let chunkSize = 512 // Optimal for Silero CoreML

        // Process chunks and get speech probabilities using energy-based VAD
        // (Silero CoreML model would be used in production; here we use energy-based fallback)
        var speechProbs: [(index: Int, probability: Float)] = []
        for i in stride(from: 0, to: floatArray.count, by: chunkSize) {
            let end = min(i + chunkSize, floatArray.count)
            let chunk = Array(floatArray[i..<end])
            let energy = calculateEnergy(chunk)
            // Map energy to probability (0-1 range)
            let prob = min(1.0, energy * 10.0)
            speechProbs.append((i, prob))
        }

        // Apply threshold + duration filters to get speech timestamps
        let rawSegments = extractSpeechSegments(
            probabilities: speechProbs,
            sampleRate: sampleRate,
            chunkSize: chunkSize
        )

        // Extract audio segments with padding
        return rawSegments.compactMap { segment -> AudioSegment? in
            let padSamples = Int(Float(config.speechPadMs) / 1000.0 * Float(sampleRate))
            let start = max(0, segment.start - padSamples)
            let end = min(floatArray.count, segment.end + padSamples)

            guard end > start else { return nil }

            let segmentFrames = Array(floatArray[start..<end])
            guard let segmentBuffer = createBuffer(from: segmentFrames, sampleRate: buffer.format.sampleRate) else { return nil }

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

    private func calculateEnergy(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }

    private func bufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }

    private func createBuffer(from samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<samples.count {
                channelData[i] = samples[i]
            }
        }

        return buffer
    }
}
