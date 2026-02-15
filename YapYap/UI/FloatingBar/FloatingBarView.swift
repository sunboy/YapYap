// FloatingBarView.swift
// YapYap — Compact floating pill with creature states
import SwiftUI

struct FloatingBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            // Creature - always visible, shows state through animation
            CreatureView(state: appState.creatureState, size: 28)

            // Contextual indicator next to creature
            if appState.isLoadingModels {
                ProgressView(value: appState.modelLoadingProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 48)
                    .tint(Color.ypWarm)
                    .transition(.opacity)
            } else if appState.isRecording {
                WaveformView(rms: appState.currentRMS)
                    .frame(width: 36, height: 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(red: 20/255, green: 18/255, blue: 28/255, opacity: 0.85))
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: appState.isRecording)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: appState.isProcessing)
        .animation(.easeInOut(duration: 0.3), value: appState.isLoadingModels)
    }
}
