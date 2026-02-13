import AppKit
import SwiftData
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var appState = AppState()
    var pipeline: TranscriptionPipeline?
    var floatingBarPanel: FloatingBarPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar
        statusBarController = StatusBarController(appState: appState)

        // Setup pipeline
        pipeline = TranscriptionPipeline(appState: appState, container: DataManager.shared.container)

        // Setup hotkeys
        HotkeyManager.shared.configure(pipeline: pipeline!, appState: appState)

        // Setup floating bar
        setupFloatingBar()

        // Check for first launch
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }
    }

    @MainActor
    private func setupFloatingBar() {
        floatingBarPanel = FloatingBarPanel()

        // Set content view with FloatingBarView
        let floatingView = FloatingBarView(appState: appState)
        floatingBarPanel?.contentView = NSHostingView(rootView: floatingView)

        // Position the bar
        floatingBarPanel?.positionOnScreen(position: .bottomCenter)

        // Show if enabled in settings
        let settings = DataManager.shared.fetchSettings()
        if settings.showFloatingBar {
            floatingBarPanel?.showBar()
        }
    }

    private func showOnboarding() {
        DispatchQueue.main.async {
            let onboardingWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            onboardingWindow.title = "Welcome to YapYap"
            onboardingWindow.titlebarAppearsTransparent = true
            onboardingWindow.isMovableByWindowBackground = true
            onboardingWindow.level = .floating
            onboardingWindow.center()
            onboardingWindow.contentView = NSHostingView(
                rootView: OnboardingView {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    onboardingWindow.close()
                }
            )
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
