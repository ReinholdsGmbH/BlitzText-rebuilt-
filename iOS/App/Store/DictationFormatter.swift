import Foundation

/// Feste Regeln nach dem Transkribieren: gesprochene Satzzeichen, Emojis, Aufzählungen.
/// Die KI-Formatierung (DictationAI) setzt darauf auf; scheitert sie, bleibt dieses Ergebnis.
enum DictationFormatter {

    static func apply(_ text: String) -> String {
        var result = spokenPunctuation(text)
        result = EmojiReplacer.apply(result)
        result = ordinalList(result)
        return fixListStart(tidy(result))
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

    /// Wörter, die eine Aufzählung beginnen. „erstens“ und „als Erstes“ reichen mit einem
    /// Folgewort; „zuerst“ und „zunächst“ kommen auch in normalen Sätzen vor und brauchen zwei.
    static let strongStarts = ["erstens", "als erstes", "zum einen"]
    static let weakStarts = ["zuerst", "zunächst"]
    static let followers = Array(ordinals.dropFirst()) + [
        "als nächstes", "als letztes", "zum anderen", "zum schluss", "danach", "außerdem",
        "zudem", "weiterhin", "zuletzt", "schließlich", "dann",
    ]
    /// Am Rand eines Listenpunkts entbehrlich.
    static let edgeFillers: Set<String> = [
        "und", "oder", "ich", "wir", "möchte", "möchten", "will", "wollen", "muss", "müssen", "würde",
        "würden", "sollte", "sollten", "gern", "gerne", "noch", "außerdem", "dann", "danach", "auch",
        "zudem", "bitte", "mal", "also",
    ]

    /// Aufzählung im Fließtext → Einleitung mit Doppelpunkt plus nummerierte Liste.
    /// „Erstens möchte ich A klären, dann außerdem B und als Letztes noch C.“ → 1. A klären, 2. B, 3. C
    static func ordinalList(_ text: String) -> String {
        let alternatives = (strongStarts + weakStarts + followers)
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: #"\b("# + alternatives + #")\b"#, options: [.caseInsensitive]) else {
            return text
        }
        let ns = text as NSString
        let all = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        // Erst ab dem ersten Startwort zählt die Aufzählung.
        guard let startIndex = all.firstIndex(where: { match in
            let word = ns.substring(with: match.range).lowercased()
            return strongStarts.contains(word) || weakStarts.contains(word)
        }) else { return text }
        let startWord = ns.substring(with: all[startIndex].range).lowercased()
        let markers = Array(all[startIndex...])
        let neededFollowers = weakStarts.contains(startWord) ? 2 : 1
        guard markers.count - 1 >= neededFollowers else { return text }

        // Ende der Aufzählung: Satzende nach dem letzten Marker.
        let lastMarkerEnd = markers.last!.range.location + markers.last!.range.length
        let tail = ns.substring(from: lastMarkerEnd)
        let sentenceEndOffset = tail.firstIndex(where: { ".!?\n".contains($0) }).map { tail.distance(from: tail.startIndex, to: $0) + 1 }
        let listEnd = sentenceEndOffset.map { lastMarkerEnd + ($0 as Int) } ?? ns.length

        var items: [String] = []
        for (index, marker) in markers.enumerated() {
            let start = marker.range.location + marker.range.length
            let end = index + 1 < markers.count ? markers[index + 1].range.location : listEnd
            guard end > start else { continue }
            let item = cleanItem(ns.substring(with: NSRange(location: start, length: end - start)))
            if !item.isEmpty { items.append(item) }
        }
        guard items.count >= 2 else { return text }

        var intro = ns.substring(to: markers[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = intro.last, ",;.".contains(last) { intro.removeLast() }
        intro = intro.trimmingCharacters(in: .whitespaces)
        if !intro.isEmpty { intro += ":" }
        let outro = ns.substring(from: min(listEnd, ns.length)).trimmingCharacters(in: .whitespacesAndNewlines)

        let list = items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return [intro, list, outro].filter { !$0.isEmpty }.joined(separator: "\n")
            .replacingOccurrences(of: list + "\n" + outro, with: outro.isEmpty ? list : list + "\n\n" + outro)
    }

    /// Satzzeichen und Füllwörter am Rand weg, erster Buchstabe groß.
    private static func cleanItem(_ raw: String) -> String {
        var words = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        func bare(_ word: String) -> String { word.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        while let first = words.first, edgeFillers.contains(bare(first)) || bare(first).isEmpty { words.removeFirst() }
        while let last = words.last, edgeFillers.contains(bare(last)) || bare(last).isEmpty { words.removeLast() }
        var item = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;.:"))
        if let first = item.first { item = first.uppercased() + item.dropFirst() }
        return item
    }

    // MARK: - Aufräumen

    /// Hängt „1. …“ noch am Satz davor („… sprechen. 1. Test“), obwohl ab „2.“ eine Liste folgt,
    /// bekommt der erste Punkt eine eigene Zeile und der Satz davor einen Doppelpunkt.
    static func fixListStart(_ text: String) -> String {
        guard text.contains("\n2. ") || text.contains("\n2.\t") else { return text }
        var lines = text.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.range(of: #"\S\s+1\.\s"#, options: .regularExpression) != nil }),
              index + 1 < lines.count, lines[index + 1].hasPrefix("2.") else { return text }
        let line = lines[index]
        guard let match = line.range(of: #"\s+1\.\s"#, options: .regularExpression) else { return text }
        var intro = String(line[..<match.lowerBound]).trimmingCharacters(in: .whitespaces)
        while let last = intro.last, ".,;".contains(last) { intro.removeLast() }
        if let last = intro.last, !":!?".contains(last) { intro += ":" }
        let first = "1. " + line[match.upperBound...].trimmingCharacters(in: .whitespaces)
        lines.replaceSubrange(index...index, with: [intro, first])
        return lines.joined(separator: "\n")
    }

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

    /// Wörter, die in einer Liste wegfallen dürfen: Aufzählungs- und Füllwörter.
    static let listFillers: Set<String> = Set(ordinals + [
        "als", "erstes", "nächstes", "letztes", "zuerst", "zunächst", "dann", "danach", "außerdem",
        "zudem", "weiterhin", "zuletzt", "schließlich", "noch", "und", "sowie", "auch", "ich", "möchte",
        "will", "würde", "muss", "müssen", "wir", "gern", "gerne", "mal", "bitte",
    ])

    /// Hat die KI-Fassung den Wortbestand behalten? Erlaubt: Satzzeichen, Großschreibung,
    /// Listenzeichen, wegfallende Aufzählungs- und Füllwörter. Inhaltswörter und Zahlen müssen
    /// bleiben, neue Wörter darf es kaum geben.
    static func preservesWords(original: String, formatted: String) -> Bool {
        let withoutMarkers = replace(#"(?m)^\s*(\d+\.|-|•)\s+"#, in: formatted, with: "")
        func words(_ text: String) -> [String] {
            text.lowercased()
                .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
                .map(String.init)
        }
        let originalWords = words(original)
        var remaining = Dictionary(originalWords.map { ($0, 1) }, uniquingKeysWith: +)
        var added = 0
        for word in words(withoutMarkers) {
            if let count = remaining[word], count > 0 { remaining[word] = count - 1 } else { added += 1 }
        }
        let missing = remaining.filter { $0.value > 0 && !listFillers.contains($0.key) }
        // Zahlen sind nie entbehrlich („Sache 1“).
        if missing.keys.contains(where: { $0.allSatisfy(\.isNumber) }) { return false }
        let missingContent = missing.values.reduce(0, +)
        let total = max(originalWords.count, 1)
        return missingContent <= max(0, total / 25) && added <= max(1, total / 15)
    }

    /// Fängt die KI-Fassung direkt mit „1.“ an, obwohl im Diktat ein Satz vor der Aufzählung
    /// stand, wird dieser Satz mit Doppelpunkt davorgesetzt.
    static func restoreIntro(original: String, formatted: String) -> String {
        let firstLine = formatted.split(separator: "\n").first.map(String.init) ?? ""
        guard firstLine.range(of: #"^\s*(1\.|-)\s"#, options: .regularExpression) != nil else { return formatted }
        let markers = ordinals + ["als erstes", "zuerst", "zunächst"]
        let lower = original.lowercased()
        guard let marker = markers.compactMap({ lower.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return formatted
        }
        let before = original[..<marker.lowerBound]
        guard let sentenceEnd = before.lastIndex(where: { ".!?".contains($0) }) else { return formatted }
        var intro = String(original[...sentenceEnd]).trimmingCharacters(in: .whitespaces)
        guard !intro.isEmpty else { return formatted }
        intro = String(intro.dropLast()) + ":"
        return intro + "\n" + formatted
    }
}
