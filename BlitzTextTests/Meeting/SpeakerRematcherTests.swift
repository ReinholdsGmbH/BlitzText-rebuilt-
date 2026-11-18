import Foundation
import Testing
@testable import BlitzText

struct SpeakerRematcherTests {
    private func voice(_ id: String, _ seconds: Float, _ embedding: [Float], _ name: String? = nil) -> SpeakerRematcher.Voice {
        .init(id: id, duration: seconds, embedding: embedding, name: name)
    }

    @Test("Profil passt: unbenannte Stimme bekommt den Namen oder geht in die vorhandene Person auf")
    func matchesProfiles() {
        let voices = [voice("1-2", 100, [1, 0, 0], "Anna"), voice("2-5", 80, [0.99, 0.05, 0]), voice("3-1", 60, [0, 1, 0])]
        let plan = SpeakerRematcher.plan(voices: voices, profiles: [("Anna", [1, 0, 0]), ("Bernd", [0, 1, 0.02])])
        #expect(plan.merges["2-5"] == "1-2")
        #expect(plan.names["3-1"] == "Bernd")
    }

    @Test("Ohne Profil: gleich klingende unbenannte Stimmen aus verschiedenen Teilen werden eine")
    func mergesUnnamedAmongEachOther() {
        let voices = [voice("1-3", 120, [0, 0, 1]), voice("2-4", 40, [0.02, 0, 1]), voice("3-9", 50, [1, 0, 0])]
        let plan = SpeakerRematcher.plan(voices: voices, profiles: [])
        #expect(plan.merges == ["2-4": "1-3"])
        #expect(plan.names.isEmpty)
    }

    @Test("Kurze oder unklare Stimmen bleiben offen")
    func leavesUnclearOpen() {
        let voices = [voice("1-1", 100, [1, 0, 0], "Anna"), voice("2-2", 5, [1, 0, 0]),
                      voice("2-3", 60, [0.4, 0.9, 0])]
        let plan = SpeakerRematcher.plan(voices: voices, profiles: [])
        #expect(plan.isEmpty)
    }

    @Test("Anwenden hängt Beiträge um und setzt Namen")
    func appliesPlan() {
        let doc = MeetingDocument(startedAt: Date(), duration: 10, sourceNames: ["Teams"],
                                  lines: [TranscriptLine(speaker: .others, start: 0, end: 1, text: "A", speakerID: "1"),
                                          TranscriptLine(speaker: .others, start: 2, end: 3, text: "B", speakerID: "2"),
                                          TranscriptLine(speaker: .others, start: 4, end: 5, text: "C", speakerID: "3")],
                                  summary: nil, notes: [], speakerNames: ["1": "Anna"], nameSources: ["1": .confirmed])
        let updated = doc.applying(.init(names: ["3": "Bernd"], merges: ["2": "1"]))
        #expect(updated.lines.map { updated.label(for: $0) } == ["Anna", "Anna", "Bernd"])
        #expect(updated.nameSources["3"] == .profile)
        #expect(updated.unconfirmedSpeakerIDs.isEmpty)
    }
}
