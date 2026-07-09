import Foundation

/// Wandelt ausgeschriebene deutsche Zahlen in Ziffern um — on-device, rein, ohne
/// Abhängigkeiten. Wird nur im Standard-Modus (`.blitztext`) angewandt, weil dort kein
/// Rewrite-Schritt formatiert. Plus/$%&! überlassen das dem LLM.
///
/// Umfang: Grundzahlen (inkl. zusammengesetzter, `dreihundertfünfundzwanzig` → `325`),
/// Ordinalzahlen (`der dritte` → `der 3.`), Dezimalzahlen (`drei Komma fünf` → `3,5`)
/// und Uhrzeiten im Doppelpunkt-Format (`acht Uhr dreißig` → `8:30`).
///
/// Leitprinzip: **im Zweifel Text behalten**. Ein nicht eindeutig als Zahl erkennbares
/// Token bleibt unangetastet — der Konverter darf nie Text zerstören. Insbesondere bleibt
/// der Artikel „ein/eine" Text (`ein Auto` bleibt), nur `eins` und Komposita werden Ziffern.
enum NumberWordConverter {

    // MARK: - Öffentliche API

    static func convert(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let atoms = tokenize(text)
        var out = ""
        var index = 0
        /// Vorheriges Wort-Atom (kleingeschrieben) — Gate für Ordinalzahlen.
        var previousWord: String?

        while index < atoms.count {
            let atom = atoms[index]
            guard isWord(atom) else {
                out += atom
                index += 1
                continue
            }
            let lower = atom.lowercased()

            // 1) Grundzahl-Lauf (ggf. + Uhrzeit/Dezimal). Startpunkt entweder eine echte
            //    Grundzahl oder „ein/eine" direkt vor „Uhr" (→ 1 Uhr).
            let leading = cardinalRun(atoms, at: index)
                ?? einArticleHour(atoms, at: index)

            if let run = leading {
                if let decimal = tryDecimal(atoms, afterEnd: run.endAtom, integer: run.value) {
                    out += decimal.text
                    previousWord = nil
                    index = decimal.nextIndex
                    continue
                }
                if let time = tryTime(atoms, afterEnd: run.endAtom, hour: run.value) {
                    out += time.text
                    previousWord = nil
                    index = time.nextIndex
                    continue
                }
                out += String(run.value)
                previousWord = String(run.value)
                index = run.endAtom + 1
                continue
            }

            // 2) Ordinalzahl — nur nach Artikel/Präposition (verhindert „achte darauf" → Verb).
            if let prev = previousWord, determiners.contains(prev),
               let ordinal = parseOrdinal(lower) {
                out += "\(ordinal)."
                previousWord = lower
                index += 1
                continue
            }

            // 3) Default: Wort unverändert übernehmen.
            out += atom
            previousWord = lower
            index += 1
        }
        return out
    }

    // MARK: - Tokenisierung

    /// Zerlegt in alternierende Läufe aus Buchstaben (Wort) und Nicht-Buchstaben (Trenner).
    /// Ziffern und Satzzeichen landen in Trenner-Atomen und bleiben so unangetastet.
    private static func tokenize(_ text: String) -> [String] {
        var atoms: [String] = []
        var current = ""
        var currentIsLetter: Bool?
        for char in text {
            let isLetter = char.isLetter
            if currentIsLetter == nil {
                current = String(char)
                currentIsLetter = isLetter
            } else if isLetter == currentIsLetter {
                current.append(char)
            } else {
                atoms.append(current)
                current = String(char)
                currentIsLetter = isLetter
            }
        }
        if !current.isEmpty { atoms.append(current) }
        return atoms
    }

    private static func isWord(_ atom: String) -> Bool {
        atom.first?.isLetter == true
    }

    private static func isSpacesOnly(_ atom: String) -> Bool {
        atom.allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// Index des nächsten Wort-Atoms nach `k`, sofern es durch reinen Leerraum getrennt ist.
    private static func nextWordIndex(_ atoms: [String], after k: Int) -> Int? {
        guard k + 2 < atoms.count,
              isSpacesOnly(atoms[k + 1]),
              isWord(atoms[k + 2]) else { return nil }
        return k + 2
    }

    // MARK: - Grundzahl-Lauf über Tokens

    private struct Run { let endAtom: Int; let value: Int }

    /// Liest ab `start` einen möglichst langen Lauf zusammenhängender Zahlwörter und löst ihn
    /// über `parseCardinal` auf. Bindet auch getrennt gesprochene Skalen (`zwei Millionen`)
    /// und Bausteine (`drei hundert`) ein, solange die Konkatenation als Zahl parst.
    private static func cardinalRun(_ atoms: [String], at start: Int) -> Run? {
        guard isWord(atoms[start]) else { return nil }
        let first = atoms[start].lowercased()
        // Startbedingung: echte Zahl, oder „ein/eine" (nur sinnvoll vor Skala), oder Skalenwort.
        let canStart = parseCardinal(first) != nil
            || first == "ein" || first == "eine"
            || bareScaleWords.contains(first)
        guard canStart else { return nil }

        var concat = first
        var value = parseCardinal(first)
        var endAtom = start
        var cursor = start
        while let next = nextWordIndex(atoms, after: cursor) {
            let trial = concat + atoms[next].lowercased()
            guard let parsed = parseCardinal(trial) else { break }
            concat = trial
            value = parsed
            endAtom = next
            cursor = next
        }

        guard let resolved = value else { return nil }
        // Ein alleinstehendes Skalenwort (`hundert`, `Millionen`) bleibt Text — sonst würde
        // „Millionen Menschen" zu „1000000 Menschen". Nur mit vorangestellter Zahl gültig.
        if endAtom == start && bareScaleWords.contains(first) { return nil }
        return Run(endAtom: endAtom, value: resolved)
    }

    /// Sonderfall Artikel: „ein/eine" direkt vor „Uhr" zählt als Stunde 1 (`ein Uhr` → `1 Uhr`).
    private static func einArticleHour(_ atoms: [String], at start: Int) -> Run? {
        let lower = atoms[start].lowercased()
        guard lower == "ein" || lower == "eine",
              let uhr = nextWordIndex(atoms, after: start),
              atoms[uhr].lowercased() == "uhr" else { return nil }
        return Run(endAtom: start, value: 1)
    }

    // MARK: - Dezimal & Uhrzeit

    private static func tryDecimal(_ atoms: [String], afterEnd end: Int, integer: Int)
        -> (text: String, nextIndex: Int)? {
        guard let kommaIdx = nextWordIndex(atoms, after: end),
              atoms[kommaIdx].lowercased() == "komma",
              let firstIdx = nextWordIndex(atoms, after: kommaIdx),
              cardinalRun(atoms, at: firstIdx) != nil else { return nil }

        // Nachkommateil ziffernweise zusammensetzen: „fünf zwei" → „52", „fünfzehn" → „15".
        var digits = ""
        var lastEnd = firstIdx
        var idx: Int? = firstIdx
        while let cur = idx, let num = cardinalRun(atoms, at: cur) {
            digits += String(num.value)
            lastEnd = num.endAtom
            idx = nextWordIndex(atoms, after: num.endAtom)
        }
        return ("\(integer),\(digits)", lastEnd + 1)
    }

    private static func tryTime(_ atoms: [String], afterEnd end: Int, hour: Int)
        -> (text: String, nextIndex: Int)? {
        guard let uhrIdx = nextWordIndex(atoms, after: end),
              atoms[uhrIdx].lowercased() == "uhr" else { return nil }

        // Minuten vorhanden und plausibel (0–59) → Doppelpunkt-Format „H:MM".
        if let minIdx = nextWordIndex(atoms, after: uhrIdx),
           let minutes = cardinalRun(atoms, at: minIdx),
           (0...59).contains(minutes.value) {
            let mm = minutes.value < 10 ? "0\(minutes.value)" : "\(minutes.value)"
            return ("\(hour):\(mm)", minutes.endAtom + 1)
        }
        // Ohne Minuten bleibt die natürliche Form „H Uhr".
        return ("\(hour) Uhr", uhrIdx + 1)
    }

    // MARK: - Grundzahl-Parser (ein zusammengeschriebenes Zahlwort → Int)

    /// Parst ein deutsches Grundzahlwort. `nil`, wenn es keine gültige Zahl ist.
    static func parseCardinal(_ raw: String) -> Int? {
        let s = raw.lowercased()
        guard !s.isEmpty else { return nil }
        return parseScaled(s, scaleIndex: 0)
    }

    /// Skalenwörter absteigend — Milliarde vor Million vor Tausend.
    private static let scales: [(word: String, value: Int)] = [
        ("milliarde", 1_000_000_000),
        ("million", 1_000_000),
        ("tausend", 1_000)
    ]

    private static func parseScaled(_ s: String, scaleIndex: Int) -> Int? {
        guard scaleIndex < scales.count else { return parseHundredsGroup(s) }
        let (word, value) = scales[scaleIndex]
        guard let range = s.range(of: word) else {
            return parseScaled(s, scaleIndex: scaleIndex + 1)
        }
        let left = String(s[..<range.lowerBound])
        var after = String(s[range.upperBound...])
        // Plural abstreifen: Millionen (+en), Milliarden (+n).
        if after.hasPrefix("en") { after.removeFirst(2) }
        else if after.hasPrefix("n") { after.removeFirst(1) }

        let leftValue: Int
        if left.isEmpty {
            leftValue = 1                                   // „tausend" = 1000
        } else if let parsed = parseHundredsGroup(left) {
            leftValue = parsed
        } else if let unit = units[left] {
            leftValue = unit                                // „eintausend", „einemillion"
        } else {
            return nil
        }

        let rightValue: Int
        if after.isEmpty {
            rightValue = 0
        } else if let parsed = parseScaled(after, scaleIndex: scaleIndex + 1) {
            rightValue = parsed
        } else {
            return nil
        }
        return leftValue * value + rightValue
    }

    /// Werte unterhalb der Tausender-Skala: optionaler Hunderter-Block + Rest unter 100.
    /// Erlaubt auch Jahreszahl-Formen wie „neunzehnhundert" (19 × 100).
    private static func parseHundredsGroup(_ s: String) -> Int? {
        guard !s.isEmpty else { return nil }
        guard let range = s.range(of: "hundert") else { return parseBelow100(s) }

        let prefix = String(s[..<range.lowerBound])
        let hundreds: Int
        if prefix.isEmpty {
            hundreds = 1                                    // „hundert" = 100
        } else if let parsed = parseBelow100(prefix) {
            hundreds = parsed                               // „neunzehnhundert"
        } else if let unit = units[prefix] {
            hundreds = unit                                 // „einhundert"
        } else {
            return nil
        }

        let rest = String(s[range.upperBound...])
        if rest.isEmpty { return hundreds * 100 }
        guard let below = parseBelow100(rest) else { return nil }
        return hundreds * 100 + below
    }

    private static func parseBelow100(_ s: String) -> Int? {
        if let exact = below100[s] { return exact }
        // Zusammengesetzt: „{einer}und{zehner}" — z. B. „einundzwanzig" = 1 + 20.
        if let range = s.range(of: "und") {
            let unit = String(s[..<range.lowerBound])
            let ten = String(s[range.upperBound...])
            if let u = units[unit], let t = tens[ten] { return u + t }
        }
        return nil
    }

    // MARK: - Ordinalzahl-Parser

    /// Parst ein deutsches Ordinalwort (beliebige Flexion) → Grundwert. `nil` sonst.
    static func parseOrdinal(_ raw: String) -> Int? {
        let normalized = normalizeOrdinal(raw.lowercased())
        if let exact = ordinalUnits[normalized] { return exact }
        // Ab 20 sowie Hunderter/Tausender: Stamm + „-ste" (z. B. „zwanzigste", „hundertste").
        if normalized.hasSuffix("ste") {
            let stem = String(normalized.dropLast(3))
            if let value = parseCardinal(stem) { return value }
        }
        return nil
    }

    /// Normalisiert die Adjektivendung (-e/-en/-em/-er/-es) auf die Nominativ-Form „-e",
    /// damit `dritten`/`dritter`/`drittem` alle als `dritte` nachgeschlagen werden.
    private static func normalizeOrdinal(_ w: String) -> String {
        for ending in ["en", "em", "er", "es", "e"] where w.hasSuffix(ending) && w.count > ending.count {
            return String(w.dropLast(ending.count)) + "e"
        }
        return w
    }

    // MARK: - Lexika

    /// Einer als Multiplikator/Baustein — enthält bewusst `ein`/`eine`, damit `einhundert`
    /// und `eine Million` parsen. `below100` enthält `ein` NICHT, sodass der Artikel „ein"
    /// alleinstehend nie zur Ziffer wird.
    private static let units: [String: Int] = [
        "ein": 1, "eine": 1, "eins": 1,
        "zwei": 2, "drei": 3, "vier": 4, "fünf": 5,
        "sechs": 6, "sieben": 7, "acht": 8, "neun": 9
    ]

    private static let tens: [String: Int] = [
        "zwanzig": 20, "dreißig": 30, "dreissig": 30, "vierzig": 40, "fünfzig": 50,
        "sechzig": 60, "siebzig": 70, "achtzig": 80, "neunzig": 90
    ]

    private static let below100: [String: Int] = [
        "null": 0, "eins": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5,
        "sechs": 6, "sieben": 7, "acht": 8, "neun": 9, "zehn": 10,
        "elf": 11, "zwölf": 12, "dreizehn": 13, "vierzehn": 14, "fünfzehn": 15,
        "sechzehn": 16, "siebzehn": 17, "achtzehn": 18, "neunzehn": 19,
        "zwanzig": 20, "dreißig": 30, "dreissig": 30, "vierzig": 40, "fünfzig": 50,
        "sechzig": 60, "siebzig": 70, "achtzig": 80, "neunzig": 90
    ]

    /// Alleinstehende Skalenwörter (auch Plural) — dürfen ohne führende Zahl nicht konvertiert
    /// werden, damit „Millionen Menschen" Text bleibt.
    private static let bareScaleWords: Set<String> = [
        "hundert", "tausend",
        "million", "millionen", "milliarde", "milliarden"
    ]

    /// Ordinal-Grundformen 1–19 (Nominativ „-e"), inkl. Unregelmäßiger.
    private static let ordinalUnits: [String: Int] = [
        "erste": 1, "zweite": 2, "dritte": 3, "vierte": 4, "fünfte": 5,
        "sechste": 6, "siebte": 7, "siebente": 7, "achte": 8, "neunte": 9,
        "zehnte": 10, "elfte": 11, "zwölfte": 12, "dreizehnte": 13, "vierzehnte": 14,
        "fünfzehnte": 15, "sechzehnte": 16, "siebzehnte": 17, "achtzehnte": 18, "neunzehnte": 19
    ]

    /// Artikel/Präpositionen, nach denen eine Ordinalzahl umgewandelt wird.
    private static let determiners: Set<String> = [
        "der", "die", "das", "dem", "den", "des",
        "am", "im", "vom", "zum", "zur", "beim", "ans", "ins",
        "ein", "eine", "einen", "einem", "einer",
        "mein", "meine", "meinen", "meinem", "meiner",
        "dein", "deine", "sein", "seine", "unser", "unsere", "ihr", "ihre"
    ]
}
