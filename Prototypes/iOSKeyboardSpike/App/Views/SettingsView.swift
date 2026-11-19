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
                    NavigationLink {
                        UserWordsView()
                    } label: {
                        LabeledContent("Eigene Wörter", value: "\(Spike.userWords.count)")
                    }
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

/// Eigene Wörter der Tastatur: Namen und Fachbegriffe für Vorschläge und Swipe.
struct UserWordsView: View {
    @State private var words: [String] = Spike.userWords
    @State private var newWord = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Neues Wort, z. B. ein Name", text: $newWord)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("Hinzufügen", action: add)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("In der Tastatur: unbekanntes Wort tippen, dann den Vorschlag in „…“ antippen. Es landet hier.")
            }
            Section("\(words.count) Wörter") {
                ForEach(words, id: \.self) { Text($0) }
                    .onDelete { offsets in
                        words.remove(atOffsets: offsets)
                        Spike.userWords = words
                    }
            }
        }
        .navigationTitle("Eigene Wörter")
        .onAppear { words = Spike.userWords }
    }

    private func add() {
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        Spike.userWords = words + [word]
        words = Spike.userWords
        newWord = ""
    }
}
