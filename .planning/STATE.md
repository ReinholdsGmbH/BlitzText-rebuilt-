---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-01T08:19:00.000Z"
progress:
  total_phases: 12
  completed_phases: 2
  total_plans: 9
  completed_plans: 9
  percent: 100
---

# Project State: BlitzText

**Last updated:** 2026-05-01

## Project Reference

**Core Value:** Vom gedrückten Hotkey bis zum eingefügten Text wenige Sekunden — Text muss benutzbar sein, ohne nachzubearbeiten.

**Current Focus:** Phase 8 (Apple Foundation Rewrite-Backend) — PLANNED (5/5 plans), naechster Schritt: /gsd-execute-phase 8 (Wave 0 zuerst). Phase 3 verification (manual UAT) bleibt offen, blockt aber Phase 8 nicht.

## Current Position

Phase: 3 (Diarization-UX) — EXECUTION COMPLETE
Plan: 2 of 2 — beide abgeschlossen (03-01 Wave 0, 03-02 Wave 2)

- **Milestone:** Sprecher-Profile + Stabilisierung
- **Phase:** Phase 3 ausgefuehrt — Wave 0 (03-01: Manager-Foundation) + Wave 2 (03-02: UI + AppDelegate-Wiring)
- **Plan:** 03-02 ✅ — Vier-State-UI in SettingsView, Manager-konsumierender ParakeetClient, AppDelegate-Prewarm, 39/39 Tests gruen, 3x consecutive
- **Status:** Phase 3 Plans complete; manuelle UI-Verifikation steht noch aus (/gsd-verify-phase 3)
- **Progress:** 2/6 phases complete (Phase 3 awaiting verification)

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
| Plan 03-01 Dauer | — | ~25 min, 4 Commits, 6 Files (Manager + ETAEstimator + Tests, 15 Tests) |
| Plan 03-02 Dauer | — | ~8 min, 5 Commits, 9 Files modified (4-State UI + DI-Wiring, 39/39 Tests 3x grün) |

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
- DiarizerModelManager als @MainActor ObservableObject wraps FluidAudio.DiarizerModels.downloadIfNeeded(progressHandler:) (Variant A) — keine eigene URLSession (Phase 3, 03-01)
- ParakeetClient ruft `manager.ensureInstalled()` statt `DiarizerModels.downloadIfNeeded()` direkt — Manager ist Single-Source-of-Truth (D-16, Phase 3, 03-02)
- SettingsStore.parakeetDiarization didSet feuert manager.start() via Task @MainActor (D-01, Phase 3, 03-02)
- AppDelegate.bootstrap prewarmt Diarizer als detached MainActor-Task wenn parakeetDiarization persistiert (D-13/D-14, Phase 3, 03-02)
- DiarizerStatusBlock rendert vier visuell distinkte States (notInstalled / downloading / installed / failed) via switch über manager.state — Toggle wird im Downloading-State nicht disabled, sondern komplett ersetzt (D-03, D-18, Phase 3, 03-02)

### Open Todos

- Phase 3 diskutieren (`/gsd-discuss-phase 3`) — Diarization-UX
- UAT für Phase 1 (offen, kein Blocker für Phase 3):
  - Schlüsselbund-Roundtrip (Dummy-Key speichern → Schlüsselbund.app prüfen)
  - Legacy-Migration End-to-End (`defaults write … apiKey 'sk-legacy-123'` → App-Start → Migration)
  - TCC-Auto-Recovery (Permission entfernen → App starten → live aktivieren → Tap greift ohne Restart)

### Blockers

Keine.

## Session Continuity

**Letzte Aktion:** Phase 8 Plan-Phase abgeschlossen. UI-Phase 6/6 APPROVED (08-UI-SPEC.md), Research live-verifiziert (08-RESEARCH.md mit Apple-Doku-Sources + Open Questions Resolution), Patterns gemappt (08-PATTERNS.md, 13/13 NEW/MODIFY analogs), Validation-Strategie Nyquist-konform (08-VALIDATION.md mit doppeltem Protocol-Wrapping). 5 Plans erstellt + verified PASSED in Iteration 2 (1 Revision löste 2 BLOCKERs + 6 WARNINGs). AC-AVAIL-1/2/3 + 5 ROADMAP-Erfolgskriterien vollständig abgedeckt.

**Nächste Aktion:** `/gsd-execute-phase 8` — Wave 0 zuerst: 08-01 Spike löst 3 Open Questions (LanguageModelSession-Concurrency, GenerationError-Naming, prewarm-Signatur) live in Xcode → 08-RESEARCH-LIVE.md gating für Wave 1+. Phase 3 manual UAT bleibt offen, blockt Phase 8 nicht.

---
*Phase 1 abgeschlossen: 2026-04-30*
*Phase 2 abgeschlossen: 2026-05-01*
*Phase 3 Plans ausgefuehrt: 2026-05-01 (verification pending)*
