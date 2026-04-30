# Technology Stack

**Analysis Date:** 2026-04-30

## Languages

**Primary:**
- Swift 6.0 — All application source under `BlitzText/` (~30 `.swift` files). Configured via `SWIFT_VERSION: "6.0"` in `project.yml`. Strict concurrency set to `minimal` (`SWIFT_STRICT_CONCURRENCY: minimal` in `project.yml`).

**Secondary:**
- Bash — Build/dev scripts under `Scripts/` (`build.sh`, `create-signing-cert.sh`, `dmg.sh`, `install.sh`, `build-icon.sh`).
- Swift script — `Scripts/make-icon.swift` (one-off icon generator, uses `swift` shebang).

## Runtime

**Environment:**
- macOS 26.0+ (Apple Silicon). Set via `MACOSX_DEPLOYMENT_TARGET: "26.0"` and `LSMinimumSystemVersion: "26.0"` in `project.yml`.
- App runs as menu-bar accessory: `LSUIElement: true` (no Dock icon, no main window).
- Hardened Runtime: `ENABLE_HARDENED_RUNTIME: YES`.
- App Sandbox: **disabled** in MVP — `com.apple.security.app-sandbox: false` in `BlitzText/BlitzText.entitlements` (declared via `project.yml`).

**Package Manager:**
- Swift Package Manager (SPM) — managed via Xcode project's `swiftpm` workspace.
- Lockfile: `BlitzText.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (present, version 3 manifest).

## Frameworks

**Apple System Frameworks (linked implicitly via `import`):**
- `SwiftUI` — `BlitzText/UI/HUDView.swift`, `BlitzText/Settings/SettingsView.swift`, `BlitzText/History/HistoryView.swift`, `BlitzText/App/BlitzTextApp.swift`. Used for HUD, Settings tabs, History view.
- `AppKit` — `BlitzText/MenuBar/MenuBarController.swift`, `BlitzText/App/AppDelegate.swift`, `BlitzText/Insertion/TextInserter.swift`, `BlitzText/Hotkeys/HotkeyManager.swift`. Used for `NSStatusItem`, `NSPopover`, `NSPasteboard`, window controllers.
- `AVFoundation` — `BlitzText/Audio/AudioRecorder.swift`. `AVAudioEngine` for mic capture, `AVAudioConverter` to resample to 16 kHz mono PCM16, `AVCaptureDevice` for mic permission.
- `CoreGraphics` — `BlitzText/Hotkeys/HotkeyManager.swift`, `BlitzText/Insertion/TextInserter.swift`. `CGEventTap` (`kCGEventFlagsChanged`), `CGEvent` synthesis for ⌘V auto-paste.
- `ApplicationServices` — `BlitzText/Settings/PermissionsHelper.swift`, `BlitzText/Hotkeys/HotkeyManager.swift`. `AXIsProcessTrusted`, `AXIsProcessTrustedWithOptions` for Accessibility/TCC.
- `Security` — `BlitzText/Settings/Keychain.swift`. `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete` (file-based login keychain wrapper; note: API key now lives in `UserDefaults`, see `BlitzText/Settings/SettingsStore.swift:31-42`).
- `Combine` — `BlitzText/Settings/SettingsStore.swift`, `BlitzText/Transcription/LocalModelManager.swift`. `@Published`/`ObservableObject` plus `objectWillChange` debounced auto-persist.
- `NaturalLanguage` — `BlitzText/ProperNouns/EigennamenAnalyzer.swift` (NL tagger for proper-noun extraction).
- `Foundation` — ubiquitous (URL, URLSession, JSONEncoder/Decoder, FileManager, UserDefaults).
- `CoreML` / `MLX` — transitive via `WhisperKit` and `FluidAudio` (no direct `import CoreML` in app code, but local model inference runs on CoreML/MLX).

**Third-Party SPM Packages (`Package.resolved`):**
- `WhisperKit` 0.18.0 (resolved; `project.yml` pins `from: "0.13.0"`) — `https://github.com/argmaxinc/WhisperKit`. Local Whisper inference (CoreML). Used by `BlitzText/Transcription/LocalWhisperClient.swift` and `BlitzText/Transcription/ModelDownloader.swift`.
- `FluidAudio` 0.14.3 (resolved; `project.yml` pins `from: "0.6.0"`) — `https://github.com/FluidInference/FluidAudio`. Parakeet TDT v3 ASR + speaker diarization. Used by `BlitzText/Transcription/ParakeetClient.swift` (`AsrManager`, `DiarizerManager`, `AudioConverter`, `TdtDecoderState`, `ASRResult`, `TimedSpeakerSegment`).

**Transitive Dependencies (pulled in by `WhisperKit` / `FluidAudio`):**
- `swift-argument-parser` 1.7.1 — `https://github.com/apple/swift-argument-parser.git`
- `swift-asn1` 1.7.0 — `https://github.com/apple/swift-asn1.git`
- `swift-collections` 1.4.1 — `https://github.com/apple/swift-collections.git`
- `swift-crypto` 4.5.0 — `https://github.com/apple/swift-crypto.git`
- `swift-jinja` 2.3.5 — `https://github.com/huggingface/swift-jinja.git`
- `swift-transformers` 1.1.9 — `https://github.com/huggingface/swift-transformers.git`
- `yyjson` 0.12.0 — `https://github.com/ibireme/yyjson.git`

**Testing:**
- Not detected. No `*Tests` target in `project.yml`, no `XCTest` imports under `BlitzText/`.

**Build/Dev:**
- XcodeGen — generates `BlitzText.xcodeproj` from `project.yml` (root). Required dev tool, installed via `brew install xcodegen` (per `README.md`). The `.xcodeproj` is git-ignored.
- `xcodebuild` — invoked by `Scripts/build.sh` with `-configuration Debug` and ad-hoc signing.
- `codesign` — `Scripts/build.sh` prefers a stable local cert "BlitzText Local Dev" (created by `Scripts/create-signing-cert.sh`) so TCC permissions persist across rebuilds; falls back to ad-hoc.
- `create-dmg` (implied by `Scripts/dmg.sh`) — distribution packaging.

## Key Dependencies

**Critical:**
- `WhisperKit` 0.18.0 — Local Whisper backend. App calls `WhisperKit.download(...)` for HuggingFace model fetch and `WhisperKit(config).transcribe(audioPath:decodeOptions:)` for inference. See `BlitzText/Transcription/ModelDownloader.swift:21`, `BlitzText/Transcription/LocalWhisperClient.swift:52`.
- `FluidAudio` 0.14.3 — Parakeet TDT v3 backend with optional Speaker Diarization. App uses `AsrManager.loadModels(AsrModels.downloadAndLoad())` and `DiarizerManager(config: .default)` plus `DiarizerModels.downloadIfNeeded()`. See `BlitzText/Transcription/ParakeetClient.swift:127-138`.

**Infrastructure:**
- `swift-transformers` 1.1.9 — tokenizer/runtime support for HuggingFace models (transitive via WhisperKit).
- `swift-crypto` 4.5.0 + `swift-asn1` 1.7.0 — TLS/crypto primitives (transitive).
- `yyjson` 0.12.0 — fast JSON parsing (transitive).

## Configuration

**Environment:**
- No `.env` files. No environment variables consumed at runtime.
- Source-of-truth for build settings: `project.yml` (XcodeGen).
- App-level config:
  - Bundle id: `de.reinholds.blitztext` (`project.yml`).
  - Development region: `de` (German).
  - Hotkey bindings, prompts, glossary, backend choice, language, models — `UserDefaults` under key `de.reinholds.blitztext.settings` (JSON snapshot via `BlitzText/Settings/SettingsStore.swift:46-113`).
  - OpenAI API key — `UserDefaults` under key `de.reinholds.blitztext.apiKey` (`BlitzText/Settings/SettingsStore.swift:42`). Note: `Keychain.swift` exists but the API key was migrated to `UserDefaults` because self-signed dev builds re-prompt the keychain on every rebuild (see comment at `SettingsStore.swift:27-30`).
  - Active local Whisper model id — `UserDefaults` key `de.reinholds.blitztext.activeLocalModel` (`BlitzText/Transcription/LocalModelManager.swift:62`).
- Persisted data on disk:
  - Models: `~/Library/Application Support/BlitzText/Models/<variant>/` (`BlitzText/Transcription/LocalModelManager.swift:75-82`).
  - History: `~/Library/Application Support/BlitzText/history.json` (`BlitzText/History/HistoryStore.swift:31-36`).
  - Recording temp WAV: `FileManager.default.temporaryDirectory/blitztext-<UUID>.wav` (`BlitzText/Audio/AudioRecorder.swift:29-30`).

**Build:**
- `project.yml` — XcodeGen project spec (deployment target, packages, targets, entitlements, Info.plist).
- `BlitzText/Info.plist` — generated from `project.yml` (`CFBundleName`, `LSUIElement`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSAppleEventsUsageDescription`).
- `BlitzText/BlitzText.entitlements` — generated from `project.yml`. Keys: `com.apple.security.app-sandbox: false`, `com.apple.security.device.audio-input: true`, `com.apple.security.network.client: true`.
- `Scripts/build.sh` — full local build pipeline (xcodegen → xcodebuild → codesign with stable identity).
- `Scripts/create-signing-cert.sh` — creates the "BlitzText Local Dev" certificate so TCC grants persist across rebuilds.
- `Scripts/dmg.sh` — DMG packaging for distribution.

## Platform Requirements

**Development:**
- macOS 26+ (Apple Silicon) per `LSMinimumSystemVersion`.
- Xcode (full install, App Store) for `xcodebuild` toolchain.
- `xcodegen` (`brew install xcodegen`) — required to (re)generate `.xcodeproj` from `project.yml`.
- Optional: a self-issued local code-signing cert ("BlitzText Local Dev") created via `Scripts/create-signing-cert.sh` to keep TCC permissions stable across rebuilds.

**Production:**
- Single-user desktop install. No CI, no Developer-ID notarization, no Sparkle update mechanism in the MVP (called out in `RISKS.md` and `README.md` "Nächste Ausbau-Schritte").
- Distributable as a `.app` bundle (`build/BlitzText.app`) or DMG (`Scripts/dmg.sh`).
- Requires user to manually grant Microphone and Accessibility TCC permissions on first run.

---

*Stack analysis: 2026-04-30*
