import Foundation
import Testing
@testable import BlitzText

/// Merkt sich, was ans Modell ging.
final class CapturingSummarizer: MeetingSummarizing, @unchecked Sendable {
    private(set) var lastUser = ""
    var answer = "Antwort"
    func summarize(transcript: String) async throws -> String { "" }
    func title(for transcript: String) async throws -> String { "" }
    func ask(system: String, user: String) async throws -> String { lastUser = user; return answer }
}

@MainActor
struct LiveQuestionsTests {

    private let lines = [
        LiveLine(speaker: .others, name: "Anna Beispiel", start: 65, text: "Der Termin verschiebt sich auf Freitag."),
        LiveLine(speaker: .me, start: 80, text: "Wer gibt das frei?")
    ]

    @Test("Kontext enthält Zeit, Sprecher und eigene Notizen")
    func context() {
        let text = MeetingChat.liveContext(lines: lines, notes: "  Freigabe klären  ")
        #expect(text.contains("[00:01:05] Anna Beispiel: Der Termin verschiebt sich auf Freitag."))
        #expect(text.contains("[00:01:20] Ich: Wer gibt das frei?"))
        #expect(text.hasSuffix("Notizen von „Ich“:\nFreigabe klären"))
    }

    @Test("Zu langes Transkript behält das Neueste")
    func keepsNewest() {
        let text = MeetingChat.liveContext(lines: lines, notes: "", limit: 30)
        #expect(text.contains("Wer gibt das frei?"))
        #expect(!text.contains("Anna Beispiel"))
    }

    @Test("Fragen landen im gespeicherten Verlauf und hängen sich ans fertige Meeting")
    func askSaveAndLink() async throws {
        let fake = CapturingSummarizer()
        let store = FileManager.default.temporaryDirectory.appendingPathComponent("live-chat-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: store) }
        let chat = MeetingChat(makeSummarizer: { fake }, storeURL: store)
        let started = Date(timeIntervalSince1970: 1000)

        await chat.askLive("Was ist mit dem Termin?", startedAt: started, lines: lines, notes: "")
        #expect(fake.lastUser.contains("verschiebt sich auf Freitag"))
        await chat.askLive("Und weiter?", startedAt: started, lines: lines, notes: "")
        #expect(fake.lastUser.contains("Bisheriger Verlauf:\nFrage: Was ist mit dem Termin?\nAntwort: Antwort"))
        #expect(chat.threads.count == 1)
        #expect(chat.liveThread(for: started)?.messages.map(\.role) == [.user, .assistant, .user, .assistant])
        #expect(chat.liveThread(for: Date(timeIntervalSince1970: 5000)) == nil)

        // Meeting ist fertig: Beginn passt (Sekundenbruchteile Abweichung), Chat zeigt darauf.
        let folder = URL(fileURLWithPath: "/tmp/meeting-a")
        let document = MeetingDocument(startedAt: started.addingTimeInterval(0.4), duration: 600, sourceNames: ["Teams"],
                                       lines: [], summary: nil, notes: [])
        chat.linkLiveThreads(entries: [MeetingLibrary.Entry(folder: folder, document: document)])
        #expect(chat.threads.first?.meetingFolder == folder)
        #expect(chat.threads.first?.scope == .meeting(folder))

        let reloaded = MeetingChat(makeSummarizer: { fake }, storeURL: store)
        #expect(reloaded.threads.first?.liveStartedAt == started)
        #expect(reloaded.threads.first?.meetingFolder == folder)
    }
}
