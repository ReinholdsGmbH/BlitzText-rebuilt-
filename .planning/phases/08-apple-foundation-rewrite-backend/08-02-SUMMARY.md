---
phase: 08-apple-foundation-rewrite-backend
plan: 02
subsystem: rewrite
tags: [swift, macos, apple-foundation-models, di-seams, settings, generable]

requires:
  - phase: 08-apple-foundation-rewrite-backend
    provides: 08-01 PIN(A1)/PIN(A2) — LanguageModelSession non-MainActor, GenerationError 9 Cases mit Context-Payload
provides:
  - FoundationAvailabilityProviding-Protocol + SystemLanguageModelAvailabilityProvider Live-Impl (Wave 1 + 2 konsumieren via DI-Slot)
  - LanguageModelInferring-Protocol mit respond + respondGuided<T: Generable> (Wave 1 AppleFoundationRewriteClient hängt daran)
  - DeescalatedOutput @Generable Schema (1 Feld, neutralText)
  - AppleFoundationError LocalizedError mit 9 Cases + from(FoundationAvailability) factory; Marker-Substrings "Apple Intelligence" + "Systemeinstellungen" für Wave-1-Test-Asserts
  - RewriteBackend-Enum + per-Mode-Mapping (rewriteBackendForPlus/Rant) + foundationAvailability-State + refreshFoundationAvailability() + applyAutoFallbackIfNeeded() (self-idempotent)
  - #if DEBUG _testApiKeyOverride-Hook in SettingsStore.apiKey (BLOCKER 2 / T-08-02-06)
  - FakeFoundationAvailabilityProvider + FakeLanguageModelInferring (Test-Seams für Wave 1)
  - 7 Availability-Tests (AC-AVAIL-1 vier Cases + AC-AVAIL-2 Übergang + WARNING 7 Self-Idempotency)
affects:
  - 08-03-PLAN (Wave 1 Client) — kann jetzt LanguageModelInferring + AppleFoundationError direkt konsumieren
  - 08-04-PLAN (Wave 2 UI) — kann jetzt foundationAvailability + didAutoFallbackToOpenAI + RewriteBackend-Picker rendern

tech-stack:
  added: []
  patterns:
    - "DI-Seam-Pattern für Apple-System-Singletons (FoundationAvailabilityProviding analog DiarizerLoaderProtocol)"
    - "@Generable Schema für strukturierten Output (DeescalatedOutput)"
    - "Self-Idempotency-Guard mit @Published Boolean-Flag (didAutoFallbackToOpenAI) gegen Multi-Fire-Notifications"
    - "Runtime-Only @Published Felder (NICHT in Snapshot-Codable) für State, der bei jedem Bootstrap frisch evaluiert werden muss"
    - "#if DEBUG In-Memory-Override für Keychain-bypassende Tests"

key-files:
  created:
    - BlitzText/Rewrite/FoundationAvailabilityProvider.swift
    - BlitzText/Rewrite/LanguageModelInferring.swift
    - BlitzText/Rewrite/DeescalatedOutput.swift
    - BlitzText/Rewrite/AppleFoundationError.swift
    - BlitzTextTests/Support/FakeFoundationAvailabilityProvider.swift
    - BlitzTextTests/Support/FakeLanguageModelInferring.swift
    - BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift
  modified:
    - BlitzText/Settings/SettingsStore.swift
    - BlitzText.xcodeproj (xcodegen-regen, neue Source-Files registriert)

key-decisions:
  - "FoundationAvailability-Modell als app-internes Equatable-Enum (nicht direkt SystemLanguageModel.Availability) — entkoppelt UI-/Test-Code von Apple-API-Drift, @unknown default → .deviceNotEligible (Pitfall 2 konservativ)"
  - "LanguageModelInferring liefert respond + respondGuided<T: Generable> als generische Protocol-Methoden — ein Protocol, beide Modi (Plus + Rant)"
  - "foundationAvailability + didAutoFallbackToOpenAI sind Runtime-Only (NICHT in Snapshot persistiert) — AC-AVAIL-1 fordert frischen State bei jedem Bootstrap (T-08-02-03 mitigated)"
  - "applyAutoFallbackIfNeeded ist self-idempotent via guard !didAutoFallbackToOpenAI (WARNING 7 / T-08-02-07) — auch bei Multi-Fire didBecomeActiveNotification oder zwischen-State-Wandern unter unavailable-Reasons"
  - "BLOCKER 2 Fix: #if DEBUG _testApiKeyOverride im apiKey-Getter UND -Setter; Tests verwenden den Hook unconditional (auch bei apiKey == \"\") damit der Keychain-Pfad nie betreten wird (T-08-02-06)"

requirements-completed: [AC-AVAIL-1, AC-AVAIL-2]

duration: ~12min
completed: 2026-05-04
---

# Phase 08 Plan 02: Wave 0 Foundation Summary

**FoundationAvailabilityProviding + LanguageModelInferring + DeescalatedOutput @Generable + AppleFoundationError + SettingsStore-Erweiterung (RewriteBackend, foundationAvailability, refreshFoundationAvailability, applyAutoFallbackIfNeeded mit Self-Idempotency-Guard) — Wave 1+2 sind unblocked, AC-AVAIL-1/2 testlich abgedeckt (7/7 grün).**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-04T09:30Z
- **Completed:** 2026-05-04
- **Tasks:** 3
- **Files created:** 7 (4 Production-Source, 3 Test-Support/Test)
- **Files modified:** 2 (SettingsStore.swift, BlitzText.xcodeproj via xcodegen)
- **Tests:** 7 neue Tests (AppleFoundationAvailabilityTests); volle Suite 46/46 grün
- **LOC produktiv (neu):** ~144 (4 Files); SettingsStore +120 LOC; Tests + Fakes ~150 LOC

## Accomplishments

- **Vier neue Production-Files in BlitzText/Rewrite/:**
  - `FoundationAvailabilityProvider.swift` — Protocol + Live-Impl mit `@unknown default → .deviceNotEligible` (Pitfall 2)
  - `LanguageModelInferring.swift` — Protocol mit `respond` + `respondGuided<T: Generable>`; `LiveLanguageModelInferring` allokiert per-Request frische `LanguageModelSession` (PIN(A1): non-MainActor, kein Hop)
  - `DeescalatedOutput.swift` — `@Generable struct` mit 1 Feld (`neutralText`) + deutsche `@Guide`-Description
  - `AppleFoundationError.swift` — `LocalizedError` mit 9 Cases; `from(FoundationAvailability)`-Factory mit Marker-Substrings "Apple Intelligence" + "Systemeinstellungen"
- **SettingsStore-Erweiterung:** `RewriteBackend`-Enum, per-Mode `@Published` (Plus + Rant), Runtime-Only `foundationAvailability` + `didAutoFallbackToOpenAI`, DI-Slot `availabilityProvider`, `refreshFoundationAvailability()`, `applyAutoFallbackIfNeeded()` mit Self-Idempotency-Guard, additive Snapshot-Migration (Optional-Felder mit `?? .appleFoundation`-Default), `#if DEBUG _testApiKeyOverride`-Hook im apiKey-Getter UND -Setter
- **Test-Fakes:** `FakeFoundationAvailabilityProvider` (mutable state + callCount), `FakeLanguageModelInferring` (Result-Antworten + respondCallCount + respondGuidedCallCount + lastInput/Instructions)
- **AppleFoundationAvailabilityTests:** 7 `@MainActor`-Tests, alle deterministisch, kein Keychain-Touch:
  - 4 Cases AC-AVAIL-1 (modelNotReady-initial, appleIntelligenceNotEnabled+ApiKey, appleIntelligenceNotEnabled-ohne-ApiKey, deviceNotEligible+ApiKey)
  - 1 Test AC-AVAIL-2 (modelNotReady → available ohne App-Restart)
  - 2 Tests Self-Idempotency (refresh-mit-gleichem-State + WARNING-7 multi-fire-mit-unavailable-Wandern)
- **xcodebuild test:** volle Suite 46/46 grün

## Task Commits

Drei Tasks atomisch committet:

1. **Task 1: Foundation seams + @Generable schema + error mapper** — `b903df1` (feat)
2. **Task 2: SettingsStore extension (RewriteBackend + Foundation availability)** — `75356ee` (feat)
3. **Task 3: Foundation availability fakes + 7 AC-AVAIL-1/2 tests** — `974b301` (test)

## Files Created/Modified

### Production (BlitzText/Rewrite/, BlitzText/Settings/)

- `BlitzText/Rewrite/FoundationAvailabilityProvider.swift` (NEU, 42 LOC)
- `BlitzText/Rewrite/LanguageModelInferring.swift` (NEU, 30 LOC)
- `BlitzText/Rewrite/DeescalatedOutput.swift` (NEU, 12 LOC)
- `BlitzText/Rewrite/AppleFoundationError.swift` (NEU, 60 LOC)
- `BlitzText/Settings/SettingsStore.swift` (modifiziert, 165 → 284 LOC, +120)

### Tests (BlitzTextTests/Support/, BlitzTextTests/Rewrite/)

- `BlitzTextTests/Support/FakeFoundationAvailabilityProvider.swift` (NEU, 19 LOC)
- `BlitzTextTests/Support/FakeLanguageModelInferring.swift` (NEU, 36 LOC)
- `BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift` (NEU, 96 LOC)

### Build-System

- `BlitzText.xcodeproj` — via `xcodegen generate` regeneriert (neue Source-Files in BlitzText- und BlitzTextTests-Targets registriert)

## Decisions Made

- **`FoundationAvailability` als app-internes Enum** (nicht direkt `SystemLanguageModel.Availability` reichen): entkoppelt UI-/Test-Code von Apple-API-Drift; `@unknown default → .deviceNotEligible` mappt konservativ auf den restriktivsten Fall (kein stiller Auto-Fallback).
- **Per-Request `LanguageModelSession`-Allokation** in `LiveLanguageModelInferring` (kein app-wide Caching): RESEARCH.md Anti-Pattern, vermeidet Stale-Context und Race-Conditions zwischen parallelen Modi.
- **Runtime-Only Availability-State**: `foundationAvailability` und `didAutoFallbackToOpenAI` sind `@Published`, aber **NICHT** im Snapshot. AC-AVAIL-1 fordert frische Verfügbarkeitsprüfung bei jedem Bootstrap (T-08-02-03).
- **Self-Idempotency via `guard !didAutoFallbackToOpenAI`**: `applyAutoFallbackIfNeeded()` schaltet maximal einmal pro App-Lifecycle. Schützt gegen Multi-Fire `didBecomeActiveNotification` und gegen State-Wandern zwischen zwei `unavailable`-Reasons (WARNING 7 / T-08-02-07).
- **`_testApiKeyOverride`-Hook im Setter UND Getter**: Defense-in-Depth gegen versehentliche `store.apiKey = "..."`-Calls aus Test-Helpern. Ist Override aktiv (auch leerer String), bleibt der Keychain-Pfad versperrt.
- **Test-Helper setzt `_testApiKeyOverride` IMMER** (auch bei `apiKey == ""`): verhindert, dass auf Dev-/CI-Maschinen mit existierendem real-Key der Test fälschlich Auto-Fallback auslöst (Bug bei erstem Test-Run gefangen).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Test-Helper-Bug] makeStore setzte `_testApiKeyOverride` nur bei nicht-leerem apiKey-Argument**

- **Found during:** Task 3, erster Test-Run
- **Issue:** Plan-Code-Skizze für `makeStore` hatte `if !apiKey.isEmpty { store._testApiKeyOverride = apiKey }`. Wenn ein Test "ohne API-Key"-Verhalten prüft (`apiKey: ""`), bleibt `_testApiKeyOverride == nil`, der Getter liest aus echter Keychain — und auf der Dev-Maschine lag dort ein real-Key (weil ich bewusst keinen Keychain-Wipe für Tests will). Test `test_refresh_appleIntelligenceNotEnabled_withoutApiKey_doesNotAutoFallback` schlug damit fälschlich fehl: "openAI" statt "appleFoundation".
- **Fix:** `_testApiKeyOverride` wird unconditional gesetzt (`store._testApiKeyOverride = apiKey`, auch leerer String). Damit bleibt der Keychain-Pfad in jedem Test versperrt. Dokumentiert mit Doc-Comment im Test-Helper.
- **Files modified:** `BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift` (makeStore-Helper)
- **Commit:** `974b301` (Task 3, im selben Commit wie der initiale Test-Code)
- **Verification:** Re-Run nach Fix → 7/7 grün; volle Suite 46/46 grün.

**2. [Rule 1 — AC-Grep-Regex-Konflikt] AC fordert `grep -c 'guard !didAutoFallbackToOpenAI' = 1`, Doc-Comment enthielt aber den exakten Pattern-String**

- **Found during:** Task 2, Acceptance-Greps
- **Issue:** Mein erster Doc-Comment lautete `Self-Idempotency: \`guard !didAutoFallbackToOpenAI\` als allererste Anweisung …` — der Backtick-Inline-Code-Block matched genauso wie die echte Code-Anweisung; grep-count war 2 statt erwartet 1.
- **Fix:** Doc-Comment umformuliert ohne Backtick-Pattern (`der \`didAutoFallbackToOpenAI\`-Guard als allererste Anweisung …`). Test-Wert nun exakt 1.
- **Files modified:** `BlitzText/Settings/SettingsStore.swift` (Doc-Comment vor `applyAutoFallbackIfNeeded`)
- **Commit:** `75356ee` (Task 2, im selben Commit wie der Code)

---

**Total deviations:** 2 auto-fixed (Rule 1 — beide Plan-/Skizze-Bugs, kein Scope Creep)
**Impact on plan:** Beide Deviations sind unmittelbare Test-/AC-Fixes vor Commit; das Plan-Outcome (Wave 0 Foundation-Bausteine + 7 grüne Tests) bleibt vollständig erfüllt.

## Issues Encountered

- **Keine echten Inferenz-Calls in dieser Phase** — Wave-0 Foundation validiert ausschließlich Compile-Contract + State-Maschine. Echte `LanguageModelSession.respond()`-Calls (Latenz, Sprachbias, Output-Qualität) sind UAT-Aufgaben in `/gsd-verify-phase 8`, nicht hier.
- **`xcodegen generate` musste zweimal laufen** — einmal nach Task 1 (neue `BlitzText/Rewrite/`-Files), einmal nach Task 3 (neuer `BlitzTextTests/Rewrite/`-Folder). xcodegen ist deterministisch und idempotent — jeder Re-Generate produziert denselben pbxproj.

## Threat Mitigation Status

| Threat | Status | Evidence |
|--------|--------|----------|
| T-08-02-01 (stale availability) | mitigated (partial — Wave 1 ergänzt pre-inference re-check) | `refreshFoundationAvailability()` bei jedem Aufruf live aus provider gelesen; `foundationAvailability` ist Runtime-Only |
| T-08-02-02 (silent auto-fallback) | mitigated (state-side; UI-side in 08-04) | `didAutoFallbackToOpenAI` setzt sichtbares Flag; Wave 2 rendert Banner-Variante D |
| T-08-02-03 (snapshot persistence of stale state) | mitigated | `grep -A2 'private struct Snapshot' \| grep -c foundationAvailability` = 0 verifiziert |
| T-08-02-04 (Generable schema drift) | partially mitigated | Schema minimal (1 Feld); `.emptyGuidedOutput`-Branch in `AppleFoundationError` vorbereitet, Wave 1 ergänzt trim+empty-check |
| T-08-02-05 (test hook leaks to Release) | mitigated | `#if DEBUG`-Wrapper an Declaration + Getter-Branch + Setter-Branch (3 Wrapper, alle in einem Source-File) |
| T-08-02-06 (tests write to real Keychain) | mitigated | `grep -c 'store\.apiKey = "sk-'` = 0; Helper setzt `_testApiKeyOverride` unconditional |
| T-08-02-07 (auto-fallback multi-fire) | mitigated | `guard !didAutoFallbackToOpenAI` allererste Anweisung in `applyAutoFallbackIfNeeded`; Test `test_applyAutoFallback_calledTwiceDirectly_setsFlagOnce` verifiziert |

## User Setup Required

None — Wave 0 Foundation ist reine DI-Seam-Implementierung + Test-Coverage. Keine externen Services, keine Permission-Prompts.

## Next Phase Readiness

**Wave 1 (08-03 Client + Dispatch) ist UNBLOCKED:**

- `LanguageModelInferring`-Protocol existiert; `AppleFoundationRewriteClient` (08-03) kann es als Konstruktor-Argument nehmen.
- `AppleFoundationError` existiert mit allen 9 Cases; Wave-1-Mapper `from(GenerationError)` (laut PIN(A2) in 08-RESEARCH-LIVE.md) braucht 9 Switch-Branches + `@unknown default` und mappt auf bestehende `AppleFoundationError`-Cases.
- `DeescalatedOutput` existiert; Wave-1 Rant-Mode kann `respondGuided(input:, instructions:, type: DeescalatedOutput.self)` direkt aufrufen.
- `SettingsStore.rewriteBackend(for: Mode)` existiert; Wave-1 `ModeProcessor`-Refactor kann pro Mode dispatchen.
- `FakeLanguageModelInferring` existiert mit Result-Antwort + Aufruf-Zähler — Wave-1-Tests können Pre-Canned-Responses und Fehler injizieren.

**Wave 2 (08-04 UI) ist UNBLOCKED:**

- `foundationAvailability` + `didAutoFallbackToOpenAI` als `@Published` — UI kann via `@ObservedObject store: SettingsStore` direkt observen.
- `RewriteBackend`-Enum mit `label`-Property — `Picker`-Source-of-Truth.
- Marker-Substrings in `AppleFoundationError.from(_:)` ("Apple Intelligence", "Systemeinstellungen") sind Test-Anchor für Wave-2-Banner-Tests.
- **HINWEIS für 08-04:** PIN(A6) aus 08-RESEARCH-LIVE.md verlangt `session.prewarm()` (sync, non-throwing) statt `try? await session.prewarm()` — Plan-Snippet aus 08-PATTERNS.md AppDelegate-Section ist falsch und MUSS beim Implement angepasst werden.

**Keine Blocker für 08-03/08-04.** Phase 3 manuelles UAT bleibt offen, blockt aber Phase 8 nicht.

## Self-Check: PASSED

- Files exist:
  - `BlitzText/Rewrite/FoundationAvailabilityProvider.swift` — FOUND
  - `BlitzText/Rewrite/LanguageModelInferring.swift` — FOUND
  - `BlitzText/Rewrite/DeescalatedOutput.swift` — FOUND
  - `BlitzText/Rewrite/AppleFoundationError.swift` — FOUND
  - `BlitzTextTests/Support/FakeFoundationAvailabilityProvider.swift` — FOUND
  - `BlitzTextTests/Support/FakeLanguageModelInferring.swift` — FOUND
  - `BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift` — FOUND
- Commits exist:
  - `b903df1` (Task 1) — FOUND in `git log`
  - `75356ee` (Task 2) — FOUND in `git log`
  - `974b301` (Task 3) — FOUND in `git log`
- Tests:
  - AppleFoundationAvailabilityTests 7/7 — PASSED
  - Volle Suite (46 Tests) — PASSED
- Acceptance-Greps:
  - `grep -c '_testApiKeyOverride' SettingsStore.swift` = 5 (≥ 3) — PASSED
  - `grep -c '#if DEBUG' SettingsStore.swift` = 4 (≥ 2) — PASSED
  - `grep -c 'guard !didAutoFallbackToOpenAI' SettingsStore.swift` = 1 — PASSED
  - `grep -c 'store\.apiKey = "sk-' AppleFoundationAvailabilityTests.swift` = 0 — PASSED
  - `grep -c '^    func test_' AppleFoundationAvailabilityTests.swift` = 7 — PASSED
  - Snapshot enthält foundationAvailability NICHT (Runtime-Only verifiziert) — PASSED

---
*Phase: 08-apple-foundation-rewrite-backend*
*Completed: 2026-05-04*
