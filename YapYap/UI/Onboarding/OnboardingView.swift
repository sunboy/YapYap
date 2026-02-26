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
                    onComplete()
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            // Creature with halo glow
            ZStack {
                RadialGradient(
                    colors: [.ypLavender.opacity(0.3), .clear],
                    center: .center, startRadius: 0, endRadius: 60
                )
                .frame(width: 120, height: 120)
                .blur(radius: 20)
                CreatureView(state: .recording, size: 80)
            }

            Text("Welcome to YapYap")
                .font(.ypDisplayRounded)
                .foregroundColor(.ypText1)

            Text("You yap. It writes.")
                .font(.custom("Caveat", size: 18))
                .foregroundColor(.ypZzz)

            Text("YapYap is your cozy, offline voice-to-text companion.\nEverything runs locally on your Mac.")
                .font(.ypSubheadRounded)
                .foregroundColor(.ypText2)
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
        VStack(spacing: 16) {
            Text("Choose Your Models")
                .font(.ypHeadingRounded)
                .foregroundColor(.ypText1)

            Text("Models download once and run fully offline.\nYou can change these later in Settings.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Speech-to-Text")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.ypText2)

                Picker("STT Model", selection: $selectedSTTModel) {
                    ForEach(STTModelRegistry.allModels, id: \.id) { model in
                        Text("\(model.name) (\(model.sizeDescription))\(model.isRecommended ? " — Recommended" : "")").tag(model.id)
                    }
                }
                .labelsHidden()

                if let model = STTModelRegistry.allModels.first(where: { $0.id == selectedSTTModel }) {
                    Text(model.description)
                        .font(.system(size: 11))
                        .foregroundColor(.ypText3)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                Text("Text Cleanup (LLM)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.ypText2)

                Picker("LLM Model", selection: $selectedLLMModel) {
                    ForEach(LLMModelRegistry.allModels, id: \.id) { model in
                        Text("\(model.name) (\(model.sizeDescription))\(model.isRecommended ? " — Recommended" : "")").tag(model.id)
                    }
                }
                .labelsHidden()

                if let model = LLMModelRegistry.allModels.first(where: { $0.id == selectedLLMModel }) {
                    Text(model.description)
                        .font(.system(size: 11))
                        .foregroundColor(.ypText3)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 40)
        }
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
        VStack(spacing: 16) {
            ZStack {
                RadialGradient(
                    colors: [.ypMint.opacity(0.3), .clear],
                    center: .center, startRadius: 0, endRadius: 60
                )
                .frame(width: 120, height: 120)
                .blur(radius: 20)
                CreatureView(state: .sleeping, size: 80)
            }

            Text("You're all set!")
                .font(.ypHeadingRounded)
                .foregroundColor(.ypText1)

            Text("I'll be sleeping in your menu bar.\nJust press \(KeyboardShortcuts.getShortcut(for: .pushToTalk)?.description ?? "⌥ Space") when you need me!")
                .font(.system(size: 13))
                .foregroundColor(.ypText2)
                .multilineTextAlignment(.center)

            Text("Each time you launch YapYap, models load automatically — this takes about 30 seconds. You'll see a progress bar in the floating bar.")
                .font(.system(size: 11))
                .foregroundColor(.ypText3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 4)
        }
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
