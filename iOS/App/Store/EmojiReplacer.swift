import Foundation

/// Gesprochene Emojis im Diktat: „Herz Emoji“ → ❤️, „Zwinker-Emoji“ → 😉, „Daumen hoch Emoji“ → 👍.
/// Erkannt wird „<Name> Emoji/Emoticon/Smiley“, auch zusammengeschrieben („Herzemoji“).
enum EmojiReplacer {
    /// Namen klein geschrieben, ohne Bindestriche. Mehrwortnamen vor Einwortnamen prüfen.
    static let emojis: [String: String] = [
        "herz": "❤️", "rotes herz": "❤️", "herzchen": "❤️", "gebrochenes herz": "💔",
        "zwinker": "😉", "zwinkernd": "😉", "zwinkerndes": "😉", "zwinkernder": "😉",
        "lach": "😄", "lachend": "😄", "lachendes": "😄", "lächel": "🙂", "lächelnd": "🙂", "lächelndes": "🙂",
        "grins": "😁", "grinsend": "😁", "grinsendes": "😁", "tränen lach": "😂", "tränenlach": "😂",
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

    private static let regex: NSRegularExpression = {
        // Bis zu drei Wörter vor „Emoji“, getrennt durch Leerzeichen oder Bindestrich, oder direkt angehängt.
        let pattern = #"((?:[\p{L}]+[\s-]){0,2}[\p{L}]*?)[\s-]?(emojis?|emoticons?|smileys?)\b"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    static func apply(_ text: String) -> String {
        let ns = text as NSString
        var result = text
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let name = ns.substring(with: match.range(at: 1))
            let suffix = ns.substring(with: match.range(at: 2)).lowercased()
            guard let (emoji, consumed) = lookup(name, isSmiley: suffix.hasPrefix("smiley")) else { continue }
            // Nur die erkannten Namenswörter ersetzen, davorstehende Wörter bleiben.
            let full = match.range
            let keepLength = (name as NSString).length - consumed
            let replaceRange = NSRange(location: full.location + max(0, keepLength), length: full.length - max(0, keepLength))
            guard let range = Range(replaceRange, in: result) else { continue }
            result.replaceSubrange(range, with: emoji)
        }
        return result.replacingOccurrences(of: "  ", with: " ")
    }

    /// Längster passender Name am Ende von `name`. Liefert Emoji und Zahl der verbrauchten Zeichen.
    private static func lookup(_ name: String, isSmiley: Bool) -> (String, Int)? {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        for count in stride(from: min(3, words.count), through: 1, by: -1) {
            let tail = words.suffix(count)
            let key = tail.joined(separator: " ").lowercased()
            if let emoji = emojis[key] {
                // Verbrauchte Länge: ab Beginn des ersten Namenswortes bis Ende von `name`.
                let consumed = consumedLength(of: Array(tail), in: name)
                return (emoji, consumed)
            }
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty, isSmiley { return ("🙂", 0) }
        return nil
    }

    private static func consumedLength(of tail: [String], in name: String) -> Int {
        guard let first = tail.first,
              let range = name.range(of: first, options: [.backwards, .caseInsensitive]) else { return (name as NSString).length }
        return (String(name[range.lowerBound...]) as NSString).length
    }
}
