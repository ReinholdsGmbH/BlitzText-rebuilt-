---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-19T11:35:52.275Z"
progress:
  total_phases: 21
  completed_phases: 7
  total_plans: 26
  completed_plans: 26
  percent: 29
---

# Project State: BlitzText

**Last updated:** 2026-05-04

## Project Reference

**Core Value:** Vom gedrückten Hotkey bis zum eingefügten Text wenige Sekunden — Text muss benutzbar sein, ohne nachzubearbeiten.

**Current Focus:** Phase 04 — sprecher-profile-core (nächste offene Phase)

## Current Position

Phase: 07 (standard-hotkeys-und-eigene-hotkeys) — VERIFIED ✅

- **Milestone:** Sprecher-Profile + Stabilisierung
- **Phase:** Phase 7 UAT abgeschlossen — 6 Tests pass, 4 skipped (obsolet nach Rework), 2 Issues geschlossen
- **Status:** Phase 7 vollständig abgeschlossen
- **Progress:** [██████████] 100%

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
| Plan 08-02 Dauer | — | ~12 min, 3 Commits, 7 Files created + 1 modified (4 Production-Source + 3 Test-Files + SettingsStore +120 LOC; 7 AC-AVAIL-1/2 Tests, volle Suite 46/46 grün) |
| Plan 08-03 Dauer | — | ~9 min, 2 Commits, 3 Files created + 2 modified (AppleFoundationRewriteClient 93 LOC, ModeProcessor +35 LOC, 11 Tests in 2 Files; volle Suite 57/57 grün, 3× consecutive ohne Flake) |
| Plan 08-04 Dauer | — | ~6 min, 3 Commits, 1 File created + 3 modified (FoundationAvailabilityBanner 133 LOC mit 4 State-Varianten + SettingsView 2 Picker + Banner-Mount + RecordingHUDController BackendBadge + Window-Width 268 + AppDelegate Foundation-Refresh + Pre-Warm + didBecomeActive-Observer; volle Suite 57/57 grün) |

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
- FoundationAvailability als app-internes Equatable-Enum (nicht direkt SystemLanguageModel.Availability) — entkoppelt UI/Test-Code von Apple-API-Drift, @unknown default → .deviceNotEligible konservativ (Phase 8, 08-02)
- Runtime-Only @Published State (foundationAvailability + didAutoFallbackToOpenAI sind NICHT in Snapshot persistiert) — AC-AVAIL-1 fordert frische Verfügbarkeitsprüfung bei jedem Bootstrap (T-08-02-03, Phase 8, 08-02)
- applyAutoFallbackIfNeeded ist self-idempotent via `guard !didAutoFallbackToOpenAI` — schaltet maximal einmal pro App-Lifecycle, schützt gegen Multi-Fire didBecomeActiveNotification (WARNING 7 / T-08-02-07, Phase 8, 08-02)
- BLOCKER 2 Fix: #if DEBUG _testApiKeyOverride im apiKey-Getter UND -Setter; Tests schreiben nie in echte Keychain (T-08-02-06, Phase 8, 08-02)
- AppleFoundationRewriteClient exposed zwei Methoden — `rewrite` (Plain Session, Plus) + `rewriteGuided` (Guided Generation, Rant). Mode-Switch lebt im ModeProcessor (single source of truth), nicht im Client (Phase 8, 08-03)
- ModeProcessor Guided-Pfad nutzt `as? AppleFoundationRewriteClient`-Cast statt neues Protocol — minimal-invasiv, robust gegen Test-Fakes (Plain-Fallback) ohne API-Breakage; Production-Pfad-Test verifiziert Cast-Greift mit echtem Client (WARNING 4) (Phase 8, 08-03)
- Sprachbias-Marker im Pipeline-Code (ModeProcessor.runPipeline) statt im Client — policy-decision (deutsche UI-Prämisse), nicht Inferenz-Mechanik (T-08-03-06, Phase 8, 08-03)
- Test-Isolation gegen UserDefaults-Pollution: AppleFoundationAvailabilityTests.makeStore resettet Backend-Slots explizit nach SettingsStore.init — verteidigt gegen Test-Reihenfolge-Effekte (Phase 8, 08-03)
- FoundationAvailabilityBanner rendert via flachem `case .unavailable(.xyz)`-Switch (3 Varianten + Auto-Fallback-Overlay D) — `@ViewBuilder` content + optional autoFallbackRow; Variante D bei deviceNotEligible suppressed (UI-SPEC Zeile 216, Phase 8, 08-04)
- Privacy-Hint unter Backend-Picker ist immer sichtbar bei .openAI ohne availability-Suppression — Privacy-Marker bleibt gerade beim Auto-Fallback-Fall sichtbar (WARNING 6, Phase 8, 08-04)
- AppDelegate didBecomeActive-Observer nutzt Doppel-Capture `[weak self, weak settingsStore]` mit `Task { @MainActor in self?.settingsStore.refreshFoundationAvailability() }` — Plan-AC fordert weak settingsStore, Swift-6 strict-concurrency verlangt self-Capture für non-Sendable Cross-Actor-Aufruf (Phase 8, 08-04)
- HUD bleibt während .transcribing und .rewriting sichtbar (nicht nur .recording) — BackendBadge erscheint VOR dem Cloud-Call, User kann abbrechen (UI-SPEC Surface 3, Phase 8, 08-04)

### Open Todos

- Phase 3 diskutieren (`/gsd-discuss-phase 3`) — Diarization-UX
- UAT für Phase 1 (offen, kein Blocker für Phase 3):
  - Schlüsselbund-Roundtrip (Dummy-Key speichern → Schlüsselbund.app prüfen)
  - Legacy-Migration End-to-End (`defaults write … apiKey 'sk-legacy-123'` → App-Start → Migration)
  - TCC-Auto-Recovery (Permission entfernen → App starten → live aktivieren → Tap greift ohne Restart)

### Blockers

Keine.

## Session Continuity

**Letzte Aktion:** Phase 7 UAT abgeschlossen (2026-05-19). Rework: Carbon/KeyboardShortcuts-Toggle-Layer durch CGEventTap-Double-Tap-Erkennung (300 ms Fenster) ersetzt — fn-Modifier zweimal schnell = Toggle. ToggleHotkeyRow + ConflictWarningBanner entfernt. HotkeyStateMachineTests aktualisiert (16 Tests, 3 neue Double-Tap-Tests). ToggleHotkeyTests.swift gelöscht.

**Nächste Aktion:** Phase 4 — Sprecher-Profile Core (`/gsd-discuss-phase 4` oder `/gsd:plan-phase 4`).

---
*Phase 1 abgeschlossen: 2026-04-30*
*Phase 2 abgeschlossen: 2026-05-01*
*Phase 3 Plans ausgefuehrt: 2026-05-01 (verification pending)*
*Phase 8 Plan 01 ausgefuehrt: 2026-05-04*
*Phase 8 Plan 02 ausgefuehrt: 2026-05-04*
*Phase 8 Plan 03 ausgefuehrt: 2026-05-04*
*Phase 8 Plan 04 ausgefuehrt: 2026-05-04*
*Phase 7 verifiziert: 2026-05-19*
