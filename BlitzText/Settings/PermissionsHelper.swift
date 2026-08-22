import AppKit
import AVFoundation
import ApplicationServices

/// Liest und öffnet macOS-Permissions, die BlitzText braucht.
@MainActor
enum PermissionsHelper {

    enum Status {
        case granted
        case denied
        case undetermined
    }

    static func accessibilityStatus() -> Status {
        AXIsProcessTrusted() ? .granted : .denied
    }

    static func microphoneStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .denied
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Fragt den AX-Zugriff MIT Prompt-Option ab. Genau dieser Aufruf trägt BlitzText in
    /// Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen ein (Schalter zunächst
    /// aus) — das Umlegen des Schalters bleibt die passwortgeschützte Aktion des Nutzers.
    ///
    /// War der Zugriff schon erteilt, passiert nichts: kein zweiter Prompt, kein Nebeneffekt.
    @discardableResult
    static func requestAccessibilityPrompt() -> Bool {
        guard accessibilityStatus() != .granted else { return true }
        // Literal statt `kAXTrustedCheckOptionPrompt`: die globale CFString-Konstante ist
        // ein `var` und damit unter Swift-6-Concurrency nicht nutzbar.
        let opts: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(opts)
    }
}
