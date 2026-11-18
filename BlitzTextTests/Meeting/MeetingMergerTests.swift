import Foundation
import Testing
@testable import BlitzText

struct MeetingMergerTests {

    private func part(_ minute: Int, lines: [TranscriptLine], names: [String: String] = [:],
                      notes: String? = nil, track: String = MeetingArchive.othersTrackFile) -> MeetingDocument {
        var doc = MeetingDocument(
            startedAt: Date(timeIntervalSince1970: TimeInterval(minute * 60)), duration: 60, sourceNames: ["Teams"],
            lines: lines, summary: "alt", notes: [], speakerNames: names,
            nameSources: names.mapValues { _ in .confirmed }, diarizedTrack: track)
        doc.userNotes = notes
        return doc
    }

    @Test("Zeiten versetzt, gleiche Namen vereint, unbenannte Stimmen je Teil getrennt")
    func mergesDocuments() throws {
        let a = part(0, lines: [TranscriptLine(speaker: .others, start: 5, end: 8, text: "A1", speakerID: "1"),
                                TranscriptLine(speaker: .others, start: 10, end: 12, text: "A2", speakerID: "2"),
                                TranscriptLine(speaker: .me, start: 20, end: 22, text: "Ich A")],
                     names: ["1": "Max Muster"], notes: "Notiz A")
        let b = part(90, lines: [TranscriptLine(speaker: .others, start: 3, end: 6, text: "B1", speakerID: "7"),
                                 TranscriptLine(speaker: .others, start: 8, end: 9, text: "B2", speakerID: "2")],
                     names: ["7": "max muster"], notes: "Notiz B")

        let merged = try MeetingMerger.mergedDocument([a, b], lengths: [60, 40])

        #expect(merged.duration == 100)
        #expect(merged.lines.map(\.text) == ["A1", "A2", "Ich A", "B1", "B2"])
        #expect(merged.lines[3].start == 63)
        // Max aus beiden Teilen ist eine Stimme, die beiden unbenannten „2“ bleiben getrennt.
        #expect(merged.lines[0].speakerID == merged.lines[3].speakerID)
        #expect(merged.lines[1].speakerID != merged.lines[4].speakerID)
        #expect(merged.speakerNames.values.filter { SpeakerNaming.key($0) == "max muster" }.count == 1)
        #expect(merged.summary == nil)
        #expect(merged.userNotes?.contains("Notiz A") == true && merged.userNotes?.contains("Notiz B") == true)
        #expect(merged.notes.first?.hasPrefix("Zusammengeführt aus 2 Teilen") == true)
    }

    @Test("Aufnahme und Mischspur-Import ergeben zusammen eine Mischspur")
    func mixedKindsBecomeMixed() throws {
        let a = part(0, lines: [TranscriptLine(speaker: .me, start: 1, end: 2, text: "Ich")])
        let b = part(5, lines: [], track: MeetingArchive.mixedTrackFile)
        let merged = try MeetingMerger.mergedDocument([a, b], lengths: [60, 60])
        #expect(merged.diarizedTrack == MeetingArchive.mixedTrackFile)
        #expect(MeetingMerger.sources(for: MeetingArchive.mixedTrackFile, in: a)
                == [MeetingArchive.microphoneTrackFile, MeetingArchive.othersTrackFile])
        #expect(MeetingMerger.sources(for: MeetingArchive.mixedTrackFile, in: b) == [MeetingArchive.mixedTrackFile])
    }

    @Test("Tonspuren werden aneinandergehängt und auf die Teil-Länge aufgefüllt")
    func concatenatesAudio() throws {
        let first = try TestAudio.wav(duration: 2, bursts: [0.5...1], at: TestAudio.tempURL())
        let second = try TestAudio.wav(duration: 3, bursts: [1...2], at: TestAudio.tempURL())
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID()).wav")
        let output = TestAudio.tempURL()
        defer { [first, second, output].forEach { try? FileManager.default.removeItem(at: $0) } }

        try MeetingMerger.concatenate([[first], [missing], [second, first]], lengths: [2.5, 1, 3], into: output)

        #expect(abs(MeetingMerger.duration(of: output) - 6.5) < 0.01)
    }
}
