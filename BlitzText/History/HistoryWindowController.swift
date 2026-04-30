import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController {
    private let history: HistoryStore
    private var window: NSWindow?

    init(history: HistoryStore) {
        self.history = history
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        let host = NSHostingController(rootView: HistoryView().environmentObject(history))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Verlauf"
        window.contentViewController = host
        window.setContentSize(NSSize(width: 720, height: 600))
        window.minSize = NSSize(width: 520, height: 400)
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
