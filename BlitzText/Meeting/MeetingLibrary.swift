import AppKit
import Combine
import Foundation

/// Alle gespeicherten Meetings plus die Aktionen darauf: Sprecher benennen (baut Profile),
/// Notizen neu erstellen, Transkript kopieren.
@MainActor
final class MeetingLibrary: ObservableObject {

    struct Entry: Identifiable, Equatable {
        let folder: URL
        var document: MeetingDocument
        var id: URL { folder }
    }

    @Published private(set) var entries: [Entry] = []
    @Published var selection: URL?
    /// Während einer Aufnahme zeigt das Fenster das Live-Meeting. Klickt man in der Liste
    /// ein gespeichertes Meeting an, wird dieses gezeigt, bis man zurückschaltet.
    @Published var showsArchiveWhileRecording = false
    /// Laufende Aktion für die Anzeige, z. B. „Lerne Stimme …".
    @Published private(set) var busy: String?
    @Published var lastError: String?
    /// Namen für die Vorschläge beim Tippen: gespeicherte Profile plus bestätigte Namen
    /// aus allen Meetings.
    @Published private(set) var knownNames: [String] = []
    /// Letzte Löschung im Transkript, solange sie sich zurücknehmen lässt. Jede weitere
    /// Änderung am Archiv verwirft sie, damit „Rückgängig“ nichts anderes überschreibt.
    @Published private(set) var lastDeletion: TranscriptDeletion?

    struct TranscriptDeletion: Equatable {
        let id = UUID()
        let folder: URL
        let previous: MeetingDocument
        let count: Int
    }

    private let archive: MeetingArchive
    private let diarizer: MeetingDiarizing?
    private let makeSummarizer: () -> MeetingSummarizing
    private let makeExporter: () -> VaultExporter?

    init(archive: MeetingArchive, diarizer: MeetingDiarizing?,
         makeSummarizer: @escaping () -> MeetingSummarizing,
         makeExporter: @escaping () -> VaultExporter? = { nil }) {
        self.archive = archive
        self.makeExporter = makeExporter
        self.diarizer = diarizer
        self.makeSummarizer = makeSummarizer
    }

    var selected: Entry? { selection.flatMap(index(of:)).map { entries[$0] } }

    /// Ordner-URLs kommen mal mit `/private/var` und Schrägstrich, mal ohne. Verglichen
    /// wird deshalb der aufgelöste Pfad.
    static func key(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func index(of folder: URL) -> Int? {
        let key = Self.key(folder)
        return entries.firstIndex { Self.key($0.folder) == key }
    }

    /// Wählt ein Meeting aus, auch wenn die URL anders geschrieben ist als in der Liste.
    func select(_ folder: URL) {
        if let index = index(of: folder) { selection = entries[index].folder }
    }

    func reload() {
        let archive = self.archive
        entries = archive.loadAll().map { Entry(folder: $0.folder, document: $0.document) }
        refreshKnownNames()
        if selection.flatMap(index(of:)) == nil {
            selection = entries.first?.folder
        }
    }

    // MARK: - Sprecher

    func refreshKnownNames() {
        let fromProfiles = diarizer?.knownSpeakerNames() ?? []
        let fromMeetings = entries.flatMap { entry in
            entry.document.speakerNames.compactMap { id, name in
                entry.document.nameSources[id] == .meetingApp ? nil : name
            }
        }
        var seen = Set<String>()
        knownNames = (fromProfiles + fromMeetings).filter { seen.insert(SpeakerNaming.key($0)).inserted }
    }

    /// Gibt einer Stimme einen Namen und legt daraus ein Profil an bzw. schärft ein
    /// vorhandenes gleichen Namens nach. Danach wird die Stimme in künftigen Meetings
    /// automatisch erkannt.
    ///
    /// Gegen Dubletten: Ein getippter Name, der einem vorhandenen entspricht („anna mueller“
    /// zu „Anna Müller“), übernimmt dessen Schreibweise. Trägt im Meeting schon eine andere
    /// Stimme diesen Namen, werden beide zusammengeführt.
    func assign(name rawName: String, to speakerID: String, in folder: URL) async {
        let name = SpeakerNaming.canonical(rawName, known: knownNames)
        guard !name.isEmpty, let index = index(of: folder) else { return }
        let document = entries[index].document

        busy = "Lerne die Stimme von \(name) …"
        defer { busy = nil }

        let spans = document.lines
            .filter { $0.speakerID == speakerID }
            .map { SpeechSpan(start: $0.start, end: $0.end) }
        let track = folder.appendingPathComponent(document.diarizedTrack)
        var profileNote: String?
        if let diarizer {
            do {
                try await diarizer.learnProfile(name: name, from: track, spans: spans)
            } catch {
                profileNote = error.localizedDescription
            }
        }

        // Reicht die Stimme nicht für ein Profil (etwa nur ein kurzer Satz), gilt der Name
        // trotzdem als zugeordnet: `.manual` statt `.meetingApp`, sonst stünde die Stimme
        // für immer wieder unter „Wer spricht hier?“.
        let updated = document.assigning(name: name, to: speakerID,
                                         source: profileNote == nil ? .confirmed : .manual)
        save(updated, at: index)
        refreshKnownNames()
        if let profileNote { lastError = "Name übernommen, ohne Stimmprofil: \(profileNote)" }
    }

    /// Ein einzelner Beitrag gehört zu einer anderen Person. Lernt bewusst kein Profil:
    /// Ein Beitrag ist oft nur ein paar Sekunden lang, und ein Fehlgriff soll kein Stimmprofil
    /// verfälschen. Profile entstehen weiter über „Wer spricht hier?“ und die Kapseln.
    func reassign(lineAt index: Int, to target: ReassignTarget, in folder: URL) {
        guard let entryIndex = self.index(of: folder) else { return }
        let document = entries[entryIndex].document
        let updated: MeetingDocument
        switch target {
        case .speaker(let id):
            updated = document.reassigning(lineAt: index, toSpeaker: id)
        case .name(let raw):
            let name = SpeakerNaming.canonical(raw, known: knownNames + document.speakerNames.values)
            guard !name.isEmpty else { return }
            updated = document.reassigning(lineAt: index, toName: name)
        }
        save(updated, at: entryIndex)
        refreshKnownNames()
    }

    /// Beitrag vor einem Wort in zwei teilen; danach lässt sich jeder Teil einzeln umhängen.
    func split(lineAt index: Int, beforeWord wordIndex: Int, in folder: URL) {
        guard let entryIndex = self.index(of: folder) else { return }
        save(entries[entryIndex].document.splitting(lineAt: index, beforeWord: wordIndex), at: entryIndex)
    }

    /// Löscht Beiträge aus dem Transkript. Lässt sich über `undoDeletion()` zurücknehmen.
    func deleteLines(_ indices: IndexSet, in folder: URL) {
        guard let entryIndex = index(of: folder) else { return }
        let before = entries[entryIndex].document
        let after = before.removingLines(at: indices)
        let removed = before.lines.count - after.lines.count
        guard removed > 0 else { return }
        save(after, at: entryIndex)
        lastDeletion = TranscriptDeletion(folder: folder, previous: before, count: removed)
    }

    func undoDeletion() {
        guard let deletion = lastDeletion else { return }
        lastDeletion = nil
        guard let entryIndex = index(of: deletion.folder) else { return }
        save(deletion.previous, at: entryIndex)
    }

    func dismissDeletion() { lastDeletion = nil }

    enum ReassignTarget: Equatable {
        case speaker(String)
        case name(String)
    }

    // MARK: - Notizen

    func regenerateSummary(in folder: URL) async {
        guard let index = index(of: folder) else { return }
        var document = entries[index].document
        busy = "Schreibe Notizen neu …"
        defer { busy = nil }
        do {
            let split = MeetingSummarizer.splitTitle(try await makeSummarizer().summarize(transcript: document.summaryInput))
        document.summary = split.notes
            document.summaryOutdated = nil
            if let title = split.title, document.titleChosenByUser != true { document.aiTitle = title }
            save(document, at: index)
        } catch {
            lastError = "Notizen nicht erstellt: \(error.localizedDescription)"
        }
    }

    // MARK: - Eigene Notizen

    /// Speichert die eigenen Notizen (und spiegelt sie in den Wissensordner).
    func setUserNotes(_ text: String, in folder: URL) {
        guard let index = index(of: folder) else { return }
        var document = entries[index].document
        let value: String? = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        guard document.userNotes != value else { return }
        document.userNotes = value
        save(document, at: index)
    }

    // MARK: - Titel

    /// Neuer KI-Titel für ein Meeting, etwa ältere ohne Titel oder wenn der alte nicht passt.
    func regenerateTitle(in folder: URL) async {
        guard let index = index(of: folder) else { return }
        var document = entries[index].document
        guard !document.lines.isEmpty else { lastError = "Ohne Transkript kein Titel."; return }
        busy = "Erzeuge Titel …"
        defer { busy = nil }
        do {
            document.aiTitle = try await makeSummarizer().title(for: document.summaryInput)
            document.titleChosenByUser = false
            save(document, at: index)
        } catch {
            lastError = "Titel nicht erzeugt: \(error.localizedDescription)"
        }
    }

    /// Titel von Hand. Leer setzt auf den automatischen Titel zurück.
    func rename(in folder: URL, to title: String) {
        guard let index = index(of: folder) else { return }
        var document = entries[index].document
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        document.aiTitle = trimmed.isEmpty ? nil : String(trimmed.prefix(80))
        document.titleChosenByUser = !trimmed.isEmpty
        save(document, at: index)
    }

    func copyTranscript(of entry: Entry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.document.transcriptText, forType: .string)
    }

    func copyNotes(of entry: Entry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MeetingMarkdown.summaryWithTime(entry.document), forType: .string)
    }

    func reveal(_ entry: Entry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.folder.appendingPathComponent(MeetingArchive.protocolFile)])
    }

    // MARK: - Sprecher neu abgleichen

    /// Unbenannte Stimmen gegen Stimmprofile und gegen einander abgleichen. Nur Eindeutiges
    /// wird übernommen; der Rest bleibt unter „Wer spricht hier?“.
    func rematchSpeakers(in folder: URL) async {
        guard let diarizer, let index = index(of: folder) else { return }
        let document = entries[index].document
        let track = folder.appendingPathComponent(document.diarizedTrack)
        busy = "Gleiche Sprecher ab …"
        defer { busy = nil }

        var voices: [SpeakerRematcher.Voice] = []
        for id in document.speakerIDs {
            let spans = document.lines.filter { $0.speakerID == id }.map { SpeechSpan(start: $0.start, end: $0.end) }
            let duration = Float(spans.reduce(0) { $0 + $1.end - $1.start })
            let embedding = (try? await diarizer.voiceEmbedding(from: track, spans: spans)) ?? []
            voices.append(.init(id: id, duration: duration, embedding: embedding, name: document.speakerNames[id]))
        }
        // Auf der reinen Gegenseite kann ich nicht sprechen; in einer Mischspur schon.
        let excluding: Set<String> = document.diarizedTrack == MeetingArchive.othersTrackFile
            ? Set([SpeakerNaming.selfName].compactMap { $0 }.map(SpeakerNaming.key)) : []
        let plan = SpeakerRematcher.plan(voices: voices, profiles: diarizer.profileEmbeddings(), excluding: excluding)
        Log.write("MeetingLibrary: Abgleich \(folder.lastPathComponent) — \(voices.count) Stimmen, \(plan.names.count) erkannt, \(plan.merges.count) zusammengelegt")
        guard !plan.isEmpty, let current = self.index(of: folder) else { return }
        save(entries[current].document.applying(plan), at: current)
    }

    static let mixedVoicesName = "Mehrere Personen"

    /// Für Stimmen, in denen mehrere Leute übereinander reden: ehrlich als Gemisch markieren,
    /// ohne Stimmprofil, damit „Wer spricht hier?“ nicht zum Auseinanderklauben zwingt.
    func markMixedVoices(_ speakerID: String, in folder: URL) {
        guard let index = index(of: folder) else { return }
        var document = entries[index].document
        document.speakerNames[speakerID] = Self.mixedVoicesName
        document.nameSources[speakerID] = .manual
        save(document, at: index)
    }

    // MARK: - Zusammenführen

    /// Für die Mehrfachauswahl in der Liste (⌘-Klick, ⇧-Klick).
    @Published var marked: Set<String> = []

    func isMarked(_ folder: URL) -> Bool { marked.contains(Self.key(folder)) }

    /// Mehrere Teile eines Termins zu einem Meeting. Die Teile wandern danach in den Papierkorb
    /// (samt ihren Dateien im Wissensordner), das neue Meeting bekommt Notizen und Titel neu.
    func merge(_ folders: [URL]) async {
        let parts = folders.compactMap { folder in
            entries.first { Self.key($0.folder) == Self.key(folder) }
        }
        guard parts.count >= 2 else { lastError = MeetingMerger.MergeError.tooFewParts.errorDescription; return }
        busy = "Führe \(parts.count) Meetings zusammen …"
        let archive = self.archive
        let input = parts.map { MeetingMerger.Part(folder: $0.folder, document: $0.document) }
        do {
            let folder = try await Task.detached(priority: .userInitiated) {
                try MeetingMerger.merge(input, into: archive)
            }.value
            Log.write("MeetingLibrary: \(parts.count) Meetings zusammengeführt → \(folder.lastPathComponent)")
            for part in parts { delete(part) }
            marked = []
            reload()
            selection = folder
            busy = nil
            // Stimmen über die Teile hinweg abgleichen, bevor die Zusammenfassung Namen nennt.
            await rematchSpeakers(in: folder)
            await regenerateSummary(in: folder)
        } catch {
            busy = nil
            lastError = "Zusammenführen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Verschiebt das Meeting in den Papierkorb, nicht endgültig gelöscht.
    func delete(_ entry: Entry) {
        makeExporter()?.remove(entry.document)
        do {
            try FileManager.default.trashItem(at: entry.folder, resultingItemURL: nil)
            if let selection, MeetingLibrary.key(selection) == MeetingLibrary.key(entry.folder) { self.selection = nil }
            reload()
        } catch {
            lastError = "Löschen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Speichert und spiegelt jede Korrektur in den Wissensordner, damit dort immer die
    /// aktuelle Fassung liegt (Sprecher, Umhängen, Notizen, Bereich).
    private func save(_ document: MeetingDocument, at index: Int) {
        lastDeletion = nil
        let result = archive.persist(document, in: entries[index].folder, exporter: makeExporter())
        entries[index].document = result.document
        if let error = result.exportError {
            lastError = "Gespeichert, aber nicht im Wissensordner: \(error.localizedDescription)"
        }
    }

    /// Bereich im Wissensordner von Hand festlegen. Die Datei zieht dorthin um.
    func setProject(_ key: String, in folder: URL) {
        guard let index = index(of: folder) else { return }
        var document = entries[index].document
        document.project = key
        document.projectChosenByUser = true
        save(document, at: index)
    }

    /// Zeigt die Datei im Wissensordner im Finder.
    func revealInVault(_ entry: Entry) {
        guard let file = entry.document.vaultFile, let root = makeExporter()?.root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(file)])
    }

    var vaultEnabled: Bool { makeExporter() != nil }

    /// Ein Meeting nachträglich in den Wissensordner bringen, etwa nach dem Einschalten.
    func exportAgain(in folder: URL) {
        guard let index = index(of: folder) else { return }
        save(entries[index].document, at: index)
    }
}
