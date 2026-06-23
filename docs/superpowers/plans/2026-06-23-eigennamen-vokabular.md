# Intelligentes Eigennamen-Vokabular — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die gespeicherte Eigennamen-Liste korrigiert aktiv jede Transkription (backend-agnostisch, on-device), und die Erkennung neuer Eigennamen wird streng genug, dass nur echte Namen — keine Wort-Ketten, keine Halluzinations-Varianten — in der Liste landen.

**Architecture:** Die Liste wird vom passiven Speicher zum aktiven Korrektor. Ein `VocabularyCorrector` matcht ASR-Output per Levenshtein gegen Listen-Einträge + Aliase und ersetzt Treffer (Guard via Wörterbuch). Nicht-exakte Treffer werden als neue Aliase gelernt — das schließt die „halluziniert-immer-neu"-Schleife. Die Erkennung bekommt ein Wörterbuch-Gate (`NSSpellChecker`), Wort-Ketten-Split und einen Kandidaten-Ledger (Auto-Save erst ab 2 Vorkommen).

**Tech Stack:** Swift 6 (strict concurrency: minimal), AppKit (`NSSpellChecker`), `NaturalLanguage` (`NLTagger`), Swift Testing (`import Testing`), XcodeGen, xcodebuild.

## Global Constraints

- Deutsche UI-Strings, englische Code-Identifier (Swift-Konvention). Verbatim aus CLAUDE.md.
- `SWIFT_STRICT_CONCURRENCY: minimal` — verbatim aus `project.yml`.
- Keine externe Cloud für Eigennamen-Korrektur/-Erkennung der neuen Logik — alles on-device (Korrektor, Analyzer-Gate, Ledger). Die bestehende optionale `EigennamenAISuggester`-Cloud bleibt unverändert.
- `TranscriptionService`-Protokoll abstrahiert Backends — nicht aufweichen. Verbatim aus CLAUDE.md.
- Neue Dateien unter `BlitzText/` werden von XcodeGen per Glob erfasst → nach dem Anlegen neuer Dateien **immer** `xcodegen generate` vor dem Build.
- Tests spiegeln die Source-Hierarchie unter `BlitzTextTests/`, Swift Testing bevorzugt, Verhaltens-Namen. Verbatim aus `.planning/codebase/TESTING.md`.
- Keine neuen Package-Dependencies (verbatim aus TESTING.md: „keep zero new dependencies").

### Standard-Kommandos

- Projekt regenerieren (nach neuen Dateien): `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate`
- Ein Test-Bundle/Subset: `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/<KlasseOderSuite>`
- Alle Tests + Coverage: `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -enableCodeCoverage YES`

> **Hinweis zu xcodebuild-Output:** Erfolg endet mit `** TEST SUCCEEDED **`, Fehlschlag mit `** TEST FAILED **` plus den fehlgeschlagenen Assertions. Bei „kann Scheme nicht finden" zuerst `xcodegen generate` laufen lassen.

---

## File Structure

**Neu (Source):**
- `BlitzText/ProperNouns/StringSimilarity.swift` — Levenshtein + längenbasierte Fuzzy-Schwelle. Geteilt von Korrektor + Analyzer (DRY).
- `BlitzText/ProperNouns/ProperNoun.swift` — strukturiertes Listen-Modell (text, aliases, occurrenceCount, lastSeenAt).
- `BlitzText/ProperNouns/WordChecking.swift` — Protokoll + `SystemSpellChecker` (NSSpellChecker-Wrapper, injizierbar für Tests).
- `BlitzText/ProperNouns/VocabularyCorrector.swift` — Problem A: Text-Level-Korrektur + Alias-Entdeckung.
- `BlitzText/ProperNouns/CandidateLedger.swift` — Problem B: Vorkommen zählen, Auto-Save-Schwelle (≥2×).

**Neu (Tests):**
- `BlitzTextTests/ProperNouns/StringSimilarityTests.swift`
- `BlitzTextTests/ProperNouns/ProperNounMigrationTests.swift`
- `BlitzTextTests/ProperNouns/VocabularyCorrectorTests.swift`
- `BlitzTextTests/ProperNouns/EigennamenAnalyzerTests.swift`
- `BlitzTextTests/ProperNouns/CandidateLedgerTests.swift`

**Modifiziert:**
- `BlitzText/Settings/SettingsStore.swift` — `properNouns: [ProperNoun]`, `properNounTexts`, UserDefaults-Injektion, Snapshot-Migration, Mutations-Helfer.
- `BlitzText/Modes/ModeProcessor.swift` — Korrektor in Pipeline einklinken; Prompt-Builder auf `properNounTexts`; Erkennung mit Wörterbuch-Gate + bestehender Liste.
- `BlitzText/ProperNouns/EigennamenAnalyzer.swift` — Wort-Ketten-Split, Mindestlänge 4, Wörterbuch-Gate.
- `BlitzText/ProperNouns/SuggestionPresenter.swift` — Ledger-Integration, `ProperNoun` speichern, Alias-Merge.
- `BlitzText/Settings/Tabs/AnpassenTab.swift` — Übersicht (Häufigkeit, zuletzt gesehen, Aliase).

---

## Task 1: StringSimilarity (geteilte Fuzzy-Util)

**Files:**
- Create: `BlitzText/ProperNouns/StringSimilarity.swift`
- Test: `BlitzTextTests/ProperNouns/StringSimilarityTests.swift`

**Interfaces:**
- Produces:
  - `enum StringSimilarity`
  - `static func levenshtein(_ a: String, _ b: String) -> Int`
  - `static func maxDistance(forLength length: Int) -> Int` — 1 für len≤5, 2 für len≤8, sonst 3
  - `static func isFuzzyMatch(_ a: String, _ b: String) -> Bool` — case-insensitiv; Schwelle aus `maxDistance(forLength:)` über die längere der beiden Längen; verlangt zusätzlich `abs(lenA-lenB) <= maxDistance`

- [ ] **Step 1: Failing-Test schreiben**

`BlitzTextTests/ProperNouns/StringSimilarityTests.swift`:

```swift
import Testing
@testable import BlitzText

struct StringSimilarityTests {

    @Test("levenshtein zählt Einzel-Edits korrekt")
    func levenshteinCountsEdits() {
        #expect(StringSimilarity.levenshtein("kitten", "sitting") == 3)
        #expect(StringSimilarity.levenshtein("Vardhaman", "Vardhaman") == 0)
        #expect(StringSimilarity.levenshtein("", "abc") == 3)
    }

    @Test("maxDistance skaliert mit Wortlänge")
    func maxDistanceScalesWithLength() {
        #expect(StringSimilarity.maxDistance(forLength: 4) == 1)
        #expect(StringSimilarity.maxDistance(forLength: 7) == 2)
        #expect(StringSimilarity.maxDistance(forLength: 12) == 3)
    }

    @Test("isFuzzyMatch akzeptiert nahe Varianten, lehnt entfernte ab")
    func fuzzyMatchAcceptsCloseRejectsFar() {
        // "Vardhaman" (9) → maxDistance 3; "Wardhaman" = 1 Edit
        #expect(StringSimilarity.isFuzzyMatch("Vardhaman", "Wardhaman"))
        #expect(StringSimilarity.isFuzzyMatch("vardhaman", "VARDAMAN")) // case-insensitiv, 1 Edit
        // Kurzwort: "Ott" (3) → maxDistance 1; "Akt" = 2 Edits → kein Match
        #expect(!StringSimilarity.isFuzzyMatch("Ott", "Akt"))
        // Sehr verschiedene Wörter
        #expect(!StringSimilarity.isFuzzyMatch("Garten", "Vardhaman"))
    }
}
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate && xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/StringSimilarityTests`
Expected: FAIL — `cannot find 'StringSimilarity' in scope`.

- [ ] **Step 3: Implementierung schreiben**

`BlitzText/ProperNouns/StringSimilarity.swift`:

```swift
import Foundation

/// Geteilte Fuzzy-String-Hilfen für Korrektur (VocabularyCorrector) und
/// Erkennung (EigennamenAnalyzer). Längenabhängige Schwelle, damit kurze
/// Wörter nicht über-korrigiert werden.
enum StringSimilarity {

    /// Maximal erlaubte Edit-Distanz für ein Wort dieser Länge.
    static func maxDistance(forLength length: Int) -> Int {
        switch length {
        case ...5: return 1
        case 6...8: return 2
        default: return 3
        }
    }

    /// Case-insensitiver Fuzzy-Vergleich. True, wenn die Edit-Distanz die
    /// längenbasierte Schwelle nicht überschreitet und der Längenunterschied
    /// nicht schon allein größer als die Schwelle ist.
    static func isFuzzyMatch(_ a: String, _ b: String) -> Bool {
        let lowerA = a.lowercased()
        let lowerB = b.lowercased()
        let threshold = maxDistance(forLength: max(lowerA.count, lowerB.count))
        guard abs(lowerA.count - lowerB.count) <= threshold else { return false }
        return levenshtein(lowerA, lowerB) <= threshold
    }

    /// Klassische Levenshtein-Distanz (Einfüge/Lösch/Ersetz = je 1).
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let n = aChars.count, m = bChars.count
        if n == 0 { return m }
        if m == 0 { return n }
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        for i in 1...n {
            for j in 1...m {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                dp[i][j] = Swift.min(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + cost
                )
            }
        }
        return dp[n][m]
    }
}
```

- [ ] **Step 4: Test laufen lassen, grün bestätigen**

Run: `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/StringSimilarityTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add BlitzText/ProperNouns/StringSimilarity.swift BlitzTextTests/ProperNouns/StringSimilarityTests.swift project.yml
git commit -m "feat(vokabular): StringSimilarity-Util (Levenshtein + Laengen-Schwelle)"
```

---

## Task 2: ProperNoun-Modell + SettingsStore-Migration

Dieser Task führt das strukturierte Modell ein, kippt `properNouns` auf `[ProperNoun]` und repariert **alle** Aufrufstellen mechanisch, damit der Build grün bleibt. Verhaltens-Erweiterungen kommen in späteren Tasks.

**Files:**
- Create: `BlitzText/ProperNouns/ProperNoun.swift`
- Modify: `BlitzText/Settings/SettingsStore.swift`
- Modify: `BlitzText/Modes/ModeProcessor.swift` (nur Prompt-Builder, mechanisch)
- Modify: `BlitzText/ProperNouns/SuggestionPresenter.swift` (mechanisch)
- Modify: `BlitzText/Settings/Tabs/AnpassenTab.swift` (mechanisch)
- Test: `BlitzTextTests/ProperNouns/ProperNounMigrationTests.swift`

**Interfaces:**
- Produces:
  - `struct ProperNoun: Codable, Identifiable, Equatable, Sendable` mit `id: UUID`, `text: String`, `aliases: [String]`, `occurrenceCount: Int`, `lastSeenAt: Date?`, computed `allForms: [String]` (= `[text] + aliases`), Init mit Defaults.
  - `SettingsStore.properNouns: [ProperNoun]`
  - `SettingsStore.properNounTexts: [String]` (computed, `properNouns.map(\.text)`)
  - `SettingsStore.init(defaults: UserDefaults = .standard)` — UserDefaults injizierbar (Test-Voraussetzung lt. TESTING.md)
  - `SettingsStore.bumpOccurrence(termID: UUID)` — `occurrenceCount += 1`, `lastSeenAt = Date()`
  - `SettingsStore.addAlias(_ alias: String, toTermID id: UUID)` — fügt Alias hinzu, wenn noch nicht (case-insensitiv) vorhanden
- Consumes: nichts aus Vortasks (StringSimilarity wird erst ab Task 4 gebraucht).

- [ ] **Step 1: Failing-Test schreiben**

`BlitzTextTests/ProperNouns/ProperNounMigrationTests.swift`:

```swift
import Testing
import Foundation
@testable import BlitzText

struct ProperNounMigrationTests {

    /// Eigene UserDefaults-Suite pro Test, damit die echte App-Konfig nicht berührt wird.
    private func freshDefaults() -> UserDefaults {
        let suite = "bt-propernoun-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Alter [String]-Snapshot migriert verlustfrei zu [ProperNoun]")
    func legacyStringArrayMigrates() throws {
        let defaults = freshDefaults()
        // Alten Snapshot mit dem Legacy-Feld "properNouns": [String] simulieren.
        let legacyJSON = """
        {"styleForPlus":"neutral","customPromptPlus":"","customPromptRant":"",
         "context":"","properNouns":["Vardhaman","Clara"],"autoInsert":false,
         "transcriptionLanguage":"de","rewriteModel":"gpt-4o-mini",
         "transcriptionModel":"whisper-1","backend":"parakeet"}
        """
        defaults.set(legacyJSON.data(using: .utf8)!, forKey: "de.reinholds.blitztext.settings")

        let store = SettingsStore(defaults: defaults)

        #expect(store.properNounTexts == ["Vardhaman", "Clara"])
        #expect(store.properNouns.allSatisfy { $0.aliases.isEmpty && $0.occurrenceCount == 0 })
    }

    @Test("bumpOccurrence erhöht Zähler und setzt lastSeenAt")
    func bumpOccurrenceUpdatesCounter() {
        let store = SettingsStore(defaults: freshDefaults())
        let noun = ProperNoun(text: "Vardhaman")
        store.properNouns = [noun]

        store.bumpOccurrence(termID: noun.id)

        #expect(store.properNouns.first?.occurrenceCount == 1)
        #expect(store.properNouns.first?.lastSeenAt != nil)
    }

    @Test("addAlias fügt neuen Alias case-insensitiv nur einmal hinzu")
    func addAliasDeduplicates() {
        let store = SettingsStore(defaults: freshDefaults())
        let noun = ProperNoun(text: "Vardhaman")
        store.properNouns = [noun]

        store.addAlias("Wardhaman", toTermID: noun.id)
        store.addAlias("wardhaman", toTermID: noun.id) // Duplikat (case)

        #expect(store.properNouns.first?.aliases == ["Wardhaman"])
    }
}
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate && xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/ProperNounMigrationTests`
Expected: FAIL — `cannot find 'ProperNoun'` bzw. `extra argument 'defaults' in call`.

- [ ] **Step 3a: ProperNoun-Modell anlegen**

`BlitzText/ProperNouns/ProperNoun.swift`:

```swift
import Foundation

/// Ein gelernter Eigenname samt bekannten Fehlhörungen (Aliase) und Statistik.
/// Ersetzt das frühere `[String]`-Modell — die Aliase treiben die Fuzzy-Korrektur,
/// occurrenceCount/lastSeenAt die Übersicht im Anpassen-Tab.
struct ProperNoun: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var aliases: [String]
    var occurrenceCount: Int
    var lastSeenAt: Date?

    init(
        id: UUID = UUID(),
        text: String,
        aliases: [String] = [],
        occurrenceCount: Int = 0,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.aliases = aliases
        self.occurrenceCount = occurrenceCount
        self.lastSeenAt = lastSeenAt
    }

    /// Alle Schreibweisen, gegen die gematcht wird (kanonisch + Aliase).
    var allForms: [String] { [text] + aliases }
}
```

- [ ] **Step 3b: SettingsStore umstellen**

In `BlitzText/Settings/SettingsStore.swift`:

1. Property-Typ ändern (Zeile 17):

```swift
    @Published var properNouns: [ProperNoun] = []
```

2. UserDefaults injizierbar machen. `defaultsKey` bleibt; neues gespeichertes `defaults`. Ersetze den `init()` (Zeilen 92–99) und ergänze die Property:

```swift
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        migrateAPIKeyFromUserDefaultsIfNeeded()
        objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }
```

3. In `load()` (Zeile 185) und `save()` (Zeile 241) sowie `migrateAPIKeyFromUserDefaultsIfNeeded()` (Zeile 143) jedes `UserDefaults.standard` durch `defaults` ersetzen. Konkret:
   - Zeile 143: `let defaults = UserDefaults.standard` → diese lokale Zeile **löschen** (es gibt jetzt die Property `defaults`).
   - Zeile 185: `guard let data = UserDefaults.standard.data(forKey:` → `guard let data = defaults.data(forKey:`
   - Zeile 241: `UserDefaults.standard.set(data, forKey:` → `defaults.set(data, forKey:`
   - Zeile 155: `defaults.removeObject(forKey:` bleibt (zeigt nun auf die Property — identisches Verhalten).

4. Snapshot erweitern. In `struct Snapshot` (nach Zeile 163) das Legacy-Feld zu Optional machen und ein neues Feld ergänzen — additiv, alte Snapshots laden ohne Crash:

```swift
        var properNouns: [String]?          // Legacy (vor V2) — nur noch zum Migrieren gelesen
        var properNounsV2: [ProperNoun]?    // Aktuelles Modell
```

   (Die bisherige Zeile `var properNouns: [String]` ersetzen.)

5. In `load()` das Mapping ersetzen (bisher Zeile 198 `properNouns = snap.properNouns`):

```swift
        if let v2 = snap.properNounsV2 {
            properNouns = v2
        } else {
            properNouns = (snap.properNouns ?? []).map { ProperNoun(text: $0) }
        }
```

6. In `save()` den Snapshot-Init anpassen (bisher Zeile 221 `properNouns: properNouns`):

```swift
            properNouns: nil,
            properNounsV2: properNouns,
```

7. Mutations-Helfer ans Ende der Klasse (vor der schließenden `}` von `SettingsStore`, nach `save()`):

```swift
    /// Erhöht den Vorkommens-Zähler eines Eintrags und stempelt „zuletzt gesehen".
    func bumpOccurrence(termID: UUID) {
        guard let idx = properNouns.firstIndex(where: { $0.id == termID }) else { return }
        properNouns[idx].occurrenceCount += 1
        properNouns[idx].lastSeenAt = Date()
    }

    /// Fügt einem Eintrag einen neu entdeckten Alias hinzu (case-insensitiv dedupliziert).
    func addAlias(_ alias: String, toTermID id: UUID) {
        guard let idx = properNouns.firstIndex(where: { $0.id == id }) else { return }
        let lower = alias.lowercased()
        let known = properNouns[idx].allForms.map { $0.lowercased() }
        guard !known.contains(lower) else { return }
        properNouns[idx].aliases.append(alias)
    }
```

- [ ] **Step 3c: Aufrufstellen mechanisch reparieren (Build grün halten)**

`BlitzText/Modes/ModeProcessor.swift` — Prompt-Builder. Ersetze in `makeWhisperPrompt()` (Zeilen 246–247):

```swift
        if !settings.properNounTexts.isEmpty {
            pieces.append("Eigennamen: " + settings.properNounTexts.joined(separator: ", "))
        }
```

und in `makeRewriteSystemPrompt(...)` (Zeilen 267–268):

```swift
        if !settings.properNounTexts.isEmpty {
            parts.append("Schreibe folgende Eigennamen exakt richtig: " + settings.properNounTexts.joined(separator: ", ") + ".")
        }
```

`BlitzText/ProperNouns/SuggestionPresenter.swift` — mechanische Anpassung an `[ProperNoun]`:
- Zeile 30: `let existing = Set(settings.properNouns.map { $0.lowercased() })` → `let existing = Set(settings.properNounTexts.map { $0.lowercased() })`
- Zeilen 53–54 in `acceptCurrent()`:

```swift
        if let word = current?.word, !settings.properNounTexts.contains(word) {
            settings.properNouns.append(ProperNoun(text: word))
```

`BlitzText/Settings/Tabs/AnpassenTab.swift`:
- Zeilen 97–103 (FlowLayout/ForEach):

```swift
                FlowLayout(spacing: 6) {
                    ForEach(settings.properNouns) { noun in
                        TagView(text: noun.text) {
                            settings.properNouns.removeAll { $0.id == noun.id }
                        }
                    }
                }
```

- `addNoun()` (Zeilen 118–123):

```swift
    private func addNoun() {
        let trimmed = newProperNoun.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.properNounTexts.contains(trimmed) else { return }
        settings.properNouns.append(ProperNoun(text: trimmed))
        newProperNoun = ""
    }
```

- [ ] **Step 4: Test + Build grün bestätigen**

Run: `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate && xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/ProperNounMigrationTests`
Expected: `** TEST SUCCEEDED **` (impliziert: gesamtes App-Target kompiliert, alle Aufrufstellen repariert).

- [ ] **Step 5: Commit**

```bash
git add BlitzText/ProperNouns/ProperNoun.swift BlitzText/Settings/SettingsStore.swift BlitzText/Modes/ModeProcessor.swift BlitzText/ProperNouns/SuggestionPresenter.swift BlitzText/Settings/Tabs/AnpassenTab.swift BlitzTextTests/ProperNouns/ProperNounMigrationTests.swift project.yml
git commit -m "feat(vokabular): ProperNoun-Modell + verlustfreie Snapshot-Migration"
```

---

## Task 3: WordChecking + SystemSpellChecker

**Files:**
- Create: `BlitzText/ProperNouns/WordChecking.swift`
- Test: erweitert in Task 4/6 via Fake; hier ein Smoke-Test fürs Produktiv-Verhalten.
- Test: `BlitzTextTests/ProperNouns/StringSimilarityTests.swift` (neue Suite anhängen ODER neue Datei — siehe Step 1)

**Interfaces:**
- Produces:
  - `protocol WordChecking: Sendable { func isKnownWord(_ word: String) -> Bool }`
  - `struct SystemSpellChecker: WordChecking` mit `init(language: String = "de")`; `isKnownWord` nutzt `NSSpellChecker.shared` und gibt `true` zurück, wenn das Wort **nicht** als Tippfehler markiert ist.

- [ ] **Step 1: Failing-Test schreiben**

`BlitzTextTests/ProperNouns/WordCheckingTests.swift`:

```swift
import Testing
@testable import BlitzText

struct WordCheckingTests {

    @Test("SystemSpellChecker kennt gängiges deutsches Wort, nicht aber Kunstwort")
    @MainActor
    func systemCheckerDistinguishesKnownFromUnknown() {
        let checker = SystemSpellChecker(language: "de")
        #expect(checker.isKnownWord("Haus"))
        #expect(!checker.isKnownWord("Vardhaman"))
        #expect(!checker.isKnownWord("xqzwkpf"))
    }
}
```

> Hinweis: `@MainActor`, weil `NSSpellChecker` auf dem Main-Thread benutzt wird. Sollte die CI-Umgebung kein deutsches Wörterbuch installiert haben, schlägt nur dieser Smoke-Test fehl — die Logik-Tests (Task 4/6) nutzen einen Fake und sind davon unabhängig.

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate && xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/WordCheckingTests`
Expected: FAIL — `cannot find 'SystemSpellChecker' in scope`.

- [ ] **Step 3: Implementierung schreiben**

`BlitzText/ProperNouns/WordChecking.swift`:

```swift
import AppKit

/// Abstrahiert „ist dieses Wort dem Wörterbuch bekannt?" — injizierbar, damit
/// Korrektur und Erkennung deterministisch ohne echtes Wörterbuch testbar sind.
protocol WordChecking: Sendable {
    func isKnownWord(_ word: String) -> Bool
}

/// Produktiv-Implementierung über `NSSpellChecker`. Ein Wort gilt als „bekannt",
/// wenn der Checker es NICHT als Tippfehler markiert. On-device, keine Cloud.
struct SystemSpellChecker: WordChecking {
    let language: String

    init(language: String = "de") {
        self.language = language
    }

    func isKnownWord(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(
            of: trimmed,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        // location == NSNotFound → kein Fehler gefunden → Wort ist bekannt.
        return range.location == NSNotFound
    }
}
```

- [ ] **Step 4: Test laufen lassen, grün bestätigen**

Run: `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/WordCheckingTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add BlitzText/ProperNouns/WordChecking.swift BlitzTextTests/ProperNouns/WordCheckingTests.swift project.yml
git commit -m "feat(vokabular): WordChecking-Protokoll + NSSpellChecker-Wrapper"
```

---

## Task 4: VocabularyCorrector (Problem A — Herzstück)

**Files:**
- Create: `BlitzText/ProperNouns/VocabularyCorrector.swift`
- Test: `BlitzTextTests/ProperNouns/VocabularyCorrectorTests.swift`

**Interfaces:**
- Consumes: `StringSimilarity.isFuzzyMatch`, `WordChecking`, `ProperNoun`.
- Produces:
  - `struct VocabularyCorrector` mit `init(checker: WordChecking = SystemSpellChecker())`
  - `func correct(_ text: String, using nouns: [ProperNoun]) -> VocabularyCorrector.Result`
  - `struct VocabularyCorrector.Match: Equatable { let termID: UUID; let original: String; let canonical: String; let wasExact: Bool }`
  - `struct VocabularyCorrector.Result: Equatable { let text: String; let matches: [Match] }`

Logik pro Wort-Token:
1. Token in Wortkern (Buchstaben) + führende/folgende Satzzeichen zerlegen, damit „Vardhaman," korrekt behandelt wird.
2. Exakter Treffer (case-insensitiv) gegen `allForms` aller Einträge → ersetzen durch `text` (Schreibweise des Eintrags), `wasExact = true`.
3. Sonst: Quellwort ist Fuzzy-Treffer (`StringSimilarity.isFuzzyMatch`) gegen eine `allForms` UND `checker.isKnownWord(kern) == false` (Guard) → ersetzen, `wasExact = false` (= neu entdeckter Alias). Bei mehreren Kandidaten gewinnt die kleinste Levenshtein-Distanz.
4. Groß-/Kleinschreibung: Beginnt das Originalwort mit Großbuchstabe, wird die Ersetzung kapitalisiert, sonst kleingeschrieben übernommen.
5. Mindestlänge des Kerns 4 (kürzere werden nie korrigiert — schützt Kurzwörter).

- [ ] **Step 1: Failing-Test schreiben**

`BlitzTextTests/ProperNouns/VocabularyCorrectorTests.swift`:

```swift
import Testing
@testable import BlitzText

private struct FakeChecker: WordChecking {
    let known: Set<String>
    func isKnownWord(_ word: String) -> Bool { known.contains(word.lowercased()) }
}

struct VocabularyCorrectorTests {

    private func corrector(known: Set<String> = []) -> VocabularyCorrector {
        VocabularyCorrector(checker: FakeChecker(known: known))
    }

    @Test("Fuzzy-Variante eines Eigennamens wird zur kanonischen Schreibweise korrigiert")
    func correctsFuzzyVariant() {
        let nouns = [ProperNoun(text: "Vardhaman")]
        let result = corrector().correct("Ich treffe Wardhaman heute.", using: nouns)
        #expect(result.text == "Ich treffe Vardhaman heute.")
        #expect(result.matches.count == 1)
        #expect(result.matches.first?.wasExact == false)
        #expect(result.matches.first?.original == "Wardhaman")
        #expect(result.matches.first?.termID == nouns[0].id)
    }

    @Test("Satzzeichen am Wort bleiben erhalten")
    func preservesPunctuation() {
        let nouns = [ProperNoun(text: "Vardhaman")]
        let result = corrector().correct("Hallo Wardhaman!", using: nouns)
        #expect(result.text == "Hallo Vardhaman!")
    }

    @Test("Bekanntes Wörterbuchwort wird NICHT zu einem Eigennamen über-korrigiert")
    func doesNotOvercorrectKnownWord() {
        let nouns = [ProperNoun(text: "Garden")]
        // "Garten" ist im Wörterbuch bekannt → Guard greift, keine Ersetzung.
        let result = corrector(known: ["garten"]).correct("Im Garten.", using: nouns)
        #expect(result.text == "Im Garten.")
        #expect(result.matches.isEmpty)
    }

    @Test("Exakter Treffer normalisiert die Schreibweise und markiert wasExact")
    func exactMatchNormalizesCasing() {
        let nouns = [ProperNoun(text: "Vardhaman")]
        let result = corrector().correct("vardhaman kommt.", using: nouns)
        #expect(result.text == "Vardhaman kommt.")
        #expect(result.matches.first?.wasExact == true)
    }

    @Test("Leere Liste ist No-Op")
    func emptyListIsNoOp() {
        let result = corrector().correct("Beliebiger Text.", using: [])
        #expect(result.text == "Beliebiger Text.")
        #expect(result.matches.isEmpty)
    }

    @Test("Treffer über einen Alias verwendet die kanonische Schreibweise")
    func aliasMatchUsesCanonical() {
        let nouns = [ProperNoun(text: "Vardhaman", aliases: ["Wardhaman"])]
        let result = corrector().correct("Wardhaman", using: nouns)
        #expect(result.text == "Vardhaman")
        #expect(result.matches.first?.wasExact == true) // Alias = bekannte Form
    }
}
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate && xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/VocabularyCorrectorTests`
Expected: FAIL — `cannot find 'VocabularyCorrector' in scope`.

- [ ] **Step 3: Implementierung schreiben**

`BlitzText/ProperNouns/VocabularyCorrector.swift`:

```swift
import Foundation

/// Problem A — das Herzstück: korrigiert ASR-Output anhand der gespeicherten
/// Eigennamen-Liste (exakt + fuzzy), backend-agnostisch und on-device.
/// Nicht-exakte Treffer melden den Originalwortlaut als neu entdeckten Alias.
struct VocabularyCorrector {

    struct Match: Equatable {
        let termID: UUID
        let original: String   // Wort, wie es im Transkript stand
        let canonical: String  // kanonische Schreibweise (term.text)
        let wasExact: Bool     // true, wenn original bereits eine bekannte Form war
    }

    struct Result: Equatable {
        let text: String
        let matches: [Match]
    }

    /// Wortkerne unter dieser Länge werden nie korrigiert (Schutz für Kurzwörter).
    private static let minCoreLength = 4

    let checker: WordChecking

    init(checker: WordChecking = SystemSpellChecker()) {
        self.checker = checker
    }

    func correct(_ text: String, using nouns: [ProperNoun]) -> Result {
        guard !nouns.isEmpty else { return Result(text: text, matches: []) }

        var matches: [Match] = []
        // An Leerzeichen splitten, Trenner erhalten (Tabs/Newlines bleiben so bestehen).
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)

        let corrected = tokens.map { token -> String in
            let (prefix, core, suffix) = Self.peel(token)
            guard core.count >= Self.minCoreLength else { return token }

            guard let hit = bestMatch(for: core, in: nouns) else { return token }
            matches.append(
                Match(termID: hit.term.id, original: core, canonical: hit.term.text, wasExact: hit.exact)
            )
            return prefix + Self.applyCasing(of: core, to: hit.term.text) + suffix
        }

        return Result(text: corrected.joined(separator: " "), matches: matches)
    }

    // MARK: - Matching

    private struct Hit { let term: ProperNoun; let exact: Bool; let distance: Int }

    private func bestMatch(for core: String, in nouns: [ProperNoun]) -> Hit? {
        let lowerCore = core.lowercased()

        // 1. Exakter Treffer (case-insensitiv) über text oder Alias.
        for term in nouns where term.allForms.contains(where: { $0.lowercased() == lowerCore }) {
            return Hit(term: term, exact: true, distance: 0)
        }

        // 2. Fuzzy — nur wenn das Quellwort dem Wörterbuch UNbekannt ist (Über-Korrektur-Guard).
        guard !checker.isKnownWord(core) else { return nil }

        var best: Hit?
        for term in nouns {
            for form in term.allForms where StringSimilarity.isFuzzyMatch(core, form) {
                let d = StringSimilarity.levenshtein(lowerCore, form.lowercased())
                if best == nil || d < best!.distance {
                    best = Hit(term: term, exact: false, distance: d)
                }
            }
        }
        return best
    }

    // MARK: - Token-Zerlegung

    /// Zerlegt „Vardhaman," in ("", "Vardhaman", ","). Kern = führende/folgende
    /// Nicht-Buchstaben abgeschnitten.
    private static func peel(_ token: String) -> (prefix: String, core: String, suffix: String) {
        let chars = Array(token)
        var start = 0
        var end = chars.count
        while start < end, !chars[start].isLetter { start += 1 }
        while end > start, !chars[end - 1].isLetter { end -= 1 }
        let prefix = String(chars[0..<start])
        let core = String(chars[start..<end])
        let suffix = String(chars[end..<chars.count])
        return (prefix, core, suffix)
    }

    /// Überträgt die Groß-/Kleinschreibung des Originals aufs Ersatzwort
    /// (Erstbuchstabe groß → kapitalisieren, sonst kleinschreiben).
    private static func applyCasing(of original: String, to replacement: String) -> String {
        guard let first = original.first else { return replacement }
        if first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        } else {
            return replacement.lowercased()
        }
    }
}
```

- [ ] **Step 4: Test laufen lassen, grün bestätigen**

Run: `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/VocabularyCorrectorTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add BlitzText/ProperNouns/VocabularyCorrector.swift BlitzTextTests/ProperNouns/VocabularyCorrectorTests.swift project.yml
git commit -m "feat(vokabular): VocabularyCorrector — aktive Text-Korrektur + Alias-Entdeckung"
```

---

## Task 5: Korrektor in die Pipeline einklinken

**Files:**
- Modify: `BlitzText/Modes/ModeProcessor.swift` (Pipeline ~Zeilen 182–237)
- Test: `BlitzTextTests/ProperNouns/VocabularyCorrectorTests.swift` (Integrations-Test über echten Korrektor — kein ModeProcessor-Mock nötig)

**Interfaces:**
- Consumes: `VocabularyCorrector`, `SettingsStore.bumpOccurrence`, `SettingsStore.addAlias`.
- Produces: Pipeline liefert korrigierten Text aus; gelernte Aliase + Vorkommen landen in `settings`.

Die Korrektur läuft auf `raw` direkt nach dem Halluzinations-Check. Die Erkennung (Zeilen 221–236) läuft weiterhin auf dem **originalen** `raw` (damit brandneue Namen erkennbar bleiben); die Alias-Pflege bekannter Namen erledigt der Korrektor.

- [ ] **Step 1: Integrations-Test schreiben (Korrektor end-to-end auf Beispieltext)**

Ergänze in `BlitzTextTests/ProperNouns/VocabularyCorrectorTests.swift` eine Suite, die das exakte Pipeline-Verhalten (korrigieren + Aliase/Vorkommen anwenden) gegen einen echten `SettingsStore` nachstellt:

```swift
struct VocabularyCorrectorPipelineTests {

    private func freshStore() -> SettingsStore {
        let suite = "bt-corr-pipe-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: d)
    }

    @Test("Pipeline-Schritt korrigiert Text, lernt Alias und zählt Vorkommen")
    @MainActor
    func appliesCorrectionAndLearns() {
        let store = freshStore()
        let term = ProperNoun(text: "Vardhaman")
        store.properNouns = [term]

        let corrector = VocabularyCorrector(checker: FakeChecker(known: []))
        let result = corrector.correct("Hallo Wardhaman", using: store.properNouns)

        // Das ist exakt die Logik, die ModeProcessor anwendet:
        for match in result.matches {
            store.bumpOccurrence(termID: match.termID)
            if !match.wasExact { store.addAlias(match.original, toTermID: match.termID) }
        }

        #expect(result.text == "Hallo Vardhaman")
        #expect(store.properNouns.first?.aliases == ["Wardhaman"])
        #expect(store.properNouns.first?.occurrenceCount == 1)
    }
}
```

(`FakeChecker` ist in derselben Datei aus Task 4 vorhanden.)

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate && xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/VocabularyCorrectorPipelineTests`
Expected: FAIL — `cannot find 'bumpOccurrence'`/`addAlias` falls Task 2 nicht gelaufen; sonst kompiliert der Test und ist grün (er testet bereits ausgelieferte Helfer). Falls grün: weiter zu Step 3 (Verdrahtung), kein Re-Run nötig vor Step 4.

- [ ] **Step 3: ModeProcessor verdrahten**

In `BlitzText/Modes/ModeProcessor.swift`, im `runPipeline`, **nach** dem Halluzinations-Block (nach Zeile 187, vor `let output: String` Zeile 189), einfügen:

```swift
        // Problem A: gespeicherte Eigennamen korrigieren aktiv den ASR-Output.
        let corrector = VocabularyCorrector()
        let correction = corrector.correct(raw, using: settings.properNouns)
        let corrected = correction.text
        for match in correction.matches {
            settings.bumpOccurrence(termID: match.termID)
            if !match.wasExact {
                settings.addAlias(match.original, toTermID: match.termID)
                Log.write("Eigenname-Alias gelernt: \(match.original) → \(match.canonical)")
            }
        }
```

Dann `raw` durch `corrected` als Quelle für Ausgabe/Rewrite ersetzen:
- Zeile 193 `output = raw` → `output = corrected`
- Zeile 205 `input: raw,` → `input: corrected,`

Die Erkennung bleibt auf `raw` (Zeile 222 unverändert), damit komplett neue Namen weiter erkannt werden. `history.append(... rawTranscript: raw ...)` bleibt ebenfalls auf `raw` (Roh-Protokoll).

- [ ] **Step 4: Test + Build grün bestätigen**

Run: `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/VocabularyCorrectorPipelineTests`
Expected: `** TEST SUCCEEDED **` (impliziert App-Target kompiliert mit verdrahtetem Korrektor).

- [ ] **Step 5: Commit**

```bash
git add BlitzText/Modes/ModeProcessor.swift BlitzTextTests/ProperNouns/VocabularyCorrectorTests.swift
git commit -m "feat(vokabular): Korrektor in ASR-Pipeline — Liste korrigiert jede Ausgabe"
```

---

## Task 6: Strengere Erkennung (Problem B / B1)

**Files:**
- Modify: `BlitzText/ProperNouns/EigennamenAnalyzer.swift`
- Test: `BlitzTextTests/ProperNouns/EigennamenAnalyzerTests.swift`
- Modify: `BlitzText/Modes/ModeProcessor.swift` (Aufruf-Signatur, Zeile 222)

**Interfaces:**
- Consumes: `WordChecking`, `StringSimilarity` (indirekt via Gate-Logik), `ProperNoun`.
- Produces:
  - `static func candidates(rawTranscript: String, polished: String?, checker: WordChecking = SystemSpellChecker()) -> [String]`
  - Verhalten: NER + Diff wie bisher, danach Gates: an Leerzeichen splitten (keine Ketten), Mindestlänge 4, `checker.isKnownWord` → raus.

- [ ] **Step 1: Failing-Test schreiben**

`BlitzTextTests/ProperNouns/EigennamenAnalyzerTests.swift`:

```swift
import Testing
@testable import BlitzText

private struct FakeDict: WordChecking {
    let known: Set<String>
    func isKnownWord(_ word: String) -> Bool { known.contains(word.lowercased()) }
}

struct EigennamenAnalyzerTests {

    @Test("Mehr-Wort-NER-Treffer werden in Einzelwörter gesplittet")
    func splitsMultiWordChains() {
        // "Hey Clara" darf nie als ein Eintrag erscheinen.
        let result = EigennamenAnalyzer.candidates(
            rawTranscript: "Hey Clara wie geht es dir",
            polished: nil,
            checker: FakeDict(known: ["hey", "wie", "geht", "es", "dir"])
        )
        #expect(!result.contains("Hey Clara"))
        #expect(!result.contains(where: { $0.contains(" ") }))
    }

    @Test("Bekannte Wörterbuchwörter werden herausgefiltert")
    func dropsDictionaryWords() {
        let result = EigennamenAnalyzer.candidates(
            rawTranscript: "Garten Vardhaman",
            polished: nil,
            checker: FakeDict(known: ["garten"])
        )
        #expect(!result.contains("Garten"))
    }

    @Test("Wörter kürzer als 4 Zeichen werden verworfen")
    func dropsShortWords() {
        let result = EigennamenAnalyzer.candidates(
            rawTranscript: "Ott und Ann",
            polished: nil,
            checker: FakeDict(known: [])
        )
        #expect(result.allSatisfy { $0.count >= 4 })
    }
}
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate && xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/EigennamenAnalyzerTests`
Expected: FAIL — `extra argument 'checker' in call` (alte Signatur) bzw. Ketten-/Kürze-Assertions schlagen fehl.

- [ ] **Step 3: Analyzer verschärfen**

In `BlitzText/ProperNouns/EigennamenAnalyzer.swift`, die `candidates`-Signatur (Zeile 9) und den finalen Filter (Zeilen 26–28) ersetzen:

```swift
    static func candidates(
        rawTranscript: String,
        polished: String?,
        checker: WordChecking = SystemSpellChecker()
    ) -> [String] {
        var found = Set<String>()

        for word in namedEntities(in: rawTranscript) {
            found.insert(word)
        }
        if let polished {
            for word in namedEntities(in: polished) {
                found.insert(word)
            }
            for word in correctedSpellings(raw: rawTranscript, polished: polished) {
                found.insert(word)
            }
        }

        // Gates: Ketten splitten, Mindestlänge 4, bekannte Wörterbuchwörter raus.
        var result = Set<String>()
        for entry in found {
            for piece in entry.split(separator: " ").map(String.init) {
                let token = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                guard token.count >= 4 else { continue }
                guard !checker.isKnownWord(token) else { continue }
                result.insert(token)
            }
        }
        return result.sorted()
    }
```

- [ ] **Step 3b: Aufruf in ModeProcessor anpassen**

In `BlitzText/Modes/ModeProcessor.swift` Zeile 222:

```swift
        let heuristic = EigennamenAnalyzer.candidates(rawTranscript: raw, polished: polished)
```

bleibt gültig (checker hat Default). Keine Änderung nötig — nur verifizieren, dass es kompiliert.

- [ ] **Step 4: Test laufen lassen, grün bestätigen**

Run: `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/EigennamenAnalyzerTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add BlitzText/ProperNouns/EigennamenAnalyzer.swift BlitzTextTests/ProperNouns/EigennamenAnalyzerTests.swift project.yml
git commit -m "feat(vokabular): strenge Erkennung — Ketten-Split, Mindestlaenge, Woerterbuch-Gate"
```

---

## Task 7: CandidateLedger (Anti-Flut)

**Files:**
- Create: `BlitzText/ProperNouns/CandidateLedger.swift`
- Test: `BlitzTextTests/ProperNouns/CandidateLedgerTests.swift`

**Interfaces:**
- Produces:
  - `final class CandidateLedger` mit `init(defaults: UserDefaults = .standard, threshold: Int = 2)`
  - `func record(_ word: String) -> Bool` — zählt das Wort (case-insensitiv) hoch; gibt `true` zurück, sobald der Schwellenwert erreicht ist.
  - `func reset(_ word: String)` — entfernt den Zähler (nach Übernahme in die Liste).

Persistiert das Zähl-Dictionary unter eigenem UserDefaults-Key, damit Vorkommen über Sessions hinweg zählen.

- [ ] **Step 1: Failing-Test schreiben**

`BlitzTextTests/ProperNouns/CandidateLedgerTests.swift`:

```swift
import Testing
import Foundation
@testable import BlitzText

struct CandidateLedgerTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "bt-ledger-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test("Erstes Vorkommen erreicht die Schwelle (2) noch nicht, zweites schon")
    func reachesThresholdOnSecondSighting() {
        let ledger = CandidateLedger(defaults: freshDefaults(), threshold: 2)
        #expect(ledger.record("Vardhaman") == false)
        #expect(ledger.record("vardhaman") == true) // case-insensitiv, zweites Vorkommen
    }

    @Test("reset setzt den Zähler zurück")
    func resetClearsCounter() {
        let ledger = CandidateLedger(defaults: freshDefaults(), threshold: 2)
        _ = ledger.record("Clara")
        ledger.reset("Clara")
        #expect(ledger.record("Clara") == false) // Zähler war zurückgesetzt → wieder 1
    }

    @Test("Zähler überlebt eine neue Ledger-Instanz (gleiche Defaults)")
    func persistsAcrossInstances() {
        let defaults = freshDefaults()
        #expect(CandidateLedger(defaults: defaults, threshold: 2).record("Ott") == false)
        #expect(CandidateLedger(defaults: defaults, threshold: 2).record("Ott") == true)
    }
}
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate && xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/CandidateLedgerTests`
Expected: FAIL — `cannot find 'CandidateLedger' in scope`.

- [ ] **Step 3: Implementierung schreiben**

`BlitzText/ProperNouns/CandidateLedger.swift`:

```swift
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
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:]
    }

    private func save(_ counts: [String: Int]) {
        defaults.set(counts, forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 4: Test laufen lassen, grün bestätigen**

Run: `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/CandidateLedgerTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add BlitzText/ProperNouns/CandidateLedger.swift BlitzTextTests/ProperNouns/CandidateLedgerTests.swift project.yml
git commit -m "feat(vokabular): CandidateLedger — Auto-Save erst ab 2 Vorkommen"
```

---

## Task 8: SuggestionPresenter — Ledger + Alias-Merge

**Files:**
- Modify: `BlitzText/ProperNouns/SuggestionPresenter.swift`
- Test: `BlitzTextTests/ProperNouns/SuggestionPresenterTests.swift`

**Interfaces:**
- Consumes: `CandidateLedger`, `StringSimilarity.isFuzzyMatch`, `SettingsStore.addAlias`/`bumpOccurrence`/`properNouns`/`properNounTexts`, `ProperNoun`.
- Produces: `enqueue(_:)` mit neuer Logik; `init(settings:ledger:)` (Ledger injizierbar für Tests).

Neue `enqueue`-Logik je Kandidat:
1. Exakter Bestand (case-insensitiv gegen `properNounTexts`) → skip.
2. Fuzzy-Variante einer bestehenden `allForms` → als Alias mergen (`addAlias`) + `bumpOccurrence`, **nicht** vorschlagen.
3. Sonst `ledger.record`: erst bei `true` (≥2×) in die Toast-Queue; sonst skip.

`acceptCurrent` hängt `ProperNoun(text: word, occurrenceCount: 2, lastSeenAt: Date())` an und ruft `ledger.reset(word)`.

- [ ] **Step 1: Failing-Test schreiben**

`BlitzTextTests/ProperNouns/SuggestionPresenterTests.swift`:

```swift
import Testing
import Foundation
@testable import BlitzText

@MainActor
struct SuggestionPresenterTests {

    private func makeStore() -> SettingsStore {
        let suite = "bt-presenter-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: d)
    }

    private func makeLedger() -> CandidateLedger {
        let suite = "bt-presenter-ledger-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return CandidateLedger(defaults: d, threshold: 2)
    }

    @Test("Einmaliger Kandidat wird nicht sofort vorgeschlagen (Ledger-Schwelle)")
    func singleSightingNotQueued() {
        let presenter = SuggestionPresenter(settings: makeStore(), ledger: makeLedger())
        presenter.enqueue(["Vardhaman"])
        #expect(presenter.current == nil)
    }

    @Test("Zweites Vorkommen löst den Vorschlag aus")
    func secondSightingQueues() {
        let presenter = SuggestionPresenter(settings: makeStore(), ledger: makeLedger())
        presenter.enqueue(["Vardhaman"])
        presenter.enqueue(["Vardhaman"])
        #expect(presenter.current?.word == "Vardhaman")
    }

    @Test("Variante eines bekannten Namens wird als Alias gemergt, nicht vorgeschlagen")
    func variantMergesAsAlias() {
        let store = makeStore()
        let term = ProperNoun(text: "Vardhaman")
        store.properNouns = [term]
        let presenter = SuggestionPresenter(settings: store, ledger: makeLedger())

        presenter.enqueue(["Wardhaman"]) // Fuzzy-Variante

        #expect(presenter.current == nil)
        #expect(store.properNouns.first?.aliases == ["Wardhaman"])
    }
}
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag bestätigen**

Run: `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate && xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/SuggestionPresenterTests`
Expected: FAIL — `extra argument 'ledger' in call` / Queue-Verhalten falsch.

- [ ] **Step 3: SuggestionPresenter umbauen**

Ersetze in `BlitzText/ProperNouns/SuggestionPresenter.swift` den `init` (Zeilen 24–26), `enqueue` (Zeilen 28–39) und `acceptCurrent` (Zeilen 50–59):

```swift
    private let settings: SettingsStore
    private let ledger: CandidateLedger
    private var queue: [String] = []
    private var timer: Timer?

    init(settings: SettingsStore, ledger: CandidateLedger = CandidateLedger()) {
        self.settings = settings
        self.ledger = ledger
    }

    func enqueue(_ words: [String]) {
        let queued = Set(queue.map { $0.lowercased() })
        var toShow: [String] = []

        for word in words {
            let lower = word.lowercased()

            // 1. Exakt bereits bekannt → ignorieren.
            if settings.properNounTexts.contains(where: { $0.lowercased() == lower }) { continue }
            // schon in der Queue oder aktuell sichtbar → ignorieren.
            if queued.contains(lower) || current?.word.lowercased() == lower { continue }

            // 2. Fuzzy-Variante eines bestehenden Eintrags → als Alias mergen, nicht vorschlagen.
            if let term = settings.properNouns.first(where: { t in
                t.allForms.contains(where: { StringSimilarity.isFuzzyMatch($0, word) })
            }) {
                settings.addAlias(word, toTermID: term.id)
                settings.bumpOccurrence(termID: term.id)
                Log.write("Eigenname-Variante als Alias gemergt: \(word) → \(term.text)")
                continue
            }

            // 3. Brandneuer Kandidat → erst ab Schwelle (≥2×) vorschlagen.
            if ledger.record(word) {
                toShow.append(word)
            }
        }

        guard !toShow.isEmpty else { return }
        queue.append(contentsOf: toShow)
        if current == nil { showNext() }
    }

    /// Auto-Save nach Countdown.
    private func acceptCurrent() {
        timer?.invalidate()
        timer = nil
        if let word = current?.word, !settings.properNounTexts.contains(word) {
            settings.properNouns.append(ProperNoun(text: word, occurrenceCount: 2, lastSeenAt: Date()))
            ledger.reset(word)
            Log.write("Eigenname automatisch übernommen: \(word)")
        }
        current = nil
        showNext()
    }
```

- [ ] **Step 4: Test laufen lassen, grün bestätigen**

Run: `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/SuggestionPresenterTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add BlitzText/ProperNouns/SuggestionPresenter.swift BlitzTextTests/ProperNouns/SuggestionPresenterTests.swift project.yml
git commit -m "feat(vokabular): Presenter — Ledger-Schwelle + Alias-Merge gegen Flut"
```

---

## Task 9: Übersicht im Anpassen-Tab

**Files:**
- Modify: `BlitzText/Settings/Tabs/AnpassenTab.swift`

**Interfaces:**
- Consumes: `SettingsStore.properNouns: [ProperNoun]` (Häufigkeit, lastSeenAt, Aliase).
- Produces: keine (reine View).

Dieser Task ist UI — keine Unit-Tests (lt. TESTING.md visuell/manuell verifiziert). Verifikation = Build grün + manuelle QA.

- [ ] **Step 1: EIGENNAMEN-Sektion ersetzen**

In `BlitzText/Settings/Tabs/AnpassenTab.swift` den `section("EIGENNAMEN")`-Block (Zeilen 91–114) ersetzen:

```swift
            section("EIGENNAMEN") {
                Text("Begriffe, die korrekt geschrieben werden müssen. Die Liste korrigiert jede Transkription automatisch.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Toggle("KI-Vorschläge nach jeder Aufnahme (gpt-4o-mini)", isOn: $settings.aiSuggestProperNouns)
                Text("Erkennung läuft on-device (großgeschriebene, dem Wörterbuch unbekannte Wörter). Neue Begriffe werden erst nach dem 2. Vorkommen übernommen.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(settings.properNouns.sorted { $0.occurrenceCount > $1.occurrenceCount }) { noun in
                    ProperNounRow(noun: noun) {
                        settings.properNouns.removeAll { $0.id == noun.id }
                    }
                }

                HStack {
                    TextField("Neuer Begriff", text: $newProperNoun)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addNoun)
                    Button(action: addNoun) {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(newProperNoun.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
```

- [ ] **Step 2: ProperNounRow-View ergänzen**

In derselben Datei nach `private struct TagView` (nach Zeile 151) einfügen:

```swift
// MARK: - Eigennamen-Zeile (Übersicht)

private struct ProperNounRow: View {
    let noun: ProperNoun
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(noun.text).font(.body)
                if !noun.aliases.isEmpty {
                    Text("Varianten: " + noun.aliases.joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text("\(noun.occurrenceCount)×")
                .font(.caption).foregroundStyle(.secondary)
                .help(noun.lastSeenAt.map { "Zuletzt: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Noch nicht vorgekommen")
            Button(action: onRemove) {
                Image(systemName: "trash").font(.caption)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Build verifizieren**

Run: `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate && xcodebuild build -scheme BlitzText -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manuelle QA**

App starten, Einstellungen → Anpassen → EIGENNAMEN:
- Liste zeigt Begriffe nach Häufigkeit sortiert, mit „N×" und (falls vorhanden) Varianten.
- Hover über „N×" zeigt „Zuletzt: …".
- Manuelles Hinzufügen + Löschen funktioniert.

- [ ] **Step 5: Commit**

```bash
git add BlitzText/Settings/Tabs/AnpassenTab.swift
git commit -m "feat(vokabular): Anpassen-Tab — Uebersicht mit Haeufigkeit, Varianten, zuletzt gesehen"
```

---

## Abschluss

- [ ] **Voller Testlauf + Coverage**

Run: `cd /Users/t.raba/VsCode/BlitzText && xcodegen generate && xcodebuild test -scheme BlitzText -destination 'platform=macOS' -enableCodeCoverage YES`
Expected: `** TEST SUCCEEDED **`, alle Suiten grün.

- [ ] **Manueller End-to-End-Smoke (Parakeet)**

Backend Parakeet, „Vardhaman" einmal manuell in die Liste eintragen, dann Aufnahme mit dem Namen → Ausgabe enthält „Vardhaman" korrekt (nicht die Fehlhörung). Bei einer Fehlhörung wird sie als Variante unter dem Eintrag gelernt (Anpassen-Tab prüfen).

---

## Self-Review (vom Plan-Autor durchgeführt)

**Spec-Abdeckung:**
- „Liste korrigiert Ausgabe" (Problem A) → Task 4 + 5. ✓
- „backend-agnostisch" → Korrektor läuft im ModeProcessor vor Delivery, unabhängig vom Backend. ✓
- „keine Wort-Ketten" → Task 6 (Split). ✓
- „Wörterbuch-Gate" → Task 3 + 6. ✓
- „keine Re-Suggestion bekannter Varianten / Alias-Merge" → Task 5 (Korrektor lernt Alias) + Task 8 (Presenter mergt Variante). ✓
- „Anti-Flut, ≥2×" → Task 7 + 8. ✓
- „strukturiertes Modell + Migration" → Task 2. ✓
- „Übersicht" → Task 9. ✓
- „on-device / keine neue Dependency" → nur NSSpellChecker/NaturalLanguage/Foundation. ✓

**Typ-Konsistenz:** `properNouns: [ProperNoun]`, `properNounTexts`, `bumpOccurrence(termID:)`, `addAlias(_:toTermID:)`, `VocabularyCorrector.Match{termID,original,canonical,wasExact}`, `CandidateLedger.record(_)->Bool`/`reset(_)`, `WordChecking.isKnownWord(_)` — über alle Tasks identisch verwendet. ✓

**Platzhalter:** keine — jeder Code-Schritt enthält vollständigen Code. ✓
