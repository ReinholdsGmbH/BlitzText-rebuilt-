import AppKit
import SwiftUI

/// Fenster mit den aggregierten Release-Notes + Download-/Install-Button.
/// Analog zu `SettingsWindowController`: in Accessory-Apps (LSUIElement) braucht es ein
/// eigenständiges NSWindow, und für die Fokus-/Dock-Präsenz schalten wir kurz auf `.regular`.
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    private let service: UpdateService
    private var window: NSWindow?

    init(service: UpdateService) {
        self.service = service
        super.init()
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        let host = NSHostingController(
            rootView: UpdateView(onDismiss: { [weak self] in self?.window?.close() })
                .environmentObject(service)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BlitzText-Update"
        window.contentViewController = host
        window.setContentSize(NSSize(width: 560, height: 640))
        window.minSize = NSSize(width: 480, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Zurück zur Accessory-Policy (Dock-Icon weg), wenn kein anderes Fenster mehr offen ist.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
