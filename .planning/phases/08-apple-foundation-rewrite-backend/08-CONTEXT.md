# Phase 8 Context: Apple Foundation Models als Rewrite-Backend

**Captured:** 2026-05-01 (originally 999.7)
**Phase status:** ACTIVE — promoted from backlog 2026-05-01
**Source:** `/gsd-discuss-phase 999.7` → `/gsd-review-backlog`

## <domain>

**Capability:** Apple Foundation Models (macOS 26+) als zweites Backend hinter dem `RewriteService`-Protokoll integrieren — lokale Alternative zu OpenAI gpt-4o-mini im Rewrite-Pfad (Blitztext+ und Blitztext $%&!).

**Heutiger Stand (Code):**
- `RewriteService` Protocol in [RewriteService.swift](../../../BlitzText/Rewrite/RewriteService.swift): `rewrite(input:, systemPrompt:, model:) async throws -> String`
- Einzige Implementierung: [OpenAIChatClient.swift](../../../BlitzText/Rewrite/OpenAIChatClient.swift) (gpt-4o-mini)
- Pipeline-Brain in [ModeProcessor.swift](../../../BlitzText/Modes/ModeProcessor.swift): wählt RewriteService je nach Mode (Plus / Rant); plain `blitztext` umgeht Rewrite komplett
- 3 Modes in [Mode.swift](../../../BlitzText/Modes/Mode.swift): `blitztext` (raw), `blitztextPlus` (Stil-Rewrite), `blitztextRant` (Deeskalation)
- `TranscriptionBackend`-Enum in [SettingsStore.swift](../../../BlitzText/Settings/SettingsStore.swift) ist die etablierte Vorlage für Backend-Auswahl

**Phase-Boundary:** Foundation Models als Backend für die existierenden Rewrite-Modes Plus + Rant. **Nicht** Teil dieser Phase: neue Modes, Translation (das ist 999.4/999.5), Apple-Foundation-Summarization für Meetings (999.3 hat das separat).

## <decisions>

### Backend-Strategie

- **Foundation Models = Default**, OpenAI bleibt als expliziter User-Override verfügbar.
- **Kein automatischer Fallback** auf OpenAI bei Foundation-Fehler. Stattdessen: klare deutsche Fehlermeldung mit Hinweis auf Backend-Wechsel in den Settings.
- Begründung: Privacy-Markenversprechen kompromisslos halten; impliziter Fallback würde unbemerkt Daten in die Cloud schicken — das widerspricht der Identität der App.
- **Code-Form:** `RewriteBackend`-Enum (analog `TranscriptionBackend`) in `SettingsStore`. Cases: `appleFoundation` (default), `openAI`. Erweiterbar.

### Modell-Capability & Modes

- **Pro Mode wählbar:** User kann unabhängig für Blitztext+ und Blitztext $%&! das Backend setzen.
- Settings-UI: zwei Dropdowns (oder Segmented Control) im "Modi"-Tab — einer pro Rewrite-Mode.
- Defaults: beide Modes = `appleFoundation` bei verfügbarem Foundation; sonst beide = `openAI`.
- Hintergrund: Foundation-Modell ist kleiner als gpt-4o-mini — Deeskalation könnte qualitativ schlechter ausfallen als Stil-Rewrite. Der User soll den Trade-off pro Mode selbst kalibrieren können.

### Foundation-API-Auswahl

- **Plain `LanguageModelSession`** für `blitztextPlus` (Stil-Rewrite) — `LanguageModelSession(instructions: systemPrompt).respond(to: input)` mappt 1:1 auf das bestehende RewriteService-Protokoll.
- **Guided Generation (`@Generable`)** für `blitztextRant` (Deeskalation) — definiertes Schema (z.B. `struct DeescalatedOutput { var neutralText: String }`) verhindert Format-Drift und stellt sicher, dass das Modell wirklich nur den entschärften Text liefert, nicht mit "Hier ist die entschärfte Version: …"-Präambel.
- Researcher-Aufgabe: Schema-Felder genau festlegen (z.B. `neutralText: String`, optional `removedHeatTerms: [String]` für spätere Telemetry); prüfen, wie `LanguageModelSession` und `respond(to:generating:)` mit unserem deutschen Prompt umgehen (sprachbasiertes Bias?).

### Verfügbarkeit & UX

- **Start-Check** via `SystemLanguageModel.default.availability` in `AppDelegate.bootstrap()` (oder `SettingsStore.load()`).
- Verfügbarkeitsstatus wird im `SettingsStore` als beobachtbarer State gehalten.
- **Bei `unavailable`:** Settings-Tab "Modi" zeigt deutsche Fehlermeldung mit konkretem Grund (Apple Intelligence aus / Modell lädt / Region nicht unterstützt / Hardware nicht kompatibel) und Link zu System-Einstellungen. Wenn User OpenAI-API-Key bereits hat: Default automatisch auf `openAI` umstellen und Hinweis-Banner zeigen.
- **Bei `available`:** keine UI-Reibung; Foundation Models ist transparent aktiv.
- **Backend-Indikator im HUD:** subtiles Symbol/Label im Recording-HUD oder in der Toast-Bestätigung — z.B. Apple-Logo (SF Symbol `apple.logo`) für Foundation, `cloud` für OpenAI. Dezent, aber Privacy-Markenversprechen wird sichtbar.
- Researcher klärt: Wie unterscheidet `availability` zwischen "noch nicht heruntergeladen" vs. "endgültig nicht verfügbar"? Gibt es einen Reload-Mechanismus für den State, falls der User Apple Intelligence während der Session aktiviert?

## <canonical_refs>

Downstream agents (researcher, planner) müssen diese Dateien lesen:

- [.planning/ROADMAP.md](../../ROADMAP.md) — Phase 999.7 Eintrag im Backlog
- [.planning/PROJECT.md](../../PROJECT.md) — Privacy-Markenversprechen, "lokale Verarbeitung", Out-of-Scope-Note zu Apple Foundation
- [.planning/REQUIREMENTS.md](../../REQUIREMENTS.md) — Out-of-Scope-Verweis ("Apple Foundation Models — separater Track")
- [.planning/codebase/STRUCTURE.md](../../codebase/STRUCTURE.md) — Verzeichnis `BlitzText/Rewrite/`, Naming-Conventions für Clients
- [.planning/codebase/STACK.md](../../codebase/STACK.md) — Swift 6, macOS 26+, strict-concurrency: minimal
- [BlitzText/Rewrite/RewriteService.swift](../../../BlitzText/Rewrite/RewriteService.swift) — Protocol, das ein neuer `AppleFoundationRewriteClient` erfüllen muss
- [BlitzText/Rewrite/OpenAIChatClient.swift](../../../BlitzText/Rewrite/OpenAIChatClient.swift) — Vorlage-Implementierung; Fehlerbehandlung als Referenz
- [BlitzText/Modes/Mode.swift](../../../BlitzText/Modes/Mode.swift) — Mode-Enum mit System-Prompts pro Mode
- [BlitzText/Modes/ModeProcessor.swift](../../../BlitzText/Modes/ModeProcessor.swift) — Pipeline-Brain; `runPipeline`-Switch wird erweitert, um RewriteBackend-Auswahl zu konsultieren (`makeRewriteSystemPrompt(for:)`)
- [BlitzText/Settings/SettingsStore.swift](../../../BlitzText/Settings/SettingsStore.swift) — `TranscriptionBackend`-Enum als Vorlage; Snapshot-Pattern für Persistenz; neuer `RewriteBackend`-Enum + Per-Mode-Mapping
- [BlitzText/Settings/SettingsView.swift](../../../BlitzText/Settings/SettingsView.swift) — Modi-Tab; hier kommen die zwei Dropdowns rein + Verfügbarkeits-Banner
- [BlitzText/UI/HUDView.swift](../../../BlitzText/UI/HUDView.swift) und [RecordingHUDController.swift](../../../BlitzText/UI/RecordingHUDController.swift) — Backend-Indikator
- **Externe Apple-Doku** (Researcher liest live, Training-Daten unzuverlässig):
  - `FoundationModels` framework — `SystemLanguageModel`, `LanguageModelSession`, `availability`
  - `@Generable` macro / Guided Generation guide

## <code_context>

**Wiederverwendbare Assets:**
- `RewriteService` Protocol — keine Änderung nötig, neuer Client implementiert es einfach
- `TranscriptionBackend`-Enum + zugehöriger Settings-Code in `SettingsStore` — direkte Vorlage für `RewriteBackend`
- `SettingsStore.Snapshot`-Pattern — etablierte UserDefaults-Migration mit `?? default`-Fallback für neue Felder (per-Mode-Backend-Map)
- `SettingsView`-Tab-Struktur — Modi-Tab existiert; UI-Erweiterung dort
- HUD-Indikator-Slot in `RecordingHUDView` (RecordingHUDController.swift) — bereits Live-Pegel etc., Backend-Symbol passt visuell rein

**Integrationspunkte:**
- `AppDelegate.bootstrap()` — Start-Check für Foundation-Verfügbarkeit; Default-Backend ggf. korrigieren
- `ModeProcessor.runPipeline` — Backend-Lookup pro Mode aus `SettingsStore`, Client-Auswahl danach
- `ModeProcessor.makeRewriteSystemPrompt(for:)` — Prompt bleibt gleich, wird aber an beide Backends gleich übergeben (Plain) bzw. an Generable-Schema gebunden (Rant)

**Risiken / Landminen:**
- **Swift-6-Concurrency:** `SystemLanguageModel`, `LanguageModelSession` sind aktor-basiert; `RewriteService` ist `Sendable`. Researcher prüft, ob die neue Client-Klasse `@MainActor`/`Sendable` sauber zusammenpasst (Project ist `SWIFT_STRICT_CONCURRENCY: minimal`, also Spielraum).
- **Sprachbias:** Foundation-Modell-Outputs können auf Englisch driften, wenn Prompt mehrsprachig oder schwach. Deutsche System-Prompts müssen evtl. expliziter werden — Researcher testet.
- **Latenz:** Foundation-Modell-Cold-Start vs. gpt-4o-mini-Roundtrip. PROJECT.md fordert ≤ 3s end-to-end. Researcher misst Cold-Start-Kosten und prüft, ob Pre-Warm beim App-Start sinnvoll ist (Session Lazy-Init in AppDelegate).
- **Generable-Schema-Drift:** Wenn das Modell das Schema nicht zuverlässig erfüllt (z.B. leerer `neutralText`), braucht der Client Fallback-Logik. Plain-Session vs. Guided ist hier ein Robustheits-Trade-off.
- **History-Kompatibilität:** History-Replay-Funktion ruft Rewrite erneut auf — falls das ursprüngliche Backend nicht mehr verfügbar, was passiert? Researcher klärt, ob History-Eintrag das verwendete Backend speichern soll (für transparente Reproduktion).

## <deferred>

Während der Diskussion erwähnt, aber außerhalb der Phase-Boundary:

- **Apple Foundation für Meeting-Zusammenfassungen** — separate Phase 999.3 / 999.5, nicht Teil von 999.7
- **Telemetry/Latenz-Vergleich Foundation vs. OpenAI** — passt eher in v2-Requirement PERF-02 (End-to-End-Latenz-Telemetrie)
- **Optional: Apple Foundation für Translation (999.4/999.5)** — wenn Foundation Models gut genug für Übersetzung sind, könnten 999.4/999.5 von dieser Phase profitieren; aber Reihenfolge bleibt offen

## <next_steps>

Phase ist im Backlog. Bei Promotion zur aktiven Phase:

```
/gsd-plan-phase 999.7
```

Vorher idealerweise `/gsd-review-backlog` ausführen.

**Vor-Plan-Empfehlung an Researcher:** Live-Doku zu `FoundationModels` framework lesen — `SystemLanguageModel.default.availability`, `LanguageModelSession(instructions:)`, `respond(to:generating:)` für Guided Generation, `@Generable`-Macro-Anwendung. Die spezifische API-Form sollte aus offiziellen Apple-Docs verifiziert werden, nicht aus Trainingsdaten.

---
*Context erfasst: 2026-05-01 via /gsd-discuss-phase 999.7*
