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
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    static func openMicrophoneSettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }

    /// Öffnet Systemeinstellungen › Datenschutz & Sicherheit beim gegebenen Anker.
    ///
    /// Der Pane-Bezeichner ist seit Ventura `com.apple.settings.PrivacySecurity.extension`.
    /// Der alte `com.apple.preference.security` wird auf macOS 26 zwar noch akzeptiert, landet
    /// aber auf „Allgemein" statt beim Anker (verifiziert 2026-08-22) — deshalb der neue Pfad
    /// zuerst und der alte nur als Fallback, falls Apple ihn erneut umbenennt.
    private static func openPrivacySettings(anchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
        Log.write("PermissionsHelper: Systemeinstellungen (\(anchor)) ließen sich nicht öffnen")
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
