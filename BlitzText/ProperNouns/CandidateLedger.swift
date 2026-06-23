import Foundation

/// Zählt, wie oft ein Kandidat real aufgetaucht ist, bevor er automatisch in die
/// Liste übernommen wird. Bricht die „einmalige Halluzination landet sofort in
/// der Liste"-Flut: Auto-Save erst ab `threshold` Vorkommen.
final class CandidateLedger {

    private static let defaultsKey = "de.reinholds.blitztext.candidateLedger"

    private let defaults: UserDefaults
    private let threshold: Int

    init(defaults: UserDefaults = .standard, threshold: Int = 2) {
        self.defaults = defaults
        self.threshold = threshold
    }

    /// Registriert ein Vorkommen. Gibt `true` zurück, sobald der Schwellenwert erreicht ist.
    @discardableResult
    func record(_ word: String) -> Bool {
        let key = word.lowercased()
        var counts = load()
        let next = (counts[key] ?? 0) + 1
        counts[key] = next
        save(counts)
        return next >= threshold
    }

    /// Entfernt den Zähler (nach Übernahme in die Liste).
    func reset(_ word: String) {
        var counts = load()
        counts[word.lowercased()] = nil
        save(counts)
    }

    // MARK: - Persistenz

    private func load() -> [String: Int] {
        if let dict = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int] {
            return dict
        }
        // Nur loggen, wenn tatsächlich ein Wert mit unerwartetem Typ vorliegt (nicht beim Erststart).
        if defaults.object(forKey: Self.defaultsKey) != nil {
            Log.write("CandidateLedger: unerwarteter Typ unter \(Self.defaultsKey) — Zähler zurückgesetzt")
        }
        return [:]
    }

    private func save(_ counts: [String: Int]) {
        defaults.set(counts, forKey: Self.defaultsKey)
    }
}
