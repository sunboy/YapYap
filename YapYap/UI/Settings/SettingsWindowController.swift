import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = "YapYap Settings"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0x2A/255.0, green: 0x25/255.0, blue: 0x40/255.0, alpha: 1)
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
