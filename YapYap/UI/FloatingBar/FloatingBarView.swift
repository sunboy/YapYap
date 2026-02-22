// FloatingBarView.swift
// YapYap — Compact floating pill with creature states
import SwiftUI
import Combine

struct FloatingBarView: View {
    @Bindable var appState: AppState

    @State private var recordingSeconds: Int = 0
    @State private var timerCancellable: AnyCancellable?
    @State private var dotPulse: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            // Creature - always visible, shows state through animation
            CreatureView(state: appState.creatureState, size: 28)

            // Contextual indicator next to creature
            if appState.isLoadingModels {
                // Use indeterminate spinner when progress is 0 (WhisperKit
                // doesn't report incremental progress during download/ANE compile).
                // Switch to determinate bar once real progress is reported.
                if appState.modelLoadingProgress > 0 && appState.modelLoadingProgress < 1.0 {
                    ProgressView(value: appState.modelLoadingProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 48)
                        .tint(Color.ypWarm)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.ypWarm)
                }
                Text(appState.modelLoadingStatus.isEmpty ? "Loading…" : appState.modelLoadingStatus)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.ypText2)
                    .lineLimit(1)
                    .transition(.opacity)
            } else if appState.isProcessing, let preview = appState.partialTranscription {
                // Type-ahead preview: show raw STT text while LLM cleanup runs
                Text(preview)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.ypText2.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200)
                    .transition(.opacity)

                ProgressView()
                    .controlSize(.mini)
                    .tint(Color.ypWarm)
            } else if appState.isRecording {
                WaveformView(rms: appState.currentRMS)
                    .frame(width: 36, height: 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))

                // Recording timer
                Text(formatTime(recordingSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.ypText2)
                    .transition(.opacity)

                // Pulsing recording dot
                Circle()
                    .fill(Color.ypWarm)
                    .frame(width: 5, height: 5)
                    .opacity(dotPulse ? 1.0 : 0.25)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color(red: 36/255, green: 33/255, blue: 46/255, opacity: 0.97))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.ypWarm.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 4)
        .fixedSize()
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: appState.isRecording)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: appState.isProcessing)
        .animation(.easeInOut(duration: 0.3), value: appState.isLoadingModels)
        .animation(.easeInOut(duration: 0.2), value: appState.partialTranscription != nil)
        .onChange(of: appState.isRecording) { _, isRecording in
            if isRecording {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startTimer() {
        recordingSeconds = 0
        dotPulse = false

        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            dotPulse = true
        }

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                recordingSeconds += 1
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        recordingSeconds = 0
        dotPulse = false
    }
}

// MARK: - Transparent Hosting View

/// Custom NSHostingView subclass that forces complete transparency.
/// Overrides layout to recursively clear all sublayer backgrounds that
/// NSHostingView's internal SwiftUI rendering tree may set.
/// Uses throttling to avoid running the recursive layer walk on every
/// layout pass (which fires rapidly during animations).
class TransparentHostingView<Content: View>: NSHostingView<Content> {
    private var lastTransparencyPass: CFTimeInterval = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.backgroundColor = .clear
        window?.isOpaque = false
        forceTransparent()
    }

    override func layout() {
        super.layout()
        throttledTransparent()
    }

    override func updateLayer() {
        super.updateLayer()
        throttledTransparent()
    }

    /// Full recursive clear — used once when the view first appears.
    private func forceTransparent() {
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.isOpaque = false
        if let rootLayer = layer {
            clearSublayers(rootLayer)
        }
        lastTransparencyPass = CACurrentMediaTime()
    }

    /// Throttled: only run the recursive clear at most every 0.5s.
    /// layout() and updateLayer() fire on every animation frame; the
    /// recursive walk is expensive and unnecessary that often.
    private func throttledTransparent() {
        let now = CACurrentMediaTime()
        guard now - lastTransparencyPass > 0.5 else { return }
        forceTransparent()
    }

    private func clearSublayers(_ layer: CALayer) {
        layer.backgroundColor = .clear
        layer.isOpaque = false
        for sublayer in layer.sublayers ?? [] {
            clearSublayers(sublayer)
        }
    }
}
