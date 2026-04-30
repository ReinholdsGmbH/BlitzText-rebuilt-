# BlitzText

Native macOS-Menu-Bar-Diktat-App (Swift 6, SwiftUI + AppKit). Hotkey → Aufnahme → Whisper/Parakeet → optional Rewrite → Clipboard.

## GSD Workflow Active

This project uses GSD (Get-Shit-Done) for structured planning and execution.
Project artifacts live in `.planning/`:

- `PROJECT.md` — what we're building, core value, requirements buckets
- `REQUIREMENTS.md` — 18 v1 requirements across SPK / DIA / STAB / TEST
- `ROADMAP.md` — 6 v1 phases + 3 backlog (999.1–3)
- `STATE.md` — current focus and progress
- `codebase/` — Stack/Architecture/Conventions/Concerns reference (auto-generated, refresh via `/gsd-map-codebase`)
- `phases/<N>-<slug>/` — per-phase plans, executions, verifications
- `config.json` — workflow knobs (granularity, parallelization, model profile)

**Current milestone:** Sprecher-Profile + Stabilisierung
**Core value:** Vom Hotkey bis zum eingefügten Text wenige Sekunden — und der Text muss benutzbar sein.

## Active Phase

Start with `/gsd-discuss-phase 1` (Phase 1: Stabilisierung & Doku-Drift) before planning.

## Project-specific Rules

- German UI strings, English code identifiers (Swift convention).
- Swift 6 with `SWIFT_STRICT_CONCURRENCY: minimal` (deliberate, due to CGEvent/AVAudioEngine/Keychain C-callback surface).
- No external-cloud speaker ID — speaker profiles must stay on-device (DSGVO Art. 9).
- TranscriptionService protocol abstracts backends — keep new backends behind it.
