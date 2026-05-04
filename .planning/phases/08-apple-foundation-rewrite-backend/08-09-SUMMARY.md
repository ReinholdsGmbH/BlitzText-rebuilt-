---
phase: 08-apple-foundation-rewrite-backend
plan: 09
subsystem: prompt-engineering
tags: [apple-foundation, prompt, plus-mode, rant-mode, swift]

requires:
  - phase: 08-apple-foundation-rewrite-backend
    provides: AppleFoundationRewriteClient, RewriteBackend enum, rewriteGuided path wired in ModeProcessor

provides:
  - foundationRewritePrompt property on Mode enum (Plus + Rant variants)
  - makeRewriteSystemPrompt(for:backend:) — backend-aware prompt dispatch
  - Plus+Foundation: strikt am Originalinhalt, keine Prosa/Einleitungen
  - Rant+Foundation: sachliche Umschreibung, bei ruhigem Input leicht glätten statt 1:1

affects: [08-apple-foundation-rewrite-backend, future prompt tuning plans]

tech-stack:
  added: []
  patterns:
    - "Foundation-Prompts als separate computed property auf Mode enum — OpenAI-Pfad unverändert"
    - "Custom-Prompt hat Priorität vor Foundation-Variant (User-Präferenz gewinnt)"
    - "backend-Parameter in makeRewriteSystemPrompt statt globales Backend-Flag"

key-files:
  created: []
  modified:
    - BlitzText/Modes/Mode.swift
    - BlitzText/Modes/ModeProcessor.swift

key-decisions:
  - "foundationRewritePrompt als eigenes computed property statt Switch in makeRewriteSystemPrompt direkt — bessere Kohäsion, Mode kennt seine Prompts"
  - "Custom-Prompt hat Vorrang: wenn customPromptPlus/Rant gesetzt, wird Foundation-Variant übersprungen"
  - "Sprachbias-Marker (Antworte ausschließlich auf Deutsch) bleibt separat nach dem Prompt — gilt für alle Foundation-Aufrufe"

patterns-established:
  - "Backend-aware Prompt-Dispatch: if custom → custom; else if foundation → foundationPrompt; else → defaultPrompt"

requirements-completed: []

duration: 8min
completed: 2026-05-04
---

# Phase 08 Plan 09: Apple-Foundation-spezifische Prompt-Varianten Summary

**Backend-spezifische Prompt-Varianten für Plus- und Rant-Modus: Foundation bekommt eigene, knappe Instruktionen die keine Prosa erzeugen und bei sachlichem Rant-Input glätten statt 1:1 zurückgeben**

## Performance

- **Duration:** 8 min
- **Started:** 2026-05-04T11:28:00Z
- **Completed:** 2026-05-04T11:36:30Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- `Mode.foundationRewritePrompt` hinzugefügt: Plus-Variante verhindert neue Inhalte/Begrüßungen durch explizites "strikt an Originalinhalt"; Rant-Variante behandelt ruhigen Input mit leichter Glättung statt Passthrough
- `makeRewriteSystemPrompt(for:backend:)` erweitert: Foundation-Variant wird nur gewählt wenn kein Custom-Prompt gesetzt ist (User-Präferenz hat Priorität)
- Aufrufstelle in `runPipeline` auf `makeRewriteSystemPrompt(for: mode, backend: backend)` aktualisiert; bestehender Sprachbias-Marker-Block bleibt unverändert
- 59 Tests, 0 Failures — kein Regression-Treffer

## Task Commits

1. **Task 1: Foundation-Prompt-Varianten in Mode.swift** - `e31bfc7` (feat)
2. **Task 2: makeRewriteSystemPrompt um backend-Parameter erweitern** - `b14de69` (feat)
3. **Task 3: Tests anpassen + Build verifizieren** - `82cc87c` (test — empty commit, keine Testdatei-Änderungen nötig)

## Files Created/Modified

- `BlitzText/Modes/Mode.swift` - `foundationRewritePrompt: String` property nach `defaultRewritePrompt` eingefügt
- `BlitzText/Modes/ModeProcessor.swift` - `makeRewriteSystemPrompt` Signatur und Body auf backend-Parameter umgestellt

## Decisions Made

- `makeRewriteSystemPrompt` ist `private` — Tests rufen es nicht direkt auf. Keine Testdatei-Änderungen nötig.
- 59 statt 57 Tests grün (Suite ist seit Plan-Erstellung gewachsen; alle grün).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Known Stubs

None — keine Stub-Patterns in den modifizierten Dateien.

## Threat Flags

None — reine Prompt-String-Änderungen, kein neues Netzwerk/Auth/Schema-Surface.

## Self-Check

- [x] `BlitzText/Modes/Mode.swift` enthält `var foundationRewritePrompt: String` — FOUND
- [x] `BlitzText/Modes/ModeProcessor.swift` enthält `func makeRewriteSystemPrompt(for mode: Mode, backend: RewriteBackend)` — FOUND
- [x] Commit e31bfc7 existiert — FOUND
- [x] Commit b14de69 existiert — FOUND
- [x] 59 Tests, 0 Failures — PASSED

## Self-Check: PASSED

## Next Phase Readiness

Foundation-Prompt-Varianten sind eingebaut und verifiziert. Der Plus-Modus erzeugt mit Foundation keine neuen Inhalte mehr; der Rant-Modus glättet sachlichen Input statt ihn 1:1 durchzureichen. OpenAI-Pfad unverändert.

---
*Phase: 08-apple-foundation-rewrite-backend*
*Completed: 2026-05-04*
