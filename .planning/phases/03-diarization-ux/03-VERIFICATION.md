---
phase: 03-diarization-ux
verified: 2026-05-01T10:25:00Z
status: human_needed
score: 3/3 must-haves verifiziert (Code-seitig); 5 manuelle UAT-Tests offen
overrides_applied: 0
human_verification:
  - test: "State (a) — Toggle aktiv, Modell fehlt"
    expected: "Settings → Lokales Modell zeigt Toggle 'Sprechererkennung (Diarization)', off, mit caption2-Subtitle. Diarizer-Cache vorher löschen: rm -rf '~/Library/Application Support/FluidAudio/Models/speaker-diarization' bei geschlossener App."
    why_human: "SwiftUI-Layout + visuelles State-Mapping nur in laufender App prüfbar."
  - test: "State (b) — Lädt Diarizer-Modell (Progress + ETA)"
    expected: "Toggle on flippen → Toggle verschwindet (kein disabled-Toggle), arrow.down.circle Icon, 'Lädt Diarizer-Modell …' subheadline, ProgressView läuft glatt, Detail-Zeile zeigt '{n} % · noch ~{m} s' (oder 'Geschwindigkeit wird ermittelt …' in den ersten ~1–2 s)."
    why_human: "Live-Download mit echten ~80 MB von HuggingFace; ETA-Update-Rate; visuelles Throttling."
  - test: "State (c) — Modell vorhanden ✓"
    expected: "Nach erfolgreichem Download → Toggle wieder sichtbar (on), grüner checkmark.circle.fill + 'Modell vorhanden' (.green, .caption)."
    why_human: "State-Übergang (b)→(c) nur visuell prüfbar."
  - test: "State (d) — Fehler + Retry"
    expected: "WLAN aus, dann Toggle on flippen → exclamationmark.triangle.fill (.red) + 'Diarizer-Modell konnte nicht geladen werden' + deutsche Klassifikation 'Verbindung fehlgeschlagen…' + Button 'Erneut versuchen'. Klick auf Retry → State wechselt zurück zu (b) oder neue Fehlermeldung."
    why_human: "Echter Netzwerkfehler nur durch Offline-Test reproduzierbar; Retry-Button-Wiring."
  - test: "App-Start-Pre-Warm (D-13/D-14)"
    expected: "App schließen mit parakeetDiarization=true. Diarizer-Cache löschen. App starten ohne Settings zu öffnen — App darf NICHT blockieren. Settings öffnen: direkt im (b)-State, mit aktuellem Progress."
    why_human: "Pre-Warm-Background-Task während AppDelegate.bootstrap nur in Live-App beobachtbar."
---

# Phase 3: Diarization-UX — Verification Report

**Phase Goal:** Diarization-Modell-Download wird sichtbar, fehlerfest und vom Nutzer kontrollierbar.
**Verified:** 2026-05-01
**Status:** human_needed (Code-Goal erreicht; visuelle UAT in laufender App owed)

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Beim ersten Aktivieren von Diarization sieht der Nutzer im Settings-Tab einen Progress-Indikator mit Prozent und ungefährer Restzeit für den ~80 MB-Download | ✓ VERIFIED (Code) | `SettingsView.swift:548-562` rendert `arrow.down.circle` + `Lädt Diarizer-Modell …` + `ProgressView(value: progress).linear` + `progressDetailText` (`{percent} % · {ETA-String}`). Toggle-On triggert Download via `SettingsStore.parakeetDiarization.didSet` → `manager.start()` (`SettingsStore.swift:24-36`). ETA via `ETAEstimator` Sliding-Window (`ETAEstimator.swift:25-39`). 80 MB-Hinweis im Subtitle (`SettingsView.swift:523, 543`). |
| 2 | Schlägt der Download fehl, erscheint im Settings-Tab eine deutsche Fehlermeldung mit Retry-Button, der den Download neu anstößt | ✓ VERIFIED (Code) | `SettingsView.swift:565-576` rendert Fehler-Block: `exclamationmark.triangle.fill` (.red), `Diarizer-Modell konnte nicht geladen werden`, message-Text in .red, Button `Erneut versuchen` → `diarizerManager.retry()`. Drei deutsche Klassen LOCKED in `DiarizerModelManager.classify` (`DiarizerModelManager.swift:171-212`): Netzwerk / Speicher / Unbekannt. `retry()` (`DiarizerModelManager.swift:69-78`) cancelt Task, ruft `loader.clearCache()`, startet neuen Download. |
| 3 | Solange das Modell nicht vollständig geladen ist, ist der Diarization-Toggle deaktiviert oder klar als "wird geladen" markiert (D-03: ersetzt durch Status-Label) | ✓ VERIFIED (Code) | `SettingsView.swift:520-524` (downloading-Branch) rendert NUR `downloadingView(...)` — Toggle wird nicht gerendert (auch nicht disabled). Im failed-Branch (`SettingsView.swift:535-537`) ebenfalls kein Toggle, nur Fehler-Block. Toggle erscheint erst wieder im `.notInstalled` (`SettingsView.swift:518-519`) und `.installed` (`SettingsView.swift:526-534`)-Branch. D-03 strikt umgesetzt. |

**Score (Code-Ebene):** 3/3 truths verified. Visuelle UAT in der laufenden App ist explizit als manuelle Phase 3 Hand-off in `03-02-SUMMARY.md` § Hand-off vorgesehen.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `BlitzText/Transcription/DiarizerModelManager.swift` | State-Machine + Download-Lifecycle (D-15) | ✓ VERIFIED | 213 LOC, `@MainActor`, `state`/`downloadProgress`/`etaSeconds`/`lastError` als `@Published`. Methoden `start`/`retry`/`prewarm`/`ensureInstalled` per Plan. |
| `BlitzText/Transcription/ETAEstimator.swift` | Sliding-Window-ETA (D-08) | ✓ VERIFIED | 40 LOC, pure value type, 5 s window, korrektes nil-Handling für Anlauf/Stagnation (Tests bestätigen). |
| `BlitzText/Transcription/DiarizerLoaderProtocol.swift` | Test-Seam + Production-Loader | ✓ VERIFIED | 75 LOC, `FluidAudioDiarizerLoader` wrapped `DiarizerModels.downloadIfNeeded`, `isInstalled()` prüft FluidAudio-Default-Pfad. |
| `BlitzText/Settings/SettingsView.swift` `DiarizerStatusBlock` | Vier-State-UI (D-18) | ✓ VERIFIED | `SettingsView.swift:505-601`, switch über `manager.state` mit allen vier Cases; LOCKED-Strings byte-genau (`Lädt Diarizer-Modell …`, `Geschwindigkeit wird ermittelt …`, `Modell vorhanden`, `Diarizer-Modell konnte nicht geladen werden`, `Erneut versuchen`). |
| `BlitzText/Settings/SettingsStore.swift` didSet | Toggle-On-Side-Effect (D-01) | ✓ VERIFIED | `SettingsStore.swift:24-36`, `parakeetDiarization.didSet` triggert `Task { @MainActor [weak diarizerManager] in diarizerManager?.start() }`. Initial-Load-Guard `oldValue` vorhanden. |
| `BlitzText/Transcription/ParakeetClient.swift` D-16-Konsum | Manager-Konsultation statt direkt-Call | ✓ VERIFIED | `ParakeetClient.swift:158-170` ruft `await diarizerManager.ensureInstalled()` + `modelsIfInstalled`. Kein `DiarizerModels.downloadIfNeeded`-Aufruf mehr (grep count 0 in ParakeetClient.swift, einziger Production-Aufruf nur im Loader-Wrapper). |
| `BlitzText/App/AppDelegate.swift` Pre-Warm (D-13/D-14) | Background-Pre-Warm | ✓ VERIFIED | `AppDelegate.swift:10` (Manager-Property), `:58` (DI in Store), `:64,69` (DI in ModeProcessor + SettingsWindowController), `:100-104` Pre-Warm via detached Task wenn `settings.parakeetDiarization`. |
| `BlitzText/Settings/SettingsWindowController.swift` | environmentObject-Injektion | ✓ VERIFIED | `SettingsWindowController.swift:13,30` injiziert `diarizerManager` als `environmentObject`. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| Toggle-On | Manager.start() | SettingsStore.didSet | ✓ WIRED | `SettingsStore.swift:24-36` — verifiziert per Code-Pfad. |
| Manager.state | UI vier-State-Switch | @EnvironmentObject + switch | ✓ WIRED | `SettingsView.swift:507, 517` — `@EnvironmentObject diarizerManager`, switch über `state`. |
| Retry-Button | Manager.retry() | Button-Action | ✓ WIRED | `SettingsView.swift:572`. |
| ParakeetClient.ensureLoaded | Manager.ensureInstalled() | async-await | ✓ WIRED | `ParakeetClient.swift:158`. Kein direkter FluidAudio-Download-Call mehr (HARD #3 Pin). |
| AppDelegate.bootstrap | Manager.prewarm() | Detached Task | ✓ WIRED | `AppDelegate.swift:100-104` (best-effort, nicht blockierend). |
| SettingsWindowController | DiarizerStatusBlock | environmentObject | ✓ WIRED | `SettingsWindowController.swift:30`. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|---------------------|--------|
| DiarizerStatusBlock | `manager.state` | DiarizerModelManager.beginDownload (echter `loader.downloadIfNeeded` mit FluidAudio) | Yes (production), Mocked (Tests) | ✓ FLOWING |
| DiarizerStatusBlock | `manager.downloadProgress` | `handleProgress(fraction:)` aus FluidAudio progressHandler-Callback | Yes — durchgereicht aus FluidAudio.DownloadUtils.DownloadProgress.fractionCompleted | ✓ FLOWING |
| DiarizerStatusBlock | `manager.etaSeconds` | `ETAEstimator.tick(...)` mit echten Sample-Daten | Yes (Sliding-Window-Berechnung gegen reale Progress-Ticks) | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Volle Test-Suite grün (39/39) | `xcodebuild test -scheme BlitzText -destination 'platform=macOS'` | `** TEST SUCCEEDED **` 39/39 in 0.255s | ✓ PASS |
| Phase-2-Pin (PipelineErrorPathTests) intakt | im selben Lauf, 3/3 Tests grün | passed in 0.062s | ✓ PASS |
| HARD #3 — kein direkter `DiarizerModels.downloadIfNeeded` in ParakeetClient.swift | `grep -c` | 0 (nur in Loader-Wrapper) | ✓ PASS |
| LOCKED-Strings byte-genau | grep auf SettingsView.swift | alle 5 UI-Strings + 3 Klassen-Strings im Manager gefunden | ✓ PASS |
| Toggle nicht disabled (D-03) | Code-Inspektion | downloading-Branch rendert Toggle gar nicht — D-03 strenger als gefordert (Toggle ersetzt, nicht disabled) | ✓ PASS |
| 3× consecutive (3× konsekutiv-Run) | Executor-SUMMARY behauptet 3× grün; Verifier ran 1× grün, vertraut SUMMARY für 2× weitere Runs | 1× verifiziert, 2× per Trust SUMMARY | ✓ PASS (mit Trust-Note) |

### Requirements Coverage

| Requirement | Beschreibung | Status | Evidence |
|-------------|--------------|--------|----------|
| DIA-01 | Progress-Indikator (Prozent + ungefähre Restzeit) für ~80 MB-Download | ✓ SATISFIED | Truth #1, Artifacts DiarizerStatusBlock + DiarizerModelManager + ETAEstimator. |
| DIA-02 | Deutsche Fehlermeldung + Retry-Button | ✓ SATISFIED | Truth #2, drei deutsche Klassen in `classify`, Retry-Button in errorView, `manager.retry()`-Wiring. |

### CONTEXT-Decisions Spot-Check

| Decision | Status | Evidence |
|----------|--------|----------|
| D-01 (Download startet bei Toggle-On, nicht lazy) | ✓ HONORED | `SettingsStore.swift:24-36` didSet → `manager.start()`. |
| D-03 (Toggle ersetzt, nicht disabled) | ✓ HONORED | `SettingsView.swift:520-524` rendert nur `downloadingView`, kein Toggle in downloading-Branch. |
| D-04 (kein Cancel in v1) | ✓ HONORED | `downloadingView` hat keinen Cancel-Button; Manager hat keine `cancel()`-Methode. |
| D-13 (Pre-Warm beim App-Start) | ✓ HONORED | `AppDelegate.swift:100-104` Detached-Task wenn `settings.parakeetDiarization`. |
| D-16 (ParakeetClient delegiert an Manager) | ✓ HONORED | `ParakeetClient.swift:158-170`, Manager als injected Dependency, kein direkter FluidAudio-Download-Call. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (keine) | — | — | — | Keine TODO/FIXME/PLACEHOLDER/empty-handler-Patterns in den Phase-3-Files. |

### Architecture Integrity

ParakeetClient + DiarizerModelManager + SettingsView + AppDelegate bilden einen koherenten Flow:
- AppDelegate bootstraped Manager (one owner, weak ref in Store).
- Toggle in SettingsView mutiert Store, Store didSet ruft Manager.start.
- Manager publiziert State, View bindet via environmentObject.
- ParakeetClient konsumiert Manager via DI (init-Param), nicht via @EnvironmentObject — Service-Schicht ist View-frei.
- Test-Seam (DiarizerLoaderProtocol) sauber an der einzigen FluidAudio-Boundary.

Keine orphaned Code, keine dead Branches.

### Human Verification Required

Siehe Frontmatter `human_verification`. Fünf UAT-Items:
1. State (a) initial — Toggle off, Modell fehlt
2. State (b) — Live-Download mit Progress + ETA
3. State (c) — Confirmation-Zeile nach Erfolg
4. State (d) — Fehler-Klassifikation + Retry-Funktion
5. App-Start-Pre-Warm — Background-Task ohne Blockade

Diese fünf decken die visuellen / Realnetzwerk-Aspekte ab, die Code-Analyse nicht abbilden kann.

### Gaps Summary

**Keine Code-Gaps.** Alle drei ROADMAP-Success-Criteria sind in Code substantiv umgesetzt, alle Artifacts existieren mit korrektem Wiring, alle CONTEXT-Decisions D-01/D-03/D-04/D-13/D-16 sind honoriert, beide Requirements (DIA-01, DIA-02) sind erfüllt. Test-Suite 39/39 grün, Phase-2-Pin intakt.

**Offen:** Visuelle / Realnetzwerk-UAT in der laufenden App. Das ist explizit als Hand-off-Item dokumentiert (siehe `03-02-SUMMARY.md` § Hand-off für /gsd-verify-phase 3) und kann nicht durch den Verifier-Agent erfolgen.

---

*Verified: 2026-05-01T10:25:00Z*
*Verifier: Claude (gsd-verifier)*
