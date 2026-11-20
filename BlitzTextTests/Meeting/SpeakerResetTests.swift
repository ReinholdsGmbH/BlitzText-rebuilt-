import FluidAudio
import Foundation
import Testing
@testable import BlitzText

struct SpeakerResetTests {

    private let diarization = MeetingDiarization(
        segments: [
            DiarizedSegment(speakerID: "A", start: 0, end: 10),
            DiarizedSegment(speakerID: "B", start: 10, end: 20),
            DiarizedSegment(speakerID: "A", start: 30, end: 40)
        ],
        knownNames: ["B": "Bernd"])

    private func document() -> MeetingDocument {
        var doc = MeetingDocument(
            startedAt: Date(), duration: 60, sourceNames: ["Teams"],
            lines: [
                TranscriptLine(speaker: .me, start: 0, end: 2, text: "Hallo"),
                TranscriptLine(speaker: .others, start: 1, end: 9, text: "Eins", speakerID: "hand-1"),
                TranscriptLine(speaker: .others, start: 8, end: 19, text: "Zwei", speakerID: "hand-1"),
                TranscriptLine(speaker: .others, start: 25, end: 27, text: "Drei", speakerID: "hand-1")
            ],
            summary: nil, notes: [], speakerNames: ["hand-1": "Falsch"], nameSources: ["hand-1": .manual])
        doc.learnedSamples = [LearnedSample(name: "Falsch", segmentID: UUID())]
        return doc
    }

    @Test("Beiträge gehen an die Stimme mit dem größten Überlapp, ohne Überlapp an die nächste")
    func reassignsByOverlap() {
        let reset = document().resettingSpeakers(to: diarization, excludingSelf: true)
        #expect(reset.lines.map(\.speakerID) == [nil, "A", "B", "A"])
        #expect(reset.lines.map(\.text) == ["Hallo", "Eins", "Zwei", "Drei"])
    }

    @Test("Eigene Namen fallen weg, Profiltreffer bleiben, gelernte Proben sind abgehakt")
    func clearsNames() {
        let reset = document().resettingSpeakers(to: diarization, excludingSelf: true)
        #expect(reset.speakerNames == ["B": "Bernd"])
        #expect(reset.nameSources == ["B": .profile])
        #expect(reset.learnedSamples == nil)
    }

    @Test("Probe wird aus dem Profil genommen; ein Profil nur aus dieser Probe verschwindet")
    func removesSamples() {
        let wrong = UUID(), right = UUID(), alone = UUID()
        var anna = Speaker(name: "Anna", currentEmbedding: [1, 0], duration: 10, isPermanent: true)
        anna.addRawEmbedding(RawEmbedding(segmentId: right, embedding: [1, 0]))
        anna.addRawEmbedding(RawEmbedding(segmentId: wrong, embedding: [0, 1]))
        var neu = Speaker(name: "Neu", currentEmbedding: [0, 1], duration: 10, isPermanent: true)
        neu.addRawEmbedding(RawEmbedding(segmentId: alone, embedding: [0, 1]))
        let other = Speaker(name: "Ohne Proben", currentEmbedding: [1, 1], duration: 10, isPermanent: true)

        let result = FluidMeetingDiarizer.removing(
            [LearnedSample(name: "Anna", segmentID: wrong), LearnedSample(name: "Neu", segmentID: alone)],
            from: [anna, neu, other])

        #expect(result.speakers.map(\.name) == ["Anna", "Ohne Proben"])
        #expect(result.removed == 2 && result.deletedProfiles == 1)
        #expect(result.speakers[0].rawEmbeddings.map(\.segmentId) == [right])
        #expect(abs(result.speakers[0].currentEmbedding[0] - 1) < 0.001)
    }
}

@MainActor
struct SpeakerResetLibraryTests {

    @Test("Zurücksetzen nimmt die gelernten Proben zurück und baut die Zuordnung neu")
    func resetsThroughLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-reset-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = MeetingArchive(root: root)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Teams")
        let sample = LearnedSample(name: "Falsch", segmentID: UUID())
        var doc = MeetingDocument(
            startedAt: Date(), duration: 30, sourceNames: ["Microsoft Teams"],
            lines: [TranscriptLine(speaker: .others, start: 1, end: 3, text: "Hallo", speakerID: "hand-1")],
            summary: nil, notes: [], speakerNames: ["hand-1": "Falsch"], nameSources: ["hand-1": .manual])
        doc.learnedSamples = [sample]
        try archive.writeProtocol(doc, in: folder)

        let diarizer = FakeDiarizer(MeetingDiarization(
            segments: [DiarizedSegment(speakerID: "S1", start: 0, end: 5)], knownNames: [:]))
        let library = MeetingLibrary(archive: archive, diarizer: diarizer, makeSummarizer: { FakeSummarizer(result: .success("")) })
        library.reload()
        await library.resetSpeakers(in: folder)

        #expect(diarizer.forgotten == [sample])
        let saved = try #require(archive.load(folder: folder))
        #expect(saved.lines.map(\.speakerID) == ["S1"])
        #expect(saved.speakerNames.isEmpty && saved.learnedSamples == nil)
        #expect(library.lastError == nil)
    }

    @Test("Benennen merkt sich die gelernte Probe im Meeting")
    func assignRecordsSample() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-reset-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = MeetingArchive(root: root)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Teams")
        try archive.writeProtocol(MeetingDocument(
            startedAt: Date(), duration: 30, sourceNames: ["Microsoft Teams"],
            lines: [TranscriptLine(speaker: .others, start: 1, end: 9, text: "Hallo", speakerID: "S1")],
            summary: nil, notes: []), in: folder)
        let diarizer = FakeDiarizer(MeetingDiarization(segments: [], knownNames: [:]))
        let library = MeetingLibrary(archive: archive, diarizer: diarizer, makeSummarizer: { FakeSummarizer(result: .success("")) })
        library.reload()
        await library.assign(name: "Anna", to: "S1", in: folder)
        let saved = try #require(archive.load(folder: folder))
        #expect(saved.learnedSamples?.map(\.name) == ["Anna"])
    }
}
