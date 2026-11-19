import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var sharedFolder: SharedFolder
    @EnvironmentObject private var meetings: MeetingStore
    @State private var choosingFolder = false
    @State private var swipeEnabled = Spike.isSwipeEnabled
    @State private var digitsMode = Spike.digitsMode
    @State private var micOnRight = Spike.isMicOnRight

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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ziffern über den Buchstaben")
                        Picker("Ziffern", selection: $digitsMode) {
                            ForEach(Spike.DigitsMode.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: digitsMode) { _, value in Spike.digitsMode = value }
                    }
                    Picker("Mikro-Knopf", selection: $micOnRight) {
                        Text("Links").tag(false)
                        Text("Rechts").tag(true)
                    }
                    .onChange(of: micOnRight) { _, value in Spike.isMicOnRight = value }
                    Toggle("Swipe-Eingabe", isOn: $swipeEnabled)
                        .onChange(of: swipeEnabled) { _, value in Spike.defaults?.set(value, forKey: Spike.Key.swipeEnabled) }
                } header: {
                    Text("Tastatur")
                } footer: {
                    Text("Ziffern: „Langer Druck“ (Standard) legt sie auf q bis p, „Leiste“ zeigt 1 bis 0 als flache Reihe. Rücktaste 2 s halten löscht ganze Wörter.\n\nEinrichten: Einstellungen › Allgemein › Tastatur › Tastaturen › Tastatur hinzufügen › BlitzSpike, danach „Vollen Zugriff erlauben“. Den vollen Zugriff braucht das Mikro in der Tastatur.")
                }

                Section {
                    LabeledContent("Ordner", value: sharedFolder.folderName ?? "keiner")
                    Button(sharedFolder.isConfigured ? "Anderen Ordner wählen …" : "Ordner wählen …") { choosingFolder = true }
                    Toggle("Fertige Meetings automatisch ablegen", isOn: $sharedFolder.autoDeliver)
                        .disabled(!sharedFolder.isConfigured)
                    Button("Alle fertigen Meetings jetzt ablegen") {
                        Task {
                            for meeting in meetings.meetings where meeting.status == .done {
                                await session.share(meeting.id)
                            }
                        }
                    }
                    .disabled(!sharedFolder.isConfigured)
                    if let message = sharedFolder.lastMessage {
                        Text(message).font(.footnote).foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("Gemeinsame Ablage")
                } footer: {
                    Text("Ein Ordner in iCloud Drive oder OneDrive. Fertige Meetings landen dort unter „BlitzText iPhone“ mit Transkript, Notizen und Audio. Am Mac denselben Ordner unter Einstellungen › iPhone-Ablage wählen; die Mac-App übernimmt alles unverändert und legt das Protokoll im Wissensordner ab.")
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
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { sharedFolder.choose(url) }
            }
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
