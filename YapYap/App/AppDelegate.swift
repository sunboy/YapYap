import AppKit
import SwiftData

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

    private func setupFloatingBar() {
        floatingBarPanel = FloatingBarPanel()
        let settings = DataManager.shared.fetchSettings()
        if settings.showFloatingBar {
            floatingBarPanel?.showBar(appState: appState)
        }
    }

    private func showOnboarding() {
        let onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        onboardingWindow.titlebarAppearsTransparent = true
        onboardingWindow.isMovableByWindowBackground = true
        onboardingWindow.center()
        onboardingWindow.contentView = NSHostingView(
            rootView: OnboardingView(appState: appState)
        )
        onboardingWindow.makeKeyAndOrderFront(nil)
    }
}
