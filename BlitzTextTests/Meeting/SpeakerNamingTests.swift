import AVFoundation
import Foundation
import Testing
@testable import BlitzText

struct SpeakerNamingTests {

    @Test("Vergleichsform: Groß/klein, Umlaut-Schreibweise und Leerzeichen sind egal", arguments: [
        ("Anna Müller", "anna mueller"),
        ("Anna  Müller ", "ANNA MÜLLER"),
        ("José", "jose"),
        ("Strauß", "strauss")
    ])
    func keyMatches(a: String, b: String) {
        #expect(SpeakerNaming.key(a) == SpeakerNaming.key(b))
    }

    @Test("Getippte Variante übernimmt die vorhandene Schreibweise")
    func canonical() {
        let known = ["Anna Müller", "Jens Bauer"]
        #expect(SpeakerNaming.canonical("anna mueller", known: known) == "Anna Müller")
        #expect(SpeakerNaming.canonical("  Neue Person ", known: known) == "Neue Person")
    }

    @Test("Vorschläge: Wortanfang vor Wortmitte, ohne Dubletten, leer zeigt alle")
    func suggestions() {
        let known = ["Anna Müller", "Hanna Berg", "Jens Bauer", "anna müller"]
        #expect(SpeakerNaming.suggestions(for: "an", known: known) == ["Anna Müller", "Hanna Berg"])
        #expect(SpeakerNaming.suggestions(for: "bau", known: known) == ["Jens Bauer"])
        #expect(SpeakerNaming.suggestions(for: "", known: known) == ["Anna Müller", "Hanna Berg", "Jens Bauer"])
        #expect(SpeakerNaming.suggestions(for: "xyz", known: known).isEmpty)
    }

    private func document() -> MeetingDocument {
        MeetingDocument(
            startedAt: Date(), duration: 60, sourceNames: ["Teams"],
            lines: [
                TranscriptLine(speaker: .others, start: 0, end: 4, text: "Eins", speakerID: "1"),
                TranscriptLine(speaker: .others, start: 5, end: 8, text: "Zwei", speakerID: "3"),
                TranscriptLine(speaker: .others, start: 20, end: 24, text: "Drei", speakerID: "2"),
                TranscriptLine(speaker: .others, start: 30, end: 33, text: "Vier", speakerID: "3")
            ],
            summary: nil, notes: [],
            speakerNames: ["1": "Anna Müller"], nameSources: ["1": .confirmed]
        )
    }

    @Test("Zweite Stimme mit vorhandenem Namen wird mit der ersten zusammengeführt")
    func mergesTwin() {
        let merged = document().assigning(name: "anna mueller", to: "3", source: .confirmed)
        #expect(merged.speakerIDs == ["1", "2"])
        #expect(merged.lines.map(\.text) == ["Eins Zwei", "Drei", "Vier"])
        #expect(merged.lines.map { merged.label(for: $0) } == ["Anna Müller", "Sprecher 1", "Anna Müller"])
        #expect(merged.speakerNames["3"] == nil)
        #expect(merged.unconfirmedSpeakerIDs == ["2"])
    }

    @Test("Neuer Name bleibt bei seiner Stimme")
    func plainAssign() {
        let doc = document().assigning(name: "Jens", to: "2", source: .confirmed)
        #expect(doc.speakerNames["2"] == "Jens")
        #expect(doc.speakerIDs == ["1", "3", "2"])
    }
}

@MainActor
struct LibraryNamingTests {

    @Test("Bibliothek: Tippvariante eines Profils ergibt keinen zweiten Namen und führt zusammen")
    func assignUsesProfileSpelling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = MeetingArchive(root: root)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Teams")
        try archive.writeProtocol(MeetingDocument(
            startedAt: Date(), duration: 30, sourceNames: ["Teams"],
            lines: [
                TranscriptLine(speaker: .others, start: 1, end: 6, text: "A", speakerID: "4"),
                TranscriptLine(speaker: .others, start: 7, end: 9, text: "B", speakerID: "5")
            ],
            summary: nil, notes: []
        ), in: folder)

        let diarizer = FakeDiarizer(MeetingDiarization(segments: [], knownNames: [:]))
        diarizer.profileNames = ["Anna Müller"]
        let library = MeetingLibrary(archive: archive, diarizer: diarizer,
                                     makeSummarizer: { FakeSummarizer(result: .success("")) })
        library.reload()
        #expect(library.knownNames == ["Anna Müller"])

        await library.assign(name: "anna mueller", to: "4", in: folder)
        await library.assign(name: "ANNA MÜLLER", to: "5", in: folder)

        #expect(diarizer.learned.map(\.name) == ["Anna Müller", "Anna Müller"])
        let doc = try #require(archive.load(folder: folder))
        #expect(doc.speakerIDs == ["4"])
        #expect(Set(doc.speakerNames.values) == ["Anna Müller"])
    }
}

/// Prüft an einem echten Meeting, ob Text und Ton der Sprechblasen zusammenpassen:
/// Tonabschnitt herausschneiden, erneut transkribieren, mit dem gespeicherten Text vergleichen.
/// Läuft nur mit TEST_RUNNER_BLITZTEXT_ALIGN_FOLDER=<Meeting-Ordner>.
@MainActor
struct TranscriptAlignmentLiveTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["BLITZTEXT_ALIGN_FOLDER"]

    @Test("Sprechblase und Tonabschnitt sagen dasselbe", .enabled(if: folder != nil), .timeLimit(.minutes(10)))
    func textMatchesAudio() async throws {
        let folder = URL(fileURLWithPath: try #require(Self.folder))
        let doc = try #require(MeetingArchive(root: folder.deletingLastPathComponent()).load(folder: folder))
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "blitztext-align-\(UUID())")!)
        let parakeet = PlainParakeetTranscriber(client: ParakeetClient(settings: settings, diarizerManager: DiarizerModelManager()))

        var scores: [Double] = []
        for line in doc.lines.filter({ $0.end - $0.start >= 1.5 }).prefix(6) {
            let clip = TestAudio.tempURL()
            defer { try? FileManager.default.removeItem(at: clip) }
            try MeetingTranscriber.extract(SpeechSpan(start: line.start, end: line.end),
                                           from: folder.appendingPathComponent(doc.trackFile(for: line)), to: clip)
            let again = try await parakeet.transcribe(audioURL: clip, language: "de", prompt: nil)
            let score = TranscriptMerger.similarity(line.text, again)
            scores.append(score)
            print("ALIGN \(doc.label(for: line)) \(Int(line.start))–\(Int(line.end)) s: Übereinstimmung \(Int(score * 100)) %")
        }
        #expect(!scores.isEmpty)
        #expect(scores.allSatisfy { $0 >= 0.6 })
    }
}

struct LineReassignTests {

    private func document(side: TranscriptLine.Speaker = .others) -> MeetingDocument {
        MeetingDocument(
            startedAt: Date(), duration: 60, sourceNames: ["Import"],
            lines: [
                TranscriptLine(speaker: .others, start: 0, end: 4, text: "Hallo", speakerID: "1"),
                TranscriptLine(speaker: side, start: 5, end: 8, text: "Falsch zugeordnet", speakerID: side == .me ? nil : "2"),
                TranscriptLine(speaker: .others, start: 9, end: 12, text: "Weiter", speakerID: "1")
            ],
            summary: nil, notes: [],
            speakerNames: ["1": "Anna", "2": "Thomas"], nameSources: ["1": .confirmed, "2": .confirmed]
        )
    }

    @Test("Ein Beitrag wechselt die Person, Nachbarn derselben Person werden ein Absatz")
    func moveToExisting() {
        let doc = document().reassigning(lineAt: 1, toSpeaker: "1")
        #expect(doc.lines.count == 1)
        #expect(doc.lines[0].text == "Hallo Falsch zugeordnet Weiter")
        #expect(doc.speakerIDs == ["1"])
    }

    @Test("Neuer Name legt eine Person ohne Profil an; vorhandener Name nutzt deren Stimme")
    func moveToName() {
        let fresh = document().reassigning(lineAt: 1, toName: "Jens")
        let id = try! #require(fresh.lines[1].speakerID)
        #expect(fresh.speakerNames[id] == "Jens")
        #expect(fresh.nameSources[id] == .manual)
        #expect(fresh.unconfirmedSpeakerIDs.isEmpty)

        let existing = document().reassigning(lineAt: 1, toName: "anna")
        #expect(existing.speakerIDs == ["1"])
    }

    @Test("Eigene Mikrofon-Beiträge bleiben, wo sie sind")
    func microphoneStays() {
        let doc = document(side: .me)
        #expect(!doc.canReassign(doc.lines[1]))
        #expect(doc.reassigning(lineAt: 1, toSpeaker: "1") == doc)
    }
}

@MainActor
struct LibraryReassignTests {

    @Test("Bibliothek speichert das Umhängen dauerhaft")
    func persists() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = MeetingArchive(root: root)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Import")
        try archive.writeProtocol(MeetingDocument(
            startedAt: Date(), duration: 30, sourceNames: ["Import"],
            lines: [
                TranscriptLine(speaker: .others, start: 1, end: 3, text: "A", speakerID: "1"),
                TranscriptLine(speaker: .others, start: 20, end: 23, text: "B", speakerID: "2")
            ],
            summary: nil, notes: [], speakerNames: ["1": "Anna", "2": "Thomas"]
        ), in: folder)
        let library = MeetingLibrary(archive: archive, diarizer: FakeDiarizer(MeetingDiarization(segments: [], knownNames: [:])),
                                     makeSummarizer: { FakeSummarizer(result: .success("")) })
        library.reload()

        library.reassign(lineAt: 1, to: .speaker("1"), in: folder)

        let doc = try #require(archive.load(folder: folder))
        #expect(doc.lines.map { doc.label(for: $0) } == ["Anna", "Anna"])
    }
}

@Suite(.serialized)
struct SelfSpeakerTests {
    @Test("Eigenes Profil erscheint als „Ich“, andere unverändert")
    func selfLabel() {
        SpeakerNaming.selfName = "Thomas Raba"
        defer { SpeakerNaming.selfName = nil }
        let doc = MeetingDocument(startedAt: Date(), duration: 1, sourceNames: ["Import"],
            lines: [TranscriptLine(speaker: .others, start: 0, end: 1, text: "a", speakerID: "1"),
                    TranscriptLine(speaker: .others, start: 2, end: 3, text: "b", speakerID: "2")],
            summary: nil, notes: [], speakerNames: ["1": "thomas raba", "2": "Anna"])
        #expect(doc.lines.map { doc.label(for: $0) } == ["Ich", "Anna"])
    }
}

@MainActor
struct MeetingChatTests {
    private func entries() -> [MeetingLibrary.Entry] {
        func doc(_ title: String, _ text: String, _ speaker: String) -> MeetingDocument {
            var d = MeetingDocument(startedAt: Date(), duration: 60, sourceNames: ["Teams"],
                lines: [TranscriptLine(speaker: .others, start: 0, end: 5, text: text, speakerID: "1")],
                summary: nil, notes: [], speakerNames: ["1": speaker])
            d.aiTitle = title
            return d
        }
        return [
            .init(folder: URL(fileURLWithPath: "/tmp/a"), document: doc("Cutover-Planung", "Der Cutover ist am Freitag", "Anna")),
            .init(folder: URL(fileURLWithPath: "/tmp/b"), document: doc("Kursbar", "Anmeldungen laufen gut", "Vera"))
        ]
    }

    @Test("Suche findet das passende Meeting vorn, auch über den Sprechernamen")
    func ranking() {
        let hits = MeetingSearch.rank("Was hat Anna zum Cutover gesagt?", in: entries())
        #expect(hits.first?.entry.folder.path == "/tmp/a")
        #expect(hits.count == 1)
        #expect(MeetingSearch.snippet(in: entries()[0].document, for: "freitag") == "Anna: Der Cutover ist am Freitag")
    }

    @Test("Chat kennt das heutige Datum und den Wochentag jedes Meetings")
    func dates() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10, minute: 30)))
        #expect(MeetingChat.todayLine(today) == "Heute ist Donnerstag, 19.11.2026, 10:30 Uhr.")

        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 8, minute: 30)))
        let document = MeetingDocument(startedAt: yesterday, duration: 600, sourceNames: ["Teams"], lines: [],
                                       summary: nil, notes: [])
        #expect(MeetingSearch.dateLine(for: document) == "Zeit: Mittwoch, 18.11.2026, 08:30 bis 08:40 Uhr")
        #expect(MeetingSearch.context(for: document, limit: 10_000).contains("Mittwoch, 18.11.2026"))
    }

    @Test("Chat über alle Meetings nennt die Quellen")
    func askAll() async {
        let chat = MeetingChat(makeSummarizer: { FakeSummarizer(result: .success(""), askResult: .success("Am Freitag.")) })
        await chat.ask("Wann ist der Cutover?", scope: .all, entries: entries())
        #expect(chat.messages.map(\.role) == [.user, .assistant])
        #expect(chat.messages.last?.sources.map(\.path) == ["/tmp/a"])
    }
}

struct LiveAudioBufferTests {
    @Test("Puffer gibt neue Samples mit Startposition ab und behält nichts doppelt")
    func takeAdvances() throws {
        let buffer = LiveAudioBuffer()
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100))
        pcm.frameLength = 100
        buffer.append(pcm)
        let first = buffer.take()
        #expect(first.start == 0 && first.samples.count == 100)
        buffer.append(pcm)
        let second = buffer.take()
        #expect(second.start == 100 && second.samples.count == 100)
        #expect(buffer.take().samples.isEmpty)
    }
}

@MainActor
struct ChatThreadTests {
    @Test("Chats werden gespeichert, „Neuer Chat“ beginnt einen weiteren, alte bleiben")
    func threadsPersist() async throws {
        let store = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-chats-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: store) }
        let make = { FakeSummarizer(result: .success(""), askResult: .success("Antwort")) }
        let chat = MeetingChat(makeSummarizer: make, storeURL: store)
        await chat.ask("Projekt Nord, wie sieht es aus?", scope: .all, entries: [])
        await chat.ask("Und die Risiken?", scope: .all, entries: [])
        #expect(chat.threads.count == 1)
        #expect(chat.messages.count == 4)
        chat.newChat()
        await chat.ask("Neue Frage", scope: .all, entries: [])
        #expect(chat.threads.count == 2)
        #expect(chat.threads.first?.title == "Neue Frage")

        let reloaded = MeetingChat(makeSummarizer: make, storeURL: store)
        #expect(reloaded.threads.count == 2)
        reloaded.delete(reloaded.threads[0].id)
        #expect(MeetingChat(makeSummarizer: make, storeURL: store).threads.count == 1)
    }
}

struct LineSplitTests {
    private func doc() -> MeetingDocument {
        MeetingDocument(startedAt: Date(), duration: 30, sourceNames: ["Teams"],
                        lines: [TranscriptLine(speaker: .others, start: 10, end: 20, text: "Ja genau. Nein das sehe ich anders", speakerID: "1")],
                        summary: nil, notes: [], speakerNames: ["1": "Anna"])
    }

    @Test("Aufteilen vor einem Wort ergibt zwei Beiträge mit anteiligen Zeiten")
    func splitsLine() {
        let split = doc().splitting(lineAt: 0, beforeWord: 2)
        #expect(split.lines.map(\.text) == ["Ja genau.", "Nein das sehe ich anders"])
        #expect(split.lines.allSatisfy { $0.speakerID == "1" })
        #expect(split.lines[0].start == 10 && split.lines[1].end == 20)
        #expect(split.lines[0].end == split.lines[1].start)
        #expect(split.lines[0].end > 10 && split.lines[0].end < 15)
    }

    @Test("Danach lässt sich ein Teil einer anderen Person zuordnen")
    func reassignsPart() {
        let split = doc().splitting(lineAt: 0, beforeWord: 2).reassigning(lineAt: 1, toName: "Bernd")
        #expect(split.lines.map { split.label(for: $0) } == ["Anna", "Bernd"])
    }

    @Test("Ungültige Trennstellen ändern nichts", arguments: [0, 7, 99])
    func ignoresInvalid(word: Int) {
        #expect(doc().splitting(lineAt: 0, beforeWord: word).lines.count == 1)
    }
}

struct TranscriptDeletionTests {

    private func doc(summary: String? = "## Punkte\n- Eins") -> MeetingDocument {
        MeetingDocument(
            startedAt: Date(), duration: 60, sourceNames: ["Teams"],
            lines: [
                TranscriptLine(speaker: .me, start: 0, end: 4, text: "Eins"),
                TranscriptLine(speaker: .others, start: 5, end: 8, text: "Zwei", speakerID: "1"),
                TranscriptLine(speaker: .others, start: 9, end: 12, text: "Drei", speakerID: "2")
            ],
            summary: summary, notes: [])
    }

    @Test("Gelöschte Beiträge verschwinden, die Reihenfolge der übrigen bleibt")
    func removesLines() {
        let result = doc().removingLines(at: IndexSet([0, 2]))
        #expect(result.lines.map(\.text) == ["Zwei"])
    }

    @Test("Nach dem Löschen gilt eine vorhandene Zusammenfassung als veraltet")
    func marksSummaryOutdated() {
        #expect(doc().removingLines(at: IndexSet([1])).summaryOutdated == true)
        #expect(doc(summary: nil).removingLines(at: IndexSet([1])).summaryOutdated == nil)
    }

    @Test("Ungültige Indizes ändern nichts")
    func ignoresInvalid() {
        let original = doc()
        #expect(original.removingLines(at: IndexSet([7])) == original)
        #expect(original.removingLines(at: IndexSet()) == original)
    }

    @Test("Ohne die Sprecher-ID fällt die Person aus der Teilnehmerliste")
    func dropsSpeaker() {
        #expect(doc().removingLines(at: IndexSet([2])).speakerIDs == ["1"])
    }
}
