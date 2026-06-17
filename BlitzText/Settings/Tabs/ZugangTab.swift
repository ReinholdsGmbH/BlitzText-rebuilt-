import SwiftUI
import AVFoundation

// MARK: - Zugang

struct ZugangTab: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var draftKey: String = ""
    @State private var showKey: Bool = false
    @State private var saved: Bool = false
    @State private var permissionRefresh: Int = 0

    private var accessibilityGranted: Bool {
        _ = permissionRefresh
        return PermissionsHelper.accessibilityStatus() == .granted
    }
    private var microphoneStatus: PermissionsHelper.Status {
        _ = permissionRefresh
        return PermissionsHelper.microphoneStatus()
    }
    private var micSubtitle: String {
        switch microphoneStatus {
        case .granted: return "freigegeben"
        case .denied: return "abgelehnt — in Systemeinstellungen aktivieren"
        case .undetermined: return "noch nicht angefragt"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            VStack(alignment: .leading, spacing: 8) {
                Text("BERECHTIGUNGEN").font(.caption).foregroundStyle(.secondary).bold()
                permissionRow(
                    title: "Bedienungshilfen",
                    subtitle: "nötig für globale Hotkeys (fn + …) und direktes Einfügen",
                    granted: accessibilityGranted,
                    actionLabel: accessibilityGranted ? "Öffnen" : "Aktivieren"
                ) {
                    PermissionsHelper.requestAccessibilityPrompt()
                    PermissionsHelper.openAccessibilitySettings()
                }
                permissionRow(
                    title: "Mikrofon",
                    subtitle: micSubtitle,
                    granted: microphoneStatus == .granted,
                    actionLabel: microphoneStatus == .undetermined ? "Anfragen" : "Öffnen"
                ) {
                    if microphoneStatus == .undetermined {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in
                            DispatchQueue.main.async { permissionRefresh += 1 }
                        }
                    } else {
                        PermissionsHelper.openMicrophoneSettings()
                    }
                }
                Text("Nach dem Erteilen der Bedienungshilfen-Berechtigung sind die Hotkeys sofort aktiv — kein App-Neustart nötig.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Status aktualisieren") { permissionRefresh += 1 }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("OPENAI-API-KEY").font(.caption).foregroundStyle(.secondary).bold()
                Text("Wird gebraucht für: Cloud-Whisper-Backend, Blitztext+ / $%&! (Rewrite via gpt-4o-mini), KI-Eigennamen-Vorschläge. Bei rein lokalem Setup (Parakeet/Whisper-Local + Roh-Modus + KI-Vorschläge aus) ist er optional.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if showKey {
                        TextField("sk-…", text: $draftKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-…", text: $draftKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showKey ? "Verbergen" : "Anzeigen") { showKey.toggle() }
                }
                HStack {
                    Button("Speichern") {
                        settings.apiKey = draftKey
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftKey.isEmpty)
                    if saved { Text("Gespeichert ✓").foregroundStyle(.green) }
                    Spacer()
                    if !settings.apiKey.isEmpty {
                        Button("Löschen", role: .destructive) {
                            settings.apiKey = ""
                            draftKey = ""
                        }
                    }
                }
                Text("Der Schlüssel liegt in deinem macOS-Schlüsselbund (Service `de.reinholds.blitztext`, Account `openai-api-key`). Beim ersten Speichern und Lesen fragt der Schlüsselbund einmal nach Bestätigung — auf „Immer erlauben\" klicken.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("AUSGABE").font(.caption).foregroundStyle(.secondary).bold()
                Toggle("Direkt einfügen (statt nur Zwischenablage)", isOn: $settings.autoInsert)
            }

            Spacer(minLength: 0)
        }
        .onAppear { draftKey = settings.apiKey }
    }

    @ViewBuilder
    private func permissionRow(title: String, subtitle: String, granted: Bool, actionLabel: String, action: @escaping () -> Void) -> some View {
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
