---
phase: 08-apple-foundation-rewrite-backend
verified: 2026-05-04T12:00:00Z
status: human_needed
score: 19/19 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 18/19
  gaps_closed:
    - "CR-01 (AppDelegate observer leak): Token stored in didBecomeActiveObserver, removeObserver called in applicationWillTerminate, dead code removed"
    - "CR-02 (cold-boot auto-fallback): refreshFoundationAvailability now calls applyAutoFallbackIfNeeded unconditionally, didAutoFallbackToOpenAI reset on .available"
    - "Truth #19 (57 tests 3x consecutive green): DiarizerModelManagerTests.testRetry now uses delta-assert"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "UAT-1 Banner Variante A (Apple Intelligence deaktiviert)"
    expected: "Symbol/Heading/Detail/Link sichtbar, Variante D bei API-Key + auto-Picker-Switch"
    why_human: "SwiftUI-Visual-Render auf realer Apple-Intelligence-Hardware nicht automatisierbar"
  - test: "UAT-2 Banner Variante B (modelNotReady)"
    expected: "kein Orange, ProgressView, Erneut prüfen-Button sichtbar"
    why_human: "Visual-State-Inspection auf realer Hardware"
  - test: "UAT-3 Variante D Auto-Fallback-Zeile"
    expected: "orange + cloud-Symbol"
    why_human: "Visual-Render"
  - test: "UAT-4 HUD-BackendBadge Foundation/OpenAI/Plain"
    expected: "apple.logo bei Foundation, cloud bei OpenAI, kein Badge bei plain blitztext, sichtbar in recording->transcribing->rewriting"
    why_human: "HUD-Render-Behavior nur on-device verifizierbar"
  - test: "UAT-5 didBecomeActiveNotification-Refresh <= 2 s"
    expected: "Settings-Switch loest Banner-Update ohne App-Restart"
    why_human: "System-Activation-Cycle braucht reale System-UI"
  - test: "UAT-6 End-to-End-Latenz <= 3 s"
    expected: "PROJECT.md-Ziel: Hotkey bis eingefuegter Text unter 3 Sekunden mit Apple Foundation Backend"
    why_human: "Performance-Messung auf realer Apple-Intelligence-Hardware"
  - test: "UAT-7 Foundation-Output bleibt deutsch (3/3 Wiederholungen)"
    expected: "Sprachbias-Marker greift, Output ist deutsch"
    why_human: "Inferenz-Qualitaet nur mit echtem Foundation-Modell pruefbar"
---

# Phase 8: Apple Foundation Rewrite-Backend -- Gap-Closure Verification

**Phase Goal:** Apple Foundation Models (macOS 26+) als lokale Default-Alternative zu gpt-4o-mini im Rewrite-Pfad; OpenAI als expliziter User-Override.
**Verified:** 2026-05-04
**Status:** human_needed
**Re-verification:** Yes -- after closure of 3 blockers from 08-VERIFICATION-FINAL.md

---

## Re-Verification Focus

This verification targets the 3 blockers from 08-VERIFICATION-FINAL.md:

1. CR-01 -- AppDelegate NotificationCenter observer leak
2. CR-02 -- cold-boot auto-fallback state-equality guard
3. Truth #19 -- full suite 3x consecutive green without flake

All three were addressed by plans 08-06, 08-07, and 08-08 (commits 619d510, e5da445, 97ba68e, 76b8eff).

---

## 1. CR-01: AppDelegate Observer Leak (Plan 08-06, commit 619d510)

### Evidence -- AppDelegate.swift

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| `private var didBecomeActiveObserver: NSObjectProtocol?` property | present | Line 23: `private var didBecomeActiveObserver: NSObjectProtocol?` | VERIFIED |
| `didBecomeActiveObserver = NotificationCenter.default.addObserver(...)` | token stored | Line 126: token assigned | VERIFIED |
| `[weak settingsStore]` capture removed | 0 occurrences | grep-c = 0 | VERIFIED |
| `_ = settingsStore` dead code removed | 0 occurrences | grep-c = 0 | VERIFIED |
| `removeObserver(token)` in `applicationWillTerminate` | present | Lines 189-191: `if let token = self.didBecomeActiveObserver { NotificationCenter.default.removeObserver(token); self.didBecomeActiveObserver = nil }` | VERIFIED |
| `didBecomeActiveObserver` total occurrences | >= 3 | 5 (declaration + doc + bootstrap comment + assignment + willTerminate) | VERIFIED |
| `removeObserver` occurrences | >= 1 | 3 (doc comment + line 190 call + comment reference) | VERIFIED |
| AC-AVAIL-2 refresh behaviour unchanged | closure still calls `refreshFoundationAvailability()` | Lines 135-137: `self?.settingsStore.refreshFoundationAvailability()` | VERIFIED |

**CR-01: CLOSED.** Token is stored, observer is removed in `applicationWillTerminate`, dead code is eliminated.

---

## 2. CR-02: Cold-Boot Auto-Fallback (Plan 08-07, commits e5da445 + 97ba68e)

### Evidence -- SettingsStore.swift

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| `if new != foundationAvailability` guard removed | 0 occurrences | 0 | VERIFIED |
| `applyAutoFallbackIfNeeded()` called unconditionally | call after `foundationAvailability = new` without guard | Line 156: unconditional call after line 152 assignment | VERIFIED |
| `didAutoFallbackToOpenAI = false` reset on `.available` | present | Line 154: inside `if new == .available { didAutoFallbackToOpenAI = false }` | VERIFIED |
| Self-idempotency guard preserved | `guard !didAutoFallbackToOpenAI else { return }` present | Line 168: present | VERIFIED |
| `applyAutoFallbackIfNeeded()` occurrences | >= 2 | 5 (doc comment mentions x3 + 1 call + function definition) | VERIFIED |

### Evidence -- AppleFoundationAvailabilityTests.swift

| Test | Purpose | Status |
|------|---------|--------|
| `test_refresh_initialBootstrap_unavailableMatchesInitialState_triggersAutoFallback` | Pins CR-02 cold-boot edge case: Initial-State == Provider-Result == .modelNotReady must still trigger auto-fallback | EXISTS (line 97) |
| `test_refresh_returnsToAvailable_resetsAutoFallbackMarker` | Pins recovery path: .available resets didAutoFallbackToOpenAI for future re-trigger | EXISTS (line 122) |
| `test_refresh_idempotent_selfIdempotencyGuardPreventsReTrigger` | Updated from old state-equality semantics to self-idempotency guard semantics | EXISTS (line 78) |

Total AppleFoundationAvailabilityTests: 9 (7 original + 2 new CR-02 regression tests).

**CR-02: CLOSED.** Unconditional call + .available reset + 2 regression tests.

---

## 3. Truth #19: Full Suite 3x Consecutive Green (Plan 08-08, commit 76b8eff)

### Evidence -- DiarizerModelManagerTests.swift

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| `let clearsBefore = loader.clearCacheCallCount` | 1 occurrence (delta snapshot) | grep-c = 1 | VERIFIED |
| `loader.clearCacheCallCount - clearsBefore` | 1 occurrence (delta assert) | grep-c = 1 | VERIFIED |
| `XCTAssertEqual(loader.clearCacheCallCount, 1` | 0 occurrences (old absolute assert removed) | grep-c = 0 | VERIFIED |
| D-11 pin comment preserved | grep-c "D-11" >= 1 | 3 | VERIFIED |
| Production code (DiarizerModelManager.swift) unmodified | plan explicitly prohibits production changes | commit 76b8eff touches only DiarizerModelManagerTests.swift | VERIFIED |

### 3-Run Baseline (from 08-08-SUMMARY.md)

| Run | Result | Duration | Failures |
|-----|--------|----------|----------|
| 1 | PASSED | ~14s | 0 |
| 2 | PASSED | ~33s | 0 |
| 3 | PASSED | ~13s | 0 |

Total tests per run: 57. Flakes: 0.

**Truth #19: CLOSED.** Delta-assert applied; 3x consecutive green documented in 08-08-SUMMARY.md.

---

## 4. Observable Truths (Full 19/19)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | RESEARCH-LIVE A1/A2/A6 verified | VERIFIED | 08-RESEARCH-LIVE.md exists; 08-01-SUMMARY shows corrections |
| 2 | `FoundationAvailabilityProviding` protocol + Live-Impl + Fake | VERIFIED | FoundationAvailabilityProvider.swift + FakeFoundationAvailabilityProvider.swift |
| 3 | `LanguageModelInferring` protocol with `respond` + `respondGuided<T: Generable>` | VERIFIED | LanguageModelInferring.swift |
| 4 | `DeescalatedOutput` `@Generable` struct with `neutralText` | VERIFIED | DeescalatedOutput.swift |
| 5 | `RewriteBackend` enum (`.appleFoundation` default, `.openAI`) | VERIFIED | SettingsStore.swift:280-290 |
| 6 | `refreshFoundationAvailability()` calls `applyAutoFallbackIfNeeded()` unconditionally | VERIFIED | SettingsStore.swift:150-156 -- no state-equality guard |
| 7 | `applyAutoFallbackIfNeeded` self-idempotent (`!didAutoFallbackToOpenAI` guard) | VERIFIED | SettingsStore.swift:168 |
| 8 | Tests API-Key NEVER in Keychain (`_testApiKeyOverride`) | VERIFIED | SettingsStore.swift + all tests use `_testApiKeyOverride` |
| 9 | `AppleFoundationRewriteClient` pre-inference guard (AC-AVAIL-1) | VERIFIED | AppleFoundationRewriteClient.swift:31,52 |
| 10 | `.unavailable` throws WITHOUT inference call (`respondCallCount == 0` asserts) | VERIFIED | 6 client tests |
| 11 | Plus dispatches to `respond`, Rant to `respondGuided<DeescalatedOutput>` | VERIFIED | ModeProcessor.swift:196-220 |
| 12 | `humanReadable` maps `AppleFoundationError` to German user message | VERIFIED | ModeProcessor.swift:332 |
| 13 | Modi-Tab two backend pickers | VERIFIED | SettingsView.swift:93,116 |
| 14 | Banner 4 variants (A/B/C + D auto-fallback) | VERIFIED | FoundationAvailabilityBanner.swift:29-31,118-122 |
| 15 | HUD `BackendBadge` (apple.logo/cloud) during recording/transcribing/rewriting; not for plain blitztext | VERIFIED | RecordingHUDController.swift:27,102-118,145 |
| 16 | `AppDelegate.bootstrap()` calls `refreshFoundationAvailability()` BEFORE hotkey setup | VERIFIED | AppDelegate.swift:102 (before line 119 `hotkeyManager.start()`) |
| 17 | `didBecomeActiveNotification` observer (AC-AVAIL-2) -- token stored, removed on terminate | VERIFIED | AppDelegate.swift:23 (property), 126 (assignment), 189-191 (removeObserver) |
| 18 | Pre-warm via `Task.detached` at `.available` + Foundation active for >= 1 mode | VERIFIED | AppDelegate.swift:108-116 |
| 19 | Full suite 3x consecutive green without flake | VERIFIED | Delta-assert applied (76b8eff); 3-run table in 08-08-SUMMARY.md: 3/3 PASSED, 0 failures, 0 flakes |

**Score: 19/19 truths VERIFIED.**

---

## 5. Acceptance Criteria (3/3)

| AC | Description | Status |
|----|-------------|--------|
| AC-AVAIL-1 | Defensive availability check before every inference call, German errors, no silent OpenAI fallback | VERIFIED |
| AC-AVAIL-2 | Transition `modelNotReady -> available` without app restart | VERIFIED |
| AC-AVAIL-3 | README/Docs: Apple Intelligence not Siri, MDM realism | VERIFIED |

---

## 6. Anti-Pattern Scan (Gap-Closure Files)

Files touched in plans 08-06/07/08: `AppDelegate.swift`, `SettingsStore.swift`, `DiarizerModelManagerTests.swift`, `AppleFoundationAvailabilityTests.swift`.

| Pattern | Hits | Severity |
|---------|------|----------|
| TODO/FIXME/PLACEHOLDER | 0 | -- |
| placeholder/coming soon | 0 | -- |
| `return null`/`return []` empty stubs | 0 | -- |
| Hardcoded empty props | 0 | -- |
| `_ = settingsStore` dead code | 0 | Resolved by CR-01 fix |
| `[weak settingsStore]` dead capture | 0 | Resolved by CR-01 fix |
| Missing `removeObserver` for block observer | 0 | Resolved by CR-01 fix |

No anti-patterns found in gap-closure code.

---

## 7. Human Verification Required

The following 7 items require on-device Apple Intelligence hardware. They were documented in 08-VERIFICATION-FINAL.md as structural UAT expectations. They are NOT newly failing -- they have always been human-only items.

### 1. UAT-1: Banner Variante A (Apple Intelligence deaktiviert)

**Test:** Open Settings on a device where Apple Intelligence is disabled. Inspect the FoundationAvailabilityBanner.
**Expected:** Symbol, Heading, Detail text, and Systemeinstellungen-Link visible; when API-Key is present and auto-fallback fired, Variante D (orange + cloud) appears and the Picker switches automatically.
**Why human:** SwiftUI visual render on real Apple Intelligence hardware is not automatable.

### 2. UAT-2: Banner Variante B (modelNotReady)

**Test:** On a device where Apple Intelligence is downloading/initializing, inspect the banner.
**Expected:** No orange color, ProgressView spinning, "Erneut pruefen"-Button visible.
**Why human:** Visual state inspection requires real hardware state.

### 3. UAT-3: Banner Variante D Auto-Fallback-Zeile

**Test:** With API-Key present and Foundation unavailable, trigger auto-fallback. Inspect banner.
**Expected:** Orange tint, cloud symbol, German explanation of the auto-switch.
**Why human:** Visual render.

### 4. UAT-4: HUD BackendBadge Foundation/OpenAI/Plain

**Test:** Record a short dictation with each backend active (Plus mode with Foundation, Plus mode with OpenAI, Blitztext plain mode).
**Expected:** apple.logo symbol visible during transcribing/rewriting for Foundation; cloud symbol for OpenAI; no badge for plain blitztext.
**Why human:** HUD render behavior only verifiable on-device.

### 5. UAT-5: didBecomeActiveNotification-Refresh <= 2 s

**Test:** With Settings open, toggle Apple Intelligence off and back on in System Settings. Return to BlitzText.
**Expected:** Banner updates within 2 seconds of returning to the app, without an app restart.
**Why human:** System-activation cycle requires real system UI.

### 6. UAT-6: End-to-End Latency <= 3 s

**Test:** With Apple Foundation as active backend, press hotkey and speak a short sentence requiring rewrite.
**Expected:** Hotkey to clipboard insertion under 3 seconds (PROJECT.md core value).
**Why human:** Performance measurement requires real Apple Intelligence inference on qualifying hardware.

### 7. UAT-7: Foundation Output Stays German (3/3 Repetitions)

**Test:** Dictate German text requiring rewrite 3 times with Foundation backend active.
**Expected:** All 3 outputs are in German (language-bias marker in prompt is effective).
**Why human:** Inference quality is only verifiable with the real Foundation model.

---

## 8. Gaps Summary

No automated gaps remain. All 3 blockers from 08-VERIFICATION-FINAL.md are resolved:

**CR-01 (Observer Leak):** `private var didBecomeActiveObserver: NSObjectProtocol?` exists at AppDelegate.swift:23. Token assigned at line 126. `removeObserver(token)` called in `applicationWillTerminate` at lines 189-191. Dead captures `[weak settingsStore]` and `_ = settingsStore` are gone (both grep to 0).

**CR-02 (Cold-Boot Fallback):** `refreshFoundationAvailability()` in SettingsStore.swift:150-156 calls `applyAutoFallbackIfNeeded()` unconditionally -- `if new != foundationAvailability` guard removed (greps to 0). `didAutoFallbackToOpenAI = false` reset on `.available` at line 154. Two regression tests pin the fix.

**Truth #19 (3x Green):** `testRetry_clearsCacheAndRestartsDownload` uses delta-assert (`let clearsBefore` + `clearCacheCallCount - clearsBefore == 1`). Old absolute assert removed (greps to 0). 08-08-SUMMARY.md documents 3/3 consecutive PASSED runs, 57 tests, 0 failures.

Phase goal is code-complete. Status is `human_needed` because 7 on-device UAT items require Apple Intelligence hardware -- these were always expected and are not new regressions.

---

*Verified: 2026-05-04*
*Verifier: Claude (gsd-verifier, re-verification mode)*
*Previous: 08-VERIFICATION-FINAL.md (gaps_found, 18/19)*
