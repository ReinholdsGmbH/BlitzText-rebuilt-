import Testing
@testable import BlitzText

struct NumberWordConverterTests {

    // MARK: - Grundzahlen

    @Test("Grundzahlen (Einer, Teens, Zehner, Komposita, Hunderter, Tausender, Jahre, Millionen)",
          arguments: [
            (in: "null", out: "0"),
            (in: "eins", out: "1"),
            (in: "fünf", out: "5"),
            (in: "elf", out: "11"),
            (in: "zwölf", out: "12"),
            (in: "fünfzehn", out: "15"),
            (in: "zwanzig", out: "20"),
            (in: "dreißig", out: "30"),
            (in: "einundzwanzig", out: "21"),
            (in: "vierundfünfzig", out: "54"),
            (in: "neunundneunzig", out: "99"),
            (in: "hundertfünf", out: "105"),
            (in: "dreihundertfünfundzwanzig", out: "325"),
            (in: "zweitausend", out: "2000"),
            (in: "zweitausendvierundzwanzig", out: "2024"),
            (in: "neunzehnhundertvierundachtzig", out: "1984"),
          ])
    func cardinals(pair: (in: String, out: String)) {
        #expect(NumberWordConverter.convert(pair.in) == pair.out)
    }

    @Test("Getrennt gesprochene Skalen und Bausteine werden zusammengefasst",
          arguments: [
            (in: "zwei Millionen", out: "2000000"),
            (in: "drei hundert", out: "300"),
            (in: "eine Million", out: "1000000"),
          ])
    func spacedScales(pair: (in: String, out: String)) {
        #expect(NumberWordConverter.convert(pair.in) == pair.out)
    }

    // MARK: - Ordinalzahlen (nur nach Artikel/Präposition)

    @Test("Ordinalzahlen nach Artikel/Präposition werden zu N.",
          arguments: [
            (in: "der dritte", out: "der 3."),
            (in: "am dritten März", out: "am 3. März"),
            (in: "das erste Mal", out: "das 1. Mal"),
            (in: "der achte Platz", out: "der 8. Platz"),
            (in: "die siebte Runde", out: "die 7. Runde"),
            (in: "der zwanzigste", out: "der 20."),
            (in: "der einundzwanzigste Tag", out: "der 21. Tag"),
          ])
    func ordinals(pair: (in: String, out: String)) {
        #expect(NumberWordConverter.convert(pair.in) == pair.out)
    }

    // MARK: - Dezimalzahlen

    @Test("Komma-Dezimalzahlen",
          arguments: [
            (in: "drei Komma fünf", out: "3,5"),
            (in: "null Komma fünf", out: "0,5"),
            (in: "drei Komma fünf zwei", out: "3,52"),
            (in: "zwei Komma fünfundzwanzig", out: "2,25"),
          ])
    func decimals(pair: (in: String, out: String)) {
        #expect(NumberWordConverter.convert(pair.in) == pair.out)
    }

    // MARK: - Uhrzeiten

    @Test("Uhrzeiten: X Uhr Y → Doppelpunkt, X Uhr bleibt natürlich",
          arguments: [
            (in: "acht Uhr dreißig", out: "8:30"),
            (in: "fünfzehn Uhr dreißig", out: "15:30"),
            (in: "acht Uhr fünf", out: "8:05"),
            (in: "acht Uhr", out: "8 Uhr"),
            (in: "ein Uhr", out: "1 Uhr"),
            (in: "ein Uhr dreißig", out: "1:30"),
            (in: "halb drei", out: "halb 3"),
            (in: "Viertel vor fünf", out: "Viertel vor 5"),
          ])
    func times(pair: (in: String, out: String)) {
        #expect(NumberWordConverter.convert(pair.in) == pair.out)
    }

    // MARK: - Negative Fälle (kritisch: Text darf nicht zerstört werden)

    @Test("Artikel und Nicht-Zahlwörter bleiben unangetastet",
          arguments: [
            (in: "ein Auto", out: "ein Auto"),
            (in: "Ein Auto", out: "Ein Auto"),
            (in: "eine Katze", out: "eine Katze"),
            (in: "ich achte darauf", out: "ich achte darauf"),
            (in: "die beste Lösung", out: "die beste Lösung"),
            (in: "die nächste Runde", out: "die nächste Runde"),
            (in: "die Liste", out: "die Liste"),
            (in: "Millionen von Menschen", out: "Millionen von Menschen"),
            (in: "hundert Euro", out: "hundert Euro"),
            (in: "erste Ergebnisse", out: "erste Ergebnisse"),
          ])
    func negatives(pair: (in: String, out: String)) {
        #expect(NumberWordConverter.convert(pair.in) == pair.out)
    }

    // MARK: - Satz-Integration & Casing

    @Test("Zahl am Satzanfang wird konvertiert")
    func sentenceStart() {
        #expect(NumberWordConverter.convert("Fünf Leute kamen.") == "5 Leute kamen.")
    }

    @Test("Mehrere Zahlen in einem Satz")
    func multipleNumbers() {
        #expect(
            NumberWordConverter.convert("ich hätte gern fünf Stück und zwanzig Euro")
                == "ich hätte gern 5 Stück und 20 Euro"
        )
    }

    @Test("Alleinstehende Zahl 'eins' wird zur Ziffer")
    func standaloneEins() {
        #expect(NumberWordConverter.convert("ich brauche eins") == "ich brauche 1")
    }

    @Test("Leerer und zahlfreier Text bleibt unverändert")
    func passthrough() {
        #expect(NumberWordConverter.convert("") == "")
        #expect(NumberWordConverter.convert("das ist ein Test") == "das ist ein Test")
    }

    // MARK: - Parser-Einheiten (direkter Zugriff)

    @Test("parseCardinal löst Komposita korrekt auf")
    func parseCardinalUnit() {
        #expect(NumberWordConverter.parseCardinal("dreihundertfünfundzwanzig") == 325)
        #expect(NumberWordConverter.parseCardinal("zweitausendvierundzwanzig") == 2024)
        #expect(NumberWordConverter.parseCardinal("ein") == nil)      // Artikel, keine Zahl
        #expect(NumberWordConverter.parseCardinal("blabla") == nil)
    }

    @Test("parseOrdinal erkennt reguläre und unregelmäßige Formen")
    func parseOrdinalUnit() {
        #expect(NumberWordConverter.parseOrdinal("erste") == 1)
        #expect(NumberWordConverter.parseOrdinal("dritten") == 3)
        #expect(NumberWordConverter.parseOrdinal("siebte") == 7)
        #expect(NumberWordConverter.parseOrdinal("zwanzigsten") == 20)
        #expect(NumberWordConverter.parseOrdinal("beste") == nil)
    }
}
