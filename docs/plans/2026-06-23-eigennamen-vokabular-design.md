# Design: Intelligentes Eigennamen-Vokabular

**Datum:** 2026-06-23
**Status:** Freigegeben
**Milestone:** Sprecher-Profile + Stabilisierung

## Problem

Das Eigennamen-Vokabular ist halbfertig und frustriert im Alltag:

1. **Die Liste wird beim lokalen Transkribieren nicht genutzt.** Der von BlitzText
   genutzte `AsrManager.transcribe`-Pfad (Parakeet) bekommt den Prompt gar nicht
   ([ParakeetClient.swift:64](../../BlitzText/Transcription/ParakeetClient.swift#L64)),
   `LocalWhisperClient` ignoriert ihn ebenfalls
   ([LocalWhisperClient.swift:43-50](../../BlitzText/Transcription/LocalWhisperClient.swift#L43-L50)).
   Nur OpenAI-Cloud-Whisper und der Rewrite-Schritt verwenden ihn. → Die
   gespeicherte Liste ist beim Hauptanwendungsfall (Parakeet, lokal) wertlos.
2. **Halluzinations-Schleife.** Weil die ASR nie auf den Namen gebogen wird,
   verhört sie sich jedes Mal anders ("Vardhaman" → "Wardhaman" → "Vardaman"),
   und jede Variante wird als *neues* Wort erkannt und erneut gespeichert.
3. **Über-Erkennung / keine Übersicht.** NLTagger mit `.joinNames` erzeugt
   Wort-Ketten ("Hey Clara"), Mindestlänge nur 2 Zeichen, kein Wörterbuch- oder
   Häufigkeitsfilter, 5-Sekunden-Auto-Accept übernimmt fast alles ungefragt.

## Entscheidungen

- **Backend-Fokus:** Parakeet (lokal). Bestätigt durch Nutzer.
- **Erkennungs-Philosophie:** weiterhin automatisch, aber mit harten
  Qualitäts-Gates.
- **Problem A (Anwendung):** A1 jetzt (Text-Level-Fuzzy-Korrektur),
  A2 später (FluidAudio Token-Boosting) als optionales Upgrade vorgemerkt.
- **Problem B (Erkennung):** B1 — strenge Gates + Wörterbuch.

### Machbarkeit FluidAudio (warum A1 statt A2)

FluidAudio 0.14.3 *hat* echtes Vokabular-Boosting (Token-Level-Rescoring:
`VocabularyRescorer` + `CtcKeywordSpotter`, BKTree + Levenshtein), aber es hängt
ausschließlich an `SlidingWindowAsrManager.configureVocabularyBoosting`
(Streaming) und braucht ein **zusätzliches CTC-Modell** (`ctc110m`, eigener
Download). Der schlanke `AsrManager.transcribe`-Pfad hat keinen
Vokabular-Parameter; eine saubere Batch-API existiert nicht (nur Benchmark-Code
verdrahtet die Teile manuell). A2 wäre daher Streaming-Umbau + Extra-Modell +
Re-Validierung der Diarization-Token-Timings — zu großer Eingriff fürs
Stabilisierungs-Milestone. A1 (Text-Level-Korrektur) ist backend-agnostisch,
on-device, ohne Extra-Modell und isoliert testbar.

## Leitprinzip

Die gespeicherte Liste wird vom **passiven Speicher** zum **aktiven Korrektor**.
Jede Transkription wird gegen die Liste gefuzzy-matcht und korrigiert
(backend-unabhängig, on-device). Erkennung wird streng, damit nur echte
Eigennamen reinkommen und die Liste übersichtlich bleibt.

## Architektur

### 1. Datenmodell

`SettingsStore.properNouns: [String]` → strukturiertes Modell:

```swift
struct ProperNoun: Codable, Identifiable, Sendable {
    let id: UUID
    var text: String           // kanonische Schreibweise, z.B. "Vardhaman"
    var aliases: [String]      // bekannte Fehlhörungen, z.B. ["Wardhaman", "Vardaman"]
    var occurrenceCount: Int   // wie oft real vorgekommen → Sortierung/Übersicht
    var lastSeenAt: Date?
}
```

- `SettingsStore` erhält `var properNouns: [ProperNoun]` plus computed
  `properNounTexts: [String]` für die bestehenden Prompt-Stellen
  ([ModeProcessor.swift:247](../../BlitzText/Modes/ModeProcessor.swift#L247),
  [:268](../../BlitzText/Modes/ModeProcessor.swift#L268)) — kein Bruch.
- **Migration:** Snapshot-Feld additiv-optional (`properNounsV2: [ProperNoun]?`),
  alter `[String]`-Snapshot wird beim Laden zu `[ProperNoun]` gemappt (Muster wie
  bei `hotkeyFor*`/`ollamaModel`). Kein Datenverlust.

### 2. `VocabularyCorrector` (Problem A — Herzstück)

Neuer, isoliert testbarer Typ. Aufruf in
[ModeProcessor.swift](../../BlitzText/Modes/ModeProcessor.swift) direkt nach der
Halluzinations-Prüfung (~Zeile 182), auf `raw`, **vor** Rewrite/Delivery.

Ablauf:

1. Output in Wörter (Tokens) zerlegen.
2. Pro Wort besten Treffer über `text` + `aliases` aller Einträge via
   **Levenshtein** suchen. Schwelle längenabhängig: ≤1 bei ≤5 Zeichen, ≤2 bei
   ≤8, ≤3 darüber. (Phase 2 optional: Kölner Phonetik als zusätzliches Signal.)
3. **Guard gegen Über-Korrektur:** nur ersetzen, wenn das Quellwort *kein*
   gültiges deutsches Wörterbuchwort ist (`NSSpellChecker`, Sprache `de`).
   Verhindert, dass korrekte Alltagswörter zu Namen werden.
4. Groß-/Kleinschreibung des Originalworts auf die Ersetzung übertragen.
5. Treffer erhöht `occurrenceCount` und setzt `lastSeenAt` des Eintrags.

Wirkt für Parakeet, lokales Whisper und Cloud gleichermaßen. Ab dem ersten
Listeneintrag wird "Vardhaman" konsistent korrekt ausgegeben.

**Reichweite:** Korrektur nur auf `raw` (sauberer Input für Rewrite + direkte
Raw-Ausgabe). Der Rewrite-Prompt verstärkt zusätzlich.

### 3. Strengere Erkennung (Problem B / B1)

[EigennamenAnalyzer.swift](../../BlitzText/ProperNouns/EigennamenAnalyzer.swift):

- **Keine Wort-Ketten:** NER-Ergebnisse an Leerzeichen splitten → kein
  "Hey Clara", nur "Clara".
- **Mindestlänge 4** statt 2.
- **Wörterbuch-Gate:** steht das Wort im deutschen `NSSpellChecker`, ist es ein
  bekanntes Wort → kein Eigenname → raus. (Großschreibung allein taugt im
  Deutschen nicht, da alle Substantive großgeschrieben sind; "unbekannt im
  Wörterbuch" ist das tragende Signal.)
- **Keine Re-Suggestion bekannter Varianten:** Kandidat, der Fuzzy-Variante
  eines bestehenden `text`/`alias` ist, wird nicht neu vorgeschlagen, sondern als
  Alias am bestehenden Eintrag vermerkt. → bricht die Halluzinations-Schleife.

### 4. Anti-Flut beim Speichern (Problem B)

[SuggestionPresenter.swift](../../BlitzText/ProperNouns/SuggestionPresenter.swift):
ein **Kandidaten-Ledger** zählt Vorkommen über Sessions hinweg. Auto-Übernahme
erst, wenn ein Kandidat **≥2× real** aufgetaucht ist — einmalige
Halluzinationen landen nie in der Liste.

### 5. Übersicht im UI

[AnpassenTab.swift](../../BlitzText/Settings/Tabs/AnpassenTab.swift): Liste
sortiert nach Häufigkeit, mit "zuletzt gesehen" und aufklappbaren Aliases (zum
Mergen/Korrigieren). Macht die Fülle beherrschbar.

## Datenfluss (neu)

```
Aufnahme → ASR (raw)
         → Halluzinations-Check
         → VocabularyCorrector(raw, properNouns)  ← NEU: Liste korrigiert Output
            → occurrenceCount/lastSeenAt++ bei Treffer
         → [Plus/Rant: Rewrite] / [Raw: direkt]
         → deliver()
         → Erkennung (streng): EigennamenAnalyzer + AI
            → Kandidaten-Ledger (≥2×)
            → bekannte Variante? → Alias mergen, NICHT neu vorschlagen
            → sonst Toast → Auto-Save
```

## Fehlerbehandlung

- `NSSpellChecker` nicht verfügbar / Sprache unbekannt → Gate fällt auf
  "behandeln wie unbekannt" zurück (Korrektur/Erkennung degradiert sicher, kein
  Crash).
- Leere Liste → Corrector ist No-Op (Kaltstart sauber).
- Migration-Decode-Fehler → bestehendes Verhalten: Defaults laden, loggen.

## Testbarkeit

`VocabularyCorrector`, der verschärfte Analyzer und der Kandidaten-Ledger sind
pure/isolierte Typen → Swift-Testing-Unit-Tests ohne ASR-Stack:

- Levenshtein-Schwellen pro Länge (inkl. Grenzfälle).
- Über-Korrektur-Guard (Alltagswort wird nicht ersetzt).
- Groß-/Kleinschreibungs-Übernahme.
- Wort-Ketten-Split, Mindestlänge, Wörterbuch-Gate.
- Variante-bekannt → Alias-Merge statt Neu-Vorschlag.
- Ledger-Schwelle (1× nicht gespeichert, 2× gespeichert).

Deckt die 80-%-Vorgabe für die neue Logik ab.

## Später (out of scope)

- **A2:** FluidAudio Token-Level-Boosting via `SlidingWindowAsrManager` +
  CTC-Modell — präziser, aber großer Eingriff; als Folge-Milestone vorgemerkt.
- Kölner Phonetik als zusätzliches Fuzzy-Signal.
