---
phase: 08-apple-foundation-rewrite-backend
plan: 07
subsystem: settings-store
tags: [privacy, auto-fallback, bootstrap, settings-store, tdd, cr-02]
dependency_graph:
  requires: []
  provides: [cold-boot-auto-fallback, availability-reset-on-recovery]
  affects: [BlitzText/Settings/SettingsStore.swift, BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift]
tech_stack:
  added: []
  patterns: [unconditional-call-with-idempotency-guard, tdd-red-green]
key_files:
  created: []
  modified:
    - BlitzText/Settings/SettingsStore.swift
    - BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift
decisions:
  - "Unconditional applyAutoFallbackIfNeeded() call instead of state-equality guard — Self-Idempotency-Guard (didAutoFallbackToOpenAI) is the real multi-fire protection"
  - "Reset didAutoFallbackToOpenAI on recovery to .available — allows re-trigger on subsequent loss"
  - "Updated test_refresh_idempotent to test Self-Idempotency-Guard semantics (not removed state-equality guard)"
metrics:
  duration: "~8 minutes"
  completed: "2026-05-04"
  tasks_completed: 2
  files_modified: 2
---

# Phase 08 Plan 07: CR-02 Cold-Boot Privacy Invariante Fix Summary

**One-liner:** Unconditional `applyAutoFallbackIfNeeded()` call in `refreshFoundationAvailability()` plus `didAutoFallbackToOpenAI = false` reset on `.available` recovery, pinned by 9/9 passing TDD regression tests.

## What Was Built

CR-02 blocker from 08-REVIEW.md: `refreshFoundationAvailability()` guarded its `applyAutoFallbackIfNeeded()` call behind `if new != foundationAvailability`. At cold boot, the hardcoded initial state `.unavailable(.modelNotReady)` matched the provider result, so the inequality check never fired and the auto-fallback was silently skipped — even when all conditions (API-Key + .appleFoundation backend) were met.

**Fix:** Remove the state-equality guard. Call `applyAutoFallbackIfNeeded()` unconditionally on every refresh. The Self-Idempotency-Guard (`guard !didAutoFallbackToOpenAI else { return }`) inside `applyAutoFallbackIfNeeded()` remains intact and prevents double-activation on multi-fire notifications.

**Recovery path:** When the provider returns `.available`, `didAutoFallbackToOpenAI` is reset to `false` so a subsequent loss of availability triggers a fresh auto-fallback.

## Tasks

| Task | Type | Commit | Description |
|------|------|--------|-------------|
| 1 | TDD RED | e5da445 | Add 2 CR-02 regression tests (cold-boot + recovery reset) — both confirmed failing |
| 2 | TDD GREEN | 97ba68e | Fix `refreshFoundationAvailability()` + update idempotency test semantics — 9/9 pass |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated test_refresh_idempotent to reflect correct semantics**
- **Found during:** Task 2 (GREEN)
- **Issue:** `test_refresh_idempotent_doesNotReTriggerOnSameState` tested the now-removed state-equality guard behavior. After the fix, the test manually reset `didAutoFallbackToOpenAI = false` and expected no re-trigger — but unconditional calling means a manual flag reset WILL trigger again (which is correct post-fix behavior).
- **Fix:** Renamed test to `test_refresh_idempotent_selfIdempotencyGuardPreventsReTrigger` and updated it to verify the Self-Idempotency-Guard (`guard !didAutoFallbackToOpenAI`) prevents re-trigger without manual flag reset — the behavior that actually matters.
- **Files modified:** BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift
- **Commit:** 97ba68e

**2. Adapted plan's `provider.next` API to `provider.state`**
- **Found during:** Task 1 (RED)
- **Issue:** Plan used `provider.next = .unavailable(.modelNotReady)` but `FakeFoundationAvailabilityProvider` exposes `state` not `next`.
- **Fix:** Used `state` property throughout, consistent with existing test suite.

## Verification

### Grep Gates (SettingsStore.swift)

| Check | Result |
|-------|--------|
| `if new != foundationAvailability` removed | 0 matches (PASS) |
| `didAutoFallbackToOpenAI = false` present | 1 match (PASS) |
| `applyAutoFallbackIfNeeded()` count >= 2 | 5 matches (PASS) |
| `guard !didAutoFallbackToOpenAI else { return }` present | 1 match (PASS) |
| Privacy invariant: `!apiKey.isEmpty` guard | present in applyAutoFallbackIfNeeded (PASS) |

### Test Results

- AppleFoundationAvailabilityTests: 9/9 PASS
- AppleFoundationRewriteClientTests: 6/6 PASS (regression)
- RewriteBackendDispatchTests: 5/5 PASS (regression)

## Known Stubs

None.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced. Privacy invariant (`!apiKey.isEmpty` guard in `applyAutoFallbackIfNeeded()`) unchanged — no silent OpenAI fallback without API-Key.

## Self-Check: PASSED

- BlitzText/Settings/SettingsStore.swift: FOUND
- BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift: FOUND
- Commit e5da445: FOUND
- Commit 97ba68e: FOUND
