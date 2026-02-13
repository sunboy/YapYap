// OnboardingView.swift
// YapYap — First-launch onboarding wizard
import SwiftUI

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var micPermissionGranted = false
    @State private var accessibilityGranted = false
    @State private var selectedSTTModel = "parakeet-tdt-v3"
    @State private var selectedLLMModel = "qwen-2.5-3b"
    @State private var isDownloading = false
    var onComplete: () -> Void

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.ypLavender : Color.ypText4)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 24)

            Spacer()

            // Step content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: permissionsStep
                case 2: modelSelectionStep
                case 3: hotkeyTestStep
                case 4: doneStep
                default: EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep > 0 && currentStep < totalSteps - 1 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.ypText2)
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button(currentStep == 0 ? "Get Started" : "Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.ypLavender)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .frame(width: 520, height: 440)
        .background(Color.ypBg)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            CreatureView(state: .recording, size: 72)

            Text("Welcome to YapYap")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.ypText1)

            Text("You yap. It writes.")
                .font(.custom("Caveat", size: 18))
                .foregroundColor(.ypZzz)

            Text("YapYap is your cozy, offline voice-to-text companion.\nEverything runs locally on your Mac.")
                .font(.system(size: 13))
                .foregroundColor(.ypText2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Text("Permissions")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.ypText1)

            Text("YapYap needs two permissions to work:")
                .font(.system(size: 13))
                .foregroundColor(.ypText2)

            VStack(spacing: 12) {
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

                permissionRow(
                    icon: "♿️",
                    title: "Accessibility",
                    description: "To paste text and detect active apps",
                    isGranted: accessibilityGranted,
                    action: {
                        Permissions.requestAccessibilityPermission()
                        // Check after a delay since the system dialog is async
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            accessibilityGranted = Permissions.hasAccessibilityPermission
                        }
                    }
                )
            }
            .padding(.horizontal, 40)
        }
    }

    private func permissionRow(icon: String, title: String, description: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
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
        .padding(12)
        .background(Color.ypCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.ypBorder, lineWidth: 1)
        )
    }

    private var modelSelectionStep: some View {
        VStack(spacing: 16) {
            Text("Choose Your Models")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.ypText1)

            Text("Models are downloaded on first use. You can change these later.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Speech-to-Text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.ypText2)

                Picker("STT Model", selection: $selectedSTTModel) {
                    Text("Parakeet TDT v3 (~600MB) — Recommended").tag("parakeet-tdt-v3")
                    Text("Whisper Large v3 (~1.5GB)").tag("whisper-large-v3-turbo")
                    Text("Whisper Medium (~769MB)").tag("whisper-medium")
                    Text("Whisper Small (~244MB)").tag("whisper-small")
                }
                .labelsHidden()
            }
            .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                Text("Text Cleanup (LLM)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.ypText2)

                Picker("LLM Model", selection: $selectedLLMModel) {
                    Text("Qwen 2.5 3B (~2.0GB) — Recommended").tag("qwen-2.5-3b")
                    Text("Llama 3.2 3B (~2.0GB)").tag("llama-3.2-3b")
                    Text("Qwen 2.5 7B (~4.7GB)").tag("qwen-2.5-7b")
                    Text("Llama 3.1 8B (~4.7GB)").tag("llama-3.1-8b")
                }
                .labelsHidden()
            }
            .padding(.horizontal, 40)
        }
    }

    private var hotkeyTestStep: some View {
        VStack(spacing: 16) {
            Text("Try It Out")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.ypText1)

            Text("Hold ⌥ Space to record, release to transcribe")
                .font(.system(size: 13))
                .foregroundColor(.ypText2)

            VStack(spacing: 8) {
                hotkeyBadge("⌥ + Space", label: "Push-to-Talk")
                hotkeyBadge("⌥ + ⇧ + Space", label: "Hands-Free Mode")
                hotkeyBadge("⌥ + ⌘ + Space", label: "Command Mode")
                hotkeyBadge("Esc", label: "Cancel Recording")
            }
            .padding(.horizontal, 60)
        }
    }

    private func hotkeyBadge(_ keys: String, label: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.ypText2)
            Spacer()
            Text(keys)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.ypText1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.ypCard2)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.ypBorder, lineWidth: 1)
                )
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            CreatureView(state: .sleeping, size: 72)

            Text("You're all set!")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.ypText1)

            Text("I'll be sleeping in your menu bar.\nJust press ⌥ Space when you need me!")
                .font(.system(size: 13))
                .foregroundColor(.ypText2)
                .multilineTextAlignment(.center)

            Button("Start Yapping") {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .tint(.ypLavender)
            .controlSize(.large)
        }
    }
}
