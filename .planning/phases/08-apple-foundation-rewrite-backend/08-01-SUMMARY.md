---
phase: 08-apple-foundation-rewrite-backend
plan: 01
subsystem: research
tags: [swift, macos, apple-foundation-models, live-verification, swiftinterface]

requires:
  - phase: 08-apple-foundation-rewrite-backend
    provides: 08-RESEARCH.md Assumptions Log A1/A2/A6 (MEDIUM-confidence Apple-API hypotheses)
provides:
  - Live-verifizierte Apple-API-Fakten als PIN-Marker für Wave 1+2
  - Korrektur dreier Plan-Annahmen vor Production-Code-Zementierung
  - Kanonische Code-Snippets aus arm64e-apple-macos.swiftinterface (Source-of-Truth)
affects:
  - 08-02-PLAN (Wave 0 Seams — LanguageModelInferring.swift)
  - 08-03-PLAN (Wave 1 Client — AppleFoundationError mapper)
  - 08-04-PLAN (Wave 2 AppDelegate — prewarm-Aufruf)

tech-stack:
  added: []
  patterns:
    - "Live-Verification via swiftc -typecheck Mini-Probes unter /tmp (no production pollution)"
    - "Inspektion swiftinterface als Quick-Help-Source-of-Truth für Plan-blockierende API-Fragen"

key-files:
  created:
    - .planning/phases/08-apple-foundation-rewrite-backend/08-RESEARCH-LIVE.md
  modified: []

key-decisions:
  - "A1: LanguageModelSession ist final class, non-MainActor — kein @MainActor.run-Hop in Wave 1 nötig"
  - "A2: GenerationError hat 9 Cases (alle mit Context-Payload); .type-Property existiert NICHT — Switch ist Pflicht"
  - "A2: Drei zusätzliche Cases (unsupportedGuide, concurrentRequests, refusal) — Mapper braucht 3 zusätzliche Branches"
  - "A6: prewarm() ist sync, non-throwing — `try? await session.prewarm()` aus 08-PATTERNS.md falsch; korrekt: `session.prewarm()` (Task.detached-Wrapper bleibt sinnvoll)"

patterns-established:
  - "Wave-0-Spike-Pattern: Plan-blockierende API-Fragen werden via swiftc -typecheck + swiftinterface-Inspektion live verifiziert, NICHT via xcodebuild auf Production-Probe"
  - "PIN(Annnn)-Marker als persistierender Verweis für nachfolgende Waves: jede Sektion liefert Status + Snippet + Compiler-Diagnostik + PIN"

requirements-completed: [AC-AVAIL-1, AC-AVAIL-2]

duration: 8min
completed: 2026-05-04
---

# Phase 08 Plan 01: Wave-0 Live-Verifikation der Apple FoundationModels-API

**Drei Plan-blockierende Apple-API-Annahmen (LanguageModelSession-Concurrency, GenerationError-Cases, prewarm-Signatur) live gegen MacOSX26.4.sdk verifiziert — A1 bestätigt, A2 + A6 korrigiert; Wave 1 unblocked.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-04T (this session)
- **Completed:** 2026-05-04
- **Tasks:** 2
- **Files created:** 1 (`08-RESEARCH-LIVE.md`)
- **Files modified:** 0
- **Probes ausgeführt:** 5 (alle unter `/tmp/blitz-probes/`, post-verify gelöscht)

## Accomplishments

- **A1 verifiziert (Concurrency):** `LanguageModelSession` ist `final public class`, kein `@MainActor`, kein `actor`. `respond(to:)` ist explizit `nonisolated(nonsending)` annotiert — sogar stärker als die Hypothese aus 08-RESEARCH.md. Kein MainActor-Hop in Wave 1 nötig.
- **A2 korrigiert (GenerationError):** `exceededContextWindowSize` mit "ed" verifiziert. Aber: ALLE 9 Cases tragen `(Context)`/`(Refusal, Context)`; drei zusätzliche Cases existieren (`unsupportedGuide`, `concurrentRequests`, `refusal`) — Mapper-Switch in Wave 1 muss diese abdecken. `.type`-Property existiert nicht (`error: value of type 'LanguageModelSession.GenerationError' has no member 'type'`).
- **A6 korrigiert (prewarm):** Methode-Signatur ist `final public func prewarm(promptPrefix: FoundationModels.Prompt? = nil)` — **sync, non-throwing**. Hypothese-Form `try? await session.prewarm()` (08-PATTERNS.md AppDelegate-Snippet) ist falsch; korrekt: `session.prewarm()`. `Task.detached`-Wrapper bleibt für Allokations-Kosten sinnvoll.
- **Sign-Off:** Wave 0 abgeschlossen, Wave 1 unblocked.

## Task Commits

Beide Tasks atomisch committed:

1. **Task 1: A1 + A2 Live-Verifikation** — `0319688` (docs)
2. **Task 2: A6 Live-Verifikation + Wave-0-Sign-Off** — `acd92c3` (docs)

## Files Created/Modified

- `.planning/phases/08-apple-foundation-rewrite-backend/08-RESEARCH-LIVE.md` (NEU, 227 Zeilen) — Live-Verifikations-Addendum mit drei verifizierten/korrigierten Apple-API-Fakten als PIN-Marker (PIN(A1), PIN(A2), PIN(A6)) plus Wave-0-Sign-Off.

## Decisions Made

- **Probe-Verfahren angepasst:** Plan empfahl `xcodebuild build` mit Probe-Files unter `BlitzText/Rewrite/_FoundationProbe.swift` und `_PrewarmProbe.swift`. Stattdessen wurde `swiftc -typecheck` mit Probe-Files unter `/tmp/blitz-probes/` verwendet — schneller (~1 s vs. ~30 s xcodebuild) und garantiert keine Production-Pollution (T-08-01-01 mitigated by isolation, nicht nur durch nachträgliche Löschung). Plan-Acceptance-Criteria (`! test -f BlitzText/Rewrite/_*Probe.swift`) bleibt erfüllt, da diese Dateien nie angelegt wurden.
- **Zusätzlich `swiftinterface` direkt inspiziert:** Neben Live-Probes wurde `arm64e-apple-macos.swiftinterface` aus `MacOSX26.4.sdk/System/Library/Frameworks/FoundationModels.framework/` ausgelesen — das ist die kanonische Quick-Help-Source-of-Truth (was Apple Quick Help in Xcode anzeigt, ist genau dieser Text). Damit haben wir nicht nur "kompiliert vs. kompiliert nicht", sondern die exakten Apple-Signaturen — höhere Konfidenz für PIN-Marker.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Plan-Bug] Plan-Empfehlung "Probe-Files unter BlitzText/Rewrite/" durch /tmp/-Isolation ersetzt**

- **Found during:** Task 1, Vorbereitung der Probe-Datei
- **Issue:** Plan beschrieb Probes als `BlitzText/Rewrite/_FoundationProbe.swift` (Production-Pfad). T-08-01-01 (Tampering: Probe verbleibt im Production-Code) war als "mitigate" markiert, aber Mitigation hing an manueller Lösch-Action — was bei Crash/Interrupt unzuverlässig ist.
- **Fix:** Probes wurden unter `/tmp/blitz-probes/` angelegt; xcodebuild durch `swiftc -typecheck` ersetzt (gleicher Type-Checker, schneller, ohne Build-System-Side-Effects).
- **Files affected:** Keine Production-Files berührt; `BlitzText/Rewrite/_FoundationProbe.swift` und `_PrewarmProbe.swift` existieren zu **keinem** Zeitpunkt.
- **Verification:** `! test -f BlitzText/Rewrite/_FoundationProbe.swift && ! test -f BlitzText/Rewrite/_PrewarmProbe.swift` → beide PASS.
- **Committed in:** `0319688` (Task 1) und `acd92c3` (Task 2).

**2. [Rule 1 — Hypothesis-Bug] Plan-Snippet `try? await session.prewarm()` ist syntaktisch falsch**

- **Found during:** Task 2 (A6-Verifikation)
- **Issue:** 08-PATTERNS.md AppDelegate-Snippet (Zeile ~793) enthält `try? await session.prewarm()`. Live-Probe + swiftinterface zeigen: `prewarm` ist sync und non-throwing — `try?` und `await` sind beide falsch.
- **Fix:** In 08-RESEARCH-LIVE.md unter "Konsequenz für Wave 2" korrekte Form dokumentiert: `session.prewarm()` (sync, non-throwing); `Task.detached(priority: .utility)`-Wrapper bleibt für Allokations-Kosten richtig. Wave-2-Plan (08-04) muss diesen Snippet beim Implement aktualisieren — durch PIN(A6)-Marker garantiert.
- **Files modified:** `.planning/phases/08-apple-foundation-rewrite-backend/08-RESEARCH-LIVE.md` (Korrektur ist Teil von Task 2).
- **Verification:** swiftinterface Zeile 343 zeigt `final public func prewarm(promptPrefix: FoundationModels.Prompt? = nil)` — keine `async`, keine `throws`.
- **Committed in:** `acd92c3` (Task 2).

**3. [Rule 1 — Hypothesis-Bug] Plan-Hypothese "6 GenerationError-Cases" unvollständig**

- **Found during:** Task 1 (A2-Verifikation)
- **Issue:** Plan listete 6 Cases (`exceededContextWindowSize`, `guardrailViolation`, `unsupportedLanguageOrLocale`, `assetsUnavailable`, `rateLimited`, `decodingFailure`). Tatsächlich existieren 9 Cases — fehlend: `unsupportedGuide(Context)`, `concurrentRequests(Context)`, `refusal(Refusal, Context)`. Außerdem tragen alle Cases `(Context)`-Payload (Plan ging von parameter-losen Cases aus).
- **Fix:** PIN(A2) dokumentiert vollständige Case-Liste plus Mapper-Skizze für Wave 1 (drei zusätzliche `case`-Zeilen, die alle auf bestehende `AppleFoundationError`-Cases mappen — keine Erweiterung des `AppleFoundationError`-Enum nötig).
- **Files modified:** `.planning/phases/08-apple-foundation-rewrite-backend/08-RESEARCH-LIVE.md`.
- **Verification:** Compiler-Diagnostik unter `/tmp/probe-A2-full.log` zeigt vollständige Case-Liste; swiftinterface Zeilen 425–432 bestätigen Apple-Source.
- **Committed in:** `0319688` (Task 1).

**4. [Rule 2 — Doc-Quality] Markdown-Lint-Fixes (MD031/MD032/MD040)**

- **Found during:** Task 2 (Post-Edit Linter-Diagnostik)
- **Issue:** IDE-Linter meldete fehlende Leerzeilen um Code-Fences (MD031) und Listen (MD032), plus fehlende Sprachen-Tags (MD040) für Compiler-Output-Code-Fences.
- **Fix:** Leerzeilen vor Code-Fences und vor List-Blöcken eingefügt; Plain-Text-Blöcke als ` ```text ` markiert.
- **Files modified:** `.planning/phases/08-apple-foundation-rewrite-backend/08-RESEARCH-LIVE.md`.
- **Verification:** Datei strukturell sauber; alle Acceptance-Criteria-Greps bleiben grün.
- **Committed in:** `acd92c3` (Task 2, im selben Commit wie A6).

---

**Total deviations:** 4 auto-fixed (3× Rule 1 — Plan-/Hypothesis-Bugs, 1× Rule 2 — Doc-Quality)
**Impact on plan:** Alle vier Deviations sind Wave-0-Spike-Funktion erfüllend. Speziell Deviation 2 (prewarm-Signatur) und 3 (GenerationError-Cases) verhindern in Wave 1+2 echte Build-Bugs. Kein Scope Creep — Wave-0-Spike hat genau seinen Zweck erfüllt: Plan-Annahmen vor Production-Code zu validieren und Korrekturen ans Wave-1+2-Team weiterzureichen via PIN-Marker.

## Issues Encountered

- **Plan-Acceptance-Test-Pattern `grep -q 'Wave 1 unblocked: yes'` schlug initial fehl** — Datei hatte Markdown-Bold-Syntax (`**Wave 1 unblocked:** yes`) zwischen `unblocked:` und `yes`. Fix: Sign-Off-Zeilen bewusst nicht-fett, damit grep-pattern matched. Acceptance-Test war damit erfolgreich — siehe Commit `acd92c3`.
- **Keine echte Inferenz-Validierung in dieser Phase** — Wave-0-Spike validiert nur API-Signaturen via Type-Checker. Echte Inferenz-Calls (Latenz, Output-Qualität, Sprachbias) sind UAT-Aufgaben in `/gsd-verify-phase 8`, nicht hier (siehe 08-VALIDATION.md "Phase Gate Criteria" Punkt 4).

## User Setup Required

None — Wave 0 ist reine Plan-Verifikation, keine externen Services.

## Next Phase Readiness

**Wave 1 (08-02 Seams) ist UNBLOCKED:**

- PIN(A1) bestätigt: `final class LiveLanguageModelInferring: LanguageModelInferring` ohne `@MainActor`, Methoden ohne `MainActor.run`-Hop.
- PIN(A2) korrigiert: Mapper-Switch in `AppleFoundationError.from(_:)` (08-03) braucht **9 Cases + @unknown default**, nicht 6 — fertige Mapper-Skizze ist in 08-RESEARCH-LIVE.md Sektion A2.
- PIN(A6) korrigiert: AppDelegate-Snippet (08-04) verwendet `session.prewarm()`, nicht `try? await session.prewarm()` — 08-PATTERNS.md Zeile ~793 ist der einzige nachzubearbeitende Plan-Snippet.

**Keine Blocker für Wave 1+2.** Phase 3 manuelles UAT bleibt offen, blockt aber Phase 8 nicht (laut STATE.md Session Continuity).

## Self-Check: PASSED

- ✅ `08-RESEARCH-LIVE.md` existiert (`test -f`).
- ✅ Sektionen `## A1`, `## A2`, `## A6`, `## Wave 0 Spike — Sign-Off` vorhanden (`grep -q '^## ...'`).
- ✅ PIN-Marker für alle drei Annahmen vorhanden (`grep -qE 'PIN\(A[1,2,6]\)'`).
- ✅ `Wave 1 unblocked: yes` matched (Bold-Markup entfernt).
- ✅ Probe-Files in Production NICHT vorhanden (`! test -f BlitzText/Rewrite/_FoundationProbe.swift && ! test -f BlitzText/Rewrite/_PrewarmProbe.swift`).
- ✅ Beide Tasks committed: `0319688`, `acd92c3` (`git log` enthält beide Hashes).

---
*Phase: 08-apple-foundation-rewrite-backend*
*Completed: 2026-05-04*
