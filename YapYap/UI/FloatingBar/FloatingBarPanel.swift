// FloatingBarPanel.swift
// YapYap — NSPanel for floating recording bar (never steals focus)
import AppKit

class FloatingBarPanel: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isMovableByWindowBackground = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.isOpaque = false
    }

    // Never become key window (never steal focus)
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func positionOnScreen(position: FloatingBarPosition) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let barFrame = self.frame

        let x: CGFloat
        let y: CGFloat

        switch position {
        case .bottomCenter:
            x = screenFrame.midX - barFrame.width / 2
            y = screenFrame.minY + 20
        case .bottomLeft:
            x = screenFrame.minX + 20
            y = screenFrame.minY + 20
        case .bottomRight:
            x = screenFrame.maxX - barFrame.width - 20
            y = screenFrame.minY + 20
        case .topCenter:
            x = screenFrame.midX - barFrame.width / 2
            y = screenFrame.maxY - barFrame.height - 20
        }

        self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func showBar() {
        orderFront(nil)
    }

    func hideBar() {
        orderOut(nil)
    }
}
