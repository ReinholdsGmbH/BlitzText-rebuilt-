import AppKit
import SwiftUI

/// Einstellung für die Ablage im Wissensordner (Baalda-Vault).
struct VaultSection: View {
    @EnvironmentObject var settings: SettingsStore

    private var exists: Bool {
        FileManager.default.fileExists(atPath: (settings.vaultRootPath as NSString).expandingTildeInPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Meetings sofort im Wissensordner ablegen", isOn: $settings.vaultExportEnabled)
            HStack(spacing: 8) {
                TextField("Ordner", text: $settings.vaultRootPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Button("Wählen …", action: choose)
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: (settings.vaultRootPath as NSString).expandingTildeInPath)) } label: {
                    Image(systemName: "folder")
                }
                .disabled(!exists)
            }
            if !exists {
                Label("Ordner nicht gefunden.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("Jedes Meeting landet als „TT.MM.JJ_hh.mm_Titel.md“ in „<Bereich>/transkripte/“, Überschrift „TT.MM.JJ_hh:mm_Titel“, Kopfzeile „**Projekt:**“ wie bei mw-route. Den Bereich erkennt BlitzText an denselben Stichwörtern; im Meeting lässt er sich ändern. Jede Korrektur (Sprecher, Notizen) aktualisiert die Datei. Die log.md des Bereichs bekommt beim ersten Ablegen eine Zeile.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: (settings.vaultRootPath as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url { settings.vaultRootPath = url.path }
    }
}

/// Darstellung: Dock-Symbol.
struct AppearanceSection: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Dock-Symbol") {
                Picker("", selection: $settings.dockIconMode) {
                    ForEach(DockIconMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            Text("Mit Dock-Symbol verhält sich BlitzText wie eine normale App: erreichbar über ⌘-Tab, Klick aufs Symbol holt das Fenster nach vorn. Ohne bleibt es eine reine Menüleisten-App.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Welches Stimmprofil man selbst ist.
struct SelfSpeakerSection: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var names: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Das bin ich") {
                Picker("", selection: $settings.selfSpeakerName) {
                    Text("Kein Profil").tag("")
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            Text("Diese Stimme erscheint in Meetings, Notizen und im Wissensordner als „Ich“, auch in importierten Mischspuren ohne eigene Mikrofonspur. Fehlt dein Profil, gib in einem Meeting deiner Stimme deinen Namen.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            names = SpeakerProfileStore().loadSpeakers().filter(\.isPermanent).map(\.name).sorted()
            if !settings.selfSpeakerName.isEmpty, !names.contains(settings.selfSpeakerName) {
                names.append(settings.selfSpeakerName)
            }
        }
    }
}
