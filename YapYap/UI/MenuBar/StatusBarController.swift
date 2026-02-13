import AppKit
import SwiftUI

class StatusBarController {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let appState: AppState
    private var creatureHostingView: NSHostingView<CreatureView>?
    private var eventMonitor: Any?

    init(appState: AppState) {
        self.appState = appState

        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        
        setupPopover()
        setupButton()
        setupEventMonitor()
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 420)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(appState: appState)
                .frame(width: 300)
        )
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }

        // Embed SwiftUI creature in the button
        let creatureView = CreatureView(state: appState.creatureState, size: 18)
        let hostingView = NSHostingView(rootView: creatureView)
        hostingView.frame = NSRect(x: 5, y: 2, width: 18, height: 18)
        button.addSubview(hostingView)
        creatureHostingView = hostingView

        button.action = #selector(handleClick)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            appState.updateStats()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit YapYap", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
