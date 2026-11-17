import AppKit
import SwiftUI

// MARK: Meeting-Liste

struct MeetingListColumn: View {
    @ObservedObject var library: MeetingLibrary
    @ObservedObject var controller: MeetingController
    @Binding var search: String

    private var filtered: [MeetingLibrary.Entry] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return library.entries }
        return library.entries.filter { entry in
            MeetingMarkdown.title(for: entry.document).lowercased().contains(needle)
                || entry.document.lines.contains { $0.text.lowercased().contains(needle) }
                || entry.document.speakerNames.values.contains { $0.lowercased().contains(needle) }
        }
    }

    /// Nach Kalendertag gruppiert, neuester zuerst — wie „TODAY, NOV 17“ bei Wispr.
    private var groups: [(day: Date, entries: [MeetingLibrary.Entry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.document.startedAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Meetings").font(.system(size: 22, weight: .semibold)).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 4)
                Button { controller.chooseAndImport() } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(SandButtonStyle())
                    .help("Aufnahme importieren, z. B. aus MacWhisper")
                    .disabled(controller.isRecording || controller.isProcessing)
                Button { controller.revealArchive() } label: { Image(systemName: "folder") }
                    .buttonStyle(SandButtonStyle())
                    .help("Meeting-Ordner im Finder zeigen")
                Button { controller.toggle() } label: {
                    // Bei wenig Platz nur das Symbol, statt in die Nachbarspalte zu laufen.
                    ViewThatFits(in: .horizontal) {
                        Label(controller.isRecording ? "Beenden" : "Aufnehmen",
                              systemImage: controller.isRecording ? "stop.circle" : "record.circle")
                        Image(systemName: controller.isRecording ? "stop.circle" : "record.circle")
                    }
                }
                .buttonStyle(SandButtonStyle())
                .disabled(controller.isProcessing)
                .help(controller.isRecording
                      ? "Beendet die Aufnahme; danach entstehen Transkript, Sprecher und Notizen."
                      : "Startet sofort eine Aufnahme: dein Mikrofon und der Ton der Konferenz-App, getrennt.")
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(MeetingTheme.foregroundTertiary)
                TextField("Meetings durchsuchen", text: $search).textFieldStyle(.plain).font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(MeetingTheme.backgroundTertiary))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if library.entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar").font(.system(size: 26)).foregroundStyle(MeetingTheme.foregroundTertiary)
                    Text("Noch keine Meetings").font(.system(size: 15, weight: .medium))
                    Button("Aufnahme importieren") { controller.chooseAndImport() }
                        .buttonStyle(LavenderButtonStyle(compact: true))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(groups, id: \.day) { group in
                            Text(dayLabel(group.day))
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(MeetingTheme.foregroundTertiary)
                                .padding(.horizontal, 12)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                            ForEach(group.entries) { entry in
                                MeetingRow(entry: entry, library: library,
                                           selected: MeetingLibrary.key(entry.folder) == library.selection.map(MeetingLibrary.key)) {
                                    library.selection = entry.folder
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE, d. MMM"
        let prefix = calendar.isDateInToday(day) ? "HEUTE, " : (calendar.isDateInYesterday(day) ? "GESTERN, " : "")
        return (prefix + formatter.string(from: day)).uppercased()
    }
}

private struct MeetingRow: View {
    let entry: MeetingLibrary.Entry
    @ObservedObject var library: MeetingLibrary
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @State private var confirmDelete = false
    @State private var renaming = false
    @State private var draftTitle = ""

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundStyle(MeetingTheme.foregroundTertiary)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(MeetingTheme.backgroundTertiary))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(MeetingMarkdown.title(for: entry.document))
                            .font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                        if !entry.document.unconfirmedSpeakerIDs.isEmpty {
                            Circle().fill(MeetingTheme.glow300).frame(width: 6, height: 6)
                                .help("Sprecher zuordnen")
                        }
                    }
                    Text(entry.document.startedAt, format: .dateTime.hour().minute())
                        .font(.system(size: 12)).foregroundStyle(MeetingTheme.foregroundTertiary)
                }
                Spacer(minLength: 4)
                if hovering || selected {
                    // Wie Wispr: Aktionen erscheinen erst beim Überfahren der Zeile.
                    Menu { actions } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 7).fill(MeetingTheme.backgroundSecondary))
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .fixedSize()
                } else {
                    HStack(spacing: 5) {
                        GreenWave()
                        Text(MeetingMarkdown.clock(entry.document.duration, alwaysHours: false))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                    }
                    .foregroundStyle(MeetingTheme.success)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? MeetingTheme.backgroundTertiary : (hovering ? MeetingTheme.backgroundTertiary.opacity(0.6) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { actions }
        .alert("Meeting umbenennen", isPresented: $renaming) {
            TextField("Titel", text: $draftTitle)
            Button("Speichern") { library.rename(in: entry.folder, to: draftTitle) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Leer lassen setzt auf den automatischen Titel zurück. Datum und Uhrzeit stehen in der Ablage immer davor.")
        }
        .confirmationDialog("„\(MeetingMarkdown.title(for: entry.document))“ löschen?", isPresented: $confirmDelete) {
            Button("In den Papierkorb", role: .destructive) { library.delete(entry) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Protokoll, Transkript und Audiospuren landen im Papierkorb. Gelernte Stimmprofile bleiben erhalten.")
        }
    }
}

extension MeetingRow {
    /// Dieselben Einträge im „…“-Menü und im Rechtsklick-Menü.
    @ViewBuilder
    fileprivate var actions: some View {
        Button { draftTitle = entry.document.aiTitle ?? ""; renaming = true } label: {
            Label("Umbenennen …", systemImage: "pencil")
        }
        Button { Task { await library.regenerateTitle(in: entry.folder) } } label: {
            Label("Titel neu erzeugen", systemImage: "sparkles")
        }
        .disabled(entry.document.lines.isEmpty || library.busy != nil)
        Divider()
        Button { library.reveal(entry) } label: { Label("Im Finder zeigen", systemImage: "folder") }
        Button { library.copyTranscript(of: entry) } label: { Label("Transkript kopieren", systemImage: "doc.on.doc") }
        Button { library.copyNotes(of: entry) } label: { Label("Notizen kopieren", systemImage: "text.alignleft") }
        Divider()
        Button(role: .destructive) { confirmDelete = true } label: { Label("Löschen", systemImage: "trash") }
    }
}

/// Die kleine grüne Wellenform neben der Dauer.
struct GreenWave: View {
    private let heights: [CGFloat] = [3, 5, 8, 11, 7, 4, 6, 3]
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule().fill(MeetingTheme.success).frame(width: 1.6, height: heights[i])
            }
        }
        .frame(height: 12)
    }
}

struct EmptyDetail: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Kein Meeting gewählt").font(.system(size: 15, weight: .medium))
            Text("Links ein Meeting auswählen oder mitschreiben.")
                .font(.system(size: 13)).foregroundStyle(MeetingTheme.foregroundTertiary)
        }
    }
}

struct Toast: View {
    @ObservedObject var library: MeetingLibrary

    var body: some View {
        Group {
            if let busy = library.busy {
                bubble { ProgressView().controlSize(.small).tint(MeetingTheme.sand50); Text(busy) }
            } else if let error = library.lastError {
                bubble {
                    Circle().fill(MeetingTheme.coral).frame(width: 7, height: 7)
                    Text(error).lineLimit(2)
                    Button { library.lastError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 22)
    }

    private func bubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MeetingTheme.sand50)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(MeetingTheme.vast950))
    }
}

// MARK: - Detail

struct MeetingDetailView: View {
    let entry: MeetingLibrary.Entry
    @ObservedObject var library: MeetingLibrary
    @StateObject private var player = SnippetPlayer()
    @State private var tab: Tab = .notes
    @State private var transcriptSearch = ""

    enum Tab: Hashable { case notes, myNotes, transcript }

    private var document: MeetingDocument { entry.document }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !document.unconfirmedSpeakerIDs.isEmpty {
                    SpeakerAssignmentCard(entry: entry, library: library, player: player)
                }
                HStack {
                    CapsuleToggle(options: [(Tab.notes, "Zusammenfassung"), (Tab.myNotes, "Meine Notizen"), (Tab.transcript, "Transkript")], selection: $tab)
                    Spacer()
                    if tab == .notes {
                        Button("Kopieren") { library.copyNotes(of: entry) }
                            .buttonStyle(SandButtonStyle()).disabled(document.summary == nil)
                        Button("Neu erstellen") { Task { await library.regenerateSummary(in: entry.folder) } }
                            .buttonStyle(SandButtonStyle())
                            .disabled(library.busy != nil || document.lines.isEmpty)
                    } else if tab == .transcript {
                        Button("Transkript kopieren") { library.copyTranscript(of: entry) }.buttonStyle(SandButtonStyle())
                    }
                }
                switch tab {
                case .notes: notes
                case .myNotes:
                    NotesEditor(initial: document.userNotes ?? "",
                                hint: "Fließt beim nächsten „Neu erstellen“ in die Zusammenfassung ein und steht im Protokoll und im Wissensordner.") { text in
                        library.setUserNotes(text, in: entry.folder)
                    }
                case .transcript: transcript
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .onDisappear { player.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MeetingMarkdown.title(for: document)).font(.system(size: 22, weight: .semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(dateLine)
                Text("•")
                Text(MeetingMarkdown.clock(document.duration, alwaysHours: false))
                Spacer()
                if library.vaultEnabled { vaultMenu }
                Button { library.reveal(entry) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).foregroundStyle(MeetingTheme.foregroundTertiary).help("Im Finder zeigen")
            }
            .font(.system(size: 12.5))
            .foregroundStyle(MeetingTheme.foregroundTertiary)

            if !participants.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(participants.enumerated()), id: \.offset) { _, item in
                        if let id = item.2 {
                            RenameTag(name: item.0, colors: item.1, speakerID: id, entry: entry, library: library)
                        } else {
                            SpeakerTag(name: item.0, colors: item.1)
                        }
                    }
                }
                }
                .padding(.top, 4)
            }
            ForEach(document.notes, id: \.self) { note in
                Text(note).font(.system(size: 11.5)).foregroundStyle(MeetingTheme.foregroundTertiary)
            }
        }
    }

    /// Bereich im Wissensordner: zeigt, wo das Meeting liegt, und lässt es umziehen.
    private var vaultMenu: some View {
        let key = document.project ?? "eingang"
        let label = VaultExporter.areas.first { $0.key == key }?.label ?? "Eingang"
        return Menu {
            Section("Bereich im Wissensordner") {
                ForEach(VaultExporter.areas, id: \.key) { area in
                    Button {
                        if area.key != key { library.setProject(area.key, in: entry.folder) }
                    } label: {
                        if area.key == key { Label(area.label, systemImage: "checkmark") } else { Text(area.label) }
                    }
                }
            }
            Divider()
            if document.vaultFile != nil {
                Button("Im Wissensordner zeigen") { library.revealInVault(entry) }
            }
            Button(document.vaultFile == nil ? "Jetzt ablegen" : "Erneut ablegen") { library.exportAgain(in: entry.folder) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: document.vaultFile == nil ? "tray" : "checkmark.circle.fill")
                    .foregroundStyle(document.vaultFile == nil ? MeetingTheme.foregroundTertiary : MeetingTheme.success)
                Text(label)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(MeetingTheme.backgroundTertiary))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help(document.vaultFile.map { "Im Wissensordner: \($0)" } ?? "Noch nicht im Wissensordner")
    }

    private var dateLine: String {
        let calendar = Calendar.current
        let time = document.startedAt.formatted(.dateTime.hour().minute())
        if calendar.isDateInToday(document.startedAt) { return "Heute • \(time)" }
        if calendar.isDateInYesterday(document.startedAt) { return "Gestern • \(time)" }
        return document.startedAt.formatted(.dateTime.day().month(.wide).year()) + " • \(time)"
    }

    /// Teilnehmende als (Name, Farben, Sprecher-ID). Nur Stimmen mit ID lassen sich umbenennen.
    private var participants: [(String, (fill: Color, text: Color), String?)] {
        var result: [(String, (fill: Color, text: Color), String?)] = []
        if document.lines.contains(where: { $0.speaker == .me }) { result.append(("Ich", MeetingTheme.meColors, nil)) }
        for (index, id) in document.speakerIDs.enumerated() {
            result.append((document.label(forSpeaker: id), MeetingTheme.speaker(index), id))
        }
        if document.speakerIDs.isEmpty, document.lines.contains(where: { $0.speaker == .others }) {
            result.append(("Andere", MeetingTheme.speaker(0), nil))
        }
        return result
    }

    @ViewBuilder
    private var notes: some View {
        if let summary = document.summary {
            SummaryText(markdown: summary)
        } else {
            Text(document.lines.isEmpty ? "Es wurde keine Sprache erkannt." : "Noch keine Notizen. „Neu erstellen“ fasst das Transkript zusammen.")
                .font(.system(size: 13)).foregroundStyle(MeetingTheme.foregroundTertiary)
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(MeetingTheme.foregroundTertiary)
                TextField("Transkript durchsuchen", text: $transcriptSearch).textFieldStyle(.plain).font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(MeetingTheme.backgroundTertiary))

            let needle = transcriptSearch.lowercased()
            // Index im Dokument mitführen: Umhängen muss auch in der gefilterten Ansicht den
            // richtigen Beitrag treffen.
            let lines = document.lines.enumerated()
                .map { (index: $0.offset, line: $0.element) }
                .filter { needle.isEmpty || $0.line.text.lowercased().contains(needle) }
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(lines, id: \.index) { item in
                    let line = item.line
                    let id = "line-\(line.start)-\(line.speaker.rawValue)"
                    Bubble(line: line, label: document.label(for: line), nameColor: nameColor(for: line),
                           playing: player.playingID == id,
                           choices: document.canReassign(line) ? speakerChoices : [],
                           known: library.knownNames,
                           onReassign: { target in library.reassign(lineAt: item.index, to: target, in: entry.folder) }) {
                        player.toggle(id: id, url: entry.folder.appendingPathComponent(document.trackFile(for: line)),
                                      start: line.start, end: line.end)
                    }
                }
                if lines.isEmpty {
                    Text(document.lines.isEmpty ? "Es wurde keine Sprache erkannt." : "Keine Treffer.")
                        .font(.system(size: 13)).foregroundStyle(MeetingTheme.foregroundTertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(MeetingTheme.panel))
        }
    }

    /// Personen, denen ein Beitrag der Gegenseite zugeordnet werden kann.
    private var speakerChoices: [(id: String, label: String)] {
        document.speakerIDs.map { ($0, document.label(forSpeaker: $0)) }
    }

    /// Namensfarbe über der Sprechblase: die kräftige Variante der Sprecherfarbe.
    private func nameColor(for line: TranscriptLine) -> Color {
        guard line.speaker == .others else { return MeetingTheme.foreground }
        guard let id = line.speakerID, let index = document.speakerIDs.firstIndex(of: id) else {
            return MeetingTheme.evergreen
        }
        let palette: [Color] = [MeetingTheme.evergreen, MeetingTheme.glow300.opacity(0.95), MeetingTheme.dawn700,
                                Color(hex: 0x368855), Color(hex: 0xA550A7), Color(hex: 0x7232A6), Color(hex: 0xAF6A06)]
        return palette[index % palette.count]
    }
}

/// Ein Redebeitrag als weiße Sprechblase mit kleinem farbigem Namen darüber,
/// wie das Transkript auf wisprflow.ai.
private struct Bubble: View {
    let line: TranscriptLine
    let label: String
    let nameColor: Color
    let playing: Bool
    /// Personen zur Auswahl; leer heißt: dieser Beitrag lässt sich nicht umhängen.
    var choices: [(id: String, label: String)] = []
    var known: [String] = []
    var onReassign: (MeetingLibrary.ReassignTarget) -> Void = { _ in }
    let onPlay: () -> Void
    @State private var hovering = false
    @State private var askingName = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                speakerLabel
                Text(MeetingMarkdown.clock(line.start, alwaysHours: false))
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(MeetingTheme.foregroundTertiary)
                if hovering || playing {
                    PlayButton(playing: playing, action: onPlay)
                }
            }
            .frame(height: 16)
            Text(line.text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(MeetingTheme.card))
        }
        .onHover { hovering = $0 }
    }

    /// Name über der Blase. Bei umhängbaren Beiträgen ein Menü: andere Person im Meeting
    /// wählen oder eine neue mit Namensvorschlägen eintragen.
    @ViewBuilder
    private var speakerLabel: some View {
        let text = Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(nameColor)
        if choices.isEmpty {
            text
        } else {
            Menu {
                Section("Beitrag zuordnen") {
                    ForEach(choices, id: \.id) { choice in
                        Button {
                            if choice.id != line.speakerID { onReassign(.speaker(choice.id)) }
                        } label: {
                            if choice.id == line.speakerID {
                                Label(choice.label, systemImage: "checkmark")
                            } else {
                                Text(choice.label)
                            }
                        }
                    }
                }
                Divider()
                Button("Andere Person …") { draft = ""; askingName = true }
            } label: {
                HStack(spacing: 2) {
                    text
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(nameColor.opacity(0.7))
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help("Diesen Beitrag einer anderen Person zuordnen")
            .popover(isPresented: $askingName, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Wer hat das gesagt?").font(.system(size: 14, weight: .semibold))
                    Text("„\(line.text.prefix(90))\(line.text.count > 90 ? " …" : "")“")
                        .font(.system(size: 12)).foregroundStyle(MeetingTheme.foregroundTertiary).lineLimit(2)
                    NameEntry(text: $draft, known: known, others: choices.map(\.label), buttonTitle: "Zuordnen") { name in
                        askingName = false
                        onReassign(.name(name))
                    }
                }
                .padding(16)
                .frame(width: 360, alignment: .leading)
            }
        }
    }
}

/// Sprecher-Kapsel, die beim Klick das Umbenennen öffnet. So lassen sich auch schon
/// bestätigte Zuordnungen korrigieren oder zwei Stimmen einer Person zusammenführen.
private struct RenameTag: View {
    let name: String
    let colors: (fill: Color, text: Color)
    let speakerID: String
    let entry: MeetingLibrary.Entry
    @ObservedObject var library: MeetingLibrary
    @State private var open = false
    @State private var draft = ""

    var body: some View {
        Button { draft = entry.document.speakerNames[speakerID] ?? ""; open = true } label: {
            SpeakerTag(name: name, colors: colors)
        }
        .buttonStyle(.plain)
        .help("Umbenennen oder mit einer anderen Stimme zusammenführen")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Wer ist \(name)?").font(.system(size: 14, weight: .semibold))
                NameEntry(
                    text: $draft,
                    known: library.knownNames,
                    others: entry.document.speakerIDs.filter { $0 != speakerID }.compactMap { entry.document.speakerNames[$0] },
                    buttonTitle: "Speichern",
                    busy: library.busy != nil
                ) { newName in
                    open = false
                    Task { await library.assign(name: newName, to: speakerID, in: entry.folder) }
                }
            }
            .padding(16)
            .frame(width: 360, alignment: .leading)
        }
    }
}

/// Runder Abspielknopf, Lavendel wie die Primärfarbe.
private struct PlayButton: View {
    let playing: Bool
    var size: CGFloat = 16
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "stop.fill" : "play.fill")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(MeetingTheme.vast950)
                .frame(width: size, height: size)
                .background(Circle().fill(MeetingTheme.dawn500))
        }
        .buttonStyle(.plain)
        .help(playing ? "Anhalten" : "Anhören")
    }
}

// MARK: - Sprecher zuordnen

private struct SpeakerAssignmentCard: View {
    let entry: MeetingLibrary.Entry
    @ObservedObject var library: MeetingLibrary
    @ObservedObject var player: SnippetPlayer
    @State private var drafts: [String: String] = [:]

    private var document: MeetingDocument { entry.document }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Wer spricht hier?").font(.system(size: 15, weight: .semibold))
                Text("Ein Name pro Stimme. BlitzText legt daraus ein Stimmprofil auf diesem Mac an und erkennt die Person in künftigen Meetings selbst, mit jedem Meeting genauer.")
                    .font(.system(size: 12)).foregroundStyle(MeetingTheme.foregroundTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(document.unconfirmedSpeakerIDs, id: \.self) { id in
                row(for: id)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(MeetingTheme.assignCard))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MeetingTheme.assignBorder))
    }

    private func row(for id: String) -> some View {
        let index = document.speakerIDs.firstIndex(of: id) ?? 0
        let sampleLine = document.sampleLine(of: id)
        let sample = sampleLine?.text ?? ""
        let fromApp = document.nameSources[id] == .meetingApp
        let binding = Binding(
            get: { drafts[id] ?? (fromApp ? document.speakerNames[id] ?? "" : "") },
            set: { drafts[id] = $0 }
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SpeakerTag(name: document.label(forSpeaker: id), colors: MeetingTheme.speaker(index))
                Text(MeetingMarkdown.clock(document.speakingTime(of: id), alwaysHours: false) + " gesprochen")
                    .font(.system(size: 11)).foregroundStyle(MeetingTheme.foregroundTertiary)
                if fromApp {
                    Text("Name aus der Meeting-App").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MeetingTheme.vast950)
                        .padding(.horizontal, 6).frame(height: 17)
                        .background(Capsule().fill(MeetingTheme.dawn500))
                }
            }
            HStack(alignment: .center, spacing: 10) {
                if let probe = sampleLine {
                    let playID = "sample-\(id)"
                    PlayButton(playing: player.playingID == playID, size: 28) {
                        player.toggle(id: playID, url: entry.folder.appendingPathComponent(document.trackFile(for: probe)),
                                      start: probe.start, end: probe.end)
                    }
                }
                Text(sample)
                    .font(.system(size: 12.5))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12).fill(MeetingTheme.card))
            }
            NameEntry(text: binding, known: library.knownNames, others: otherNames(except: id),
                      buttonTitle: fromApp ? "Bestätigen" : "Übernehmen", busy: library.busy != nil) { name in
                submit(id, name)
            }
        }
    }

    private func submit(_ id: String, _ name: String) {
        Task { await library.assign(name: name, to: id, in: entry.folder) }
    }

    /// Namen, die in diesem Meeting schon an andere Stimmen vergeben sind.
    private func otherNames(except id: String) -> [String] {
        document.speakerIDs.filter { $0 != id }.compactMap { document.speakerNames[$0] }
    }
}

/// Namensfeld mit Vorschlägen wie bei MacWhisper: Beim Fokussieren erscheinen die bekannten
/// Personen, beim Tippen die passenden. Ein Klick übernimmt den Namen. Entspricht der
/// getippte Name einer Person, die in diesem Meeting schon eine Stimme hat, kündigt das
/// Feld an, dass beide Stimmen zusammengeführt werden.
struct NameEntry: View {
    @Binding var text: String
    let known: [String]
    /// Namen anderer Stimmen im selben Meeting.
    var others: [String] = []
    var buttonTitle = "Übernehmen"
    var busy = false
    let onCommit: (String) -> Void

    @FocusState private var focused: Bool
    @State private var highlighted = 0

    private var suggestions: [String] {
        SpeakerNaming.suggestions(for: text, known: known + others)
    }

    private var exactMatch: String? {
        let wanted = SpeakerNaming.key(text)
        guard !wanted.isEmpty else { return nil }
        return (known + others).first { SpeakerNaming.key($0) == wanted }
    }

    private var mergesWithOther: Bool {
        let wanted = SpeakerNaming.key(text)
        return !wanted.isEmpty && others.contains { SpeakerNaming.key($0) == wanted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Name eingeben oder auswählen", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .padding(.horizontal, 10)
                    .frame(width: 240, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(MeetingTheme.card))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(focused ? MeetingTheme.dawn700 : MeetingTheme.assignBorder, lineWidth: focused ? 1.5 : 1))
                    .onSubmit { commit(highlightedSuggestion ?? text) }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onChange(of: text) { _, _ in highlighted = 0 }
                Button(buttonTitle) { commit(text) }
                    .buttonStyle(LavenderButtonStyle(compact: true))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }

            if let exactMatch, SpeakerNaming.key(exactMatch) == SpeakerNaming.key(text) {
                Label(mergesWithOther
                      ? "\(exactMatch) hat in diesem Meeting schon eine Stimme. Beide werden zusammengeführt."
                      : "Vorhandene Person \(exactMatch): Das Profil wird nachgeschärft, kein zweites angelegt.",
                      systemImage: mergesWithOther ? "arrow.triangle.merge" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 11))
                    .foregroundStyle(MeetingTheme.foregroundTertiary)
            }

            if focused, !suggestions.isEmpty, !(suggestions.count == 1 && SpeakerNaming.key(suggestions[0]) == SpeakerNaming.key(text)) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, name in
                        Button { commit(name) } label: {
                            HStack(spacing: 8) {
                                Text(initials(name))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(MeetingTheme.vast950)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(MeetingTheme.dawn500))
                                Text(name).font(.system(size: 13))
                                Spacer()
                                if others.contains(where: { SpeakerNaming.key($0) == SpeakerNaming.key(name) }) {
                                    Text("in diesem Meeting").font(.system(size: 10)).foregroundStyle(MeetingTheme.foregroundTertiary)
                                } else if known.contains(where: { SpeakerNaming.key($0) == SpeakerNaming.key(name) }) {
                                    Text("Profil").font(.system(size: 10)).foregroundStyle(MeetingTheme.foregroundTertiary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(index == highlighted ? MeetingTheme.backgroundTertiary : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .frame(width: 240)
                .background(RoundedRectangle(cornerRadius: 10).fill(MeetingTheme.card)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MeetingTheme.border))
            }
        }
    }

    private var highlightedSuggestion: String? {
        guard focused, suggestions.indices.contains(highlighted), !text.isEmpty else { return nil }
        return suggestions[highlighted]
    }

    private func move(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        highlighted = (highlighted + delta + suggestions.count) % suggestions.count
    }

    private func commit(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy else { return }
        text = trimmed
        focused = false
        onCommit(trimmed)
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

// MARK: - Notizen

/// Stellt die Markdown-Notizen dar: Überschriften, Aufzählungen, Aufgaben-Checkboxen.
private struct SummaryText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                line(raw.trimmingCharacters(in: .whitespaces))
            }
        }
        .font(.system(size: 13.5))
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func line(_ text: String) -> some View {
        if text.hasPrefix("#") {
            Text(inline(text.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 12)
        } else if text.hasPrefix("- [ ]") || text.hasPrefix("- [x]") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: text.hasPrefix("- [x]") ? "checkmark.square.fill" : "square")
                    .foregroundStyle(MeetingTheme.foregroundTertiary)
                Text(inline(String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)))
            }
        } else if text.hasPrefix("- ") || text.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(MeetingTheme.foregroundTertiary).frame(width: 4, height: 4).offset(y: -2)
                Text(inline(String(text.dropFirst(2))))
            }
        } else if !text.isEmpty {
            Text(inline(text))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

/// Freies Notizfeld, speichert eine Sekunde nach der letzten Eingabe und beim Verlassen.
struct NotesEditor: View {
    let initial: String
    var hint: String = ""
    var minHeight: CGFloat = 220
    let onSave: (String) -> Void
    @State private var text = ""
    @State private var pending: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $text)
                .font(.system(size: 13.5))
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(MeetingTheme.backgroundTertiary))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Eigene Notizen, Stichpunkte, Aufgaben …")
                            .font(.system(size: 13.5))
                            .foregroundStyle(MeetingTheme.foregroundTertiary)
                            .padding(.horizontal, 15).padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: text) { _, value in
                    pending?.cancel()
                    pending = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled else { return }
                        onSave(value)
                    }
                }
            if !hint.isEmpty {
                Text(hint).font(.caption).foregroundStyle(MeetingTheme.foregroundTertiary)
            }
        }
        .onAppear { text = initial }
        .onDisappear {
            pending?.cancel()
            if text != initial { onSave(text) }
        }
    }
}

/// Rechte Seite während einer Aufnahme: Laufzeit und Notizen zum laufenden Meeting.
/// Hier kommt später auch das Live-Transkript hin.
struct LiveMeetingView: View {
    @ObservedObject var controller: MeetingController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if case .recording(let startedAt) = controller.phase {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    HStack(spacing: 10) {
                        Circle().fill(Color.red).frame(width: 9, height: 9)
                        Text("Aufnahme läuft").font(.system(size: 22, weight: .semibold))
                        Text(MeetingMarkdown.clock(context.date.timeIntervalSince(startedAt), alwaysHours: false))
                            .font(.system(size: 15, weight: .medium).monospacedDigit())
                            .foregroundStyle(MeetingTheme.foregroundTertiary)
                        Spacer()
                        Button("Aufnahme beenden") { controller.stop() }
                            .buttonStyle(LavenderButtonStyle())
                    }
                }
            }
            Text("Meine Notizen").font(.system(size: 15, weight: .semibold))
            // Direkt an die Live-Notizen gebunden, ohne Kopie: Früher schrieb das Feld beim
            // Verschwinden (Stopp) seinen alten Text zurück, nachdem die Notizen schon ins
            // Meeting übernommen und geleert waren. Die nächste Aufnahme fand sie dann wieder vor.
            TextEditor(text: $controller.liveNotes)
                .font(.system(size: 13.5))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 320)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(MeetingTheme.backgroundTertiary))
            Text("Werden beim Stopp ins Meeting übernommen und fließen in die Zusammenfassung ein.")
                .font(.caption).foregroundStyle(MeetingTheme.foregroundTertiary)
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: 760, alignment: .leading)
    }
}
