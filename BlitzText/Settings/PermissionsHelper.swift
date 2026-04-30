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

    /// Triggert den AX-Prompt — wirkt nur, wenn macOS ihn überhaupt noch zeigt.
    @discardableResult
    static func requestAccessibilityPrompt() -> Bool {
        let opts: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(opts)
    }
}
