import Foundation
import AppKit

/// Eine erkannte Meeting-Quelle: die App, deren Audio-Ausgabe mitgeschnitten würde.
struct MeetingSource: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case nativeApp      // Zoom, Teams, Webex als eigenständige App
        case browserTab     // Meeting läuft in einem Browser-Tab
    }

    let id: pid_t
    let kind: Kind
    let bundleIdentifier: String
    let displayName: String
    /// Nur bei `browserTab` belegt: der Fenstertitel, der die Einstufung getragen hat.
    let evidence: String?

    var pid: pid_t { id }
}

/// Findet heraus, ob gerade ein Meeting läuft, und liefert die Prozesse, deren Ausgabe
/// für einen Mitschnitt relevant ist.
///
/// Zwei Wege, beide ohne Netzzugriff und ohne Kalender:
///  1. Native Meeting-Apps über ihre Bundle-ID. Eindeutig, solange die App läuft.
///  2. Browser: macOS hängt an den Fenstertitel eines Fensters, dessen Tab Mikrofon oder
///     Kamera nutzt, einen Statuszusatz an („ — Microphone recording"). Das ist das
///     verlässlichste Signal, das sich ohne Browser-Erweiterung auslesen lässt: es sagt,
///     dass dort jemand aktiv an einer Konferenz teilnimmt, nicht bloß ein Video läuft.
///
/// Bewusste Grenze: Welcher Tab es ist und wie das Meeting heißt, steht hier nicht. Das
/// bräuchte einen Accessibility-Walk durch den Browser und kostet Laufzeit und eine
/// zusätzliche Berechtigung. Für die Auswahl der zu tappenden Prozesse reicht die PID.
struct MeetingDetector {

    /// Bundle-IDs nativer Konferenz-Apps. Teams führt mehrere Prozesse; `modulehost`
    /// ist der, der in neueren Versionen das Audio hält.
    static let meetingAppBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.microsoft.teams2.modulehost",
        "com.cisco.webexmeetingsapp",
        "com.webex.meetingmanager",
        "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan", // Meet als PWA
        "com.tinyspeck.slackmacgap"
    ]

    static let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",   // Arc
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi"
    ]

    /// Statuszusätze, die macOS/der Browser an den Fenstertitel hängt. Nur Mikrofon- und
    /// Kamerazusätze zählen als Meeting — „Audio playing" allein ist Musik oder ein Video.
    private static let conferencingTitleMarkers = [
        "camera and microphone recording",
        "microphone recording",
        "camera recording"
    ]

    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    /// Alle aktuell plausiblen Meeting-Quellen, native Apps zuerst.
    func detectSources() -> [MeetingSource] {
        let running = workspace.runningApplications
        var sources: [MeetingSource] = []

        for app in running {
            guard let bundleID = app.bundleIdentifier, !app.isTerminated else { continue }

            if Self.meetingAppBundleIDs.contains(bundleID) {
                sources.append(MeetingSource(
                    id: app.processIdentifier,
                    kind: .nativeApp,
                    bundleIdentifier: bundleID,
                    displayName: app.localizedName ?? bundleID,
                    evidence: nil
                ))
                continue
            }

            if Self.browserBundleIDs.contains(bundleID),
               let marker = conferencingMarker(forPID: app.processIdentifier) {
                sources.append(MeetingSource(
                    id: app.processIdentifier,
                    kind: .browserTab,
                    bundleIdentifier: bundleID,
                    displayName: app.localizedName ?? bundleID,
                    evidence: marker
                ))
            }
        }
        // Hilfsprozesse derselben App nicht doppelt führen (Teams + Teams ModuleHost).
        // Ihre Audio-PIDs sammelt der Tap ohnehin über `MeetingAudioMatcher` ein.
        return sources.filter { candidate in
            !sources.contains { candidate.bundleIdentifier.hasPrefix($0.bundleIdentifier + ".") }
        }
    }

    /// Kurzform für die Statusanzeige: läuft gerade irgendwo ein Meeting?
    func isMeetingLikely() -> Bool { !detectSources().isEmpty }

    /// Durchsucht die Fenstertitel eines Browser-Prozesses nach dem Mikrofon-/Kamera-Zusatz.
    ///
    /// Läuft über die Accessibility-API, die BlitzText für den Auto-Insert ohnehin hat.
    /// Ohne diese Berechtigung liefert der Walk nichts — dann bleibt die Browser-Erkennung
    /// still aus, statt zu raten.
    private func conferencingMarker(forPID pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &windowsValue
        ) == .success, let windows = windowsValue as? [AXUIElement] else { return nil }

        for window in windows {
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window, kAXTitleAttribute as CFString, &titleValue
            ) == .success, let title = titleValue as? String else { continue }

            let lowered = title.lowercased()
            if let marker = Self.conferencingTitleMarkers.first(where: { lowered.contains($0) }) {
                return marker
            }
        }
        return nil
    }
}
