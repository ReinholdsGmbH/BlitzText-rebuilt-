import Foundation

/// Ein eingefügtes Diktat im Verlauf.
struct DictationEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let text: String
    let seconds: Double

    var words: Int { WordCounter.count(text) }
}

enum WordCounter {
    /// Zählt Wörter: durch Leerraum getrennte Stücke, die mindestens einen Buchstaben oder eine Ziffer enthalten.
    static func count(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
    }
}

/// Verlauf der Diktate plus Lebenszeit-Wortzähler. Löschen aus dem Verlauf senkt den Zähler nicht.
@MainActor
final class DictationHistory: ObservableObject {
    private struct Snapshot: Codable {
        var entries: [DictationEntry]
        var dictatedWords: Int
        var meetingWords: Int
    }

    @Published private(set) var entries: [DictationEntry] = []
    @Published private(set) var dictatedWords = 0
    @Published private(set) var meetingWords = 0

    var totalWords: Int { dictatedWords + meetingWords }

    private let fileURL: URL

    init() {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Spike.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("history.json")
        load()
    }

    func add(text: String, seconds: Double) {
        let entry = DictationEntry(id: UUID(), date: Date(), text: text, seconds: seconds)
        entries.insert(entry, at: 0)
        dictatedWords += entry.words
        save()
    }

    func addMeetingWords(_ count: Int) {
        meetingWords += count
        save()
    }

    func delete(_ entry: DictationEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func deleteAll() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        entries = snapshot.entries
        dictatedWords = snapshot.dictatedWords
        meetingWords = snapshot.meetingWords
    }

    private func save() {
        let snapshot = Snapshot(entries: entries, dictatedWords: dictatedWords, meetingWords: meetingWords)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
