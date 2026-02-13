// FloatingBarView.swift
// YapYap — SwiftUI pill view for the floating recording bar
import SwiftUI

struct FloatingBarView: View {
    @Bindable var appState: AppState
    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 10) {
            // Creature
            CreatureView(state: appState.creatureState, size: 42)

            // Waveform bars (only when recording)
            if appState.isRecording {
                WaveformView(rms: appState.currentRMS)
                    .frame(width: 50, height: 20)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color(red: 20/255, green: 18/255, blue: 28/255, opacity: 0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(
                            appState.isRecording
                                ? Color.ypWarm.opacity(0.12)
                                : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: appState.isRecording)
        .onChange(of: appState.isRecording) { _, newValue in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isExpanded = newValue
            }
        }
    }
}
