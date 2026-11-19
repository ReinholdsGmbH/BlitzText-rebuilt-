import AVFoundation
import Foundation
import Testing
@testable import BlitzText

struct SpeakerLabelParserTests {

    @Test("Name aus Screenreader-Beschriftungen", arguments: [
        ("Anna Müller, spricht", "Anna Müller"),
        ("Anna Müller is speaking", "Anna Müller"),
        ("Jens Bauer, Mikrofon an, speaking", "Jens Bauer"),
        ("Dr. Kim Lee, talking", "Dr. Kim Lee")
    ])
    func extractsName(label: String, expected: String) {
        #expect(SpeakerLabelParser.speakingName(in: label) == expected)
    }

    @Test("Keine Treffer für eigene Kachel, Verneinung und Fremdtext", arguments: [
        "You are speaking",
        "Thomas Raba (Ich), spricht",
        "Anna Müller, spricht nicht",
        "Anna Müller, stummgeschaltet",
        "Lautsprecher auswählen",
        ", speaking"
    ])
    func rejects(label: String) {
        #expect(SpeakerLabelParser.speakingName(in: label) == nil)
    }
}

struct SpeakerNameSuggesterTests {

    private let segments = [
        DiarizedSegment(speakerID: "1", start: 0, end: 10),
        DiarizedSegment(speakerID: "2", start: 10, end: 20),
        DiarizedSegment(speakerID: "1", start: 20, end: 30)
    ]

    @Test("Dominanter Name aus der App wird der Stimme zugeordnet")
    func assignsDominantName() {
        let hints = (0..<8).map { SpeakerHint(time: Double($0) + 1, name: "Anna") }
            + (0..<5).map { SpeakerHint(time: Double($0) + 11, name: "Jens") }
            + [SpeakerHint(time: 25, name: "Anna"), SpeakerHint(time: 26, name: "Jens")]
        let result = SpeakerNameSuggester.suggest(segments: segments, hints: hints)
        #expect(result == ["1": "Anna", "2": "Jens"])
    }

    @Test("Zu wenige oder uneindeutige Belege ergeben keinen Namen")
    func needsClearEvidence() {
        let few = [SpeakerHint(time: 1, name: "Anna"), SpeakerHint(time: 2, name: "Anna")]
        #expect(SpeakerNameSuggester.suggest(segments: segments, hints: few).isEmpty)

        let mixed = (0..<4).map { SpeakerHint(time: Double($0) + 1, name: "Anna") }
            + (0..<4).map { SpeakerHint(time: Double($0) + 5, name: "Jens") }
        #expect(SpeakerNameSuggester.suggest(segments: segments, hints: mixed).isEmpty)
    }

    @Test("Ein Name geht nur an eine Stimme")
    func nameUsedOnce() {
        let hints = (0..<6).map { SpeakerHint(time: Double($0) + 1, name: "Anna") }
            + (0..<4).map { SpeakerHint(time: Double($0) + 11, name: "Anna") }
        #expect(SpeakerNameSuggester.suggest(segments: segments, hints: hints) == ["1": "Anna"])
    }
}

struct DiarizedSpanTests {

    @Test("Nachbarn derselben Stimme verschmelzen, Wechsel trennen, Überlanges wird geteilt")
    func buildsSpans() {
        let spans = MeetingTranscriber.spans(from: [
            DiarizedSegment(speakerID: "1", start: 0, end: 4),
            DiarizedSegment(speakerID: "1", start: 4.5, end: 8),
            DiarizedSegment(speakerID: "2", start: 8.2, end: 9),
            DiarizedSegment(speakerID: "2", start: 9.1, end: 9.3),
            DiarizedSegment(speakerID: "1", start: 10, end: 70)
        ], padding: 0)
        #expect(spans.map(\.speakerID) == ["1", "2", "1", "1", "1"])
        #expect(spans[0].span == SpeechSpan(start: 0, end: 8))
        #expect(spans.allSatisfy { $0.span.duration <= 25.0001 })
    }
}

struct MeetingDocumentTests {

    private func document() -> MeetingDocument {
        MeetingDocument(
            startedAt: Date(timeIntervalSince1970: 0), duration: 60, sourceNames: ["Teams"],
            lines: [
                TranscriptLine(speaker: .me, start: 0, end: 2, text: "Hallo"),
                TranscriptLine(speaker: .others, start: 3, end: 5, text: "Hi", speakerID: "7"),
                TranscriptLine(speaker: .others, start: 6, end: 9, text: "Moin", speakerID: "3"),
                TranscriptLine(speaker: .others, start: 10, end: 12, text: "Ja", speakerID: "9")
            ],
            summary: nil, notes: [],
            speakerNames: ["3": "Anna", "9": "Jens"],
            nameSources: ["3": .profile, "9": .meetingApp]
        )
    }

    @Test("Bezeichnungen: Ich, Name, durchnummerierte Unbekannte")
    func labels() {
        let doc = document()
        #expect(doc.lines.map { doc.label(for: $0) } == ["Ich", "Sprecher 1", "Anna", "Jens"])
        #expect(doc.speakerIDs == ["7", "3", "9"])
    }

    @Test("Unbestätigt sind unbenannte und nur aus der App benannte Stimmen")
    func unconfirmed() {
        #expect(document().unconfirmedSpeakerIDs == ["7", "9"])
    }

    @Test("JSON-Ablage verliert nichts")
    func roundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-doc-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = MeetingArchive(root: root)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Teams")
        try archive.writeProtocol(document(), in: folder)
        #expect(archive.load(folder: folder) == document())
        #expect(archive.loadAll().count == 1)
        let md = try String(contentsOf: folder.appendingPathComponent(MeetingArchive.protocolFile), encoding: .utf8)
        #expect(md.contains("**[00:00:06] Anna:** Moin"))
        #expect(md.contains("- Teilnehmende: Ich, Sprecher 1, Anna, Jens"))
    }
}

struct MeetingImportTests {

    @Test("MacWhisper-Paar: mic-audio wird Mikrofon, egal in welcher Reihenfolge")
    func detectsMacWhisperPair() throws {
        let mic = URL(fileURLWithPath: "/x/ABC_mic-audio_123.m4a")
        let app = URL(fileURLWithPath: "/x/ABC_app-audio_456.m4a")
        #expect(try MeetingImport.plan(for: [app, mic]) == .init(microphone: mic, others: app))
        #expect(try MeetingImport.plan(for: [mic, app]) == .init(microphone: mic, others: app))
    }

    @Test("Beginn aus dem Dateinamen einer iPhone-Aufnahme")
    func startDateFromFileName() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let date = try #require(MeetingImport.startDate(fromFileName: "19.11.26_10.07_Koalition und Reformpaket.m4a", timeZone: berlin))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(parts == DateComponents(year: 2026, month: 11, day: 19, hour: 10, minute: 7))
        #expect(MeetingImport.startDate(fromFileName: "meeting.m4a") == nil)
        #expect(MeetingImport.startDate(fromFileName: "31.02.26_10.07_x.m4a") == nil)
    }

    @Test("Eine Datei ist eine Mischspur, drei sind zu viele")
    func singleAndTooMany() throws {
        let one = URL(fileURLWithPath: "/x/meeting.m4a")
        #expect(try MeetingImport.plan(for: [one]).isMixed)
        #expect(throws: MeetingImport.ImportError.self) { try MeetingImport.plan(for: [one, one, one]) }
    }

    @Test("Stereo-Datei mit 44,1 kHz wird zu 16 kHz mono mit gleicher Dauer")
    func convertsFormat() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-\(UUID()).caf")
        let target = TestAudio.tempURL()
        defer { [source, target].forEach { try? FileManager.default.removeItem(at: $0) } }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: source, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100 * 3)!
        buffer.frameLength = buffer.frameCapacity
        for ch in 0..<2 { for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![ch][i] = Float(sin(Double(i) * 0.05) * 0.3) } }
        try file.write(from: buffer)

        let duration = try MeetingImport.convert(source, to: target)
        let out = try AVAudioFile(forReading: target)
        #expect(abs(duration - 3) < 0.05)
        #expect(out.fileFormat.sampleRate == 16_000)
        #expect(out.fileFormat.channelCount == 1)
    }
}

@MainActor
struct MeetingSpeakerPipelineTests {

    @Test("Import einer Mischspur: Stimmen getrennt, bekanntes Profil benannt, Rest nummeriert")
    func importWithDiarization() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let mixed = try TestAudio.wav(duration: 10, bursts: [1...3, 5...8], at: TestAudio.tempURL())
        defer { try? FileManager.default.removeItem(at: mixed) }

        let diarizer = FakeDiarizer(MeetingDiarization(
            segments: [DiarizedSegment(speakerID: "p1", start: 1, end: 3), DiarizedSegment(speakerID: "2", start: 5, end: 8)],
            knownNames: ["p1": "Thomas"]
        ))
        let controller = MeetingController(
            recorder: MeetingRecorder(microphone: FakeAudioRecorder(fixtureURL: mixed),
                                      systemAudio: FakeSystemAudioTap(fixtureURL: mixed),
                                      detector: MeetingDetector(), processList: FakeAudioProcessList()),
            archive: MeetingArchive(root: root),
            makeTranscriber: { SequenceTranscriber(["Erster Beitrag", "Zweiter Beitrag"]) },
            makeSummarizer: { FakeSummarizer(result: .success("### Zusammenfassung\n- ok")) },
            diarizer: diarizer,
            language: { "de" }
        )

        controller.importFiles([mixed])
        for _ in 0..<200 {
            if case .finished = controller.phase { break }
            if case .failed = controller.phase { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        guard case .finished(let folder, _, let unnamed) = controller.phase else {
            Issue.record("Phase: \(controller.phase)"); return
        }
        let doc = try #require(MeetingArchive(root: root).load(folder: folder))
        #expect(doc.diarizedTrack == MeetingArchive.mixedTrackFile)
        #expect(doc.lines.map { doc.label(for: $0) } == ["Thomas", "Sprecher 1"])
        #expect(unnamed == 1)
    }

    @Test("Benennen in der Bibliothek lernt das Profil aus genau den Abschnitten dieser Stimme")
    func assignLearnsProfile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = MeetingArchive(root: root)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Teams")
        try archive.writeProtocol(MeetingDocument(
            startedAt: Date(), duration: 30, sourceNames: ["Teams"],
            lines: [
                TranscriptLine(speaker: .others, start: 1, end: 6, text: "A", speakerID: "4"),
                TranscriptLine(speaker: .others, start: 7, end: 9, text: "B", speakerID: "5"),
                TranscriptLine(speaker: .others, start: 10, end: 15, text: "C", speakerID: "4")
            ],
            summary: nil, notes: []
        ), in: folder)

        let diarizer = FakeDiarizer(MeetingDiarization(segments: [], knownNames: [:]))
        let library = MeetingLibrary(archive: archive, diarizer: diarizer,
                                     makeSummarizer: { FakeSummarizer(result: .success("")) })
        library.reload()
        await library.assign(name: "  Anna  ", to: "4", in: folder)

        #expect(diarizer.learned.count == 1)
        #expect(diarizer.learned.first?.name == "Anna")
        #expect(diarizer.learned.first?.spans == [SpeechSpan(start: 1, end: 6), SpeechSpan(start: 10, end: 15)])
        let doc = try #require(archive.load(folder: folder))
        #expect(doc.speakerNames["4"] == "Anna")
        #expect(doc.nameSources["4"] == .confirmed)
        #expect(doc.unconfirmedSpeakerIDs == ["5"])
    }

    @Test("Zu kurze Stimme: Name wird trotzdem zugeordnet und verschwindet aus „Wer spricht hier?“")
    func assignWithoutProfileStillConfirms() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = MeetingArchive(root: root)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Teams")
        try archive.writeProtocol(MeetingDocument(
            startedAt: Date(), duration: 30, sourceNames: ["Teams"],
            lines: [TranscriptLine(speaker: .others, start: 1, end: 2, text: "Ja.", speakerID: "7")],
            summary: nil, notes: []
        ), in: folder)

        let diarizer = FakeDiarizer(MeetingDiarization(segments: [], knownNames: [:]))
        diarizer.learnError = EnrollmentError.tooShort
        let library = MeetingLibrary(archive: archive, diarizer: diarizer,
                                     makeSummarizer: { FakeSummarizer(result: .success("")) })
        library.reload()
        await library.assign(name: "Bernd", to: "7", in: folder)

        let doc = try #require(archive.load(folder: folder))
        #expect(doc.speakerNames["7"] == "Bernd")
        #expect(doc.nameSources["7"] == .manual)
        #expect(doc.unconfirmedSpeakerIDs.isEmpty)
        #expect(library.lastError?.contains("ohne Stimmprofil") == true)
    }
}

struct SnippetSelectionTests {

    @Test("Hörprobe: ein Beitrag für Text und Ton, bevorzugt 4 bis 20 Sekunden; Spur passt zur Seite")
    func sampleAndTrack() {
        let doc = MeetingDocument(
            startedAt: Date(), duration: 60, sourceNames: ["Teams"],
            lines: [
                TranscriptLine(speaker: .me, start: 0, end: 4, text: "a"),
                TranscriptLine(speaker: .others, start: 5, end: 8, text: "b", speakerID: "1"),
                TranscriptLine(speaker: .others, start: 10, end: 40, text: "c", speakerID: "1")
            ],
            summary: nil, notes: []
        )
        // Bevorzugt 4–20 s: der 3-s-Beitrag ist zu kurz, der 30-s-Beitrag zu lang → mangels
        // Alternative im Bereich der längste; mit einem 8-s-Beitrag gewinnt dieser.
        #expect(doc.sampleLine(of: "1")?.text == "c")
        #expect(doc.sampleLine(of: "9") == nil)
        var withComfortable = doc
        withComfortable.lines.append(TranscriptLine(speaker: .others, start: 45, end: 53, text: "d", speakerID: "1"))
        #expect(withComfortable.sampleLine(of: "1")?.text == "d")
        #expect(doc.trackFile(for: doc.lines[0]) == MeetingArchive.microphoneTrackFile)
        #expect(doc.trackFile(for: doc.lines[1]) == MeetingArchive.othersTrackFile)

        var mixed = doc
        mixed.diarizedTrack = MeetingArchive.mixedTrackFile
        #expect(mixed.trackFile(for: doc.lines[0]) == MeetingArchive.mixedTrackFile)
    }
}

struct MeetingProfileMatcherTests {
    private func cluster(_ id: String, _ seconds: Float, _ embedding: [Float]) -> MeetingProfileMatcher.Cluster {
        .init(id: id, duration: seconds, embedding: embedding)
    }

    @Test("Nahes Profil mit klarem Vorsprung wird zugeordnet")
    func matchesClearWinner() {
        let result = MeetingProfileMatcher.match([cluster("1", 800, [1, 0, 0])],
                                                 profiles: [("Max", [0.98, 0.1, 0]), ("Lisa", [0, 1, 0])])
        #expect(result == ["1": "Max"])
    }

    @Test("Kurze Stimme, ferne Profile und knappe Abstände bleiben ohne Namen")
    func rejectsWeakMatches() {
        let profiles: [(name: String, embedding: [Float])] = [("A", [1, 0, 0]), ("B", [0.99, 0.12, 0]), ("C", [0, 0, 1])]
        // zu kurz
        #expect(MeetingProfileMatcher.match([cluster("1", 5, [1, 0, 0])], profiles: profiles).isEmpty)
        // A und B fast gleich nah: kein klarer Vorsprung
        #expect(MeetingProfileMatcher.match([cluster("2", 60, [1, 0.06, 0])], profiles: profiles).isEmpty)
        // zu weit weg von allem
        #expect(MeetingProfileMatcher.match([cluster("3", 60, [0, 1, 0])], profiles: [("A", [1, 0, 0]), ("C", [0, 0, 1])]).isEmpty)
    }

    @Test("Ein Profil geht nur an eine Stimme, die nähere gewinnt")
    func profileUsedOnce() {
        let result = MeetingProfileMatcher.match(
            [cluster("1", 100, [1, 0.05, 0]), cluster("2", 100, [1, 0, 0])],
            profiles: [("A", [1, 0, 0]), ("C", [0, 0, 1])])
        #expect(result == ["2": "A"])
    }
}
