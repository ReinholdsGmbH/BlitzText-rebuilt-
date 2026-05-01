---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-01T06:50:00.000Z"
progress:
  total_phases: 12
  completed_phases: 2
  total_plans: 7
  completed_plans: 7
  percent: 100
---

# Project State: BlitzText

**Last updated:** 2026-05-01

## Project Reference

**Core Value:** Vom gedrückten Hotkey bis zum eingefügten Text wenige Sekunden — Text muss benutzbar sein, ohne nachzubearbeiten.

**Current Focus:** Phase 3 (Diarization-UX) — Plans READY, naechster Schritt: /gsd-execute-phase 3

## Current Position

Phase: 2 (Test-Fundament) — COMPLETE
Plan: 3 of 3 — alle abgeschlossen

- **Milestone:** Sprecher-Profile + Stabilisierung
- **Phase:** Phase 2 vollstaendig — Wave 0 (02-01) + Wave 1 (02-02 + 02-03) abgeschlossen
- **Plan:** 02-03 ✅ — Pipeline-Error-Path-Tests: 3 TEST-04-Pin-Tests, 3x consecutive gruen, volle Suite 22/22
- **Status:** Phase 3 Discuss + UI + Plan abgeschlossen — 2 Plans (03-01 Wave 0, 03-02 Wave 2) verified 12/12 dimensions
- **Progress:** 2/6 phases complete (Phase 3 ready zur Ausfuehrung)

```
[██████░░░░░░░░░░░░░░] 33% (2/6 phases)
```

## Performance Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Hotkey-Release → Clipboard (5–15 s Audio) | ≤ 3 s | nicht gemessen |
| Diarization-Modell-Download | sichtbar mit Progress | unsichtbar (Phase 3 fix) |
| Test-Coverage Hotkey + Pipeline | ≥ 1 grüner Test pro Pfad | Hotkey 17/17 + Pipeline 3/3 gruen (3x consecutive); volle Suite 22/22 |
| Plan 02-01 Dauer | — | ~5 min, 5 Commits, 8 Files |
| Plan 02-02 Dauer | — | ~4 min, 1 Commit, 1 Testfile (220 LOC, 17 Tests) |
| Plan 02-03 Dauer | — | ~6 min, 1 Commit, 1 Testfile (~155 LOC, 3 Tests) |

## Accumulated Context

### Decisions

- Sprecher-Erkennung lokal über FluidAudio `SpeakerManager` (kein Cloud-Service) — Datenschutz + bestehende API
- Persistenz als JSON in `~/Library/Application Support/BlitzText/speakers.json` (analog zu `history.json`)
- Sandbox bleibt aus dieser Milestone draußen — separate Initiative
- TEST-03 (Sprecher-Matching-Tests) wandert von Phase 2 zu Phase 4, weil Code dort entsteht
- Hotkey-Debounce: 50 ms Hold / 300 ms Toggle (Phase 1, STAB-02)
- API-Key in Keychain (Service `de.reinholds.blitztext`, Account `openai-api-key`); UserDefaults-Migration einmalig + idempotent (Phase 1, STAB-01)
- Accessibility-Permission Auto-Recovery via 1 Hz `AXIsProcessTrusted`-Watcher (Phase 1, STAB-03)
- Test-Fundament Wave 0: pure `decideTransition` als Hotkey-Seam, `ModeProcessor.init` mit optional-defaulted DI, `RecorderProtocol` fuer `AudioRecorder` (Phase 2, 02-01)
- AppDelegate `enforceSingleInstance` skippt unter XCTest, damit hosted Tests nicht durch parallel laufende BlitzText.app terminiert werden (Phase 2, 02-01)
- Hotkey-State-Machine-Tests pinnen Wave-0-Realitaet: Release innerhalb 50 ms holdDebounce wird verschluckt (Phase 2, 02-02)
- Pipeline-Error-Path-Tests pinnen ParakeetClient Diarization-Silent-Fallback als CURRENT-Verhalten (state==.idle nach erfolgreichem Backend-Fake; future Phase 3 darf Pin bewusst aendern) (Phase 2, 02-03)

### Open Todos

- Phase 3 diskutieren (`/gsd-discuss-phase 3`) — Diarization-UX
- UAT für Phase 1 (offen, kein Blocker für Phase 3):
  - Schlüsselbund-Roundtrip (Dummy-Key speichern → Schlüsselbund.app prüfen)
  - Legacy-Migration End-to-End (`defaults write … apiKey 'sk-legacy-123'` → App-Start → Migration)
  - TCC-Auto-Recovery (Permission entfernen → App starten → live aktivieren → Tap greift ohne Restart)

### Blockers

Keine.

## Session Continuity

**Letzte Aktion:** Phase 3 Plan-Phase abgeschlossen. 03-RESEARCH.md (FluidAudio 0.14.3 Live-Inspection, progressHandler-API gefunden), 03-01-PLAN.md (Wave 0: DiarizerModelManager + ETAEstimator + Loader-Protokoll + Tests, ADR Variant A vs B), 03-02-PLAN.md (Wave 2: SettingsStore didSet, ParakeetClient-Refactor, vier-State SettingsView-Block, AppDelegate Pre-Warm). Plan-Checker 12/12 dimensions PASSED. Commits: 75ab422 (Plans), a5b9486 (Research).

**Nächste Aktion:** `/gsd-execute-phase 3` — Wave 0 (Manager + Tests) parallel-safe; Wave 2 (UI + Integration) sequentiell danach.

---
*Phase 1 abgeschlossen: 2026-04-30*
*Phase 2 abgeschlossen: 2026-05-01*
