import Foundation

/// Zählt, welche Wörter du tippst, wischst, auswählst oder diktierst. Häufig benutzte Wörter
/// rücken bei Swipe und Vorschlägen nach vorn. Bleibt auf dem Gerät (App Group).
final class WordUsage {
    private(set) var counts: [String: Int] = [:]
    private var unsaved = 0

    static var url: URL? { Blitz.containerURL?.appendingPathComponent("word-usage.json") }

    func load() {
        guard let url = Self.url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else { return }
        counts = decoded
    }

    func save() {
        guard unsaved > 0, let url = Self.url, let data = try? JSONEncoder().encode(counts) else { return }
        try? data.write(to: url, options: .atomic)
        unsaved = 0
    }

    func record(_ word: String, delta: Int = 1) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard trimmed.count >= 2, trimmed.allSatisfy({ $0.isLetter }) else { return }
        let key = trimmed.lowercased()
        counts[key] = max(0, (counts[key] ?? 0) + delta)
        unsaved += 1
        if unsaved >= 20 { save() }
    }

    func recordText(_ text: String) {
        text.split(whereSeparator: { $0.isWhitespace }).forEach { record(String($0)) }
    }

    func count(_ word: String) -> Int { counts[word.lowercased()] ?? 0 }
}
