---
phase: 2
slug: test-fundament
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-30
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Swift, Xcode 26.4.1) |
| **Config file** | `project.yml` (XcodeGen — Wave 0 adds `BlitzTextTests` target + scheme) |
| **Quick run command** | `xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/<Suite> CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO` |
| **Full suite command** | `xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO` |
| **Estimated runtime** | ~10–20 seconds (target: < 30s, no flakes over 3 runs) |

---

## Sampling Rate

- **After every task commit:** Run quick command scoped to the affected suite
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green three times in a row
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

(Populated by planner — one row per task in 02-01-PLAN.md / 02-02-PLAN.md / 02-03-PLAN.md.)

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 0 | TEST-01 | — | N/A | infra | `xcodegen generate && xcodebuild -list` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `project.yml` — append `BlitzTextTests` target (`bundle.unit-test` preset) + explicit `schemes` block
- [ ] `BlitzTextTests/` directory + at least one placeholder XCTestCase so the target builds
- [ ] `HotkeyManager` refactor: extract pure `decideTransition(...)` from C-callback chain (testability seam)
- [ ] `ModeProcessor.init` refactor: optional injectable `transcriber` / `rewriter` / `recorder` parameters with production defaults
- [ ] `BlitzTextTests/Support/` test doubles: `FakeTranscriptionService`, `FakeAudioRecorder`, `FakeRewriter` (or equivalent)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real CGEventTap firing under Accessibility-TCC grant | TEST-02 (integration) | Requires system permission prompt; unit tests cover `decideTransition` purely | Granted Accessibility → press configured hotkey → recording starts |

*Pipeline error paths and hotkey state-machine logic are all automated via injected fakes — no manual verification needed.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags (xcodebuild runs once per invocation)
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
