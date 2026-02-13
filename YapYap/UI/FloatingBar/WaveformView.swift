// WaveformView.swift
// YapYap — Waveform visualization bars matching mockup formula
import SwiftUI

struct WaveformView: View {
    let rms: Float

    @State private var time: Double = 0
    private let timer = Timer.publish(every: 1.0/30.0, on: .main, in: .common).autoconnect()

    private let barCount = 5
    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 3

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(Color.ypWarm)
                    .frame(width: barWidth, height: barHeight(for: index))
            }
        }
        .onReceive(timer) { _ in
            time += 1.0 / 30.0
        }
    }

    /// Waveform formula from mockup: height = 4 + abs(sin(t * 3.5 + i * 0.9)) * 11
    private func barHeight(for index: Int) -> CGFloat {
        let t = time
        let i = Double(index)
        let baseHeight = 4.0 + abs(sin(t * 3.5 + i * 0.9)) * 11.0

        // Modulate with actual RMS when available
        let rmsMultiplier = max(0.3, min(1.0, Double(rms) * 5.0))
        return CGFloat(baseHeight * rmsMultiplier)
    }
}
