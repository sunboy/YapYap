import AppKit
import SwiftData
import SwiftUI
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var appState = AppState()
    var pipeline: TranscriptionPipeline?
    var floatingBarPanel: FloatingBarPanel?
    var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationDidFinishLaunching starting...")

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        print("[AppDelegate] Set activation policy to accessory")

        // Initialize DataManager first (may fail gracefully now)
        print("[AppDelegate] Initializing DataManager...")
        let dataManager = DataManager.shared
        print("[AppDelegate] DataManager initialized")

        // Load settings and configure managers
        let settings = dataManager.fetchSettings()
        print("[AppDelegate] Settings loaded: soundFeedback=\(settings.soundFeedback), hapticFeedback=\(settings.hapticFeedback)")
        SoundManager.shared.setEnabled(settings.soundFeedback)
        HapticManager.shared.setEnabled(settings.hapticFeedback)

        // Setup menu bar
        print("[AppDelegate] Setting up status bar...")
        statusBarController = StatusBarController(appState: appState)

        // Setup pipeline
        print("[AppDelegate] Setting up pipeline...")
        pipeline = TranscriptionPipeline(appState: appState, container: dataManager.container)

        // Setup hotkeys
        print("[AppDelegate] Configuring hotkeys...")
        HotkeyManager.shared.configure(pipeline: pipeline!, appState: appState)

        // Setup floating bar on main actor
        Task { @MainActor in
            self.setupFloatingBar()
        }

        // Check for first launch
        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        print("[AppDelegate] hasCompletedOnboarding: \(hasOnboarded)")
        if !hasOnboarded {
            print("[AppDelegate] Showing onboarding...")
            showOnboarding()
        } else {
            print("[AppDelegate] Onboarding already completed")

            // Check microphone permission status and request if needed
            Task {
                let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                print("[AppDelegate] Microphone permission status at startup: \(micStatus.rawValue)")
                print("[AppDelegate] Status meanings: 0=notDetermined, 1=restricted, 2=denied, 3=authorized")

                if micStatus == .notDetermined {
                    print("[AppDelegate] Requesting microphone permission...")
                    let granted = await AudioCaptureManager.requestMicrophonePermission()
                    print("[AppDelegate] Permission request result: \(granted)")
                } else if micStatus == .denied {
                    print("[AppDelegate] ⚠️ Microphone permission DENIED - user needs to enable in System Settings")
                } else if micStatus == .authorized {
                    print("[AppDelegate] ✅ Microphone permission already GRANTED")
                }

                // Load models in background after permission check
                print("[AppDelegate] Loading models at startup...")
                do {
                    try await pipeline?.loadModelsAtStartup()
                    print("[AppDelegate] ✅ Models loaded, app ready to transcribe")
                } catch {
                    print("[AppDelegate] ❌ Failed to load models at startup: \(error)")
                }
            }
        }

        print("[AppDelegate] applicationDidFinishLaunching complete")
    }

    @MainActor
    private func setupFloatingBar() {
        floatingBarPanel = FloatingBarPanel()

        // Set content view with FloatingBarView
        let floatingView = FloatingBarView(appState: appState)
        floatingBarPanel?.contentView = NSHostingView(rootView: floatingView)

        // Position the bar
        floatingBarPanel?.positionOnScreen(position: .bottomCenter)

        // Show the bar if setting is enabled (will show resting character)
        let settings = DataManager.shared.fetchSettings()
        if settings.showFloatingBar {
            print("[AppDelegate] Showing floating bar at launch (resting state)")
            floatingBarPanel?.showBar()
        } else {
            floatingBarPanel?.hideBar()
        }

        // Observe recording state to show/hide floating bar
        startObservingRecordingState()
    }

    @MainActor
    private func startObservingRecordingState() {
        print("[AppDelegate] startObservingRecordingState() starting observation loop")
        var lastRecordingState = false
        var lastBarVisibleState = false

        Task {
            while !Task.isCancelled {
                let isRecording = appState.isRecording
                let settings = DataManager.shared.fetchSettings()

                // Bar should be visible whenever showFloatingBar setting is enabled
                // (it will show resting character when idle, waveform when recording)
                let shouldShowBar = settings.showFloatingBar

                // Only log when state changes to avoid spam
                if isRecording != lastRecordingState {
                    print("[AppDelegate] Recording state changed: \(isRecording), showFloatingBar setting: \(settings.showFloatingBar)")
                    lastRecordingState = isRecording
                }

                // Only update bar visibility if state actually changed
                if shouldShowBar != lastBarVisibleState {
                    if shouldShowBar {
                        print("[AppDelegate] Showing floating bar")
                        floatingBarPanel?.showBar()
                    } else {
                        print("[AppDelegate] Hiding floating bar")
                        floatingBarPanel?.hideBar()
                    }
                    lastBarVisibleState = shouldShowBar
                }

                // Small delay to avoid tight loop
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
    }

    private func showOnboarding() {
        print("[AppDelegate] showOnboarding() called")

        // Ensure we're on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                print("[AppDelegate] showOnboarding: self is nil")
                return
            }

            print("[AppDelegate] Creating onboarding window...")

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to YapYap"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.level = .floating
            window.center()

            // Disable TouchBar to prevent AppKit TouchBar-related crashes
            window.toolbar = nil

            // Store reference BEFORE creating the content view to ensure it's retained
            self.onboardingWindow = window

            // Create completion handler with delayed cleanup to avoid use-after-free
            let onComplete = { [weak self] in
                print("[AppDelegate] Onboarding complete callback triggered")
                // Use a single main.async without nesting, and delay window release
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    print("[AppDelegate] Closing onboarding window...")

                    // Hide window first, then release after a delay
                    self.onboardingWindow?.orderOut(nil)

                    // Delayed cleanup to avoid autorelease pool issues
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        print("[AppDelegate] Releasing onboarding window")
                        self?.onboardingWindow = nil
                    }
                }
            }

            window.contentView = NSHostingView(rootView: OnboardingView(onComplete: onComplete))

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            print("[AppDelegate] Onboarding window shown")
        }
    }
}
