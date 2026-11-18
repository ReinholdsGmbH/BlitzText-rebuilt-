import SwiftUI
import AVFoundation

// MARK: - Berechtigungen und Autostart

struct PermissionsSection: View {
    @EnvironmentObject var settings: SettingsStore

    /// Nach jeder nutzerinitiierten Aktion (AX-Prompt, Anmeldeobjekt-Eintrag) fragt der Poller
    /// den System-Status ~1 Minute im Sekundentakt nach — so springen die Badges um, ohne dass
    /// das Fenster neu geöffnet werden muss. `poller.tick` ist der Invalidierungs-Trigger.
    @StateObject private var poller = StatusPoller()

    private var accessibilityGranted: Bool {
        _ = poller.tick
        return PermissionsHelper.accessibilityStatus() == .granted
    }
    private var microphoneStatus: PermissionsHelper.Status {
        _ = poller.tick
        return PermissionsHelper.microphoneStatus()
    }
    private var loginItemStatus: LoginItemHelper.Status {
        _ = poller.tick
        return LoginItemHelper.status()
    }
    private var micSubtitle: String {
        switch microphoneStatus {
        case .granted: return "freigegeben"
        case .denied: return "abgelehnt — in Systemeinstellungen aktivieren"
        case .undetermined: return "noch nicht angefragt"
        }
    }
    private var loginItemSubtitle: String {
        switch loginItemStatus {
        case .enabled:          return "BlitzText startet beim Anmelden am Mac"
        case .requiresApproval: return "eingetragen — Schalter in den Systemeinstellungen noch einschalten"
        case .notRegistered:    return "aus — BlitzText muss nach dem Anmelden manuell gestartet werden"
        case .notFound:         return "nicht möglich: BlitzText muss im Ordner „Programme“ liegen"
        }
    }
    private var loginItemActionLabel: String {
        switch loginItemStatus {
        case .enabled:                        return "Deaktivieren"
        case .requiresApproval, .notFound:    return "Öffnen"
        case .notRegistered:                  return "Aktivieren"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            VStack(alignment: .leading, spacing: 8) {
                Text("BERECHTIGUNGEN").font(.caption).foregroundStyle(.secondary).bold()
                statusRow(
                    title: "Bedienungshilfen",
                    subtitle: "nötig für globale Hotkeys (fn + …) und direktes Einfügen",
                    granted: accessibilityGranted,
                    actionLabel: accessibilityGranted ? "Öffnen" : "Erlauben"
                ) {
                    // Der Aufruf mit Prompt-Option ist es, der BlitzText überhaupt in die
                    // Bedienungshilfen-Liste einträgt (Schalter aus). War der Zugriff schon
                    // erteilt, ist er ein No-Op — dann nur die Einstellungen öffnen.
                    PermissionsHelper.requestAccessibilityPrompt()
                    PermissionsHelper.openAccessibilitySettings()
                    poller.start()
                }
                statusRow(
                    title: "Mikrofon",
                    subtitle: micSubtitle,
                    granted: microphoneStatus == .granted,
                    actionLabel: microphoneStatus == .undetermined ? "Anfragen" : "Öffnen"
                ) {
                    if microphoneStatus == .undetermined {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in
                            DispatchQueue.main.async { poller.refreshOnce() }
                        }
                    } else {
                        PermissionsHelper.openMicrophoneSettings()
                        poller.start()
                    }
                }
                Text("BlitzText wird beim Klick auf „Erlauben“ in die Bedienungshilfen-Liste eingetragen — den Schalter dort musst du selbst umlegen (Passwort oder Touch ID). Danach springt die Anzeige hier von allein um; die Hotkeys sind sofort aktiv, kein App-Neustart nötig.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("AUTOMATISCHER START").font(.caption).foregroundStyle(.secondary).bold()
                statusRow(
                    title: "Beim Anmelden starten",
                    subtitle: loginItemSubtitle,
                    granted: loginItemStatus == .enabled,
                    actionLabel: loginItemActionLabel
                ) {
                    switch loginItemStatus {
                    case .enabled:
                        LoginItemHelper.unregister()
                    case .notRegistered:
                        // Legt den Eintrag unter „Beim Anmelden öffnen“ an. Verlangt macOS eine
                        // Bestätigung, landen wir auf `.requiresApproval` — dann direkt an die
                        // richtige Stelle in den Systemeinstellungen springen.
                        LoginItemHelper.register()
                        if LoginItemHelper.status() == .requiresApproval {
                            LoginItemHelper.openLoginItemsSettings()
                        }
                    case .requiresApproval, .notFound:
                        LoginItemHelper.openLoginItemsSettings()
                    }
                    poller.start()
                }
                Text("Auch hier legt BlitzText nur den Eintrag in Systemeinstellungen › Allgemein › Anmeldeobjekte an. Steht der Schalter dort aus, schaltest du ihn selbst ein — die Anzeige hier folgt automatisch.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Status aktualisieren") { poller.refreshOnce() }
            }

            Spacer(minLength: 0)
        }
        .onDisappear { poller.stop() }
    }

    @ViewBuilder
    private func statusRow(title: String, subtitle: String, granted: Bool, actionLabel: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionLabel, action: action)
        }
    }
}
