// AudioSegment.swift
// YapYap — Represents a segment of speech audio
import AVFoundation

struct AudioSegment {
    let startSample: Int
    let endSample: Int
    let buffer: AVAudioPCMBuffer

    var durationSeconds: Double {
        Double(endSample - startSample) / buffer.format.sampleRate
    }

    /// Concatenate multiple audio segments into a single buffer
    static func concatenate(_ segments: [AudioSegment]) -> AVAudioPCMBuffer? {
        guard !segments.isEmpty else { return nil }
        guard let format = segments.first?.buffer.format else { return nil }

        let totalFrames = segments.reduce(0) { $0 + Int($1.buffer.frameLength) }
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else { return nil }

        var offset = 0
        for segment in segments {
            guard let srcData = segment.buffer.floatChannelData?[0],
                  let dstData = outputBuffer.floatChannelData?[0] else { continue }

            let frameCount = Int(segment.buffer.frameLength)
            for i in 0..<frameCount {
                dstData[offset + i] = srcData[i]
            }
            offset += frameCount
        }

        outputBuffer.frameLength = AVAudioFrameCount(offset)
        return outputBuffer
    }
}
