# External Integrations

**Analysis Date:** 2026-04-30

## APIs & External Services

**Speech-to-Text (Cloud):**
- OpenAI Whisper API — `https://api.openai.com/v1/audio/transcriptions`
  - Caller: `BlitzText/Transcription/WhisperAPIClient.swift` (final class `WhisperAPIClient: TranscriptionService`).
  - Method: `POST` with `multipart/form-data` body (`file` part = 16 kHz mono PCM16 WAV, `model`, optional `language`, optional `prompt`, `response_format=json`). See `WhisperAPIClient.swift:51-81`.
  - Default model: `whisper-1` (configurable via `SettingsStore.transcriptionModel`).
  - SDK/Client: hand-rolled `URLSession` (no SDK).
  - Auth: `Authorization: Bearer <apiKey>` from `SettingsStore.apiKey` (`BlitzText/Settings/SettingsStore.swift:31-42`).
  - Errors mapped to `TranscriptionError.{missingAPIKey, http, network, decoding}` (definition co-located in `BlitzText/Transcription/TranscriptionService.swift`).

**Text Rewrite / LLM:**
- OpenAI Chat Completions — `https://api.openai.com/v1/chat/completions`
  - Caller: `BlitzText/Rewrite/OpenAIChatClient.swift` (`final class OpenAIChatClient: RewriteService`).
  - Method: `POST` `application/json` with `{ model, messages: [system, user], temperature: 0.3 }`. See `OpenAIChatClient.swift:30-38`.
  - Default model: `gpt-4o-mini` (configurable via `SettingsStore.rewriteModel`). Used for two flows:
    - "Blitztext+" mode — style rewrite with user-selected style + custom prompt + context (`BlitzText/Modes/ModeProcessor.swift`, `BlitzText/Modes/Mode.swift`).
    - "Blitztext $%&!" mode — de-escalation rewrite.
  - Auth: same `Authorization: Bearer <apiKey>` from `SettingsStore.apiKey`.

**LLM (Proper-Noun Extraction):**
- OpenAI Chat Completions (second usage site) — `https://api.openai.com/v1/chat/completions`
  - Caller: `BlitzText/ProperNouns/EigennamenAISuggester.swift` (`enum EigennamenAISuggester`, static `extract(from:apiKey:)`).
  - Model: `gpt-4o-mini` (hard-coded, `EigennamenAISuggester.swift:20`).
  - Body uses `response_format: { type: "json_object" }` and `temperature: 0`. Returns `{"eigennamen": [String]}`.
  - Toggleable via `SettingsStore.aiSuggestProperNouns`.

## Data Storage

**Databases:**
- None. No SQLite/CoreData/Realm.

**File Storage:**
- Local filesystem only.
  - Whisper/Parakeet models: `~/Library/Application Support/BlitzText/Models/<variant>/` (`BlitzText/Transcription/LocalModelManager.swift:75-82`).
  - History (last 100 transcriptions): `~/Library/Application Support/BlitzText/history.json` (`BlitzText/History/HistoryStore.swift:35`).
  - Per-recording temp WAV: `NSTemporaryDirectory()/blitztext-<UUID>.wav` (`BlitzText/Audio/AudioRecorder.swift:29-30`); deleted after upload or when "silence" guard rejects the take.

**Caching:**
- WhisperKit / FluidAudio model files cached on disk after first download (see Model Downloads below). No in-memory cache layer beyond loaded pipelines.

## Authentication & Identity

**Auth Provider:**
- None. Single-user local app. The OpenAI API key is the only credential.
  - Stored in `UserDefaults` under `de.reinholds.blitztext.apiKey` (`BlitzText/Settings/SettingsStore.swift:42`).
  - Note: `BlitzText/Settings/Keychain.swift` implements a generic-password Keychain wrapper (service `de.reinholds.blitztext`), but the API key was migrated to `UserDefaults` because self-signed dev builds force a keychain re-prompt on each rebuild (rationale documented at `SettingsStore.swift:26-30`).
  - User enters the key via Settings tab "Zugang" (`BlitzText/Settings/SettingsView.swift`).

## Monitoring & Observability

**Error Tracking:**
- None. No Sentry/Crashlytics/Bugsnag.

**Logs:**
- Lightweight in-process logger: `BlitzText/App/Log.swift` (`Log.write(...)`).
- `NSLog` used in `BlitzText/Audio/AudioRecorder.swift:155` for AVAudioFile write errors.
- No remote log shipping. No telemetry — explicitly out-of-scope per `RISKS.md` ("Keine Telemetrie / Analytics").

## CI/CD & Deployment

**Hosting:**
- Not applicable — native macOS desktop app.

**CI Pipeline:**
- None detected (no `.github/workflows`, no `fastlane/`, no `Makefile`).
- Local build via `Scripts/build.sh` (xcodegen → xcodebuild → codesign).
- Distribution packaging via `Scripts/dmg.sh`.
- Stable local code-signing identity created by `Scripts/create-signing-cert.sh` so TCC permissions persist between rebuilds (`Scripts/build.sh:39-50`).

## Environment Configuration

**Required env vars:**
- None at build or runtime. The OpenAI API key is provided by the user through the in-app Settings UI.

**Secrets location:**
- OpenAI API key — `UserDefaults` (`de.reinholds.blitztext.apiKey`).
- Local code-signing certificate (private key) — user's macOS login keychain, identity name "BlitzText Local Dev".

## Webhooks & Callbacks

**Incoming:**
- None.

**Outgoing:**
- All outbound HTTPS goes to `api.openai.com`. Two endpoints:
  - `POST /v1/audio/transcriptions`
  - `POST /v1/chat/completions`
- Outbound model-file downloads from HuggingFace (see below).

## Model Downloads (HuggingFace)

**WhisperKit (CoreML) — Whisper local backend:**
- Caller: `BlitzText/Transcription/ModelDownloader.swift:21-30` invokes `WhisperKit.download(variant:downloadBase:useBackgroundSession:from:progressCallback:)`.
- HuggingFace repo: `argmaxinc/whisperkit-coreml` (passed as `from:` parameter).
- Variants offered (`BlitzText/Transcription/LocalModelManager.swift:30-48`): `openai_whisper-tiny[.en]`, `openai_whisper-base[.en]`, `openai_whisper-small[.en]`, `distil-whisper_distil-large-v3`, `openai_whisper-large-v3-v20240930_turbo_632MB`, `openai_whisper-large-v3_turbo`, `openai_whisper-large-v3`. Sizes 39 MB → 1.55 GB.
- Destination: `~/Library/Application Support/BlitzText/Models/<variant>/`.
- Progress reported through `ModelDownloader.Result` and surfaced in UI via `LocalModelManager.downloadProgress` (`@Published`).

**FluidAudio (Parakeet TDT v3 + Diarizer):**
- Caller: `BlitzText/Transcription/ParakeetClient.swift:127-138`.
- ASR models pulled by `AsrModels.downloadAndLoad()` (FluidAudio API).
- Diarization models pulled by `DiarizerModels.downloadIfNeeded()` when `SettingsStore.parakeetDiarization == true`.
- Storage paths and HuggingFace repos are managed internally by FluidAudio (not configured by app code).

## macOS System Integrations

**Microphone (AVFoundation):**
- `AVAudioEngine` input tap in `BlitzText/Audio/AudioRecorder.swift:60-66`.
- Permission gate: `AVCaptureDevice.authorizationStatus(for: .audio)` + `AVCaptureDevice.requestAccess(for: .audio)` (synchronous semaphore-based prompt at `AudioRecorder.swift:161-174`).
- Info.plist string: `NSMicrophoneUsageDescription` (`project.yml:52`).
- Entitlement: `com.apple.security.device.audio-input: true`.

**Accessibility / TCC:**
- Required for global `fn`-modifier hotkey detection and for synthesizing ⌘V auto-paste keystrokes.
- Trust check: `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])` in `BlitzText/Hotkeys/HotkeyManager.swift:140-141` and `BlitzText/Settings/PermissionsHelper.swift:42-45`.
- Settings deeplink: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` (`PermissionsHelper.swift:29`).
- App must be relaunched after grant — documented user-facing in `README.md`.

**Global Hotkeys (CGEventTap):**
- `BlitzText/Hotkeys/HotkeyManager.swift:51-67` creates a `cgSessionEventTap` listening for `flagsChanged` + `keyDown`, watching `CGEventFlags.maskSecondaryFn` combined with `.maskShift` / `.maskControl` / `.maskAlternate`. Re-enables tap on `tapDisabledByTimeout` / `tapDisabledByUserInput`.
- Carbon `RegisterEventHotKey` not used (cannot capture `fn`).

**Keystroke Synthesis (CGEvent):**
- `BlitzText/Insertion/TextInserter.swift:14-27` posts ⌘V via `CGEvent(keyboardEventSource:virtualKey:keyDown:)` (vKey `0x09`) to `cgAnnotatedSessionEventTap`. Self-paste guard: skips if frontmost app's bundle id matches BlitzText's own.

**Clipboard (NSPasteboard):**
- `BlitzText/Insertion/TextInserter.swift:6-10` — `NSPasteboard.general.clearContents()` + `setString(_:forType: .string)`.

**Menu Bar (AppKit):**
- `NSStatusItem` + `NSPopover` in `BlitzText/MenuBar/MenuBarController.swift`. App runs as `LSUIElement` (no Dock icon).

**Speech Recognition (declared, optional):**
- Info.plist string `NSSpeechRecognitionUsageDescription` declared in `project.yml:53` for a possible Apple-Speech fallback. Not currently exercised by the codebase.

**Apple Events (declared, unused):**
- Info.plist string `NSAppleEventsUsageDescription` declared in `project.yml:54` for a future `osascript` fallback. Not used in MVP.

**Network Outgoing:**
- Entitlement: `com.apple.security.network.client: true` (`project.yml:60`).
- Used by `URLSession.shared` calls in `WhisperAPIClient.swift`, `OpenAIChatClient.swift`, `EigennamenAISuggester.swift`, plus model downloaders.

---

*Integration audit: 2026-04-30*
