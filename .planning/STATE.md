---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-01T04:32:00.000Z"
progress:
  total_phases: 12
  completed_phases: 1
  total_plans: 7
  completed_plans: 5
  percent: 71
---

# Project State: BlitzText

**Last updated:** 2026-05-01

## Project Reference

**Core Value:** Vom gedrückten Hotkey bis zum eingefügten Text wenige Sekunden — Text muss benutzbar sein, ohne nachzubearbeiten.

**Current Focus:** Phase 2 — Test-Fundament

## Current Position

Phase: 2 (Test-Fundament) — EXECUTING
Plan: 2 of 3 (next: 02-02 Hotkey-State-Machine-Tests)

- **Milestone:** Sprecher-Profile + Stabilisierung
- **Phase:** Phase 2 in Arbeit — Wave 0 (02-01) abgeschlossen
- **Plan:** 02-01 ✅ — Wave 0: Test-Target + Refactors + Fakes + SmokeTests gruen
- **Status:** Executing Phase 2
- **Progress:** 1/6 phases complete (Phase 2: 1/3 plans)

```
[███░░░░░░░░░░░░░░░░░] 17% (1/6 phases)
```

## Performance Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Hotkey-Release → Clipboard (5–15 s Audio) | ≤ 3 s | nicht gemessen |
| Diarization-Modell-Download | sichtbar mit Progress | unsichtbar (Phase 3 fix) |
| Test-Coverage Hotkey + Pipeline | ≥ 1 grüner Test pro Pfad | SmokeTests gruen (2/2); Hotkey/Pipeline-Tests folgen in 02-02/02-03 |
| Plan 02-01 Dauer | — | ~5 min, 5 Commits, 8 Files |

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

### Open Todos

- Phase 2 planen (`/gsd-plan-phase 2`) — Test-Fundament
- UAT für Phase 1 (offen, kein Blocker für Phase 2):
  - Schlüsselbund-Roundtrip (Dummy-Key speichern → Schlüsselbund.app prüfen)
  - Legacy-Migration End-to-End (`defaults write … apiKey 'sk-legacy-123'` → App-Start → Migration)
  - TCC-Auto-Recovery (Permission entfernen → App starten → live aktivieren → Tap greift ohne Restart)

### Blockers

Keine.

## Session Continuity

**Letzte Aktion:** Phase 2 Plan 02-01 (Wave 0) abgeschlossen — BlitzTextTests-Target, decideTransition-Seam, ModeProcessor-DI, RecorderProtocol, 3 Fakes, SmokeTests gruen. 5 Commits auf main.

**Nächste Aktion:** Plan 02-02 ausfuehren — Hotkey-State-Machine-Tests gegen `decideTransition` (Hold/Toggle, Modifier-Matrix, Debounce, schnelles Loslassen).

---
*Phase 1 abgeschlossen: 2026-04-30*
