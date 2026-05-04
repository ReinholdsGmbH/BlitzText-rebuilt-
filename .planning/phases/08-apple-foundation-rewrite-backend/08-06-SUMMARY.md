---
phase: 08-apple-foundation-rewrite-backend
plan: 06
subsystem: app-lifecycle
tags: [swift6, notification-center, observer-leak, appdelegae, cr-01, cleanup]

# Dependency graph
requires:
  - phase: 08-apple-foundation-rewrite-backend
    provides: AppDelegate with addObserver block from plan 08-04 (source of the leak)
provides:
  - AppDelegate.didBecomeActiveObserver token property
  - applicationWillTerminate removes the observer via stored token (CR-01 fix)
  - Dead code removed: [weak settingsStore] capture and _ = settingsStore statement
affects:
  - 08-apple-foundation-rewrite-backend (CR-01 BLOCKER resolved)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Store NSObjectProtocol token from block-based NotificationCenter observer and remove in applicationWillTerminate"

key-files:
  created: []
  modified:
    - BlitzText/App/AppDelegate.swift

key-decisions:
  - "Retain only [weak self] capture — [weak settingsStore] and _ = settingsStore were dead code since the closure body uses self?.settingsStore, not the captured settingsStore directly"
  - "Remove observer in applicationWillTerminate before hotkeyManager.stop() to maintain clean shutdown order"

patterns-established:
  - "Block-based NotificationCenter observers: always store token, always removeObserver in deinit/willTerminate"

requirements-completed: []

# Metrics
duration: 8min
completed: 2026-05-04
---

# Phase 08 Plan 06: CR-01 NotificationCenter Observer Leak Fix Summary

**Block-based NSNotificationCenter observer token now stored in AppDelegate property and removed in applicationWillTerminate, eliminating stale-observer accumulation in XCTest-hosted runs (CR-01)**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-04T11:10:00Z
- **Completed:** 2026-05-04T11:18:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Added `private var didBecomeActiveObserver: NSObjectProtocol?` property with doc-comment explaining CR-01 rationale
- Replaced fire-and-forget `addObserver` call with token-storing assignment `didBecomeActiveObserver = NotificationCenter.default.addObserver(...)`
- Removed dead captures `[weak settingsStore]` and `_ = settingsStore` from the observer closure
- Extended `applicationWillTerminate` to call `removeObserver(token)` before `hotkeyManager.stop()`
- AC-AVAIL-2 refresh behaviour (didBecomeActive → refreshFoundationAvailability) unchanged
- All 7 AppleFoundationAvailabilityTests remain green

## Task Commits

1. **Task 1: Token-Property + sauberer Observer-Setup + Cleanup in willTerminate** - `619d510` (fix)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `BlitzText/App/AppDelegate.swift` — Added observer token property; fixed observer setup to store token; extended applicationWillTerminate with removeObserver call; removed dead code

## Decisions Made

- Kept `[weak self]` capture only — `[weak settingsStore]` was redundant because the closure body already accesses the store via `self?.settingsStore`, not the captured variable. Removing it is safe and eliminates the dead `_ = settingsStore` statement.
- `removeObserver` placed before `hotkeyManager.stop()` in termination to ensure the observer cannot fire during teardown.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- CR-01 BLOCKER from 08-REVIEW.md is resolved
- AppDelegate lifecycle management is now correct with no accumulating stale observers
- Phase 8 test suite (7/7 AppleFoundationAvailabilityTests) remains green

## Self-Check: PASSED

- BlitzText/App/AppDelegate.swift: FOUND
- .planning/phases/08-apple-foundation-rewrite-backend/08-06-SUMMARY.md: FOUND
- Task commit 619d510: FOUND

---
*Phase: 08-apple-foundation-rewrite-backend*
*Completed: 2026-05-04*
