import Foundation

/// Gesprochene Emojis im Diktat: „Herz Emoji“ → ❤️, „Zwinker-Emoji“ → 😉, „Daumen hoch Emoji“ → 👍.
/// Arbeitet auf Wörtern statt auf festen Mustern, weil die Spracherkennung die Grenze oft
/// verschiebt: „Herz Emoji“ kommt auch als „Herr Zemoji“ oder „Herzemoji“. Die Wörter vor
/// „…emoji“ werden zusammengesetzt und mit Toleranz gegen die Namensliste verglichen.
/// Über Satzgrenzen („erledigen?“) greift die Suche nicht hinaus.
enum EmojiReplacer {
    /// Namen ohne Leerzeichen und Bindestriche, klein geschrieben.
    static let emojis: [String: String] = {
        let list: [String: String] = [
            "herz": "❤️", "rotes herz": "❤️", "herzchen": "❤️", "gebrochenes herz": "💔",
            "zwinker": "😉", "zwinkernd": "😉", "zwinkerndes": "😉", "zwinkernder": "😉",
            "lach": "😄", "lachend": "😄", "lachendes": "😄", "lächel": "🙂", "lächelnd": "🙂", "lächelndes": "🙂",
            "grins": "😁", "grinsend": "😁", "grinsendes": "😁", "tränen lach": "😂",
            "traurig": "😢", "trauriges": "😢", "wein": "😭", "weinend": "😭", "weinendes": "😭",
            "wütend": "😠", "wütendes": "😠", "sauer": "😠", "kuss": "😘", "küsschen": "😘",
            "verliebt": "😍", "herzaugen": "😍", "cool": "😎", "sonnenbrillen": "😎", "sonnenbrille": "😎",
            "nachdenklich": "🤔", "nachdenk": "🤔", "denk": "🤔", "schock": "😱", "schockiert": "😱",
            "augenroll": "🙄", "augenrollen": "🙄", "zungen": "😛", "zunge": "😛", "müde": "😴", "schlaf": "😴",
            "daumen hoch": "👍", "daumen": "👍", "like": "👍", "daumen runter": "👎",
            "klatsch": "👏", "applaus": "👏", "gebets": "🙏", "danke": "🙏", "bitte": "🙏",
            "ok": "👌", "okay": "👌", "muskel": "💪", "stark": "💪", "wink": "👋", "winke": "👋",
            "feuer": "🔥", "party": "🎉", "konfetti": "🎉", "rakete": "🚀", "stern": "⭐️", "sterne": "✨",
            "haken": "✅", "häkchen": "✅", "kreuz": "❌", "achtung": "⚠️", "warn": "⚠️",
            "hundert": "💯", "glühbirne": "💡", "idee": "💡", "kaffee": "☕️", "bier": "🍺", "sonne": "☀️",
            "regenbogen": "🌈", "geschenk": "🎁", "kalender": "📅", "uhr": "⏰", "telefon": "📞",
            "auge": "👀", "augen": "👀", "affe": "🙈", "nichts sehen": "🙈", "smiley": "🙂",
        ]
        return Dictionary(uniqueKeysWithValues: list.map { (key($0.key), $0.value) })
    }()

    private static let triggers = ["emoticons", "emoticon", "emojis", "emoji", "smileys", "smiley"]
    private static let sentenceEnd = CharacterSet(charactersIn: ".!?;:")

    static func key(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter }
    }

    static func apply(_ text: String) -> String {
        var tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < tokens.count {
            guard let hit = trigger(in: tokens[index]) else { index += 1; continue }
            if let (emoji, start) = match(tokens: tokens, at: index, glued: hit.glued) {
                tokens.replaceSubrange(start...index, with: [emoji + hit.trailing])
                index = start + 1
            } else {
                index += 1
            }
        }
        return tokens.joined(separator: " ")
    }

    /// „Zemoji.“ → glued „z“, trailing „.“; „Emoji“ → glued „“.
    private static func trigger(in token: String) -> (glued: String, trailing: String)? {
        let trailing = String(token.reversed().prefix { !$0.isLetter }.reversed())
        let word = String(token.dropLast(trailing.count))
        let lower = word.lowercased()
        for trigger in triggers where lower.hasSuffix(trigger) {
            let glued = String(word.dropLast(trigger.count)).filter { $0.isLetter }
            return (glued, trailing)
        }
        return nil
    }

    /// Sucht den Namen aus bis zu drei Wörtern davor plus dem angeklebten Rest.
    private static func match(tokens: [String], at index: Int, glued: String) -> (String, Int)? {
        var exact: (emoji: String, start: Int)?
        var fuzzy: (emoji: String, start: Int, distance: Int)?
        for count in 0...3 {
            let start = index - count
            guard start >= 0 else { break }
            let previous = tokens[start..<index]
            // Satzgrenze: ein Wort mit Satzzeichen am Ende gehört nicht mehr zum Namen.
            if previous.contains(where: { $0.unicodeScalars.last.map(sentenceEnd.contains) ?? false }) { break }
            let name = key(previous.joined() + glued)
            guard name.count >= 2 else { continue }
            if let emoji = emojis[name] {
                exact = (emoji, start)
                continue
            }
            let tolerance = name.count >= 7 ? 2 : (name.count >= 4 ? 1 : 0)
            guard tolerance > 0 else { continue }
            for (candidate, emoji) in emojis where abs(candidate.count - name.count) <= tolerance {
                let distance = levenshtein(candidate, name)
                if distance <= tolerance, distance < (fuzzy?.distance ?? .max) {
                    fuzzy = (emoji, start, distance)
                }
            }
        }
        if let exact { return (exact.emoji, exact.start) }
        if let fuzzy { return (fuzzy.emoji, fuzzy.start) }
        if glued.isEmpty, tokens[index].lowercased().hasPrefix("smiley") { return nil }
        return nil
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }
}
