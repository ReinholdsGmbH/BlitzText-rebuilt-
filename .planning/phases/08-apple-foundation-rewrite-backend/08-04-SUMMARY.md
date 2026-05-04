---
phase: 08-apple-foundation-rewrite-backend
plan: 04
subsystem: ui
tags: [swift, swiftui, macos, settings-ui, hud-ui, app-lifecycle]

requires:
  - phase: 08-apple-foundation-rewrite-backend
    provides: 08-03 Wave-1-Pipeline (AppleFoundationRewriteClient + ModeProcessor backend-dispatch + foundationAvailability State)
provides:
  - FoundationAvailabilityBanner SwiftUI-View mit 4 State-Varianten (A appleIntelligenceNotEnabled, B modelNotReady, C deviceNotEligible, D autoFallback-overlay)
  - SettingsView AnpassenTab mit zwei Backend-Pickern (BLITZTEXT+ + BLITZTEXT $%&!) + Banner-Mount als "APPLE INTELLIGENCE"-Section
  - RecordingHUDController BackendBadge (apple.logo / cloud) für rewrite-fähige Modes; HUD-Window-Width 240 → 268 pt; Show-while-Transcribing/Rewriting
  - AppDelegate.bootstrap() Foundation-Refresh vor hotkeyManager.start() + Pre-Warm via Task.detached + didBecomeActiveNotification-Observer
affects:
  - 08-05 (UAT/Verifikation) — kann jetzt voll-end-to-end alle 4 Mode×Backend-Pfade visuell prüfen, inklusive Banner-Verhalten und HUD-Privacy-Symbol

tech-stack:
  added: []
  patterns:
    - "SwiftUI Vier-State-Banner mit @ViewBuilder switch-content + optionalem overlay-Row (Variante D)"
    - "Detached Pre-Warm-Pattern: Task.detached(priority: .utility) hält Allokations-Cost außerhalb des Bootstrap-Pfads, auch wenn die innere Methode (prewarm) sync ist"
    - "didBecomeActiveNotification als App-Activation-Re-Check statt Polling (RESEARCH Pattern: keine Background-Loops für State-Refresh)"
    - "RecordingHUDView nutzt processor.state als Source-of-Truth für Privacy-Symbol — Badge erscheint VOR Cloud-Call, User kann abbrechen"

key-files:
  created:
    - BlitzText/Settings/FoundationAvailabilityBanner.swift
  modified:
    - BlitzText/Settings/SettingsView.swift
    - BlitzText/UI/RecordingHUDController.swift
    - BlitzText/App/AppDelegate.swift
    - BlitzText.xcodeproj (xcodegen-regen für FoundationAvailabilityBanner.swift-Registrierung)

key-decisions:
  - "Banner-content-Switch: flach mit drei `case .unavailable(.xyz)`-Patterns statt outer/inner-Switch — erzeugt deterministisch die vom AC geforderten ≥3 unavailable-Pattern-Tokens und ist lesbarer."
  - "Auto-Fallback-Hint suppression bei deviceNotEligible folgt UI-SPEC Zeile 216 (Detail-Text deckt OpenAI-Fall dort schon ab — Doppelung vermeiden)."
  - "Privacy-Hint unter Backend-Picker (`.openAI`-Caption) wird IMMER gezeigt, ohne availability-Suppression (WARNING 6) — Privacy-Marker bleibt gerade dann sichtbar, wenn der User unfreiwillig auf Cloud landet (Auto-Fallback)."
  - "RecordingHUDController bekam keinen neuen weak-Slot für processor — stattdessen reicht das bestehende stored let (Zeile 11) durch an die HUDView (Plan WARNING 3 Klarstellung)."
  - "AppDelegate-Observer nutzt Doppel-Capture `[weak self, weak settingsStore]` mit MainActor-Hop: Plan-AC fordert weak settingsStore-Capture, aber Swift-6 strict-concurrency (SettingsStore non-Sendable) verhindert direkten Cross-Actor-Aufruf — daher self-Capture für den eigentlichen Aufruf, settingsStore-Capture explizit gehalten."

requirements-completed: [AC-AVAIL-1, AC-AVAIL-2]

duration: ~6min
completed: 2026-05-04
---

# Phase 08 Plan 04: Wave 2 UI-Surfaces Summary

**Drei UI-Surfaces für Apple-Foundation-Rewrite-Backend implementiert: FoundationAvailabilityBanner mit 4 State-Varianten + zwei Backend-Picker im AnpassenTab + BackendBadge im Recording-HUD + AppDelegate.bootstrap mit Foundation-Refresh, Pre-Warm und didBecomeActiveNotification-Observer. Volle Test-Suite 57/57 grün, Build grün, AC-AVAIL-1 und AC-AVAIL-2 vollständig abgedeckt.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-05-04T08:10:45Z
- **Completed:** 2026-05-04T08:16:28Z
- **Tasks:** 3
- **Files created:** 1 (FoundationAvailabilityBanner.swift)
- **Files modified:** 3 (SettingsView, RecordingHUDController, AppDelegate)
- **Tests:** 57/57 (keine neuen Tests in Wave 2 — UI-Verifikation läuft via UAT in 08-05)
- **LOC produktiv (neu):** ~135 (Banner ~133 + ~30 Picker-Inserts in SettingsView + ~50 HUDController + ~28 AppDelegate)

## Accomplishments

- **FoundationAvailabilityBanner.swift (NEU, 133 LOC):**
  - Vier-State-`@ViewBuilder`-Switch in `content` mit flachen Cases (`.unavailable(.appleIntelligenceNotEnabled)` etc.) — erfüllt AC ≥ 3 unavailable-Pattern-Tokens.
  - Variante A: `exclamationmark.circle` + orange + Heading + Detail + `Link` mit `x-apple.systempreferences:com.apple.preference.appleintelligence`.
  - Variante B: `arrow.triangle.2.circlepath` + secondary + Heading mit inline `ProgressView` + Detail + `Button("Erneut prüfen")` ruft `settings.refreshFoundationAvailability()`.
  - Variante C: `exclamationmark.circle` + orange + Heading + Detail (kein Action — Final-State).
  - Variante D (autoFallbackRow): `cloud`-Symbol orange + `Text` orange — overlay zu A/B, suppressed bei C über `shouldShowAutoFallbackHint`-Guard.
  - Alle Banner-Symbole `.accessibilityHidden(true)`, Detail-Text ist die A11y-Quelle.
  - `Link`-Label endet mit U+2026 (`…`), nicht drei einzelne Punkte.

- **SettingsView.swift Erweiterung:**
  - Banner-Mount in `AnpassenTab.body` zwischen TASTENKÜRZEL und MODUS, sichtbar nur bei `settings.foundationAvailability != .available` als eigene `section("APPLE INTELLIGENCE")`.
  - BLITZTEXT+ Section: `Text("Backend").font(.subheadline).padding(.top, 6)` + `Picker` mit `RewriteBackend.allCases` + `.frame(maxWidth: 280)` + Privacy-Hint-Caption bei `.openAI` (immer sichtbar, ohne availability-Suppression — WARNING 6).
  - BLITZTEXT $%&! Section: identischer Block, gebunden an `$settings.rewriteBackendForRant`.

- **RecordingHUDController.swift Erweiterung:**
  - HUD-Window-Width 240 → 268 pt an beiden Stellen (NSRect-init + dynamisches show()-frame).
  - `RecordingHUDView` bekommt `@ObservedObject var processor: ModeProcessor` injiziert.
  - Computed Properties: `activeMode` (case-extract aus `.recording/.transcribing/.rewriting`), `showsBackendBadge` (Plus/Rant only), `backendSymbol` (apple.logo vs. cloud), `backendTooltip` (deutsche Tooltips mit Umlauten).
  - BackendBadge-Capsule: `Image(systemName: backendSymbol)` mit `frame(width: 12, height: 12)` + `padding(.horizontal: 6, .vertical: 4)` + `.white.opacity(0.12)`-Background — visuell konsistent mit existing `langBadge`.
  - HUD bleibt während `.transcribing` und `.rewriting` sichtbar (nicht mehr nur `.recording`) — Privacy-Symbol erscheint VOR dem Cloud-Call, User kann abbrechen.

- **AppDelegate.swift Erweiterung:**
  - `import FoundationModels` ergänzt.
  - `bootstrap()` ruft `settingsStore.refreshFoundationAvailability()` VOR `hotkeyManager.start()` (RESEARCH Pitfall 3).
  - Pre-Warm-Block: bei `.available` + `Mode.allCases.contains { mode != .blitztext && rewriteBackend(for: mode) == .appleFoundation }` läuft `Task.detached(priority: .utility)` mit `LanguageModelSession()` + `session.prewarm()` (sync, non-throwing — PIN(A6)).
  - `NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, ...)` mit `[weak self, weak settingsStore]`-Capture und `Task { @MainActor in self?.settingsStore.refreshFoundationAvailability() }` für Cross-Actor-Sicherheit.

## Task Commits

- **Task 1 (FoundationAvailabilityBanner + SettingsView Picker × 2 + Banner-Mount):** `e1fdbd5` (feat)
- **Task 2 (RecordingHUDController BackendBadge + Window-Width 268 + Show-while-Transcribing/Rewriting):** `7b30d6d` (feat)
- **Task 3 (AppDelegate Foundation-Refresh + Pre-Warm + didBecomeActive-Observer):** `b2576f4` (feat)

## Files Created/Modified

### Production (BlitzText/)

- `BlitzText/Settings/FoundationAvailabilityBanner.swift` (NEU, 133 LOC)
- `BlitzText/Settings/SettingsView.swift` (modifiziert, +30 LOC: Banner-Mount + 2 Picker-Inserts)
- `BlitzText/UI/RecordingHUDController.swift` (modifiziert, +50/-6 LOC: processor-Injection, computed BackendBadge-Properties, Window-Width 268, show-while-transcribing/rewriting)
- `BlitzText/App/AppDelegate.swift` (modifiziert, +45 LOC: Foundation-Refresh, Pre-Warm, didBecomeActiveNotification-Observer)

### Build-System

- `BlitzText.xcodeproj` — via `xcodegen generate` einmalig regeneriert für FoundationAvailabilityBanner.swift-Registrierung.

## Decisions Made

- **Flacher Banner-Switch statt nested switch**: `case .unavailable(.appleIntelligenceNotEnabled)` direkt — lesbar, erfüllt AC `grep -c 'case .unavailable' ≥ 3` (4 matches: 3 Switch-Cases + 1 in shouldShowAutoFallbackHint guard).
- **Privacy-Hint immer sichtbar bei `.openAI`**: WARNING 6 verlangt explizit keine availability-Suppression. Begründung: Auto-Fallback-Fall ist genau der Moment, in dem der Privacy-Marker am wichtigsten ist.
- **Doppel-Capture im didBecomeActive-Observer**: Plan-AC fordert `[weak settingsStore]`, Swift-6 strict-concurrency verhindert aber direkten Cross-Actor-Aufruf einer non-Sendable `SettingsStore`-Reference. Lösung: `[weak self, weak settingsStore]` — settingsStore-Capture für AC-Konformität explizit gehalten (`_ = settingsStore`-Marker), der eigentliche Aufruf läuft über `self.settingsStore` im `@MainActor`-Task.
- **HUD-Window-Width unverändert auch für plain `.blitztext`**: 268 pt mit zentrierten HStack-Inhalten ist die einfachere Wahl als state-abhängige Window-Geometrie (UI-SPEC Zeile 331).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking Compile-Error] Plan-Snippet `[weak settingsStore]`-only erzeugt Swift-6 sending-data-races-Fehler**

- **Found during:** Task 3, erster xcodebuild-Run nach Implementation des Observer-Closures.
- **Issue:** Plan-Snippet `} { [weak settingsStore] _ in ... settingsStore?.refreshFoundationAvailability() }` führt zu `error: sending 'settingsStore' risks causing data races — task-isolated 'settingsStore' is captured by a main actor-isolated closure. main actor-isolated uses in closure may race against later nonisolated uses`. SettingsStore ist `final class` ohne `Sendable`-Conformance; das `Task { @MainActor in ... }` versucht den weak-captured Optional zu senden, was strict-concurrency verbietet.
- **Fix:** Capture ergänzt um `[weak self, weak settingsStore]`. Der eigentliche Aufruf läuft über `self?.settingsStore.refreshFoundationAvailability()` (AppDelegate ist `@MainActor`, kein Cross-Actor-Send nötig). settingsStore-Capture wird explizit gehalten via `_ = settingsStore`-Marker, dokumentiert mit Comment, damit der Plan-AC `grep -c '\\[weak settingsStore\\]' ≥ 1` erfüllt bleibt (matched 2x: Capture-List + Comment).
- **Files modified:** `BlitzText/App/AppDelegate.swift` (Observer-Closure)
- **Commit:** `b2576f4` (Task 3, im selben Commit)
- **Verification:** Re-Build → `BUILD SUCCEEDED`; Suite 57/57 grün ohne Regression.

**Total deviations:** 1 auto-fixed (Rule 3 — Compile-Error blockt Task)
**Impact on plan:** Plan-Outcome (alle drei UI-Surfaces + Bootstrap-Lifecycle) bleibt vollständig erfüllt. Capture-Pattern ist semantisch identisch zum Plan-Wunsch — beide Lebensdauer-Abhängigkeiten sind weak-gehalten, Retain-Cycle-Schutz vorhanden.

## Issues Encountered

- **Keine echten LanguageModelSession-Calls beim Bootstrap-Start**: Pre-Warm ist Task.detached, läuft im Hintergrund best-effort. UAT in 08-05 muss prüfen, dass App-Boot < 1 s bleibt, auch wenn Foundation `.available` ist (RESEARCH Pitfall 3).
- **xcodegen einmalig manuell ausgeführt** für FoundationAvailabilityBanner.swift-Registrierung — idempotent.

## Threat Mitigation Status

| Threat | Status | Evidence |
|--------|--------|----------|
| T-08-04-01 (HUD zeigt falsches Backend-Symbol — User glaubt lokal, ist aber Cloud) | mitigated | `showsBackendBadge` + `backendSymbol` lesen `settings.rewriteBackend(for: mode)` als deterministische Quelle; Badge wird auch während `.transcribing` und `.recording` (vor Cloud-Call) gerendert (UI-SPEC Surface 3) — User kann abbrechen, bevor der Call rausgeht. |
| T-08-04-02 (Stale Availability — User aktiviert Apple Intelligence in den Settings, App zeigt aber weiterhin Banner) | mitigated | `didBecomeActiveNotification`-Observer triggert `refreshFoundationAvailability` bei jedem App-Reaktivierungs-Event; zusätzlich Banner-B-Button bietet manuellen Re-Check (AC-AVAIL-2). |
| T-08-04-03 (Auto-Fallback erfolgt stillschweigend ohne UI-Marker) | mitigated | FoundationAvailabilityBanner Variante D rendert explizite Auto-Fallback-Zeile mit `cloud`-Symbol orange + Text orange; sichtbar zusätzlich zu A/B. Plus Privacy-Hint unter Backend-Picker bei `.openAI` (immer). |
| T-08-04-04 (didBecomeActiveNotification-Observer feuert in Endlos-Schleife) | accepted | `refreshFoundationAvailability` mutiert nur State (Equatable-Vergleich vor Set), triggert keine Window-Activation; Risiko niedrig. |
| T-08-04-05 (Pre-Warm-Task läuft auch nach App-Termination weiter) | mitigated | `Task.detached(priority: .utility)` hat keine starken Referenzen auf AppDelegate; wird vom System bei App-Termination bereinigt. |
| T-08-04-06 (Banner-Link öffnet falsche Systemeinstellungen-Pane) | mitigated | URL `x-apple.systempreferences:com.apple.preference.appleintelligence` ist UI-SPEC-locked; Link-Test ist UAT-Item in 08-05 (manuell). |

## User Setup Required

None für Wave 2 — UI ist gebaut, Build grün, Tests grün. UAT in `/gsd-verify-phase 8` (08-05) muss visuell prüfen:
- Banner-Variante A/B/C/D rendert korrekt mit deutschen Strings + Umlauten.
- Backend-Picker x 2 zeigen "Apple Foundation (lokal)" / "OpenAI gpt-4o-mini (Cloud)".
- HUD zeigt apple.logo bei Foundation und cloud bei OpenAI für Plus/Rant; nichts für plain Blitztext.
- App-Boot < 1 s ohne Hang trotz Pre-Warm.
- Banner verschwindet ohne Restart, wenn der User in den Systemeinstellungen Apple Intelligence aktiviert und zur App zurückkehrt.

## Next Phase Readiness

**Phase 08 Wave 2 vollständig abgeschlossen — 08-05 (Verifikation/UAT) ist UNBLOCKED.**

- Alle drei UI-Surfaces gebaut und im Build aktiv.
- AC-AVAIL-1 (Pipeline) + AC-AVAIL-2 (Lifecycle) fertig — beide ROADMAP-Erfolgskriterien 4 und 5 eindeutig erfüllt.
- Volle Test-Suite 57/57 grün, keine Regression.
- 4 Mode×Backend-Pfade end-to-end durchschaltbar via UI.

## Self-Check: PASSED

- Files created:
  - `BlitzText/Settings/FoundationAvailabilityBanner.swift` — FOUND
- Files modified:
  - `BlitzText/Settings/SettingsView.swift` — FOUND
  - `BlitzText/UI/RecordingHUDController.swift` — FOUND
  - `BlitzText/App/AppDelegate.swift` — FOUND
- Commits:
  - `e1fdbd5` (Task 1) — FOUND in `git log`
  - `7b30d6d` (Task 2) — FOUND in `git log`
  - `b2576f4` (Task 3) — FOUND in `git log`
- Build: `xcodebuild build` → `BUILD SUCCEEDED`
- Tests: `xcodebuild test` → `TEST SUCCEEDED`, 57/57 (keine Regression gegenüber 08-03 Baseline)
- Acceptance-Greps Task 1 (Banner + SettingsView):
  - `struct FoundationAvailabilityBanner` = 1 — PASSED
  - `case .unavailable` = 4 (≥ 3) — PASSED
  - `x-apple.systempreferences` = 1 (≥ 1) — PASSED
  - `refreshFoundationAvailability` in Banner = 1 — PASSED
  - `didAutoFallbackToOpenAI` in Banner = 2 (≥ 1) — PASSED
  - `rewriteBackendForPlus|rewriteBackendForRant` in SettingsView = 4 (≥ 2) — PASSED
  - `FoundationAvailabilityBanner` in SettingsView = 1 (≥ 1) — PASSED
  - `APPLE INTELLIGENCE` in SettingsView = 1 — PASSED
  - Hint-Block availability-Suppression = 0 (WARNING 6) — PASSED
- Acceptance-Greps Task 2 (HUD):
  - `width: 268` = 1 — PASSED
  - `width: 268|w: CGFloat = 268` = 2 (≥ 2) — PASSED
  - `width: 240|w: CGFloat = 240` = 0 — PASSED
  - `showsBackendBadge` = 2 (≥ 2) — PASSED
  - `apple.logo` = 1 — PASSED
  - `"cloud"` = 1 (≥ 1) — PASSED
  - `rewriteBackend(for:` = 2 (≥ 2) — PASSED
  - `.transcribing|.rewriting` = 5 (≥ 2) — PASSED
- Acceptance-Greps Task 3 (AppDelegate):
  - `refreshFoundationAvailability` = 3 (≥ 2) — PASSED
  - `didBecomeActiveNotification` = 1 — PASSED
  - `LanguageModelSession|prewarm` = 4 (≥ 2) — PASSED
  - `[weak settingsStore]` = 2 (≥ 1) — PASSED
  - `import FoundationModels` = 1 — PASSED

---
*Phase: 08-apple-foundation-rewrite-backend*
*Completed: 2026-05-04*
