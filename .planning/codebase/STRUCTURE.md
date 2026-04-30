# Codebase Structure

**Analysis Date:** 2026-04-30

## Directory Layout

```
BlitzText/                            # repo root
├── README.md                         # User-facing docs (German)
├── ARCHITECTURE.md                   # High-level architecture overview
├── RISKS.md                          # Known edge cases and risks
├── project.yml                       # XcodeGen source — generates the .xcodeproj
├── BlitzText.xcodeproj/              # Generated; gitignored
├── Scripts/                          # Build / packaging shell scripts (build.sh)
├── Mocks/                            # Static design references / screenshots
├── build/                            # `xcodebuild` output → BlitzText.app
├── dist/                             # Distributable artefacts (DMG/zip)
├── .planning/codebase/               # GSD codebase maps (this file lives here)
└── BlitzText/                        # ► Application source root
    ├── App/                          # Entry point, NSApplicationDelegate, logging
    │   ├── BlitzTextApp.swift
    │   ├── AppDelegate.swift
    │   └── Log.swift
    ├── MenuBar/                      # Status item + popover plumbing
    │   └── MenuBarController.swift
    ├── Hotkeys/                      # CGEventTap fn-modifier detection
    │   └── HotkeyManager.swift
    ├── Audio/                        # Microphone capture → 16 kHz mono WAV
    │   └── AudioRecorder.swift
    ├── Transcription/                # STT backends behind TranscriptionService
    │   ├── TranscriptionService.swift   # protocol + error enum
    │   ├── WhisperAPIClient.swift       # OpenAI cloud
    │   ├── LocalWhisperClient.swift     # WhisperKit (CoreML)
    │   ├── ParakeetClient.swift         # FluidAudio Parakeet TDT v3
    │   ├── LocalModelManager.swift      # download / activate / delete CoreML models
    │   └── ModelDownloader.swift        # raw HTTP downloader
    ├── Rewrite/                      # Post-transcription text shaping
    │   ├── RewriteService.swift         # protocol
    │   └── OpenAIChatClient.swift       # gpt-4o-mini chat completion
    ├── Modes/                        # Mode enum + pipeline orchestrator
    │   ├── Mode.swift
    │   └── ModeProcessor.swift
    ├── Insertion/                    # Clipboard + ⌘V synthesis
    │   └── TextInserter.swift
    ├── Settings/                     # Prefs, Keychain wrapper, Settings UI
    │   ├── SettingsStore.swift
    │   ├── Keychain.swift
    │   ├── PermissionsHelper.swift
    │   ├── SettingsWindowController.swift
    │   └── SettingsView.swift           # Largest file (~498 lines)
    ├── History/                      # Transcription history (last 100)
    │   ├── HistoryStore.swift
    │   ├── HistoryView.swift
    │   └── HistoryWindowController.swift
    ├── ProperNouns/                  # NER + AI suggestion + toast UI
    │   ├── EigennamenAnalyzer.swift
    │   ├── EigennamenAISuggester.swift
    │   ├── SuggestionPresenter.swift
    │   └── SuggestionToastController.swift
    ├── UI/                           # SwiftUI views hosted by AppKit shells
    │   ├── HUDView.swift                # Menu-bar popover content
    │   └── RecordingHUDController.swift # Floating NSPanel during recording
    └── Resources/
        ├── Assets.xcassets/             # AppIcon
        ├── Info.plist                   # Generated from project.yml
        └── BlitzText.entitlements       # Generated from project.yml
```

## Directory Purposes

**`BlitzText/App/`**
- Purpose: Process bootstrap.
- Contains: SwiftUI `@main` (`BlitzTextApp.swift`), `NSApplicationDelegate` (`AppDelegate.swift`), shared file logger (`Log.swift`).
- Key files: `BlitzText/App/AppDelegate.swift` is the wiring hub — every controller is instantiated here.

**`BlitzText/MenuBar/`**
- Purpose: `NSStatusItem` lifecycle.
- Contains: `MenuBarController.swift` (single file).
- Key files: hosts the popover that mounts `HUDView` from `BlitzText/UI/HUDView.swift`.

**`BlitzText/Hotkeys/`**
- Purpose: Global keyboard input.
- Contains: `HotkeyManager.swift` — `CGEventTap` on `.flagsChanged`, debouncing, mode-detection state machine.

**`BlitzText/Audio/`**
- Purpose: Microphone capture only.
- Contains: `AudioRecorder.swift` — `AVAudioEngine`, format conversion to 16 kHz mono Int16 WAV, live RMS metering, silence/short-cut filter.

**`BlitzText/Transcription/`**
- Purpose: Audio-file → text. Multiple swappable backends behind one protocol.
- Contains: protocol (`TranscriptionService.swift`), three implementations, model lifecycle manager + downloader.
- Key files: `TranscriptionService.swift` defines the contract; new backends implement it and are wired into `ModeProcessor.runPipeline`'s switch.

**`BlitzText/Rewrite/`**
- Purpose: Optional gpt-4o-mini rewrite step (Plus / Rant modes).
- Contains: `RewriteService.swift` (protocol) + `OpenAIChatClient.swift`.

**`BlitzText/Modes/`**
- Purpose: The pipeline brain.
- Contains: `Mode.swift` (enum + default prompts) and `ModeProcessor.swift` (orchestrator + state machine).

**`BlitzText/Insertion/`**
- Purpose: Output to user.
- Contains: `TextInserter.swift` — clipboard write, optional `⌘V` synthesis with self-paste guard.

**`BlitzText/Settings/`**
- Purpose: Preferences, secrets, permissions UI.
- Contains: `SettingsStore` (`@Published` + `UserDefaults` JSON), `Keychain.swift` (currently dormant), `PermissionsHelper.swift`, the `NSWindowController` and the SwiftUI tabbed settings view (`SettingsView.swift` — largest file at ~498 lines).

**`BlitzText/History/`**
- Purpose: Last 100 transcriptions, persisted to `~/Library/Application Support/BlitzText/history.json`.
- Contains: store + SwiftUI list view + `NSWindowController`.

**`BlitzText/ProperNouns/`**
- Purpose: Detect proper nouns from each transcript and offer to add them to the user's glossary.
- Contains: heuristic (`EigennamenAnalyzer` — NLTagger NER + raw↔polished diff), AI suggester, toast presenter, toast controller.

**`BlitzText/UI/`**
- Purpose: Shared SwiftUI views and the floating recording HUD.
- Contains: `HUDView.swift` (popover content), `RecordingHUDController.swift` (non-activating `NSPanel` + the inline `RecordingHUDView`).

**`BlitzText/Resources/`**
- Purpose: Asset catalog + generated build artefacts (Info.plist, entitlements). Both `.plist` and `.entitlements` are produced by `xcodegen` from `project.yml` — do **not** edit them by hand.

## Key File Locations

**Entry Points:**
- `BlitzText/App/BlitzTextApp.swift` — SwiftUI `@main`. Body is intentionally `Settings { EmptyView() }` because the app runs as `LSUIElement`/accessory.
- `BlitzText/App/AppDelegate.swift` — bootstrap, single-instance enforcement, controller wiring.

**Configuration:**
- `project.yml` — XcodeGen source of truth. Bundle ID, deployment target (macOS 26), Swift version (6.0), package deps (WhisperKit, FluidAudio), entitlements, Info.plist properties — all live here.
- `BlitzText/Resources/Info.plist` — generated; reflects `project.yml`.
- `BlitzText/Resources/BlitzText.entitlements` — generated; reflects `project.yml`.
- `Scripts/build.sh` — runs `xcodegen generate` then `xcodebuild` then `codesign --sign -` (ad-hoc).

**Core Logic:**
- `BlitzText/Modes/ModeProcessor.swift` — pipeline orchestrator. Read this first to understand the runtime.
- `BlitzText/Hotkeys/HotkeyManager.swift` — input boundary.
- `BlitzText/Transcription/TranscriptionService.swift` — backend contract.

**Persistence:**
- `BlitzText/Settings/SettingsStore.swift` — UserDefaults-backed prefs.
- `BlitzText/History/HistoryStore.swift` — JSON history.
- `BlitzText/Transcription/LocalModelManager.swift` — downloaded model registry.

**Testing:**
- No test target exists. `Mocks/` contains design references (screenshots), not unit-test mocks.

## Naming Conventions

**Files:** `UpperCamelCase.swift`, one primary type per file, file name matches the primary type (e.g., `ModeProcessor.swift` contains `final class ModeProcessor`). Small inline support types (e.g., `RecordingHUDView` inside `RecordingHUDController.swift`) are co-located only when they are private to the controller.

**Directories:** `UpperCamelCase` matching the subsystem name (`Audio`, `Hotkeys`, `Transcription`, `ProperNouns`). One subsystem per directory. Mixed German/English naming is normal in this project (`ProperNouns/EigennamenAnalyzer.swift`).

**Types:**
- Controllers (AppKit shells) end in `Controller`: `MenuBarController`, `RecordingHUDController`, `SettingsWindowController`, `HistoryWindowController`, `SuggestionToastController`.
- Stores (`ObservableObject` state holders) end in `Store`: `SettingsStore`, `HistoryStore`.
- Service protocols end in `Service`: `TranscriptionService`, `RewriteService`.
- API clients end in `Client`: `WhisperAPIClient`, `OpenAIChatClient`, `LocalWhisperClient`, `ParakeetClient`.
- Views end in `View`: `HUDView`, `SettingsView`, `HistoryView`, `RecordingHUDView`.
- Enums for finite domain values are bare nouns: `Mode`, `WritingStyle`, `TriggerMode`, `TranscriptionBackend`.

**Methods:** `lowerCamelCase`. Async APIs use `async`/`throws` consistently. UI lifecycle methods follow AppKit conventions (`show()`, `hide()`, `togglePopover()`).

**Constants & keys:** `UserDefaults` keys are reverse-DNS (`"de.reinholds.blitztext.settings"`, `"de.reinholds.blitztext.apiKey"`) and declared as `private static let` on the owning store.

## Where to Add New Code

**New transcription backend** (e.g., a Deepgram or Apple Speech client)
- Implementation: `BlitzText/Transcription/<Name>Client.swift` conforming to `TranscriptionService`.
- Add a case to `TranscriptionBackend` enum in `BlitzText/Settings/SettingsStore.swift`.
- Wire it into `ModeProcessor` lazy-properties and the `runPipeline` switch (`BlitzText/Modes/ModeProcessor.swift:23-27`, `:102-108`).
- Surface in `SettingsView.swift` "Zugang" tab.

**New rewrite mode** (e.g., translate-to-English)
- Add a case to `Mode` enum (`BlitzText/Modes/Mode.swift`) with default prompt.
- Update `HotkeyManager.handleFlagsChanged` (`BlitzText/Hotkeys/HotkeyManager.swift:92`) to map a modifier combo.
- Update `ModeProcessor.runPipeline` switch and `makeRewriteSystemPrompt(for:)` (`BlitzText/Modes/ModeProcessor.swift:131`, `:189`).
- Add UI strings in `Mode` (title/subtitle/systemImage) and any custom-prompt field in `SettingsStore` + `SettingsView`.

**New persisted preference**
- Add `@Published var foo: T` on `SettingsStore` (`BlitzText/Settings/SettingsStore.swift`).
- Add to the `Snapshot` struct, `load()`, and `save()` (handle missing key with `?? default` for back-compat).
- Bind in `SettingsView`.

**New UI surface (window or panel)**
- Controller: `BlitzText/UI/<Name>Controller.swift` or, if it's window-shaped, `BlitzText/<Subsystem>/<Name>WindowController.swift`.
- SwiftUI view: alongside the controller or in `BlitzText/UI/`.
- Instantiate in `AppDelegate.bootstrap()` and pass dependencies in via init.

**New permission**
- Add the usage description to `project.yml` under `targets.BlitzText.info.properties` (regenerate the project; never hand-edit `Info.plist`).
- Add the entitlement under `targets.BlitzText.entitlements.properties`.
- Add status/open helpers to `BlitzText/Settings/PermissionsHelper.swift`.
- Surface state in `SettingsView`'s permissions section.

**Shared utility**
- Cross-cutting helpers (logging, formatting): `BlitzText/App/` if they're process-wide, otherwise alongside the consuming subsystem.
- There is currently no `Common/` or `Utilities/` directory — keep helpers near their primary caller until a second caller appears.

## Special Directories

**`BlitzText.xcodeproj/`**
- Purpose: Xcode project file.
- Generated: Yes — by `xcodegen generate` from `project.yml`.
- Committed: No — gitignored. Always re-generate via `Scripts/build.sh`.

**`build/`**
- Purpose: `xcodebuild` output (`build/BlitzText.app`).
- Generated: Yes.
- Committed: No.

**`dist/`**
- Purpose: Distributable artefacts.
- Generated: Yes.
- Committed: No.

**`Mocks/`**
- Purpose: Static design references (PNG/SVG screenshots used during UI work).
- Generated: No.
- Committed: Yes.

**`Scripts/`**
- Purpose: `build.sh` (and any future packaging/notarization helpers).
- Generated: No.
- Committed: Yes.

**`.planning/`**
- Purpose: GSD codebase maps and planning artefacts.
- Generated: Partially (this directory is written by the gsd-codebase-mapper).
- Committed: Yes.

---

*Structure analysis: 2026-04-30*
