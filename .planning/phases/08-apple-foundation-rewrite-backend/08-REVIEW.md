---
status: issues
phase: 08
critical_count: 2
warning_count: 7
info_count: 4
depth: standard
reviewed: 2026-05-04
---

# Phase 8: Code Review Report — Apple Foundation Rewrite-Backend

**Reviewed:** 2026-05-04
**Depth:** standard
**Files Reviewed:** 11 source + 5 test
**Status:** issues_found

## Summary

Sauber strukturierte Phase mit guter DI-Disziplin (Test-Seams, Fakes, Snapshot-Migration). Die kritischen Privacy-Invarianten (kein Auto-Fallback ohne API-Key, Pre-Inference-Guard) sind in Code und Tests verankert. Trotzdem zwei echte BLOCKER: ein NotificationCenter-Observer-Leak in `AppDelegate` und eine inkonsistente Initial-State-Logik im `SettingsStore`, die `applyAutoFallbackIfNeeded` beim allerersten Bootstrap nicht-idempotent zwischen App-Starts macht. Zusätzlich mehrere semantisch korrekte aber fragile Stellen, die unter Last drift-anfällig sind.

---

## BLOCKER Issues

### CR-01: NotificationCenter-Observer wird nie entfernt — Leak + potenzielle Use-After-Free im Test-Host

**File:** `BlitzText/App/AppDelegate.swift:124-137`

Der `addObserver(forName: NSApplication.didBecomeActiveNotification, …)`-Block-basierte Observer wird mit `[weak self, weak settingsStore]` registriert, aber das Rückgabe-Token (`NSObjectProtocol`) wird **nicht gespeichert** und im `applicationWillTerminate` **nicht entfernt**. `AppDelegate` hat auch keinen `deinit` mit `NotificationCenter.default.removeObserver(self)`. Im XCTest-Hosted-Run werden mehrere `AppDelegate`-Instanzen instantiiert, jede registriert ihren eigenen Observer, und keiner wird aufgeräumt — über mehrere Test-Runs akkumulieren stale Observer, die jedes Mal `MainActor`-Tasks gegen schon-deallocated SettingsStores schedulen.

Zusätzlich: das `_ = settingsStore` ist ein Capture-Marker ohne Effekt — der eigentliche Aufruf nutzt `self?.settingsStore`, also den implizit re-fetched Store, **nicht** den im Closure capturten. Damit ist der `[weak settingsStore]`-Capture toter Code.

**Fix:** Token in Property speichern, in `applicationWillTerminate` removeObserver, toten Capture entfernen.

---

### CR-02: `applyAutoFallbackIfNeeded` greift initial nicht — Privacy-Invariante bricht beim allerersten Bootstrap

**File:** `BlitzText/Settings/SettingsStore.swift:145-170`

`refreshFoundationAvailability()` ruft `applyAutoFallbackIfNeeded()` **nur, wenn sich der State ändert**. Initial-Wert ist hardcoded `.unavailable(.modelNotReady)`. Wenn `currentAvailability()` zufällig dieselben `.unavailable(.modelNotReady)` zurückgibt (häufiger Fall: erstes Modell-Loading), feuert der Inequality-Check **nicht**, und Auto-Fallback läuft nie an, obwohl alle anderen Bedingungen (API-Key + `.appleFoundation`-Backend) erfüllt sind. User landet im Limbo: alle Rewrite-Calls schlagen mit `AppleFoundationError.unavailable` fehl, obwohl Auto-Fallback laufen sollte.

**Fix:** Auto-Fallback unconditional in `refreshFoundationAvailability()` aufrufen — Self-Idempotency-Guard schützt vor Doppelschaltung. Plus `didAutoFallbackToOpenAI = false` reset wenn `new == .available`.

---

## WARNING Issues

### WR-01: `availability == .available`-Vergleich semantisch fragil
**Files:** AppDelegate.swift:102, AppleFoundationRewriteClient.swift:32+53, SettingsStore.swift:163, SettingsView.swift:62
Convenience-Property `var isAvailable: Bool` einführen, alle `==`/`!=` ersetzen.

### WR-02: Self-Idempotency-Lücke in `applyAutoFallbackIfNeeded`
**File:** SettingsStore.swift:161-170
`didAutoFallbackToOpenAI` wird nicht gesetzt wenn User schon manuell auf OpenAI ist. Plus fehlender Reset-Pfad bei `.available`. Banner-Hint inkonsistent.

### WR-03: Pre-Warm wird bei `modelNotReady→available`-Übergang nicht erneut ausgelöst — AC-AVAIL-2 nur halb umgesetzt
**File:** AppDelegate.swift:102-112 + 124-137
Prewarm-Logik in private Methode extrahieren, sowohl aus `bootstrap()` als auch `didBecomeActive`-Observer aufrufen, mit Doppel-Prewarm-Guard.

### WR-04: AppleFoundationRewriteClient catched nur GenerationError — andere Errors propagieren ohne deutsche Lokalisierung
**File:** AppleFoundationRewriteClient.swift:38, 65
`catch let err as LanguageModelSession.GenerationError` + zweiter `catch`-all mit `AppleFoundationError.unknown` ergänzen.

### WR-05: `prewarm()`-Task captured Session ohne lifetime guarantee
**File:** AppDelegate.swift:107-111
Pre-Compute-State session-scoped vs. model-scoped ist nicht verifiziert in 08-RESEARCH-LIVE.md. Bei session-scope wirft die detached-Closure den State weg → erster Request bleibt cold.

### WR-06: `FakeLanguageModelInferring.guidedResponse: Result<Any, Error>` — Type-Erasure verbirgt Test-Misuse
**File:** BlitzTextTests/Support/FakeLanguageModelInferring.swift:10, 23-34
Stark typisieren: `Result<DeescalatedOutput, Error>`.

### WR-07: `@unknown default` mappt still auf `.deviceNotEligible` — verbirgt Apple-API-Drift
**File:** FoundationAvailabilityProvider.swift:38
Mindestens `Log.write("FoundationAvailability: unbekannter Apple-Reason — Mapper-Update prüfen")` ergänzen.

---

## INFO Issues

### IN-01: `AppleFoundationError.from(_ availability:)` hat toten `.available`-Branch
**File:** AppleFoundationError.swift:50-51

### IN-02: `_ = settingsStore` ist toter Code
**File:** AppDelegate.swift:133

### IN-03: `defaultFoundationRewriter` lazy alloziert auch wenn nie genutzt
**File:** ModeProcessor.swift:41

### IN-04: Banner-Link-URL `x-apple.systempreferences:com.apple.preference.appleintelligence` ist nicht durch Test verankert
**File:** FoundationAvailabilityBanner.swift:51

---

## Files Reviewed

Source (11):
- BlitzText/Rewrite/AppleFoundationRewriteClient.swift
- BlitzText/Rewrite/FoundationAvailabilityProvider.swift
- BlitzText/Rewrite/LanguageModelInferring.swift
- BlitzText/Rewrite/DeescalatedOutput.swift
- BlitzText/Rewrite/AppleFoundationError.swift
- BlitzText/Settings/SettingsStore.swift
- BlitzText/Settings/SettingsView.swift
- BlitzText/Settings/FoundationAvailabilityBanner.swift
- BlitzText/UI/RecordingHUDController.swift
- BlitzText/App/AppDelegate.swift
- BlitzText/Modes/ModeProcessor.swift

Tests (5):
- BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift
- BlitzTextTests/Rewrite/AppleFoundationRewriteClientTests.swift
- BlitzTextTests/Rewrite/RewriteBackendDispatchTests.swift
- BlitzTextTests/Support/FakeFoundationAvailabilityProvider.swift
- BlitzTextTests/Support/FakeLanguageModelInferring.swift

---

## Recommended Next Step

`/gsd-code-review-fix 8` — automatisch CR-01 + CR-02 fixen (beide BLOCKER, beide Privacy-relevant), danach Tests re-runnen.
