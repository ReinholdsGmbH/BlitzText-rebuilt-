import Foundation
import Testing
@testable import BlitzText

struct VaultExporterTests {

    @Test("Bereich wie mw-route", arguments: [
        ("Thomas Daily", "irgendwas", "intern"),
        ("x", "Wir besprechen die Kursbar-Anmeldung und den Teststatus", "kursbar"),
        ("x", "Der Cutover für Werk Süd und der UAT-Teststatus", "pag"),
        ("x", "Salesforce Attio Sync im CRM Workshop", "wk"),
        ("x", "TenderMatch Checkpoint", "tm"),
        ("x", "Wetter und Urlaub", "eingang")
    ])
    func detects(title: String, text: String, expected: String) {
        #expect(VaultExporter.detectProject(title: title, text: text) == expected)
    }

    @Test("Titelzeile wird von den Notizen getrennt")
    func splitsTitle() {
        let split = MeetingSummarizer.splitTitle("TITEL: Release-Termin abgestimmt\n\n### Zusammenfassung\n- A")
        #expect(split.title == "Release-Termin abgestimmt")
        #expect(split.notes.hasPrefix("### Zusammenfassung"))
        #expect(MeetingSummarizer.splitTitle("### Zusammenfassung\n- A").title == nil)
    }

    private func document() -> MeetingDocument {
        var date = DateComponents(); date.year = 2026; date.month = 11; date.day = 17; date.hour = 21; date.minute = 43
        date.timeZone = TimeZone(identifier: "Europe/Berlin")
        var doc = MeetingDocument(
            startedAt: Calendar(identifier: .gregorian).date(from: date)!, duration: 99, sourceNames: ["Teams"],
            lines: [TranscriptLine(speaker: .others, start: 1, end: 3, text: "Der UAT Teststatus für Werk Süd", speakerID: "1")],
            summary: "### Zusammenfassung\n- Teststatus besprochen", notes: [],
            speakerNames: ["1": "Anna"]
        )
        doc.aiTitle = "Werk Süd Teststatus: nächste Schritte"
        return doc
    }

    @Test("Dateiname mit Punkt, Überschrift mit Doppelpunkt")
    func names() {
        #expect(VaultExporter.fileName(for: document()) == "17.11.26_21.43_Werk Süd Teststatus- nächste Schritte.md")
        #expect(VaultExporter.heading(for: document()) == "17.11.26_21:43_Werk Süd Teststatus: nächste Schritte")
    }

    @Test("Export schreibt nach Bereich, log.md nur einmal, Umzug entfernt die alte Datei")
    func exportsAndMoves() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-vault-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exporter = VaultExporter(root: root)

        let first = try exporter.export(document())
        #expect(first.project == "pag")
        let file = try #require(first.vaultFile)
        #expect(file.hasPrefix("arbeit/pag/transkripte/17.11.26_21.43_"))
        let md = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
        #expect(md.hasPrefix("# 17.11.26_21:43_Werk Süd Teststatus: nächste Schritte"))
        #expect(md.contains("**Projekt:** pag"))
        #expect(md.contains("Anna: Der UAT Teststatus"))

        _ = try exporter.export(first)
        let log = try String(contentsOf: root.appendingPathComponent("arbeit/pag/log.md"), encoding: .utf8)
        #expect(log.components(separatedBy: "\n").filter { !$0.isEmpty }.count == 1)
        #expect(log.contains("Teststatus besprochen"))

        var moved = first
        moved.project = "intern"
        moved.projectChosenByUser = true
        let after = try exporter.export(moved)
        #expect(after.vaultFile?.hasPrefix("arbeit/reinholds/transkripte/") == true)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("arbeit/reinholds/log.md").path))
    }

    @Test("Fehlender Wissensordner bricht das Speichern nicht ab")
    func missingRoot() throws {
        let archiveRoot = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: archiveRoot) }
        let archive = MeetingArchive(root: archiveRoot)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Teams")
        let result = archive.persist(document(), in: folder,
                                     exporter: VaultExporter(root: URL(fileURLWithPath: "/nicht/vorhanden")))
        #expect(result.exportError != nil)
        #expect(archive.load(folder: folder) != nil)
    }
}

@MainActor
struct TitleActionsTests {

    private func setup(_ summarizer: FakeSummarizer) throws -> (MeetingLibrary, MeetingArchive, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-archive-\(UUID())")
        let archive = MeetingArchive(root: root)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Teams")
        try archive.writeProtocol(MeetingDocument(
            startedAt: Date(), duration: 30, sourceNames: ["Microsoft Teams"],
            lines: [TranscriptLine(speaker: .others, start: 1, end: 3, text: "Release verschieben", speakerID: "1")],
            summary: "### Zusammenfassung\n- A", notes: []
        ), in: folder)
        let library = MeetingLibrary(archive: archive, diarizer: nil, makeSummarizer: { summarizer })
        library.reload()
        return (library, archive, folder, root)
    }

    @Test("Älteres Meeting bekommt einen KI-Titel, der in Liste und Ablage erscheint")
    func regenerates() async throws {
        let (library, archive, folder, root) = try setup(FakeSummarizer(result: .success(""), titleResult: .success("Release verschoben")))
        defer { try? FileManager.default.removeItem(at: root) }
        await library.regenerateTitle(in: folder)
        let doc = try #require(archive.load(folder: folder))
        #expect(MeetingMarkdown.baseTitle(for: doc) == "Release verschoben")
        #expect(MeetingMarkdown.title(for: doc).hasSuffix("_Release verschoben"))
        #expect(doc.titleChosenByUser == false)
    }

    @Test("Eigener Titel übersteht „Notizen neu erstellen“, leer setzt zurück")
    func manualTitleSticks() async throws {
        let (library, archive, folder, root) = try setup(FakeSummarizer(result: .success("TITEL: KI-Vorschlag\n### Zusammenfassung\n- B")))
        defer { try? FileManager.default.removeItem(at: root) }
        library.rename(in: folder, to: "  Mein Titel ")
        await library.regenerateSummary(in: folder)
        var doc = try #require(archive.load(folder: folder))
        #expect(doc.aiTitle == "Mein Titel")
        #expect(doc.summary == "### Zusammenfassung\n- B")

        library.rename(in: folder, to: "")
        await library.regenerateSummary(in: folder)
        doc = try #require(archive.load(folder: folder))
        #expect(doc.aiTitle == "KI-Vorschlag")
    }
}

@MainActor
struct RecorderSourceTests {
    @Test("Ohne aktives Gespräch keine Quelle: Aufnahme heißt „Meeting“, Tap nimmt alles")
    func noActiveSource() throws {
        let tap = FakeSystemAudioTap(fixtureURL: TestAudio.tempURL())
        let recorder = MeetingRecorder(microphone: FakeAudioRecorder(fixtureURL: TestAudio.tempURL()),
                                       systemAudio: tap, detector: MeetingDetector(), processList: FakeAudioProcessList())
        try recorder.start()
        let recording = try #require(recorder.stop())
        #expect(recording.sources.isEmpty)
        #expect(tap.lastProcesses.isEmpty)
        let doc = MeetingDocument(startedAt: Date(), duration: 1, sourceNames: recording.sources.map(\.displayName),
                                  lines: [], summary: nil, notes: [])
        #expect(MeetingMarkdown.baseTitle(for: doc) == "Meeting")
    }
}

struct DockIconModeTests {
    @Test("Dock-Symbol je Einstellung und Fensterzustand")
    func rules() {
        #expect(DockIconMode.whileWindowOpen.showsIcon(windowOpen: true))
        #expect(!DockIconMode.whileWindowOpen.showsIcon(windowOpen: false))
        #expect(DockIconMode.always.showsIcon(windowOpen: false))
        #expect(!DockIconMode.never.showsIcon(windowOpen: true))
        let decoded = try? JSONDecoder().decode([DockIconMode].self, from: Data(#"["spaeter"]"#.utf8))
        #expect(decoded == [.whileWindowOpen])
    }
}

@MainActor
struct UserNotesTests {
    @Test("Eigene Notizen gehen in Zusammenfassung, Protokoll und Wissensordner")
    func notesFlow() throws {
        var doc = MeetingDocument(startedAt: Date(), duration: 10, sourceNames: ["Teams"],
                                  lines: [TranscriptLine(speaker: .me, start: 0, end: 2, text: "Hallo")],
                                  summary: nil, notes: [])
        #expect(doc.summaryInput == doc.transcriptText)
        doc.userNotes = "Budget klären"
        #expect(doc.summaryInput.contains("Notizen von „Ich“"))
        #expect(doc.summaryInput.hasSuffix("Budget klären"))
        #expect(MeetingMarkdown.render(doc).contains("## Meine Notizen\n\nBudget klären"))
        #expect(VaultExporter.markdown(for: doc, area: "_eingang").contains("## Meine Notizen"))
    }

    @Test("Bibliothek speichert Notizen, leerer Text entfernt sie")
    func libraryStores() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = MeetingArchive(root: root)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Teams")
        try archive.writeProtocol(MeetingDocument(startedAt: Date(), duration: 1, sourceNames: [], lines: [],
                                                  summary: nil, notes: []), in: folder)
        let library = MeetingLibrary(archive: archive, diarizer: nil, makeSummarizer: { FakeSummarizer(result: .success("")) })
        library.reload()
        library.setUserNotes("Punkt 1", in: folder)
        #expect(archive.load(folder: folder)?.userNotes == "Punkt 1")
        library.setUserNotes("  ", in: folder)
        #expect(archive.load(folder: folder)?.userNotes == nil)
    }
}

@MainActor
struct LiveNotesTests {
    @Test("Live-Notizen gehören nur zur eigenen Aufnahme")
    func notesDoNotLeak() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        func controller() throws -> MeetingController {
            let mic = try TestAudio.wav(duration: 4, bursts: [1...2], at: TestAudio.tempURL())
            return MeetingController(
                recorder: MeetingRecorder(microphone: FakeAudioRecorder(fixtureURL: mic),
                                          systemAudio: FakeSystemAudioTap(fixtureURL: try TestAudio.wav(duration: 4, bursts: [], at: TestAudio.tempURL())),
                                          detector: MeetingDetector(), processList: FakeAudioProcessList()),
                archive: MeetingArchive(root: root),
                makeTranscriber: { SequenceTranscriber(["Hallo"]) },
                makeSummarizer: { FakeSummarizer(result: .success("### Zusammenfassung\n- A")) },
                language: { "de" })
        }
        let c = try controller()
        c.start()
        c.liveNotes = "Notiz erste Aufnahme"
        #expect(c.isRecording, "Start 1: \(c.phase)")
        c.stop()
        #expect(!c.isRecording, "Nach Stopp: \(c.phase)")
        #expect(c.liveNotes.isEmpty)
        c.liveNotes = "Rest aus der alten Ansicht"
        for _ in 0..<200 { if !c.isProcessing { break }; try await Task.sleep(for: .milliseconds(25)) }
        c.start()
        #expect(c.isRecording, "Phase: \(c.phase)")
        #expect(c.liveNotes.isEmpty, "Notizen: \(c.liveNotes) / Phase: \(c.phase)")
    }
}

struct VaultRemovalTests {
    @Test("Verwerfen nimmt die Datei aus dem Wissensordner und vermerkt es in der log.md")
    func removes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-vault-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exporter = VaultExporter(root: root)
        let doc = try exporter.export(MeetingDocument(startedAt: Date(), duration: 5, sourceNames: [],
            lines: [TranscriptLine(speaker: .me, start: 0, end: 1, text: "Kursbar Termin")], summary: nil, notes: []))
        let file = root.appendingPathComponent(try #require(doc.vaultFile))
        #expect(FileManager.default.fileExists(atPath: file.path))
        exporter.remove(doc)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let log = try String(contentsOf: root.appendingPathComponent("raba-it/kursbar/log.md"), encoding: .utf8)
        #expect(log.contains("verworfen"))
    }
}

struct MwRouteRulesTests {
    @Test("Regeln aus mw-route lesen, config.sh überschreibt, Reihenfolge bleibt")
    func parses() {
        let script = """
        PROJECT_VAULT_DIRS=(
          [pag]="arbeit/pag"
          [neu]="arbeit/neu"
          [eingang]="_eingang"
        )
        PROJECT_KEYWORDS=(
          [pag]="cutover|uat"
          [neu]="neuprojekt"
        )
        INTERN_TITLES="team.daily"
        """
        let config = """
        PROJECT_KEYWORDS=(
          [pag]="cutover|uat|golive"
        )
        """
        let rules = MwRouteRules.parse([script, config])
        #expect(rules.keywords.map(\.key) == ["pag", "neu"])
        #expect(rules.keywords.first?.pattern == "cutover|uat|golive")
        #expect(rules.areas.last?.key == "eingang")
        #expect(rules.areas.contains { $0.key == "neu" && $0.folder == "arbeit/neu" })
        #expect(rules.internTitles == "team.daily")
    }

    @Test("Echtes mw-route-Skript ergibt dieselben Bereiche wie eingebaut")
    func realScriptMatches() {
        let rules = MwRouteRules.load()
        #expect(Set(rules.areas.map(\.key)).isSuperset(of: ["pag", "wk", "tm", "intern", "eingang"]))
    }
}

struct LogDigestTests {
    @Test("Entscheidungen und Aufgaben aus den Notizen, „Keine“ entfällt")
    func items() {
        let summary = "### Zusammenfassung\n- A\n\n### Entscheidungen\n- Release am Donnerstag\n\n### Aufgaben\n- [ ] Ich: Testfälle bis Mittwoch\n\n### Offene Fragen\nKeine"
        #expect(VaultExporter.items(under: "Entscheidungen", in: summary) == ["Release am Donnerstag"])
        #expect(VaultExporter.items(under: "Aufgaben", in: summary) == ["Ich: Testfälle bis Mittwoch"])
        #expect(VaultExporter.items(under: "Entscheidungen", in: "### Entscheidungen\n- Keine").isEmpty)
    }

    @Test("Die log.md bekommt Entscheidungen und Aufgaben als Unterpunkte")
    func logContainsDigest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-vault-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try VaultExporter(root: root).export(MeetingDocument(
            startedAt: Date(), duration: 5, sourceNames: [],
            lines: [TranscriptLine(speaker: .me, start: 0, end: 1, text: "Kursbar")],
            summary: "### Zusammenfassung\n- Kursbar geplant\n### Entscheidungen\n- Start im Januar\n### Aufgaben\n- [ ] Ich: Angebot schreiben",
            notes: []))
        let log = try String(contentsOf: root.appendingPathComponent("raba-it/kursbar/log.md"), encoding: .utf8)
        #expect(log.contains("  - Entscheidung: Start im Januar"))
        #expect(log.contains("  - Aufgabe: Ich: Angebot schreiben"))
    }
}

struct MeetingAreaTests {

    private func doc(title: String, summary: String?) -> MeetingDocument {
        var document = MeetingDocument(
            startedAt: Date(), duration: 60, sourceNames: ["Teams"],
            lines: [TranscriptLine(speaker: .others, start: 1, end: 3, text: "Wir gehen die Fälle durch.", speakerID: "1")],
            summary: summary, notes: []
        )
        document.aiTitle = title
        return document
    }

    @Test("Der Titel zählt jetzt mit")
    func titleIsChecked() {
        #expect(VaultExporter.detectProject(for: doc(title: "Projekt Nord Teststatus", summary: nil)) == "pag")
    }

    @Test("Antwort des Modells: erster bekannter Schlüssel")
    func parsesAnswer() {
        let keys = ["pag", "wk", "tm", "eingang"]
        #expect(MeetingAreaSuggester.parse("pag", keys: keys) == "pag")
        #expect(MeetingAreaSuggester.parse("Bereich: PAG.", keys: keys) == "pag")
        #expect(MeetingAreaSuggester.parse("weiß nicht", keys: keys) == nil)
    }

    @Test("Ohne Stichwort schlägt das Modell PAG vor, Unsinn bleibt ohne Vorschlag")
    func suggests() async {
        let document = doc(title: "Abstimmung Prozessumfang Buchhaltung", summary: "- Umfang je Prozess")
        #expect(VaultExporter.detectProject(for: document) == "eingang")
        var model = FakeSummarizer(result: .success(""))
        model.askResult = .success("pag")
        #expect(await MeetingAreaSuggester.suggest(for: document, using: model) == "pag")
        model.askResult = .success("keine Ahnung")
        #expect(await MeetingAreaSuggester.suggest(for: document, using: model) == nil)
    }
}
