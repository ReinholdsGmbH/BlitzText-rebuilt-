import Foundation
import Testing
@testable import BlitzText

struct CallTitleTests {

    @Test("Erstes Feld des Call-Fensters ist der Besprechungsname", arguments: [
        ("TEST BlitzText | Firma AG | konto@firma.de", "TEST BlitzText"),
        ("Teams Sync Weekly | Firma AG | konto@firma.de", "Teams Sync Weekly"),
        ("Daily", "Daily")
    ])
    func readsName(title: String, expected: String) {
        #expect(TeamsCallControls.meetingName(fromWindowTitle: title) == expected)
    }

    @Test("Ansichten und Ad-hoc-Anrufe liefern keinen Namen", arguments: [
        "Chat | Firma AG | konto@firma.de",
        "Calendar | Firma AG | konto@firma.de",
        "Besprechung mit Anna Muster | Firma AG | konto@firma.de",
        "Meeting with Anna | Firma | x",
        " | Firma",
        ""
    ])
    func rejectsGeneric(title: String) {
        #expect(TeamsCallControls.meetingName(fromWindowTitle: title) == nil)
    }

    @Test("Besprechungsname ist Titel, solange kein eigener oder KI-Titel gesetzt ist")
    func titleFallsBackToCallTitle() {
        var doc = MeetingDocument(startedAt: Date(), duration: 60, sourceNames: ["Microsoft Teams"],
                                  lines: [], summary: nil, notes: [])
        doc.callTitle = "Team Daily"
        #expect(MeetingMarkdown.baseTitle(for: doc) == "Team Daily")
        #expect(doc.summaryInput.hasPrefix("Name der Besprechung laut Teams: Team Daily"))
        doc.aiTitle = "Eigener Titel"
        #expect(MeetingMarkdown.baseTitle(for: doc) == "Eigener Titel")
    }

    @Test("„Notizen neu erstellen“ überschreibt den Besprechungsnamen nicht")
    @MainActor
    func summaryKeepsCallTitle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-calltitle-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = MeetingArchive(root: root)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Teams")
        var doc = MeetingDocument(startedAt: Date(), duration: 30, sourceNames: ["Microsoft Teams"],
                                  lines: [TranscriptLine(speaker: .others, start: 1, end: 3, text: "Hallo", speakerID: "1")],
                                  summary: nil, notes: [])
        doc.callTitle = "Team Daily"
        try archive.writeProtocol(doc, in: folder)
        let library = MeetingLibrary(archive: archive, diarizer: nil,
                                     makeSummarizer: { FakeSummarizer(result: .success("TITEL: KI-Titel\n### Zusammenfassung\n- A")) })
        library.reload()
        await library.regenerateSummary(in: folder)
        let saved = try #require(archive.load(folder: folder))
        #expect(MeetingMarkdown.baseTitle(for: saved) == "Team Daily")
    }
}
