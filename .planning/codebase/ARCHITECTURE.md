<!-- refreshed: 2026-04-30 -->
# Architecture

**Analysis Date:** 2026-04-30

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         User-Facing Surface                         │
├──────────────────┬──────────────────┬──────────────────┬────────────┤
│  Menu-Bar Icon   │  Recording HUD   │  Settings Window │ History    │
│ `MenuBar/`       │  `UI/`           │  `Settings/`     │ `History/` │
│ MenuBarController│ RecordingHUDCtrl │ SettingsWindowCtl│ HistoryWnd │
└────────┬─────────┴────────┬─────────┴────────┬─────────┴─────┬──────┘
         │                  │                  │               │
         │   subscribes via Combine to ModeProcessor.$state    │
         │                                                     │
         ▼                                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   Pipeline Orchestrator (MainActor)                 │
│              `Modes/ModeProcessor.swift` (ObservableObject)         │
│                                                                     │
│  start(mode) → recorder.start() → state=.recording                  │
│  stop()      → recorder.stop()   → runPipeline()                    │
│  toggle(mode)                                                       │
└──┬─────────────┬──────────────────┬──────────────────────┬──────────┘
   │             │                  │                      │
   ▼             ▼                  ▼                      ▼
┌──────────┐ ┌────────────────────────────┐ ┌────────────────┐ ┌──────────────┐
│ Hotkeys  │ │ TranscriptionService proto │ │ RewriteService │ │ TextInserter │
│ CGEvent  │ │  - WhisperAPIClient        │ │  - OpenAIChat  │ │ NSPasteboard │
│ Tap      │ │  - LocalWhisperClient      │ │    Client      │ │ + CGEvent    │
│          │ │    (WhisperKit / CoreML)   │ │   (gpt-4o-mini)│ │   ⌘V         │
│          │ │  - ParakeetClient          │ │                │ │              │
│          │ │    (FluidAudio / MLX)      │ │                │ │              │
└──────────┘ └────────────┬───────────────┘ └────────┬───────┘ └──────┬───────┘
                          │                          │                 │
                          ▼                          ▼                 ▼
                    ┌────────────────────────────────────────────────────┐
                    │ Stores: SettingsStore (UserDefaults), HistoryStore │
                    │ (~/Library/Application Support/BlitzText/),        │
                    │ LocalModelManager (downloaded CoreML models),      │
                    │ Keychain (legacy, currently unused for API key)    │
                    └────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `BlitzTextApp` | SwiftUI `@main` entry; only hosts `Settings { EmptyView() }` so the app runs as `LSUIElement`/accessory | `BlitzText/App/BlitzTextApp.swift` |
| `AppDelegate` | Single-instance enforcement, bootstrap of all controllers, hotkey wiring, mic-permission warm-up, temp cleanup | `BlitzText/App/AppDelegate.swift` |
| `MenuBarController` | `NSStatusItem` + transient `NSPopover` hosting `HUDView`; mirrors `ModeProcessor.state` into the bolt icon tint | `BlitzText/MenuBar/MenuBarController.swift` |
| `HotkeyManager` | Global `fn`+modifier detection via `CGEventTap` on `.flagsChanged`; dispatches `(Mode, Action)` tuples to `ModeProcessor` | `BlitzText/Hotkeys/HotkeyManager.swift` |
| `AudioRecorder` | `AVAudioEngine` capture → 16 kHz mono Int16 WAV in `tmp/`; live RMS level, silence/short-cut filter | `BlitzText/Audio/AudioRecorder.swift` |
| `ModeProcessor` | Pipeline orchestrator: recorder → transcriber → rewriter → inserter; publishes `State` for UI | `BlitzText/Modes/ModeProcessor.swift` |
| `Mode` | Enum of the three trigger modes; owns default rewrite system prompts | `BlitzText/Modes/Mode.swift` |
| `TranscriptionService` (protocol) | Backend-agnostic transcription contract (`audioURL, language, prompt -> String`) | `BlitzText/Transcription/TranscriptionService.swift` |
| `WhisperAPIClient` | OpenAI `/v1/audio/transcriptions` multipart client | `BlitzText/Transcription/WhisperAPIClient.swift` |
| `LocalWhisperClient` | WhisperKit/CoreML on-device transcription | `BlitzText/Transcription/LocalWhisperClient.swift` |
| `ParakeetClient` | FluidAudio Parakeet TDT v3 + optional speaker diarization | `BlitzText/Transcription/ParakeetClient.swift` |
| `LocalModelManager` | Catalog, download progress, activation, deletion of WhisperKit CoreML models under `~/Library/Application Support/BlitzText/Models/` | `BlitzText/Transcription/LocalModelManager.swift` |
| `ModelDownloader` | HTTP download helper for CoreML model packages | `BlitzText/Transcription/ModelDownloader.swift` |
| `RewriteService` (protocol) + `OpenAIChatClient` | gpt-4o-mini chat-completion rewrite for Plus / Rant modes | `BlitzText/Rewrite/RewriteService.swift`, `BlitzText/Rewrite/OpenAIChatClient.swift` |
| `TextInserter` | Clipboard write (`NSPasteboard`) + optional `⌘V` synthesis (`CGEvent`); skips self-paste | `BlitzText/Insertion/TextInserter.swift` |
| `SettingsStore` | `@Published` preferences mirrored to `UserDefaults` JSON; API key stored in `UserDefaults` (not Keychain — see comment in file) | `BlitzText/Settings/SettingsStore.swift` |
| `Keychain` | Generic-password Keychain wrapper (currently dormant — kept for future Apple-Team-ID builds) | `BlitzText/Settings/Keychain.swift` |
| `PermissionsHelper` | Reads/opens Mic + Accessibility TCC status, deep-links into System Settings | `BlitzText/Settings/PermissionsHelper.swift` |
| `SettingsWindowController` + `SettingsView` | Standalone `NSWindow` (because `.accessory` apps can't show the App-menu Settings item) hosting tabbed SwiftUI prefs | `BlitzText/Settings/SettingsWindowController.swift`, `BlitzText/Settings/SettingsView.swift` |
| `RecordingHUDController` + `HUDView` | Floating non-activating `NSPanel` with live audio level; the popover content view shown from the menu bar | `BlitzText/UI/RecordingHUDController.swift`, `BlitzText/UI/HUDView.swift` |
| `HistoryStore` + `HistoryView` + `HistoryWindowController` | Last 100 transcriptions persisted to `~/Library/Application Support/BlitzText/history.json` | `BlitzText/History/*.swift` |
| `EigennamenAnalyzer` | NLTagger NER + raw↔polished diff to extract proper-noun candidates | `BlitzText/ProperNouns/EigennamenAnalyzer.swift` |
| `EigennamenAISuggester` | Async OpenAI call to extract proper nouns from text | `BlitzText/ProperNouns/EigennamenAISuggester.swift` |
| `SuggestionPresenter` + `SuggestionToastController` | Queues candidates and shows accept/dismiss toast at top of screen | `BlitzText/ProperNouns/SuggestionPresenter.swift`, `BlitzText/ProperNouns/SuggestionToastController.swift` |
| `Log` | Single shared file logger | `BlitzText/App/Log.swift` |

## Pattern Overview

**Overall:** macOS menu-bar agent (`LSUIElement = true`) implementing a thin **MVVM-style** layout:

- **View** = SwiftUI (`HUDView`, `SettingsView`, `HistoryView`, `RecordingHUDView`) hosted inside AppKit shells (`NSStatusItem`, `NSWindow`, `NSPanel`).
- **ViewModel-ish** = `ModeProcessor` and the various `…Store` classes — `ObservableObject` + `@Published` so SwiftUI views and AppKit controllers can both subscribe via Combine.
- **Model / Services** = swappable protocol-backed clients (`TranscriptionService`, `RewriteService`).
- **Controllers** = AppKit glue (`MenuBarController`, `RecordingHUDController`, `SuggestionToastController`, `*WindowController`) that bridge Combine state into AppKit windowing.

**Key Characteristics:**
- Single `@MainActor` orchestrator (`ModeProcessor`) owns all pipeline state — no shared mutable state across actors.
- Backends are protocol-bound and selected per call by reading `settings.backend`, so swapping cloud↔local is a one-line settings change.
- One global event tap (`HotkeyManager`) is the sole input source — no responder-chain key handling, no first-responder shortcuts.
- App is intentionally **un-sandboxed** (MVP) so `CGEventTap` + Accessibility-driven `⌘V` synthesis work without sandbox-broker plumbing (`project.yml`: `com.apple.security.app-sandbox: false`).

## Layers

**App Lifecycle / Bootstrap (`BlitzText/App/`):**
- Purpose: SwiftUI entry, NSApplicationDelegate, single-instance enforcement, controller wiring.
- Depends on: every other layer (instantiates them).
- Used by: macOS launch.

**Input (`BlitzText/Hotkeys/`):**
- Purpose: Translate global keyboard events into `(Mode, Action)`.
- Depends on: `SettingsStore` (for `triggerMode`), `Mode`.
- Used by: `AppDelegate` closure → `ModeProcessor`.

**Capture (`BlitzText/Audio/`):**
- Purpose: Microphone → temporary 16 kHz mono Int16 WAV.
- Depends on: AVFoundation only.
- Used by: `ModeProcessor.start()` / `stop()`; `RecordingHUDView` reads `currentLevel`.

**Transcription (`BlitzText/Transcription/`):**
- Purpose: Audio file → text. Three interchangeable implementations behind one protocol.
- Depends on: `SettingsStore` (api key, model id, language), `LocalModelManager` (for `.local` backend).
- Used by: `ModeProcessor.runPipeline()`.

**Rewrite (`BlitzText/Rewrite/`):**
- Purpose: gpt-4o-mini chat completion with mode-specific system prompt.
- Depends on: `SettingsStore` (api key, model name).
- Used by: `ModeProcessor.runPipeline()` for `.blitztextPlus` and `.blitztextRant` only.

**Pipeline (`BlitzText/Modes/`):**
- Purpose: Stitch input → capture → transcription → optional rewrite → output. Owns `State` machine.
- Depends on: every service layer.
- Used by: `MenuBarController`, `RecordingHUDController`, `HotkeyManager` callback.

**Output (`BlitzText/Insertion/`):**
- Purpose: Clipboard + optional `⌘V` simulation.
- Depends on: AppKit + CoreGraphics only.
- Used by: `ModeProcessor.deliver()`.

**Persistence (`BlitzText/Settings/`, `BlitzText/History/`):**
- Purpose: User prefs (UserDefaults JSON), API key (UserDefaults), Keychain wrapper (currently unused for the live key path), transcription history (JSON in `~/Library/Application Support/BlitzText/`).
- Used by: `ModeProcessor`, every UI layer.

**UI (`BlitzText/UI/`, `BlitzText/MenuBar/`, plus SwiftUI views in `Settings/` and `History/`):**
- Purpose: Menu-bar icon, popover HUD, recording HUD panel, settings window, history window, proper-noun suggestion toast.
- Depends on: `ModeProcessor.$state`, `SettingsStore`, `HistoryStore`, `LocalModelManager`.

**Proper Nouns (`BlitzText/ProperNouns/`):**
- Purpose: Heuristic + AI proper-noun extraction with toast UI to add to glossary.
- Depends on: `SettingsStore.properNouns`, NLTagger.
- Triggered by: `ModeProcessor.runPipeline()` after delivery.

## Data Flow

### Primary Recording Path (single end-to-end run)

1. User presses `fn+Shift` (or `+Control` / `+Option`). macOS posts a `flagsChanged` event.
2. `CGEventTap` callback in `HotkeyManager.handleFlagsChanged` (`BlitzText/Hotkeys/HotkeyManager.swift:83`) decodes the modifier combo into a `Mode` and dispatches `.start` (hold mode) or `.toggle` (toggle mode) on the main queue.
3. `AppDelegate`'s closure (`BlitzText/App/AppDelegate.swift:65`) routes to `ModeProcessor.start(mode:)` (`BlitzText/Modes/ModeProcessor.swift:59`).
4. `ModeProcessor.start` calls `AudioRecorder.start()` (`BlitzText/Audio/AudioRecorder.swift:26`), which installs a tap on `engine.inputNode`, opens an `AVAudioFile` at `…/blitztext-<UUID>.wav`, starts the engine, and sets `state = .recording(mode)`.
5. Combine subscribers react: `MenuBarController.updateIcon` tints the bolt green (`BlitzText/MenuBar/MenuBarController.swift:78`); `RecordingHUDController.show` displays the floating panel (`BlitzText/UI/RecordingHUDController.swift:32`); `HUDView` updates the live level bar.
6. User releases the keys → `flagsChanged` fires again, `HotkeyManager` emits `.stop`, `ModeProcessor.stop()` calls `AudioRecorder.stop()`. If duration < 0.3 s **or** peak < 0.005, the WAV is discarded and `state = .idle` (no API call — prevents Whisper hallucinations).
7. Otherwise `runPipeline(mode:audioURL:)` runs:
   - Selects transcriber by `settings.backend` (`ModeProcessor.swift:102-108`).
   - `state = .transcribing(mode)`; calls `transcriber.transcribe(audioURL:language:prompt:)` with a glossary/context prompt assembled by `makeWhisperPrompt()`.
   - Empty result or hallucination match (`isLikelyHallucination`, `ModeProcessor.swift:227`) → silent abort.
   - For `.blitztext`: passes raw text straight through.
   - For `.blitztextPlus` / `.blitztextRant`: `state = .rewriting(mode)`; calls `OpenAIChatClient.rewrite` with `makeRewriteSystemPrompt(for:)`.
8. `deliver(_:)` calls `TextInserter.copyToClipboard` and, if `settings.autoInsert`, `simulatePaste()` (CGEvent ⌘V, gated by Accessibility permission and self-paste guard).
9. `HistoryStore.append` records the entry; the temp WAV is deleted by `defer` in `runPipeline`.
10. Async, on a detached task: `EigennamenAnalyzer.candidates` (heuristic) and optionally `EigennamenAISuggester.extract` (AI) feed `SuggestionPresenter.enqueue`, which `SuggestionToastController` displays at the top of the screen.
11. `state = .idle` — UI returns to the bolt-icon idle tint.

### Settings / Model-Activation Flow

1. User opens Settings via menu-bar gear button → `MenuBarController` closes popover and calls `SettingsWindowController.show()`.
2. `SettingsView` reads/writes `SettingsStore` (`@Published` → debounced JSON save to `UserDefaults`, key `de.reinholds.blitztext.settings`).
3. Activating a local Whisper model in the Models tab calls `LocalModelManager.activate(_:)`; its `onActivate` callback (set in `AppDelegate.bootstrap`) re-triggers `ModeProcessor.preloadLocalModelIfActive()` so the next recording doesn't pay the 1–3 min CoreML compile cost.

### State Management

- One source of truth per concern: `ModeProcessor.state` for pipeline phase, `SettingsStore.@Published` for prefs, `HistoryStore.entries` for history, `LocalModelManager` for model lifecycle.
- All UI subscribes via Combine (`AnyCancellable` stored on each controller). No notifications, no singletons except `Keychain.shared` and `Log`.

## Key Abstractions

**`TranscriptionService` protocol** (`BlitzText/Transcription/TranscriptionService.swift`)
- Purpose: Decouple `ModeProcessor` from the actual STT engine.
- Implementations: `WhisperAPIClient`, `LocalWhisperClient`, `ParakeetClient`.
- Selection: `ModeProcessor.runPipeline` switch on `settings.backend`.
- Errors: shared `TranscriptionError` enum (missing key, http, network, decoding, backend-unavailable).

**`RewriteService` protocol** (`BlitzText/Rewrite/RewriteService.swift`)
- Purpose: Same idea for the post-transcription text-shaping step.
- Sole implementation today: `OpenAIChatClient`.
- Future hook noted in README backlog: Apple Foundation Models on macOS 26.

**`Mode` enum** (`BlitzText/Modes/Mode.swift`)
- Three cases: `.blitztext`, `.blitztextPlus`, `.blitztextRant`.
- Owns title, subtitle, SF-Symbol, and the **default** rewrite system prompt — actual prompt is composed in `ModeProcessor.makeRewriteSystemPrompt(for:)` from `customPromptPlus` / `customPromptRant`, `WritingStyle.promptHint`, `context`, and `properNouns`.

**`ModeProcessor` orchestrator** (`BlitzText/Modes/ModeProcessor.swift`)
- The only object that knows about the *whole* pipeline; no other class chains services.
- Lazy-instantiates each backend so unused ones never load.

**`State` enum** (`ModeProcessor.State`): `.idle`, `.recording(Mode)`, `.transcribing(Mode)`, `.rewriting(Mode)`, `.error(String)`. Drives all UI tinting and HUD visibility.

## Entry Points

**App launch (`BlitzTextApp` → `AppDelegate`)**
- Location: `BlitzText/App/BlitzTextApp.swift`, `BlitzText/App/AppDelegate.swift:18`
- Triggers: macOS launch.
- Responsibilities: enforce single instance, set `.accessory` activation policy, instantiate every controller, start `HotkeyManager`, preload active local model, request mic permission proactively, optionally auto-open Settings (`--settings` flag or empty API key).

**Global hotkey (`HotkeyManager.start`)**
- Location: `BlitzText/Hotkeys/HotkeyManager.swift:29`
- Triggers: any global key event (`.flagsChanged` / `.keyDown`) once Accessibility is granted.
- Responsibilities: decode `fn`+modifier combos, debounce (50 ms hold, 300 ms toggle), bridge to `ModeProcessor` on the main queue.

**Menu-bar click (`MenuBarController.togglePopover`)**
- Location: `BlitzText/MenuBar/MenuBarController.swift:68`
- Triggers: user click on the bolt icon.
- Responsibilities: show/hide the SwiftUI HUD popover.

**Settings re-launch flag**
- Location: `BlitzText/App/AppDelegate.swift:97`
- Triggers: launching with `--settings` argument (workaround for the menubar being too full to find the icon).
- Responsibilities: forces `SettingsWindowController.show()` on launch.

## Architectural Constraints

- **Threading:** `ModeProcessor`, `MenuBarController`, `RecordingHUDController`, `SettingsWindowController`, `HistoryStore`, `LocalModelManager`, and `AppDelegate` are all `@MainActor`. Long-running work (network upload, local Whisper inference, FluidAudio inference, model download) happens via `async`/`await` so the actor yields. Detached tasks are used only for fire-and-forget AI proper-noun extraction and model warm-up.
- **Concurrency mode:** `SWIFT_STRICT_CONCURRENCY: minimal` (see `project.yml:65`). Service classes annotate `@unchecked Sendable` to cross actor boundaries (`HotkeyManager`, `WhisperAPIClient`, `OpenAIChatClient`, `LocalWhisperClient`, `ParakeetClient`, `Keychain`).
- **Global state:** Two true singletons — `Keychain.shared` (`BlitzText/Settings/Keychain.swift:12`) and the file-based `Log`. Everything else is dependency-injected from `AppDelegate.bootstrap`.
- **Sandbox:** Off in MVP (`com.apple.security.app-sandbox: false`). Enabling it would break `CGEventTap` for `⌘V` synthesis and complicate Accessibility prompts.
- **Single instance:** Enforced in `applicationWillFinishLaunching` by walking `NSRunningApplication.runningApplications(withBundleIdentifier:)` and `exit(0)` if another PID owns the bundle id.
- **No circular imports detected** — module is single-target, but the dependency graph is strictly bottom-up (App → Pipeline → Services → Stores).

## Anti-Patterns

### API key in `UserDefaults` instead of Keychain

**What happens:** `SettingsStore.apiKey` (`BlitzText/Settings/SettingsStore.swift:31`) reads/writes `UserDefaults` under `de.reinholds.blitztext.apiKey`, even though `Keychain.swift` exists.
**Why it's wrong here:** Keys in `UserDefaults` live in `~/Library/Preferences/de.reinholds.blitztext.plist` in plaintext. The file comment explains the trade-off: self-signed-dev builds re-prompt the Keychain on every code-hash change.
**Do this instead:** Once the app ships with a stable Apple-Team-ID signing identity, switch back to `Keychain.shared.write(value:account:)` — `Keychain.swift` is already wired and ready.

### `@unchecked Sendable` everywhere

**What happens:** Every service class is `@unchecked Sendable` (e.g., `HotkeyManager`, `WhisperAPIClient`, `LocalWhisperClient`).
**Why it's wrong here:** Bypasses Swift 6 concurrency-checking. Right now it's safe because mutation is funnelled through `@MainActor` callers, but a future refactor could introduce data races silently.
**Do this instead:** When tightening concurrency (move `SWIFT_STRICT_CONCURRENCY` from `minimal` → `complete`), audit each `@unchecked Sendable` and replace with proper actor isolation or value types.

### Synchronous mic-permission wait via `DispatchSemaphore`

**What happens:** `AudioRecorder.ensureMicrophonePermissionSync` (`BlitzText/Audio/AudioRecorder.swift:161`) blocks on a semaphore while `AVCaptureDevice.requestAccess` calls back.
**Why it's wrong here:** Called from `recorder.start()` which can run on the main actor — risks UI hitch on first launch when the prompt appears.
**Do this instead:** Move permission prompt to launch-time (already partially done in `AppDelegate.bootstrap` at `:88`). Once first-run prompt is reliable, drop the semaphore and just throw `.micDenied` if not authorized at recording time.

## Error Handling

**Strategy:** Typed error enums, surfaced into `ModeProcessor.State.error(String)`, then read by the UI for human-readable display.

**Patterns:**
- `TranscriptionError: LocalizedError` (`BlitzText/Transcription/TranscriptionService.swift:8`) provides German `errorDescription` for each case.
- `AudioRecorder.RecorderError.micDenied` mapped by `ModeProcessor.humanReadable` (`ModeProcessor.swift:249`) to a "go to System Settings" hint.
- Network/decoding/HTTP failures from `WhisperAPIClient` are wrapped at the boundary — `ModeProcessor` never re-interprets a raw `URLError`.
- Hallucination filter (`ModeProcessor.isLikelyHallucination`) silently discards known-bad Whisper outputs (Amara-Untertitel etc.) rather than showing them.

## Cross-Cutting Concerns

**Logging:** `Log.write(_:)` in `BlitzText/App/Log.swift` — single shared file logger. Every subsystem uses it. No `os_log`, no levels.

**Validation:** Input is validated at the edges only:
- `AudioRecorder.stop` rejects too-short / too-quiet recordings.
- `ModeProcessor.runPipeline` rejects empty or hallucinated transcripts.
- API responses validated by JSON `Decodable` structs inside each client.

**Authentication:** Single secret — the OpenAI API key in `SettingsStore.apiKey`. Read just-in-time inside each network client (no caching, no header injection layer).

**Permissions:** Centralized in `BlitzText/Settings/PermissionsHelper.swift` — Mic + Accessibility status checks and System-Settings deep-links.

**Persistence locations:**
- `UserDefaults`: prefs JSON (`de.reinholds.blitztext.settings`) + API key (`de.reinholds.blitztext.apiKey`).
- `~/Library/Application Support/BlitzText/history.json`: transcription log (last 100).
- `~/Library/Application Support/BlitzText/Models/<variant>/`: downloaded WhisperKit CoreML packages.
- `tmp/blitztext-<UUID>.wav`: in-flight recordings (cleaned on launch + after each pipeline run).

---

*Architecture analysis: 2026-04-30*
