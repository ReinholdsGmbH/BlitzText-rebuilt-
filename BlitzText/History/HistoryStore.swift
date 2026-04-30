import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let mode: Mode
    let rawTranscript: String
    /// Bei Blitztext = nil (raw == final). Bei Plus/Rant = polierte Version.
    let polished: String?

    init(id: UUID = UUID(), date: Date = Date(), mode: Mode, rawTranscript: String, polished: String?) {
        self.id = id
        self.date = date
        self.mode = mode
        self.rawTranscript = rawTranscript
        self.polished = polished
    }

    /// Was im Clipboard landete (= polished falls vorhanden, sonst raw)
    var finalText: String { polished ?? rawTranscript }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let maxEntries = 100
    private let url: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BlitzText", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        self.url = support.appendingPathComponent("history.json")
        load()
    }

    func append(mode: Mode, rawTranscript: String, polished: String?) {
        let entry = HistoryEntry(mode: mode, rawTranscript: rawTranscript, polished: polished)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([HistoryEntry].self, from: data) {
            self.entries = loaded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
