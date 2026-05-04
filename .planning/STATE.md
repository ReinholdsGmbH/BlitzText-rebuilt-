---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-04T00:00:00.000Z"
progress:
  total_phases: 12
  completed_phases: 2
  total_plans: 10
  completed_plans: 10
  percent: 100
---

# Project State: BlitzText

**Last updated:** 2026-05-04

## Project Reference

**Core Value:** Vom gedrückten Hotkey bis zum eingefügten Text wenige Sekunden — Text muss benutzbar sein, ohne nachzubearbeiten.

**Current Focus:** Phase 8 (Apple Foundation Rewrite-Backend) — IN PROGRESS (1/5 plans). Plan 08-01 Wave-0-Spike abgeschlossen: A1/A2/A6 live verifiziert, Wave 1 unblocked. Naechster Schritt: 08-02 (Wave 0 Foundation — Protocols + DeescalatedOutput + AppleFoundationError + SettingsStore-Erweiterung). Phase 3 verification (manual UAT) bleibt offen, blockt aber Phase 8 nicht.

## Current Position

Phase: 8 (Apple Foundation Rewrite-Backend) — EXECUTION IN PROGRESS
Plan: 1 of 5 — 08-01 Wave-0-Spike abgeschlossen

- **Milestone:** Sprecher-Profile + Stabilisierung
- **Phase:** Phase 8 ausführend — Wave 0 Spike (08-01: Live-Verifikation A1/A2/A6)
- **Plan:** 08-01 ✅ — A1 verified (LanguageModelSession ist final class, non-MainActor, nonisolated(nonsending)), A2 corrected (9 Cases mit Context-Payload, drei mehr als gedacht; .type existiert nicht), A6 corrected (prewarm ist sync, non-throwing — `session.prewarm()` statt `try? await ...`). Wave 1 unblocked.
- **Status:** Plan 08-01 complete (2 atomic commits: 0319688, acd92c3); 08-RESEARCH-LIVE.md ist Source-of-Truth für PIN(A1)/PIN(A2)/PIN(A6) für Wave 1+2.
- **Progress:** 2/6 phases complete (Phase 3 awaiting verification, Phase 8 in progress)

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
| Plan 08-01 Dauer | — | ~8 min, 2 Commits, 1 File created (08-RESEARCH-LIVE.md, 227 Zeilen, 3 PIN-Marker, A1 verified + A2/A6 corrected) |

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
- A1 verifiziert: LanguageModelSession ist final class, non-MainActor, respond ist nonisolated(nonsending) — kein @MainActor-Hop in Wave 1 nötig (Phase 8, 08-01)
- A2 korrigiert: GenerationError hat 9 Cases (alle mit Context-Payload), drei zusätzliche zu RESEARCH.md (unsupportedGuide, concurrentRequests, refusal); .type-Property existiert nicht — Switch über Cases ist Pflicht (Phase 8, 08-01)
- A6 korrigiert: prewarm(promptPrefix: Prompt? = nil) ist sync, non-throwing — `session.prewarm()` aufrufen, NICHT `try? await session.prewarm()`. 08-PATTERNS.md AppDelegate-Snippet muss in Wave 2 (08-04) entsprechend korrigiert werden (Phase 8, 08-01)
- Wave-0-Spike-Pattern: API-Verifikation via swiftc -typecheck Mini-Probes unter /tmp/ + Inspektion arm64e-apple-macos.swiftinterface (kanonische Apple-Source) — KEINE Production-Pollution (Phase 8, 08-01)

### Open Todos

- Phase 3 diskutieren (`/gsd-discuss-phase 3`) — Diarization-UX
- UAT für Phase 1 (offen, kein Blocker für Phase 3):
  - Schlüsselbund-Roundtrip (Dummy-Key speichern → Schlüsselbund.app prüfen)
  - Legacy-Migration End-to-End (`defaults write … apiKey 'sk-legacy-123'` → App-Start → Migration)
  - TCC-Auto-Recovery (Permission entfernen → App starten → live aktivieren → Tap greift ohne Restart)

### Blockers

Keine.

## Session Continuity

**Letzte Aktion:** Plan 08-01 (Wave 0 Spike) ausgeführt — A1/A2/A6 live gegen MacOSX26.4.sdk verifiziert. 08-RESEARCH-LIVE.md erstellt (227 Zeilen, 3 PIN-Marker + Wave-0-Sign-Off). A1 verified (LanguageModelSession non-MainActor), A2 corrected (9 Cases, alle mit Context, drei mehr als gedacht; .type existiert nicht), A6 corrected (prewarm sync non-throwing). 2 atomic Commits (0319688, acd92c3). Wave 1 unblocked.

**Nächste Aktion:** `/gsd-execute-phase 8` Plan 08-02 — Wave 0 Foundation: Protocols (FoundationAvailabilityProviding, LanguageModelInferring), DeescalatedOutput @Generable, AppleFoundationError, SettingsStore-Erweiterung (RewriteBackend, refreshFoundationAvailability), Availability-Tests. Wave-1-Plan (08-03) muss A2-Korrektur (3 zusätzliche GenerationError-Cases) im AppleFoundationError.from-Mapper berücksichtigen; Wave-2-Plan (08-04) den A6-Snippet-Fix (`session.prewarm()` statt `try? await session.prewarm()`).

---
*Phase 1 abgeschlossen: 2026-04-30*
*Phase 2 abgeschlossen: 2026-05-01*
*Phase 3 Plans ausgefuehrt: 2026-05-01 (verification pending)*
*Phase 8 Plan 01 ausgefuehrt: 2026-05-04*
