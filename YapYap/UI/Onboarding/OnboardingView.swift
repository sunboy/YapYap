// OnboardingView.swift
// YapYap — First-launch onboarding wizard (Liquid Glass redesign)
import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    let appState: AppState
    let pipeline: TranscriptionPipeline
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var micPermissionGranted = false
    @State private var accessibilityGranted = false
    @State private var selectedSTTModel = STTModelRegistry.recommendedModel.id
    @State private var selectedLLMModel = LLMModelRegistry.recommendedModel.id
    @State private var loadingFailed = false
    @State private var accessibilityPollTask: Task<Void, Never>? = nil

    private let totalSteps = 6

    var body: some View {
        ZStack {
            // Layer 1: ambient glow (animates per step)
            AmbientGlowBackground(layers: glowForStep(currentStep))
                .animation(.easeInOut(duration: 0.8), value: currentStep)

            // Layer 2: glass content card
            VStack(spacing: 0) {
                OnboardingProgressBar(current: currentStep, total: totalSteps)
                    .padding(.horizontal, 40)
                    .padding(.top, 28)

                Spacer()

                Group {
                    switch currentStep {
                    case 0: welcomeStep
                    case 1: microphoneStep
                    case 2: accessibilityStep
                    case 3: modelSelectionStep
                    case 4: loadingStep
                    case 5: doneStep
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.97)),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                navigationButtons
                    .padding(.horizontal, 40)
                    .padding(.bottom, 36)
            }
            .frame(width: 560, height: 560)
            .glassPanel(cornerRadius: 24, tint: .ypLavender, tintOpacity: 0.04)
        }
        .frame(width: 560, height: 560)
        .onAppear {
            checkPermissions()
        }
        .onChange(of: currentStep) { _, step in
            switch step {
            case 2:
                Permissions.requestAccessibilityPermission()
                startAccessibilityPolling()
            case 4:
                startModelLoading()
            default:
                break
            }
        }
    }

    // MARK: - Glow per step

    private func glowForStep(_ step: Int) -> [AmbientGlowBackground.GlowLayer] {
        switch step {
        case 0: return AmbientGlowBackground.onboardingWelcome
        case 1: return AmbientGlowBackground.onboardingMic
        case 2: return AmbientGlowBackground.onboardingAccess
        case 3: return AmbientGlowBackground.onboardingModels
        case 4: return AmbientGlowBackground.onboardingLoading
        case 5: return AmbientGlowBackground.onboardingDone
        default: return AmbientGlowBackground.onboardingWelcome
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private var navigationButtons: some View {
        switch currentStep {
        case 0:
            HStack {
                Spacer()
                GlassPillButton(label: "Get Started") {
                    withAnimation { currentStep = 1 }
                }
            }
        case 1:
            HStack {
                Spacer()
                GlassPillButton(label: "Continue", isDisabled: !micPermissionGranted) {
                    withAnimation { currentStep = 2 }
                }
            }
        case 2:
            HStack {
                GlassSecondaryButton(label: "Skip for now") {
                    accessibilityPollTask?.cancel()
                    withAnimation { currentStep = 3 }
                }
                Spacer()
                GlassPillButton(label: "Continue") {
                    accessibilityPollTask?.cancel()
                    withAnimation { currentStep = 3 }
                }
            }
        case 3:
            HStack {
                Spacer()
                GlassPillButton(label: "Continue") {
                    withAnimation { currentStep = 4 }
                }
            }
        case 4:
            // No button — auto-advances; retry shown inline on failure
            EmptyView()
        case 5:
            HStack {
                Spacer()
                GlassPillButton(label: "Start Yapping") {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    UserDefaults.standard.synchronize()
                    Analytics.trackInstall(sttModel: selectedSTTModel, llmModel: selectedLLMModel)
                    Analytics.trackOnboardingCompleted()
                    onComplete()
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            // Creature with halo glow
            ZStack {
                RadialGradient(
                    colors: [.ypLavender.opacity(0.3), .clear],
                    center: .center, startRadius: 0, endRadius: 70
                )
                .frame(width: 140, height: 140)
                .blur(radius: 24)
                CreatureView(state: .recording, size: 80)
            }

            VStack(spacing: 8) {
                Text("Welcome to YapYap")
                    .font(.ypDisplayRounded)
                    .foregroundColor(.ypText1)

                Text("you yap. it writes.")
                    .font(.custom("Caveat", size: 20))
                    .foregroundColor(.ypZzz)
            }

            VStack(spacing: 6) {
                Text("Your cozy, offline voice-to-text companion.")
                    .font(.ypSubheadRounded)
                    .foregroundColor(.ypText2)

                Text("Everything runs locally on your Mac \u{2014} no cloud, no tracking, just you.")
                    .font(.system(size: 12))
                    .foregroundColor(.ypText3)
            }
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 40)
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 20) {
            Text("Microphone Access")
                .font(.ypHeadingRounded)
                .foregroundColor(.ypText1)

            Text("YapYap needs to hear you to transcribe your voice.")
                .font(.system(size: 13))
                .foregroundColor(.ypText2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            permissionRow(
                icon: "🎙",
                title: "Microphone",
                description: "To capture your voice",
                isGranted: micPermissionGranted,
                action: {
                    Task {
                        micPermissionGranted = await Permissions.requestMicrophonePermission()
                    }
                }
            )
            .padding(.horizontal, 40)
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Text("Accessibility Access")
                .font(.ypHeadingRounded)
                .foregroundColor(.ypText1)

            Text("Used to paste transcribed text and detect which app is active.\nClick **Open System Settings**, then toggle YapYap on.")
                .font(.system(size: 13))
                .foregroundColor(.ypText2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Status row
            HStack(spacing: 12) {
                Text("♿️")
                    .font(.system(size: 24))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.ypText1)
                    Text(accessibilityGranted ? "Access granted" : "Waiting — toggle YapYap ON in System Settings")
                        .font(.system(size: 12))
                        .foregroundColor(accessibilityGranted ? .ypMint : .ypText3)
                }

                Spacer()

                if accessibilityGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.ypMint)
                        .font(.system(size: 20))
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(14)
            .glassPanel(cornerRadius: 12)
            .padding(.horizontal, 40)

            if !accessibilityGranted {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard currentStep == 2 else { return }
            accessibilityGranted = Permissions.hasAccessibilityPermission
        }
    }

    private var modelSelectionStep: some View {
        VStack(spacing: 20) {
            Text("Choose Your Models")
                .font(.ypHeadingRounded)
                .foregroundColor(.ypText1)

            Text("Models download once and run fully offline.\nYou can change these later in Settings.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .multilineTextAlignment(.center)

            // STT Model Selection
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                        .foregroundColor(.ypLavender)
                    Text("Speech-to-Text")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.ypText1)
                }

                VStack(spacing: 6) {
                    ForEach(STTModelRegistry.allModels.filter { $0.id != "voxtral-mini-3b" }, id: \.id) { model in
                        onboardingModelCard(
                            name: model.name,
                            size: model.sizeDescription,
                            description: model.description,
                            isRecommended: model.isRecommended,
                            isSelected: selectedSTTModel == model.id,
                            tint: .ypLavender
                        ) {
                            selectedSTTModel = model.id
                        }
                    }
                }
            }
            .padding(.horizontal, 32)

            // LLM Model Selection
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(.ypWarm)
                    Text("Text Cleanup")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.ypText1)
                }

                VStack(spacing: 6) {
                    ForEach(LLMModelRegistry.allModels, id: \.id) { model in
                        onboardingModelCard(
                            name: model.name,
                            size: model.sizeDescription,
                            description: model.description,
                            isRecommended: model.isRecommended,
                            isSelected: selectedLLMModel == model.id,
                            tint: .ypWarm
                        ) {
                            selectedLLMModel = model.id
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private func onboardingModelCard(
        name: String, size: String, description: String,
        isRecommended: Bool, isSelected: Bool, tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            // Selection indicator
            ZStack {
                Circle()
                    .stroke(isSelected ? tint : Color.ypText4, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                if isSelected {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(isSelected ? .ypText1 : .ypText2)
                    Text(size)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.ypText4)
                    if isRecommended {
                        Text("Recommended")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(tint.opacity(0.15))
                            .cornerRadius(3)
                    }
                }
                if isSelected {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(.ypText3)
                        .lineLimit(2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? tint.opacity(0.08) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? tint.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { action() } }
    }

    private var loadingStep: some View {
        VStack(spacing: 20) {
            if loadingFailed {
                Text("⚠️ Loading Failed")
                    .font(.ypHeadingRounded)
                    .foregroundColor(.ypText1)

                Text(appState.modelLoadingStatus)
                    .font(.system(size: 13))
                    .foregroundColor(.ypText2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                GlassPillButton(label: "Retry") {
                    loadingFailed = false
                    startModelLoading()
                }
            } else {
                ZStack {
                    RadialGradient(
                        colors: [.ypLavender.opacity(0.25), .clear],
                        center: .center, startRadius: 0, endRadius: 50
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 16)
                    CreatureView(state: .recording, size: 60)
                }

                Text("Setting Up YapYap…")
                    .font(.ypHeadingRounded)
                    .foregroundColor(.ypText1)

                Text(appState.modelLoadingStatus.isEmpty ? "Preparing models…" : appState.modelLoadingStatus)
                    .font(.system(size: 13))
                    .foregroundColor(.ypText2)
                    .multilineTextAlignment(.center)

                ProgressView(value: appState.modelLoadingProgress)
                    .progressViewStyle(.linear)
                    .tint(.ypLavender)
                    .padding(.horizontal, 60)

                Text("\(Int(appState.modelLoadingProgress * 100))%")
                    .font(.system(size: 11))
                    .foregroundColor(.ypText3)
            }
        }
        .onChange(of: appState.modelsReady) { _, ready in
            if ready {
                withAnimation { currentStep = 5 }
            }
        }
        .onChange(of: appState.isLoadingModels) { _, loading in
            if !loading && !appState.modelsReady {
                loadingFailed = true
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 20) {
            ZStack {
                RadialGradient(
                    colors: [.ypMint.opacity(0.3), .clear],
                    center: .center, startRadius: 0, endRadius: 70
                )
                .frame(width: 140, height: 140)
                .blur(radius: 24)
                CreatureView(state: .sleeping, size: 80)
            }

            Text("You're all set!")
                .font(.ypDisplayRounded)
                .foregroundColor(.ypText1)

            VStack(spacing: 8) {
                Text("I'll be sleeping in your menu bar.\nHold \(KeyboardShortcuts.getShortcut(for: .pushToTalk)?.description ?? "\u{2325}Space") and start talking!")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.ypText2)
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    tipPill(icon: "mic.fill", text: "Hold to talk")
                    tipPill(icon: "sparkles", text: "AI cleans up")
                    tipPill(icon: "doc.on.clipboard", text: "Auto-pasted")
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 40)
        }
    }

    private func tipPill(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.ypLavender)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.ypText3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func permissionRow(icon: String, title: String, description: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.ypText1)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.ypText3)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.ypMint)
                    .font(.system(size: 20))
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: 12)
    }

    private func checkPermissions() {
        Task { @MainActor in
            accessibilityGranted = Permissions.hasAccessibilityPermission
            micPermissionGranted = await Permissions.hasMicrophonePermission
        }
    }

    private func startAccessibilityPolling() {
        accessibilityPollTask?.cancel()
        accessibilityPollTask = Task {
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                let granted = Permissions.hasAccessibilityPermission
                await MainActor.run {
                    accessibilityGranted = granted
                }
                if granted { break }
            }
        }
    }

    private func startModelLoading() {
        let settings = DataManager.shared.fetchSettings()
        settings.sttModelId = selectedSTTModel
        settings.llmModelId = selectedLLMModel
        try? DataManager.shared.container.mainContext.save()
        print("[OnboardingView] Saved STT: \(selectedSTTModel), LLM: \(selectedLLMModel)")

        Task {
            do {
                try await pipeline.loadModelsAtStartup()
            } catch {
                print("[OnboardingView] Model loading failed: \(error)")
                await MainActor.run {
                    loadingFailed = true
                }
            }
        }
    }
}
