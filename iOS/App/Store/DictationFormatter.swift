import Foundation

/// Feste Regeln nach dem Transkribieren: gesprochene Satzzeichen, Emojis, Aufzählungen.
/// Die KI-Formatierung (DictationAI) setzt darauf auf; scheitert sie, bleibt dieses Ergebnis.
enum DictationFormatter {

    static func apply(_ text: String) -> String {
        var result = spokenPunctuation(text)
        result = EmojiReplacer.apply(result)
        result = ordinalList(result)
        return tidy(result)
    }

    // MARK: - Gesprochene Satzzeichen

    /// „Ausrufezeichen“ → !, „Fragezeichen“ → ?, „Doppelpunkt“ → :, „neue Zeile“ → Umbruch.
    /// Satzzeichen, die die Spracherkennung selbst um das Wort gesetzt hat, fallen weg.
    /// „Komma“ und „Punkt“ nur, wo sie eindeutig Satzzeichen sind: „Komma“ nicht zwischen Ziffern,
    /// „Punkt“ nur am Ende des Textes oder vor einem Umbruch.
    static func spokenPunctuation(_ text: String) -> String {
        var result = text
        let clutter = #"[\s,.;:!?]*"#
        let rules: [(pattern: String, replacement: String)] = [
            (clutter + #"\bneuer absatz\b"# + clutter, "\n\n"),
            (clutter + #"\bneue zeile\b"# + clutter, "\n"),
            (clutter + #"\bausrufezeichen\b"# + clutter, "! "),
            (clutter + #"\bfragezeichen\b"# + clutter, "? "),
            (clutter + #"\bdoppelpunkt\b"# + clutter, ": "),
            (clutter + #"\bsemikolon\b"# + clutter, "; "),
            (#"(?<!\d)\s*\bkomma\b[\s,]*(?!\s*\d)"#, ", "),
            (#"\s*\bpunkt\b[\s.,!?]*(?=\n|$)"#, ". "),
        ]
        for rule in rules {
            result = replace(rule.pattern, in: result, with: rule.replacement)
        }
        return result
    }

    // MARK: - Aufzählungen

    static let ordinals = ["erstens", "zweitens", "drittens", "viertens", "fünftens",
                           "sechstens", "siebtens", "achtens", "neuntens", "zehntens"]

    /// „… erstens A, zweitens B und drittens C“ → Einleitung plus nummerierte Liste.
    static func ordinalList(_ text: String) -> String {
        let pattern = #"[\s,;]*\b("# + ordinals.joined(separator: "|") + #")\b[\s,:]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return text }

        var intro = ns.substring(to: matches[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [String] = []
        for (index, match) in matches.enumerated() {
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            var item = ns.substring(with: NSRange(location: start, length: max(0, end - start)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            for suffix in [" und", " oder", ",", ";"] where item.lowercased().hasSuffix(suffix) {
                item = String(item.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
            if !item.isEmpty { items.append(capitalizeFirst(item)) }
        }
        guard items.count >= 2 else { return text }
        if !intro.isEmpty, let last = intro.last, !":.!?".contains(last) { intro += ":" }
        let list = items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return intro.isEmpty ? list : intro + "\n" + list
    }

    // MARK: - Aufräumen

    /// Leerzeichen um Umbrüche, doppelte Leerzeichen, Großschreibung nach Satzende.
    static func tidy(_ text: String) -> String {
        var result = replace(#"[ \t]+\n"#, in: text, with: "\n")
        result = replace(#"\n[ \t]+"#, in: result, with: "\n")
        result = replace(#" {2,}"#, in: result, with: " ")
        result = replace(#"\s+([,.;:!?])"#, in: result, with: "$1")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        // Großschreibung nach . ! ? und am Zeilenanfang
        var output = ""
        var capitalizeNext = true
        for character in result {
            if capitalizeNext, character.isLetter {
                output += character.uppercased()
                capitalizeNext = false
            } else {
                output.append(character)
                if ".!?\n".contains(character) { capitalizeNext = true }
                else if !character.isWhitespace && !character.isNumber { capitalizeNext = false }
            }
        }
        return output
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                              withTemplate: template)
    }

    // MARK: - Prüfung der KI-Fassung

    /// Hat die KI-Fassung den Wortbestand behalten? Erlaubt sind Satzzeichen, Großschreibung,
    /// Listenzeichen und das Wegfallen von „erstens/zweitens …“; Wörter dürfen kaum fehlen oder dazukommen.
    static func preservesWords(original: String, formatted: String) -> Bool {
        func words(_ text: String) -> [String] {
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { !ordinals.contains($0) }
        }
        var remaining = Dictionary(words(original).map { ($0, 1) }, uniquingKeysWith: +)
        var added = 0
        for word in words(formatted) {
            if let count = remaining[word], count > 0 { remaining[word] = count - 1 } else { added += 1 }
        }
        let missing = remaining.values.reduce(0, +)
        let total = max(words(original).count, 1)
        return missing <= max(1, total / 20) && added <= max(2, total / 12)
    }
}
