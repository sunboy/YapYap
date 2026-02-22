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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 36/255, green: 33/255, blue: 46/255))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.ypWarm.opacity(0.15), lineWidth: 1)
                )
        )
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

/// Wrapper view that embeds an NSHostingView inside a transparent container.
/// Instead of fighting NSHostingView's internal layer management, we place
/// the hosting view inside a non-drawing NSView container. The container's
/// layer is set to clear, and the hosting view sits on top. The window's
/// own transparency (backgroundColor = .clear, isOpaque = false) ensures
/// the compositing is correct.
class TransparentHostingView<Content: View>: NSView {
    let hostingView: NSHostingView<Content>

    init(rootView: Content) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.isOpaque = false
        layerContentsRedrawPolicy = .never

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.backgroundColor = .clear
        window?.isOpaque = false
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Do not fill — keep fully transparent
    }
}
