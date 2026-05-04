---
status: gaps_found
phase: 08
must_haves_verified: 18/19
ac_verified: 3/3
test_runs_green: 0
test_runs_total: 2
test_failures:
  - test: BlitzTextTests/DiarizerModelManagerTests/testRetry_clearsCacheAndRestartsDownload
    file: BlitzTextTests/Diarizer/DiarizerModelManagerTests.swift:113
    message: 'XCTAssertEqual failed: ("2") is not equal to ("1") — retry() muss clearCache() aufrufen (D-11)'
    note: Phase-3-Test, nicht durch Phase-8-Code verursacht; widerspricht aber 08-VERIFICATION.md "test_runs_green: 3"
human_verification:
  - test: UAT-1 Banner Variante A (Apple Intelligence deaktiviert)
    expected: Symbol/Heading/Detail/Link sichtbar, Variante D bei API-Key + auto-Picker-Switch
    why_human: SwiftUI-Visual-Render auf realer Apple-Intelligence-Hardware nicht automatisierbar
  - test: UAT-2 Banner Variante B (modelNotReady)
    expected: kein Orange, ProgressView, "Erneut prüfen"-Button
    why_human: Visual-State-Inspection auf realer Hardware
  - test: UAT-3 Variante D Auto-Fallback-Zeile
    expected: orange + cloud-Symbol
    why_human: Visual-Render
  - test: UAT-4 HUD-BackendBadge Foundation/OpenAI/Plain
    expected: apple.logo bei Foundation, cloud bei OpenAI, kein Badge bei plain blitztext, sichtbar in recording→transcribing→rewriting
    why_human: HUD-Render-Behavior nur on-device verifizierbar
  - test: UAT-5 didBecomeActiveNotification-Refresh ≤ 2 s
    expected: Settings-Switch löst Banner-Update ohne App-Restart
    why_human: System-Activation-Cycle braucht reale System-UI
  - test: UAT-6 End-to-End-Latenz ≤ 3 s
    expected: PROJECT.md-Ziel
    why_human: Performance-Messung auf realer Apple-Intelligence-Hardware
  - test: UAT-7 Foundation-Output bleibt deutsch (3/3 Wiederholungen)
    expected: Sprachbias-Marker greift
    why_human: Inferenz-Qualität nur mit echtem Foundation-Modell prüfbar
review_blockers_open:
  - id: CR-01
    file: BlitzText/App/AppDelegate.swift:124-137
    issue: NotificationCenter-Observer wird nie entfernt — Leak + potenzieller Use-After-Free im XCTest-Host
    severity: blocker
  - id: CR-02
    file: BlitzText/Settings/SettingsStore.swift:145-170
    issue: applyAutoFallbackIfNeeded greift initial nicht (state-equality-guard maskiert Privacy-Invariante beim Erst-Bootstrap mit hardcoded .modelNotReady-Default)
    severity: blocker
overrides: []
---

# Phase 8: Apple Foundation Rewrite-Backend — Final Verification Report

**Phase Goal (ROADMAP.md L121):** Apple Foundation Models (macOS 26+) als lokale Default-Alternative zu gpt-4o-mini im Rewrite-Pfad; OpenAI als expliziter User-Override.

**Verified:** 2026-05-04
**Verifier:** gsd-verifier (goal-backward, adversarial)
**Mode:** Final/supplemental verification (08-VERIFICATION.md von 08-05 enthielt bereits `status: partial`)

---

## 1. Goal-Backward Truth Verification

### 1.1 ROADMAP-Erfolgskriterien (5/5 — Code-Pfade)

| # | Erfolgskriterium | Status | Evidence |
|---|------------------|--------|----------|
| 1 | `AppleFoundationRewriteClient` implementiert `RewriteService`, `RewriteBackend`-Enum in `SettingsStore` | VERIFIED | `BlitzText/Rewrite/AppleFoundationRewriteClient.swift:14` (`final class AppleFoundationRewriteClient: RewriteService`); `BlitzText/Settings/SettingsStore.swift:274-277` (`enum RewriteBackend` cases `.appleFoundation`, `.openAI`) |
| 2 | Pro Mode unabhängig wählbar | VERIFIED | `SettingsStore:24-25` Plus/Rant @Published; `SettingsView.swift:93,116` zwei Picker; `rewriteBackend(for:)`/`setRewriteBackend(_:for:)` lookup-Helper |
| 3 | Plus = Plain, Rant = Guided | VERIFIED | `AppleFoundationRewriteClient.swift:31` plain `respond`; L50 `func rewriteGuided(...) → respondGuided<DeescalatedOutput>`; `ModeProcessor.swift:215` Cast-Branch ruft `rewriteGuided` |
| 4 | App-Start `availability`-Check + Auto-Fallback + deutsche Erklärung | VERIFIED (mit BLOCKER-Caveat CR-02) | `AppDelegate.swift:97` Bootstrap-Refresh; `FoundationAvailabilityBanner.swift:29-31,51` deutsche Variants A/B/C + Systemeinstellungen-Link |
| 5 | HUD zeigt subtilen Backend-Indikator | VERIFIED | `RecordingHUDController.swift:102-118,145` `showsBackendBadge`/`backendSymbol` (`apple.logo`/`cloud`) + Show-while-transcribing/rewriting |

### 1.2 Acceptance Criteria (3/3 — Phase-spezifisch in 08-CONTEXT.md, NICHT in REQUIREMENTS.md)

**Wichtige Klarstellung:** AC-AVAIL-1/2/3 sind **phase-lokale Acceptance Criteria** aus `08-CONTEXT.md` § Acceptance Criteria. Sie erscheinen NICHT in `.planning/REQUIREMENTS.md` (Phase 8 ist milestone-erweiternd, kein v1-Mapping per ROADMAP.md L302). Das ist konsistent mit dem Phase-Frontmatter `requirements: [AC-AVAIL-1, AC-AVAIL-2]` in PLAN-Files.

| AC | Beschreibung | Status | Evidence |
|----|--------------|--------|----------|
| AC-AVAIL-1 | Defensive Verfügbarkeitsprüfung vor jedem Inferenz-Call, deutsche Fehler, kein silent OpenAI-Fallback | VERIFIED | `AppleFoundationRewriteClient.swift:31,52` Pre-Inference-Guard (Plain + Guided); `AppleFoundationAvailabilityTests.swift` 7 Tests; `AppleFoundationRewriteClientTests.swift` 6 Tests (3× unavailable + Plain + Guided + emptyGuidedOutput) |
| AC-AVAIL-2 | Übergang `modelNotReady → available` ohne App-Restart | VERIFIED | `AppleFoundationAvailabilityTests.swift::test_refresh_modelNotReady_to_available_updatesPublishedState`; `AppDelegate.swift:124-137` `didBecomeActiveNotification`-Observer |
| AC-AVAIL-3 | README/Doku: Apple Intelligence ≠ Siri, MDM-Realitätscheck | VERIFIED | `README.md:66-89` neue Sektion „Rewrite-Backend: Apple Foundation Models"; nennt Apple Intelligence (9×), Siri (5×), unabhängig (2×), MDM (1×) |

### 1.3 Plan-Frontmatter Must-Haves (kumuliert aus 08-01..08-05)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | RESEARCH-LIVE A1/A2/A6 verifiziert | VERIFIED | `08-RESEARCH-LIVE.md` existiert; `08-01-SUMMARY` zeigt A2/A6 corrected, A1 verified |
| 2 | `FoundationAvailabilityProviding`-Protocol + Live-Impl + Fake | VERIFIED | `FoundationAvailabilityProvider.swift:7,15,38`; `FakeFoundationAvailabilityProvider.swift` |
| 3 | `LanguageModelInferring`-Protocol mit `respond` + `respondGuided<T: Generable>` | VERIFIED | `LanguageModelInferring.swift:11-13,25` |
| 4 | `DeescalatedOutput` `@Generable`-struct mit `neutralText` | VERIFIED | `DeescalatedOutput.swift:8-11` |
| 5 | `RewriteBackend`-Enum (`.appleFoundation` Default, `.openAI`) | VERIFIED | `SettingsStore.swift:274-277` |
| 6 | `refreshFoundationAvailability()` persistiert State + triggert `applyAutoFallbackIfNeeded` | VERIFIED (caveat: nur bei State-Wechsel — siehe CR-02) | `SettingsStore.swift:145-151` |
| 7 | `applyAutoFallbackIfNeeded` self-idempotent (`!didAutoFallbackToOpenAI`-Guard) | VERIFIED | `SettingsStore.swift:162` |
| 8 | Tests-API-Key NIE in Keychain (`_testApiKeyOverride`) | VERIFIED | `SettingsStore.swift:63,72,78`; AC-Test grep: `store.apiKey = "sk-` count = 0 |
| 9 | `AppleFoundationRewriteClient` Pre-Inference-Guard (AC-AVAIL-1) | VERIFIED | `AppleFoundationRewriteClient.swift:31,52` |
| 10 | Bei `.unavailable` throw OHNE Inferenz-Call (`respondCallCount == 0` asserts) | VERIFIED | 6 Client-Tests prüfen explizit `respondCallCount == 0` |
| 11 | Plus dispatched zu `respond`, Rant zu `respondGuided<DeescalatedOutput>` | VERIFIED | `ModeProcessor.swift:196-220` switch + Cast-Branch |
| 12 | `humanReadable` mappt `AppleFoundationError` → deutsche User-Message | VERIFIED | `ModeProcessor.swift:332` `as? AppleFoundationError`-Branch |
| 13 | Modi-Tab zwei Backend-Picker | VERIFIED | `SettingsView.swift:93,116` |
| 14 | Banner 4 Varianten (A/B/C + D Auto-Fallback) | VERIFIED | `FoundationAvailabilityBanner.swift:29-31,118-122` |
| 15 | HUD `BackendBadge` (apple.logo/cloud) während recording/transcribing/rewriting; nicht bei plain blitztext | VERIFIED | `RecordingHUDController.swift:27,102-118,145` |
| 16 | `AppDelegate.bootstrap()` ruft `refreshFoundationAvailability()` VOR Hotkey-Setup | VERIFIED | `AppDelegate.swift:97` |
| 17 | `didBecomeActiveNotification`-Observer (AC-AVAIL-2) | VERIFIED | `AppDelegate.swift:124-137` |
| 18 | Pre-Warm via `Task.detached` bei `.available` + Foundation aktiv für ≥1 Mode | VERIFIED | `AppDelegate.swift:108-109` |
| 19 | **Volle Suite 3× consecutive grün ohne Flake** (08-VERIFICATION.md Behauptung) | **FAILED** | Test-Run am 2026-05-04 reproduzierbar: 1/57 rot (`DiarizerModelManagerTests.testRetry_clearsCacheAndRestartsDownload`) |

**Score: 18/19 Truths VERIFIED.**

---

## 2. Test-Suite Verification

**Behauptung 08-VERIFICATION.md:** „57 Tests, 3× consecutive grün ohne Flake (Run 1: 23s, Run 2: 8s, Run 3: 6s)".

**Ergebnis bei Re-Verification (verifier-Run 2026-05-04 ~10:33 UTC+2):** Reproduzierbar **56/57 grün, 1 Failure**.

| Run | Result | Failures | Detail |
|-----|--------|----------|--------|
| 1 (full suite) | FAILED | 1 | `DiarizerModelManagerTests.testRetry_clearsCacheAndRestartsDownload` (line 113) |
| 2 (isolated) | FAILED | 1 | Gleicher Test, gleicher Assert |

```
XCTAssertEqual failed: ("2") is not equal to ("1") — retry() muss clearCache() aufrufen (D-11)
```

**Klassifikation:** Der Test gehört zu Phase 3 (Diarization-Modell-Manager). Letzte Modifikation: Phase-3-Commits (`da4a4e9`, `f747853`, `a39e637`). Phase 8 modifiziert KEINE Diarizer-Files. Daher:

- ✗ **NICHT** durch Phase-8-Code verursacht
- ✗ Aber: 08-VERIFICATION.md `test_runs_green: 3` ist FAKTISCH FALSCH zum Verifikationszeitpunkt
- ⚠️ Möglicherweise State-Leak in Diarizer-Tests aus früherem Run-Kontext oder Apple-Modell-Cache-Drift seit Phase-8-Abschluss

**Empfehlung:** Phase-3-Owner verifizieren, ob `testRetry_clearsCacheAndRestartsDownload` eine echte Regression oder ein hardware-/cache-state-abhängiges Setup-Issue ist. Phase 8 sollte nicht auf "complete" gesetzt werden, solange die volle Suite nicht grün ist (Phase-2/3-3×-green-Konvention wird sonst gebrochen).

---

## 3. Code-Review-Blocker (08-REVIEW.md)

08-REVIEW.md (depth: standard, 2026-05-04) listet **2 BLOCKER + 7 WARNING + 4 INFO**. Beide BLOCKER sind in der Codebase **noch offen** (kein Fix-Commit zwischen Review und Verification):

### CR-01: NotificationCenter-Observer-Leak (BlitzText/App/AppDelegate.swift:124-137)

```swift
NotificationCenter.default.addObserver(
    forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
) { [weak self, weak settingsStore] _ in ... }
```

- Rückgabe-Token (`NSObjectProtocol`) wird nicht gespeichert.
- `applicationWillTerminate` ruft kein `removeObserver`.
- `[weak settingsStore]`-Capture ist toter Code (Closure nutzt `self?.settingsStore`, nicht den Capture).
- Im XCTest-Host akkumulieren stale Observer über mehrere Test-Runs.
- **Risk:** Use-After-Free, Multi-Fire mit stale State.

### CR-02: applyAutoFallback bricht beim Erst-Bootstrap (BlitzText/Settings/SettingsStore.swift:145-170)

```swift
@Published var foundationAvailability: FoundationAvailability = .unavailable(.modelNotReady)  // hardcoded initial

func refreshFoundationAvailability() {
    let new = availabilityProvider.currentAvailability()
    if new != foundationAvailability {  // ← state-equality-Guard
        foundationAvailability = new
        applyAutoFallbackIfNeeded()
    }
}
```

- Initial-Wert ist hardcoded `.unavailable(.modelNotReady)`.
- Wenn `currentAvailability()` zufällig `.unavailable(.modelNotReady)` zurückliefert (häufiger Cold-Boot-Fall), feuert der Inequality-Check **nicht**.
- `applyAutoFallbackIfNeeded()` wird nicht aufgerufen, obwohl alle anderen Bedingungen (API-Key + `.appleFoundation`-Backend) erfüllt sind.
- **Risk:** Privacy-Invariante bricht beim allerersten Bootstrap — User landet im Limbo (alle Rewrite-Calls werfen `AppleFoundationError.unavailable`, obwohl der Auto-Fallback laufen sollte).
- **Direkt relevant** für ROADMAP-Erfolgskriterium 4 ("Default-Backend automatisch auf OpenAI gestellt"): das Erfolgskriterium ist code-pfad-vorhanden, aber im Cold-Boot-Edge-Case nicht zuverlässig wirksam.

**Note (Workflow-Konvention):** `gsd-code-review` ist advisory; Review-Blocker fail nicht automatisch die Phase. Aber: CR-02 berührt direkt eine ROADMAP-SC-Garantie und sollte vor `Complete` adressiert werden — nicht als Goal-Failure, sondern als Privacy-Risk-Restschuld.

---

## 4. Anti-Pattern Scan (Phase-8-Files)

Stichproben in 11 source + 5 test files (08-REVIEW.md `Files Reviewed`):

| Pattern | Hits | Severity | Note |
|---------|------|----------|------|
| `TODO`/`FIXME`/`PLACEHOLDER` in Phase-8-Code | 0 | — | Sauber |
| `placeholder`/`coming soon`/`will be here` | 0 | — | Sauber |
| `return null`/`return []`/empty stubs in Production | 0 | — | Sauber |
| Hardcoded empty Props an UI-Mount-Sites | 0 | — | Banner/Picker bekommen `EnvironmentObject(settings)` mit echtem State |
| `console.log`/`print`-only handlers | 0 | — | Pipeline-Errors gehen über `humanReadable(_:)` |
| `@unknown default` in switches gegen Apple-API-Drift | 4 | INFO | `FoundationAvailabilityProvider.swift:38`, `AppleFoundationRewriteClient.swift:86`, etc. — defensiv, gewünscht |

**Keine Stub-Smell-Funde in Phase-8-Code.**

---

## 5. Data-Flow Trace (Level 4)

| Artifact | Datenquelle | Echte Daten? | Status |
|----------|-------------|--------------|--------|
| `FoundationAvailabilityBanner` | `settings.foundationAvailability` (`@Published`) | Ja — `SystemLanguageModelAvailabilityProvider.currentAvailability()` ruft `SystemLanguageModel.default.availability` 1:1 | FLOWING |
| Backend-Picker (Plus/Rant) | `$settings.rewriteBackendForPlus`/`Rant` | Ja — Two-Way-Binding auf `@Published`-State, persistiert via Snapshot | FLOWING |
| `BackendBadge` | `settings.rewriteBackend(for: mode)` mit `mode` aus `processor.state` | Ja — deterministisch aus Settings + ModeProcessor-State | FLOWING |
| `AppleFoundationRewriteClient.rewrite` | `availabilityProvider.currentAvailability()` + `inferring.respond(...)` | Ja in Production (`SystemLanguageModelAvailabilityProvider` + `LiveLanguageModelInferring` als Default-DI); Tests via Fakes | FLOWING |
| `applyAutoFallback` Initial-Trigger | `foundationAvailability` initial = hardcoded `.modelNotReady` | ⚠️ STATIC bei Cold-Boot (CR-02): wenn Provider auch `.modelNotReady` liefert → Inequality-Check bricht den Fallback-Pfad | DISCONNECTED |

---

## 6. Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Volle Test-Suite grün | `xcodebuild test -scheme BlitzText -destination 'platform=macOS,arch=arm64'` | 56/57, 1 failure | FAIL |
| `AppleFoundationAvailabilityTests` | `-only-testing:BlitzTextTests/AppleFoundationAvailabilityTests` (geprüft via voller Suite-Output) | 7/7 grün | PASS |
| `AppleFoundationRewriteClientTests` | dito | 6/6 grün | PASS |
| `RewriteBackendDispatchTests` | dito | 5/5 grün | PASS |
| Phase-8-spezifische Tests | 7+6+5 = 18 Tests | 18/18 grün | PASS |
| README AC-AVAIL-3 Marker | `grep -E "Apple Intelligence|Siri|unabhängig|MDM" README.md` | 17 hits | PASS |

**Phase-8-spezifischer Code: 18/18 Tests grün.** Der einzige rote Test gehört zu Phase 3.

---

## 7. Gaps Summary (gaps_found Status)

```yaml
gaps:
  - truth: "Volle Test-Suite 3× consecutive grün ohne Flake (08-VERIFICATION.md test_runs_green: 3)"
    status: failed
    reason: "Test DiarizerModelManagerTests.testRetry_clearsCacheAndRestartsDownload schlägt reproduzierbar fehl. Phase-3-Test, NICHT durch Phase-8-Code verursacht — aber widerspricht der Phase-8-Verifikations-Behauptung. Die Phase-2/3-3×-green-Konvention ist gebrochen."
    artifacts:
      - path: BlitzTextTests/Diarizer/DiarizerModelManagerTests.swift
        issue: "Line 113 Assert: ('2') ≠ ('1') — retry() muss clearCache() aufrufen (D-11)"
    missing:
      - "Phase-3-Owner-Triage: echte Regression oder Setup-State-Leak?"
      - "08-VERIFICATION.md test_runs_green muss von 3 auf real-state aktualisiert werden ODER der Test muss grün sein bevor Phase 8 ROADMAP-Status auf Complete geht"

deferred: []
```

---

## 8. Status: gaps_found

**Begründung:**

- **Goal Achievement (Code-Pfad):** Alle 5 ROADMAP-SCs + alle 3 phase-lokalen ACs sind im Code vorhanden und an 18/18 Phase-8-spezifischen Tests verifizierbar. Das **Goal an sich** ist erreicht.
- **Test-Stabilität:** Eine zentrale Behauptung der Verifikation (3×-green-Konvention) ist nicht reproduzierbar.
- **Code-Review-Restschuld:** 2 BLOCKER aus 08-REVIEW (CR-01 Observer-Leak, CR-02 Initial-Bootstrap-Auto-Fallback-Lücke) sind ungelöst. CR-02 berührt eine ROADMAP-SC-Garantie.
- **UAT:** 7 manuelle UI-Tests pending — strukturell erwartet (Plan 08-05 ist `autonomous: false`).

**Empfehlung:** Phase 8 NICHT auf ROADMAP-Status `Complete` setzen, bis:

1. Diarizer-Test-Failure geklärt (Phase-3-Triage oder Test-Update)
2. 08-VERIFICATION.md `test_runs_green` an realen Stand angepasst
3. CR-01 + CR-02 entweder gefixt ODER explizit als „accepted technical debt" mit Override geloggt
4. UAT-Checkliste 11/11 abgehakt (User-Aufgabe via `/gsd-verify-phase 8`)

Die Code-Pfade sind solide — die Phase ist **nicht bereit für Closure**, ist aber in einem belastbaren Zustand für die nächste Iteration.

---

*Verified: 2026-05-04*
*Verifier: gsd-verifier (goal-backward, adversarial mindset)*
*Supplements: 08-VERIFICATION.md (status: partial) from plan 08-05*
