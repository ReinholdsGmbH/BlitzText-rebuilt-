import Foundation

/// Gemeinsames Wörterbuch mit der Mac-App: `woerterbuch.json` im OneDrive-App-Ordner.
/// Abgleich als Vereinigung: Neue Wörter kommen auf beiden Seiten an, Löschen gleicht sich
/// nicht ab. Fehlhörungen (Aliase) vom Mac bleiben in der Datei erhalten.
struct SharedDictionary: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var text: String
        var aliases: [String]
    }

    var format = "blitztext-dictionary"
    var version = 1
    var updatedAt: Date
    var entries: [Entry]

    static let fileName = "woerterbuch.json"

    /// Vereinigt Datei-Einträge mit lokalen Wörtern (Groß-/Kleinschreibung egal, Aliase vereinigt).
    static func merge(_ entries: [Entry], words: [String]) -> [Entry] {
        var byKey: [String: Entry] = [:]
        var order: [String] = []
        for entry in entries + words.map({ Entry(text: $0, aliases: []) }) {
            let key = entry.text.lowercased()
            if var existing = byKey[key] {
                for alias in entry.aliases where !existing.aliases.contains(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) {
                    existing.aliases.append(alias)
                }
                byKey[key] = existing
            } else {
                byKey[key] = entry
                order.append(key)
            }
        }
        return order.compactMap { byKey[$0] }
            .sorted { $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending }
    }
}

@MainActor
final class DictionarySync: ObservableObject {
    @Published private(set) var status = ""
    private let oneDrive: OneDriveSync
    private var running = false

    init(oneDrive: OneDriveSync) {
        self.oneDrive = oneDrive
    }

    func sync() async {
        guard oneDrive.isConnected, !running else { return }
        running = true
        defer { running = false }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remote = try await oneDrive.download(SharedDictionary.fileName)
                .flatMap { try? decoder.decode(SharedDictionary.self, from: $0) }
            let local = Spike.userWords
            let merged = SharedDictionary.merge(remote?.entries ?? [], words: local)

            let mergedWords = merged.map(\.text)
            let added = mergedWords.filter { word in !local.contains { $0.caseInsensitiveCompare(word) == .orderedSame } }
            if !added.isEmpty { Spike.userWords = local + added }

            if merged != remote?.entries {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let file = SharedDictionary(updatedAt: Date(), entries: merged)
                try await oneDrive.upload(encoder.encode(file), to: SharedDictionary.fileName)
            }
            status = "\(merged.count) Wörter abgeglichen\(added.isEmpty ? "" : ", \(added.count) neu vom Mac")"
        } catch {
            status = "Abgleich fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
