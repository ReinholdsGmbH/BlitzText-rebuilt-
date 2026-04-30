import AppKit
import CoreGraphics

final class TextInserter {

    func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Simuliert ⌘V im Frontmost-App. Setzt Accessibility-Permission voraus.
    /// Verhindert Self-Paste in BlitzText selbst.
    func simulatePaste() {
        if let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           frontBundle == Bundle.main.bundleIdentifier {
            return
        }
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
