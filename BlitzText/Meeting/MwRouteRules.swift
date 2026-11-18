import Foundation

/// Liest Bereiche und Stichwörter direkt aus dem mw-route-Skript (`~/.local/bin/mw-route`)
/// und einer optionalen `~/.config/mw-route/config.sh`. So bleibt eine Quelle der Wahrheit:
/// Wer in mw-route eine Regel ändert, ändert sie auch für BlitzText.
///
/// Gelesen werden nur einfache Zuweisungen der Form `[schluessel]="wert"` in den Blöcken
/// `PROJECT_VAULT_DIRS=( … )` und `PROJECT_KEYWORDS=( … )` sowie `INTERN_TITLES="…"`.
/// Ausgeführt wird nichts.
struct MwRouteRules {
    var areas: [(key: String, label: String, folder: String)]
    var keywords: [(key: String, pattern: String)]
    var internTitles: String

    static let builtIn = MwRouteRules(
        areas: VaultExporter.builtInAreas,
        keywords: VaultExporter.builtInKeywords,
        internTitles: VaultExporter.builtInInternTitles
    )

    /// Prüfreihenfolge wie in mw-route: Spezifisches zuerst, PAG zuletzt.
    static let order = ["kursbar", "auftragslauf", "rabaconsulting", "thraba", "tm", "wk", "pag"]

    static func load(
        script: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/mw-route"),
        config: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/mw-route/config.sh")
    ) -> MwRouteRules {
        let texts = [script, config].compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        guard !texts.isEmpty else { return builtIn }
        return parse(texts)
    }

    static func parse(_ texts: [String]) -> MwRouteRules {
        var folders: [String: String] = [:]
        var patterns: [String: String] = [:]
        var intern = builtIn.internTitles
        for text in texts {
            folders.merge(block("PROJECT_VAULT_DIRS", in: text)) { _, new in new }
            patterns.merge(block("PROJECT_KEYWORDS", in: text)) { _, new in new }
            if let value = scalar("INTERN_TITLES", in: text) { intern = value }
        }
        guard !folders.isEmpty, !patterns.isEmpty else { return builtIn }

        let labels = Dictionary(uniqueKeysWithValues: builtIn.areas.map { ($0.key, $0.label) })
        var areas = folders.keys.sorted().map { key in (key: key, label: labels[key] ?? key, folder: folders[key]!) }
        // Eingang immer zuletzt.
        areas.sort { ($0.key == "eingang" ? 1 : 0, $0.label) < ($1.key == "eingang" ? 1 : 0, $1.label) }
        let ordered = order.filter { patterns[$0] != nil } + patterns.keys.filter { !order.contains($0) }.sorted()
        let keywords = ordered.map { (key: $0, pattern: patterns[$0]!) }
        return MwRouteRules(areas: areas, keywords: keywords, internTitles: intern)
    }

    private static func block(_ name: String, in text: String) -> [String: String] {
        guard let start = text.range(of: "\(name)=(") ,
              let end = text.range(of: "\n)", range: start.upperBound..<text.endIndex) else { return [:] }
        var result: [String: String] = [:]
        for line in text[start.upperBound..<end.lowerBound].components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]"),
                  let eq = trimmed.range(of: "=\"", range: close..<trimmed.endIndex),
                  trimmed.hasSuffix("\"") else { continue }
            let key = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            let value = String(trimmed[eq.upperBound..<trimmed.index(before: trimmed.endIndex)])
            result[key] = value
        }
        return result
    }

    private static func scalar(_ name: String, in text: String) -> String? {
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(name)=\""), trimmed.hasSuffix("\"") else { continue }
            return String(trimmed.dropFirst(name.count + 2).dropLast())
        }
        return nil
    }
}
