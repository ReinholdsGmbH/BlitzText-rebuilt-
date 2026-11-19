import Foundation
import Testing
@testable import BlitzText

@MainActor
struct PhoneInboxTests {

    private func packageJSON(id: String, sharedAt: String, summary: String = "### Zusammenfassung\n- Termin morgen um 10 Uhr") -> Data {
        Data("""
        {
          "format": "blitztext-iphone-meeting", "version": 1,
          "id": "\(id)", "title": "Termin Abstimmung",
          "start": "2026-11-18T08:30:00Z", "end": "2026-11-18T08:40:00Z",
          "sharedAt": "\(sharedAt)",
          "transcript": "Sprecher 1: Morgen um zehn.\\n\\nSprecher 2: Passt.",
          "segments": [
            {"speaker": "1", "start": 0, "end": 3, "text": "Morgen um zehn."},
            {"speaker": "2", "start": 3.5, "end": 4.2, "text": "Passt."}
          ],
          "summary": "\(summary.replacingOccurrences(of: "\n", with: "\\n"))",
          "ownNotes": "Raum klären",
          "audioFile": null
        }
        """.utf8)
    }

    private func write(_ data: Data, into inbox: URL, folder: String) throws {
        let dir = inbox.appendingPathComponent("BlitzText iPhone/\(folder)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("meeting.json"))
    }

    @Test("Paket wird zum Mac-Meeting: Abschnitte, Notizen, eigene Notizen, Titel, Quelle")
    func documentFromPackage() throws {
        let package = try PhoneInbox.decode(packageJSON(id: "A", sharedAt: "2026-11-18T09:00:00Z"))
        let document = PhoneInbox.document(from: package)
        #expect(document.lines.count == 2)
        #expect(document.lines.map(\.speakerID) == ["1", "2"])
        #expect(document.lines.allSatisfy { $0.speaker == .others })
        #expect(document.summary?.contains("Termin morgen") == true)
        #expect(document.userNotes == "Raum klären")
        #expect(document.aiTitle == "Termin Abstimmung")
        #expect(document.sourceNames == ["iPhone"])
        #expect(abs(document.duration - 600) < 0.5)
    }

    @Test("Abholen übernimmt einmal und aktualisiert bei neuerem Stand im selben Ordner")
    func pollImportsAndUpdates() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-inbox-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temp) }
        let inbox = temp.appendingPathComponent("Ablage"), archiveRoot = temp.appendingPathComponent("Archiv")
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        let archive = MeetingArchive(root: archiveRoot)
        var saved = 0
        let importer = PhoneInboxImporter(archive: archive, makeExporter: { nil }, rootPath: { inbox.path },
                                          stateURL: temp.appendingPathComponent("state.json")) { _ in saved += 1 }

        try write(packageJSON(id: "A", sharedAt: "2026-11-18T09:00:00Z"), into: inbox, folder: "2026-11-18 09-30 iPhone A")
        #expect(await importer.poll() == 1)
        #expect(await importer.poll() == 0)
        #expect(archive.loadAll().count == 1)

        try write(packageJSON(id: "A", sharedAt: "2026-11-18T10:00:00Z", summary: "### Zusammenfassung\n- Neu"),
                  into: inbox, folder: "2026-11-18 09-30 iPhone A")
        #expect(await importer.poll() == 1)
        let all = archive.loadAll()
        #expect(all.count == 1)
        #expect(all.first?.document.summary?.contains("Neu") == true)
        #expect(saved == 2)
    }
}
