import Foundation

/// Gemeinsames Wörterbuch mit der iPhone-App: `woerterbuch.json` in der iPhone-Ablage
/// (OneDrive „Anwendungen/BlitzText iPhone“). Gleiches Format wie auf dem iPhone.
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

    /// Vereinigung: Groß-/Kleinschreibung egal, Aliase zusammengeführt, alphabetisch sortiert.
    static func merge(_ lists: [Entry]...) -> [Entry] {
        var byKey: [String: Entry] = [:]
        for entry in lists.flatMap({ $0 }) {
            let key = entry.text.lowercased()
            guard var existing = byKey[key] else { byKey[key] = entry; continue }
            for alias in entry.aliases where !existing.aliases.contains(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) {
                existing.aliases.append(alias)
            }
            byKey[key] = existing
        }
        return byKey.values.sorted { $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending }
    }
}

/// Gleicht die Eigennamen der Mac-App mit dem iPhone ab. Vereinigung: Neue Wörter kommen auf
/// beiden Seiten an, Aliase werden ergänzt; Löschen gleicht sich bewusst nicht ab.
@MainActor
final class PhoneDictionarySync {
    private let rootPath: () -> String
    private let nouns: () -> [ProperNoun]
    private let setNouns: ([ProperNoun]) -> Void
    private var timer: Timer?

    init(rootPath: @escaping () -> String, nouns: @escaping () -> [ProperNoun], setNouns: @escaping ([ProperNoun]) -> Void) {
        self.rootPath = rootPath
        self.nouns = nouns
        self.setNouns = setNouns
    }

    func start() {
        sync()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.sync() }
        }
    }

    /// Datei liegt im Unterordner „BlitzText iPhone“, falls es ihn gibt, sonst direkt in der Ablage
    /// (OneDrive-App-Ordner).
    static func fileURL(inAblage root: URL) -> URL {
        let nested = root.appendingPathComponent(PhoneMeetingPackage.folderName, isDirectory: true)
        var isDirectory: ObjCBool = false
        let base = FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDirectory) && isDirectory.boolValue ? nested : root
        return base.appendingPathComponent(SharedDictionary.fileName)
    }

    /// Liefert die Zahl der neu übernommenen Wörter.
    @discardableResult
    func sync() -> Int {
        let path = (rootPath() as NSString).expandingTildeInPath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return 0 }
        let url = Self.fileURL(inAblage: URL(fileURLWithPath: path, isDirectory: true))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remote = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(SharedDictionary.self, from: $0) }

        let current = nouns()
        let local = current.map { SharedDictionary.Entry(text: $0.text, aliases: $0.aliases) }
        let merged = SharedDictionary.merge(remote?.entries ?? [], local)

        let (updated, added) = Self.apply(merged, to: current)
        if updated != current { setNouns(updated) }

        if merged != remote?.entries {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                try encoder.encode(SharedDictionary(updatedAt: Date(), entries: merged)).write(to: url, options: .atomic)
            } catch {
                Log.write("Wörterbuch-Abgleich: nicht geschrieben — \(error.localizedDescription)")
            }
        }
        if added > 0 { Log.write("Wörterbuch-Abgleich: \(added) neue Eigennamen vom iPhone") }
        return added
    }

    /// Übernimmt neue Wörter und fehlende Aliase in die Eigennamen-Liste.
    static func apply(_ entries: [SharedDictionary.Entry], to nouns: [ProperNoun]) -> (nouns: [ProperNoun], added: Int) {
        var result = nouns
        var added = 0
        for entry in entries {
            if let index = result.firstIndex(where: { $0.text.caseInsensitiveCompare(entry.text) == .orderedSame }) {
                for alias in entry.aliases where !result[index].aliases.contains(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) {
                    result[index].aliases.append(alias)
                }
            } else {
                result.append(ProperNoun(text: entry.text, aliases: entry.aliases))
                added += 1
            }
        }
        return (result, added)
    }
}
