---
phase: 8
slug: apple-foundation-rewrite-backend
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-04
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Source-of-truth detail in `08-RESEARCH.md` § Validation Architecture (lines 631-682) — this file is the executive summary + checklist.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (bundled with Xcode 17 / Swift 6) |
| **Config file** | `project.yml` (XcodeGen) — `BlitzTextTests` target bereits aus Phase 2 (TEST-01) |
| **Quick run command** | `xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/AppleFoundationRewriteClientTests` |
| **Full suite command** | `xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS'` |
| **Estimated runtime (full)** | ~25 s (Phase-2-Baseline 22 Tests/<30 s + ~12 Phase-8-Tests; Mocks halten alles I/O-frei) |

---

## Sampling Rate

- **After every task commit:** `xcodebuild test … -only-testing:BlitzTextTests/AppleFoundationRewriteClientTests` (~5 s)
- **After every plan wave:** `xcodebuild test … -only-testing:BlitzTextTests/Rewrite` + `BlitzTextTests/Pipeline` (~20 s)
- **Before `/gsd-verify-work`:** Full suite green, **3× consecutive** (Phase-2/3-Konvention)
- **Max feedback latency:** 30 Sekunden

---

## Per-Task Verification Map

> Detailliert in `08-RESEARCH.md:642-654`. Hier die Acceptance-Criteria-Achse:

| AC ID | Behavior | Test Type | Mock-Strategie | File (NEW) |
|-------|----------|-----------|---------------|------------|
| AC-AVAIL-1 | Pre-inference availability-Check; vier Cases liefern spezifizierte deutsche Fehler; KEIN Cloud-Call bei `unavailable` | unit | `FakeFoundationAvailabilityProvider` + `OpenAIChatClient`-Spy | `BlitzTextTests/Rewrite/AppleFoundationRewriteClientTests.swift` |
| AC-AVAIL-2 | Übergang `modelNotReady` → `available` ohne App-Restart; idempotent + main-actor-safe | unit | `FakeFoundationAvailabilityProvider` mit mutable State | `BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift` |
| AC-AVAIL-3 | README/Settings-Help-String "Apple Intelligence" + "unabhängig von Siri" | smoke / manual UAT | n/a | manual (in `/gsd-verify-phase`) |
| Mode-Dispatch | `ModeProcessor.runPipeline` wählt korrekten Client (4 Pfade: 2 Modes × 2 Backends) | unit | RewriteService-Spy für beide Backends | `BlitzTextTests/Rewrite/RewriteBackendDispatchTests.swift` |
| Schema-Fill-Failure | Guided Generation mit leerem `neutralText` wirft `.emptyGuidedOutput` | unit | `FakeLanguageModelInferring` mit pre-canned Empty-Response | `BlitzTextTests/Rewrite/AppleFoundationRewriteClientTests.swift` |
| HUD-Indikator | `showsBackendBadge` true für Plus/Rant, false für plain | unit (optional) | direkter State-Test | `BlitzTextTests/UI/RecordingHUDStateTests.swift` (optional) |

---

## Mock-Strategie (Doppeltes Protocol-Wrapping)

`SystemLanguageModel.default` ist non-instanzierbarer Singleton — direkt nicht mockbar. Lösung:

1. **`FoundationAvailabilityProviding`** (Sendable Protocol) — wrappt `SystemLanguageModel.default.availability`. LiveImpl liest direkt; FakeImpl trägt mutablen State für AC-AVAIL-2-Übergangstest.
2. **`LanguageModelInferring`** (Sendable Protocol) — wrappt `LanguageModelSession.respond(to:)` + `respond(to:generating:)`. LiveImpl wrappt echte Session; FakeImpl injiziert pre-canned Responses + Error-Injection.

Beide Protocols werden in `AppleFoundationRewriteClient.init` per Default injiziert; Tests injizieren Fakes. **CI bleibt grün auf nicht-Apple-Intelligence-Hardware.**

---

## Wave 0 Gaps (was muss VOR Wave 1 stehen)

- [ ] `BlitzText/Rewrite/FoundationAvailabilityProviding.swift` — Protocol + Live-Impl
- [ ] `BlitzText/Rewrite/LanguageModelInferring.swift` — Protocol + Live-Impl (wrappt `LanguageModelSession`)
- [ ] `BlitzText/Rewrite/DeescalatedOutput.swift` — `@Generable` struct mit `neutralText: String`
- [ ] `BlitzText/Rewrite/AppleFoundationRewriteClient.swift` — Client (RewriteService-Conformance, Pre-Inference-Check)
- [ ] `BlitzTextTests/Support/FakeFoundationAvailabilityProvider.swift` — Mock-Provider mit Mutable-State
- [ ] `BlitzTextTests/Support/FakeLanguageModelInferring.swift` — Mock-Inferenz mit pre-canned Outputs + Error-Injection
- [ ] `BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift` — AC-AVAIL-1 (4 Cases) + AC-AVAIL-2 (Übergang)
- [ ] `BlitzTextTests/Rewrite/AppleFoundationRewriteClientTests.swift` — Pre-Inference-Check + Schema-Fill-Failure
- [ ] `BlitzTextTests/Rewrite/RewriteBackendDispatchTests.swift` — Mode×Backend-Dispatch (4 Pfade)

**Live-Verifikations-Tasks (15-30 min, blocking für Wave 1):**
- [ ] Open Question #1 lösen: `LanguageModelSession`-Concurrency-Annotation in Xcode Quick Help (Class? Actor? @MainActor?)
- [ ] Open Question #2 lösen: `GenerationError`-exakte-Case-Spelling in Xcode (`exceededContextWindowSize` mit "ed" verifiziert vs. ohne; existiert `.type`-Property?)
- [ ] Open Question #3 lösen: `LanguageModelSession.prewarm()`-Signatur (parameter-los oder mit `promptPrefix`)

---

## Phase Gate Criteria

Vor `/gsd-verify-work`:

1. ✅ Alle Acceptance Criteria (AC-AVAIL-1/2/3) abgedeckt durch automatisierte Tests ODER manuelles UAT (AC-AVAIL-3 ist manual).
2. ✅ Full suite green, 3× consecutive runs (Phase-2/3-Konvention).
3. ✅ Wave-0-Live-Verifikation Open Questions #1-#3 dokumentiert oder gelöst.
4. ✅ Manuelles UAT auf realer Apple-Intelligence-Hardware: Cold-Start-Latenz ≤ 3 s end-to-end PROJECT.md-Ziel (UAT-Item, kein automatisierter Test möglich).

---

*Validation strategy abgeleitet aus 08-RESEARCH.md § Validation Architecture (Zeilen 631-682). Detaillierte Mock-Strategie und Sources dort.*
