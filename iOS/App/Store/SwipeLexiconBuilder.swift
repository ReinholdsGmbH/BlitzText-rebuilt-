import UIKit

/// Baut das Swipe-Wörterbuch aus Apples Rechtschreibprüfung: Vervollständigungen zu allen
/// Anfängen bis drei Buchstaben. Apple liefert je Anfang höchstens 20 Wörter, nach
/// Wahrscheinlichkeit sortiert; Rang und Länge des Anfangs ergeben eine grobe Häufigkeit.
/// Ergebnis (rund 65.000 Wörter) liegt in der App Group, die Tastatur liest es.
@MainActor
final class SwipeLexiconBuilder: ObservableObject {
    @Published private(set) var status = ""
    @Published private(set) var running = false

    static let version = 1
    private static let versionKey = "swipeLexiconVersion"
    private static let maxDepth = 3
    private static let letters = Array("abcdefghijklmnopqrstuvwxyzäöüß")

    init() {
        if let count = Self.existingWordCount() { status = "\(count.grouped) Wörter" }
    }

    static func existingWordCount() -> Int? {
        guard UserDefaults.standard.integer(forKey: versionKey) == version,
              let url = Blitz.swipeLexiconURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
    }

    func buildIfNeeded() {
        guard Self.existingWordCount() == nil else { return }
        Task { await build() }
    }

    func build() async {
        guard !running, let url = Blitz.swipeLexiconURL else { return }
        running = true
        defer { running = false }
        let checker = UITextChecker()
        let language = UITextChecker.availableLanguages.first { $0.hasPrefix("de") } ?? "de_DE"
        var scores: [String: Double] = [:]
        var frontier = Self.letters.map { String($0) }
        var done = 0
        let started = Date()

        while !frontier.isEmpty {
            let prefix = frontier.removeFirst()
            let capital = prefix.prefix(1).uppercased() + prefix.dropFirst()
            var results: [String] = []
            for variant in [prefix, capital] {
                let range = NSRange(location: 0, length: (variant as NSString).length)
                results += checker.completions(forPartialWordRange: range, in: variant, language: language) ?? []
            }
            // Kurze Anfänge zählen mehr: ein Wort unter den ersten 20 bei „d“ ist sehr häufig.
            let weight = 1.0 / Double(prefix.count * prefix.count)
            for (index, word) in results.enumerated() where word.count > 1 && word.allSatisfy(\.isLetter) {
                scores[word, default: 0] += weight * Double(20 - index % 20) / 20
            }
            if results.count >= 20, prefix.count < Self.maxDepth {
                frontier += Self.letters.map { prefix + String($0) }
            }
            done += 1
            if done % 200 == 0 {
                status = "Wird aufgebaut … \(scores.count.grouped) Wörter"
                await Task.yield()
            }
        }

        let lines = scores.sorted { $0.value > $1.value }
            .map { "\($0.key)\t\(String(format: "%.5f", $0.value))" }
            .joined(separator: "\n")
        do {
            try (lines + "\n").write(to: url, atomically: true, encoding: .utf8)
            UserDefaults.standard.set(Self.version, forKey: Self.versionKey)
            status = "\(scores.count.grouped) Wörter (\(Int(Date().timeIntervalSince(started))) s)"
        } catch {
            status = "Fehler: \(error.localizedDescription)"
        }
    }
}
