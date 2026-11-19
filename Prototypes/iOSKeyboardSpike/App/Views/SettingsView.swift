import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionController
    @State private var swipeEnabled = Spike.isSwipeEnabled

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Auto-Stop bei Leerlauf", selection: $session.idleLimitMinutes) {
                        Text("5 min").tag(5)
                        Text("30 min").tag(30)
                        Text("aus").tag(0)
                    }
                } header: {
                    Text("Session")
                } footer: {
                    Text("Solange die Session läuft, ist das Mikrofon offen (orange Anzeige). Ohne Diktat endet sie nach der gewählten Zeit.")
                }

                Section {
                    Toggle("Swipe-Eingabe", isOn: $swipeEnabled)
                        .onChange(of: swipeEnabled) { _, value in Spike.defaults?.set(value, forKey: Spike.Key.swipeEnabled) }
                } header: {
                    Text("Tastatur")
                } footer: {
                    Text("Einrichten: Einstellungen › Allgemein › Tastatur › Tastaturen › Tastatur hinzufügen › BlitzSpike, danach „Vollen Zugriff erlauben“. Den vollen Zugriff braucht das Mikro in der Tastatur.")
                }

                Section("Status") {
                    LabeledContent("App Group", value: session.appGroupOK ? "ok" : "fehlt")
                    LabeledContent("Spracherkennung", value: session.modelStatus)
                    if let start = session.batteryAtStart {
                        LabeledContent("Akku Start / jetzt",
                                       value: "\(Int(start * 100)) % / \(Int(session.batteryNow * 100)) %")
                    }
                    NavigationLink("Protokoll") { LogView() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Einstellungen")
        }
    }
}

struct LogView: View {
    @EnvironmentObject private var session: SessionController

    var body: some View {
        List(session.log, id: \.self) { line in
            Text(line).font(.caption.monospaced())
        }
        .navigationTitle("Protokoll")
        .toolbar {
            ShareLink(item: session.log.joined(separator: "\n"))
        }
    }
}
