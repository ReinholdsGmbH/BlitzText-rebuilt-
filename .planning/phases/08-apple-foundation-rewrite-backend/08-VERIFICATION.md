---
phase: 08-apple-foundation-rewrite-backend
status: partial
test_runs: 3
test_runs_green: 3
gates:
  ac_avail_1: passed-via-tests
  ac_avail_2: passed-via-tests
  ac_avail_3: passed-via-doc
  full_suite_3x: passed
  uat_apple_intelligence_hardware: pending
---

# Phase 8 — Verification

**Status:** `partial` — Code-vollständig + Test-Suite 3× grün + Doku komplett. Manuelle Visual-UAT auf realer Apple-Intelligence-Hardware steht noch aus und wird vom User über `/gsd-verify-phase 8` (oder direkt durch Eintragen unten) ausgefüllt.

## Test-Suite

Volle Suite via `xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS'`. Drei consecutive Runs am 2026-05-04, alle grün, kein Flake.

| Run | Result | Test Count | Duration |
|-----|--------|-----------|----------|
| 1   | green  | 57         | 23 s (cold) |
| 2   | green  | 57         | 8 s         |
| 3   | green  | 57         | 6 s         |

**Konvention:** Phase 2 (22/22) und Phase 3 (39/39) haben dieselbe 3×-consecutive-grün-Schwelle gesetzt; Phase 8 erbt diese Konvention.

## Acceptance Criteria

- [x] AC-AVAIL-1 (defensive Verfügbarkeitsprüfung, vier Cases) — abgedeckt durch
      `AppleFoundationAvailabilityTests` (6 Tests, 08-02) +
      `AppleFoundationRewriteClientTests` (6 Tests, 08-03)
- [x] AC-AVAIL-2 (Übergang `modelNotReady` → `available` ohne App-Restart) —
      abgedeckt durch `test_refresh_modelNotReady_to_available_updatesPublishedState` (08-02)
      + `didBecomeActiveNotification`-Observer in `AppDelegate.bootstrap` (08-04)
- [x] AC-AVAIL-3 (Apple Intelligence ≠ Siri Doku) — README.md Sektion
      „Rewrite-Backend: Apple Foundation Models" (08-05 Task 1, Commit `6a9f0e3`)

## ROADMAP-Erfolgskriterien

- [x] Erfolgskriterium 1: `AppleFoundationRewriteClient` implementiert
      `RewriteService`, `RewriteBackend`-Enum in `SettingsStore` (08-02 + 08-03)
- [x] Erfolgskriterium 2: Pro Mode unabhängig wählbar (Picker × 2 in 08-04)
- [x] Erfolgskriterium 3: Plus = Plain Session, Rant = Guided Generation
      (`rewriteGuided`-Methode in 08-03 Task 1)
- [x] Erfolgskriterium 4: App-Start prüft `availability` + Auto-Fallback +
      deutsche Erklärung (`AppDelegate.bootstrap` in 08-04 + Banner in 08-04)
- [x] Erfolgskriterium 5: HUD zeigt subtilen Backend-Indikator
      (`BackendBadge` in 08-04 Task 2)

## UAT Checkliste

> **Status:** PENDING — wird vom User auf realer Apple-Intelligence-Hardware ausgefüllt.
>
> Setup vor UAT: App auf realer Hardware mit aktivem Apple Intelligence starten, Settings → Modi-Tab öffnen. Detaillierte Reproduktions-Schritte stehen im Plan `08-05-PLAN.md` Task 3.

- [ ] UAT-1 Banner Variante A korrekt gerendert (Symbol/Heading/Detail/Link, Apple Intelligence deaktiviert)
- [ ] UAT-1 Variante D zusätzlich sichtbar bei API-Key + auto-Picker-Switch
- [ ] UAT-2 Banner Variante B (`modelNotReady`) korrekt (kein Orange, ProgressView, „Erneut prüfen"-Button)
- [ ] UAT-3 Variante D Auto-Fallback-Zeile orange + `cloud`-Symbol
- [ ] UAT-4 HUD-BackendBadge zeigt `apple.logo` bei Foundation-Backend
- [ ] UAT-4 HUD-BackendBadge zeigt `cloud` bei OpenAI-Backend
- [ ] UAT-4 HUD-BackendBadge bleibt sichtbar bei State `recording → transcribing → rewriting`
- [ ] UAT-4 plain `blitztext`-Mode zeigt KEINEN BackendBadge
- [ ] UAT-5 `didBecomeActiveNotification`-Refresh greift ohne Restart (≤ 2 s)
- [ ] UAT-6 End-to-End-Latenz ≤ 3 s (PROJECT.md-Ziel)
- [ ] UAT-7 Foundation-Output bleibt deutsch (3/3 Wiederholungen, Sprachbias-Check)

## Performance-UAT (optional)

Nur ausfüllen, falls UAT-6 die 3-s-Schwelle reißt:

- Cold-Start-Latenz (erster Hotkey nach App-Boot): _____ s
- Warm-Latenz (zweiter+ Hotkey): _____ s
- Hardware: _____ (Modell, RAM)
- Notiz: kein Phase-Gate-Blocker, sondern Eingabe für künftige PERF-02-Initiative.

## Phase-Gate-Sign-Off

**Code:** ✅ Wave 1 (08-02 + 08-03) + Wave 2 (08-04) abgeschlossen, 57/57 Tests, 3× consecutive grün ohne Flake.
**Doku:** ✅ AC-AVAIL-3 in README.md erfüllt (Commit `6a9f0e3`).
**UAT:** ⏳ Pending — User-Eintrag erforderlich.

Phase 8 ist bereit für ROADMAP-Statuswechsel auf "Complete" via `/gsd-verify-phase 8`, sobald die UAT-Checkliste oben mit 11/11 `[x]` approved ist.

---
*Phase: 08-apple-foundation-rewrite-backend*
*Verification initial commit: 2026-05-04*
