# Codebase Concerns

**Analysis Date:** 2026-04-30

Cross-references and expands the existing top-level `RISKS.md`. Severity levels:
**P0** = blocks usage / data loss / security; **P1** = high-impact, frequent breakage; **P2** = quality / UX / scaling; **P3** = roadmap or nice-to-have.

---

## Tech Debt

### API key stored in UserDefaults instead of Keychain (P1, security)

- Files: `BlitzText/Settings/SettingsStore.swift:31-42`, `BlitzText/Settings/Keychain.swift`
- Issue: The `apiKey` getter/setter persists the OpenAI key to plain `UserDefaults` (`de.reinholds.blitztext.apiKey`). The inline comment justifies this with self-signed dev-build keychain prompts ("Code-Hash-gebunden → jedes Rebuild triggert einen Schlüsselbund-Prompt"), but `Keychain.swift` is fully implemented and unused for this purpose.
- Impact: API key sits in `~/Library/Preferences/de.reinholds.blitztext.plist` in cleartext. Any process running as the user (Spotlight indexers, backup tools, leaked log uploads) can read it. Also contradicts the architecture doc (`ARCHITECTURE.md:75`) which still claims Keychain storage.
- Fix approach: Once a stable Apple-Team-ID signing identity is in place, switch to `kSecUseDataProtectionKeychain`. For self-signed dev builds, gate behind a debug build flag (`#if DEBUG`) so release builds always use Keychain. Migrate existing UserDefaults values on first launch and delete the plist entry.

### `LocalWhisperClient` is no longer a stub but doc/risks still describe it that way (P3, doc drift)

- Files: `BlitzText/Transcription/LocalWhisperClient.swift`, `ARCHITECTURE.md:42`, `ARCHITECTURE.md:97`, `RISKS.md:30`
- Issue: `ARCHITECTURE.md` and `RISKS.md` describe `LocalWhisperClient` as "Platzhalter / Stub". The actual implementation is a full WhisperKit integration with model download, CoreML preload, and inference.
- Impact: Misleading for new contributors and for /gsd-plan-phase.
- Fix approach: Update `ARCHITECTURE.md` and `RISKS.md` to reflect that local Whisper (WhisperKit) and Parakeet are real backends, not stubs.

### Three-line repo state vs. claimed module list (P2)

- File: `ARCHITECTURE.md:33-43` lists `MenuBarController`, `HotkeyManager`, etc. but omits `HistoryStore`, `ParakeetClient`, `LocalModelManager`, `EigennamenAnalyzer`, `EigennamenAISuggester`, `SuggestionPresenter`, `SuggestionToastController`, `RecordingHUDController`.
- Impact: Architecture doc is incomplete; planners working from it will miss substantial subsystems.
- Fix approach: Refresh the module table during the next codebase-map run.

### Per-call closure on `objectWillChange` debounces full snapshot save (P2, perf)

- File: `BlitzText/Settings/SettingsStore.swift:52-55`
- Issue: Every published mutation (including transient UI typing into `customPromptPlus`/`context`) triggers a 150 ms debounced JSON re-encode + UserDefaults write of the full `Snapshot` blob.
- Impact: Negligible today; will grow if more fields are added (e.g. per-app profiles). Also re-saves the unchanged 99% of fields on each keystroke.
- Fix approach: Either accept (current footprint is small), or split rarely changing fields into a second snapshot key.

---

## Known Bugs / Fragile Behavior

### Hotkey debounce of 50 ms is too short to defeat key-repeat in `.hold` mode (P1)

- File: `BlitzText/Hotkeys/HotkeyManager.swift:111`
- Issue: `RISKS.md` row 11 promises "Debounce 250 ms" but the implementation uses `0.05` (50 ms) for hold and `0.3` (300 ms) for toggle. macOS key-repeat for sticky modifiers can fire faster than 50 ms during flag jitter.
- Symptom: Rapid start/stop ping-pong when fn is wobbly (laptop hinge flex, Karabiner remap).
- Fix approach: Bring `.hold` debounce in line with the documented 250 ms, or differentiate "transition direction" (start vs stop) so that releasing fn never gets debounced.

### `CGEventTap` not auto-restarted after permission revocation (P1)

- File: `BlitzText/Hotkeys/HotkeyManager.swift:29-68`
- Issue: `start()` returns silently if Accessibility permission is missing. There is no observer for permission changes. The user has to relaunch BlitzText after granting Accessibility (which is exactly the most common first-run path).
- Symptom: User grants permission in System Settings → hotkeys still don't work until app relaunch.
- Fix approach: Poll `AXIsProcessTrusted()` (e.g. on `applicationDidBecomeActive` and a 2 s timer when tap is `nil`) and call `start()` again when it flips to `true`.

### `tapDisabledByTimeout`/`tapDisabledByUserInput` re-enable, but no fallback if it keeps disabling (P2)

- File: `BlitzText/Hotkeys/HotkeyManager.swift:44-47`
- Issue: We re-enable the tap once. Repeated disable storms (heavy CPU, Karabiner conflict) loop forever without surfacing in the UI.
- Fix approach: Counter + HUD warning after N disables in T seconds.

### Auto-paste uses `.maskCommand` only (P2, edge case)

- File: `BlitzText/Insertion/TextInserter.swift:14-27`
- Issue: `simulatePaste()` posts a `cmd+v`. If the user holds fn or any modifier when releasing the hotkey, the posted `keyDown/keyUp` may inherit lingering flags, producing `cmd+fn+v` and weird app behavior. Also: posts events even into Secure Input fields (Terminal sudo, password prompts) where it silently fails or produces a beep.
- Fix approach: Detect Secure Input via `IsSecureEventInputEnabled()` and skip / show HUD warning. Force-clear flags on the posted events.

### Auto-paste targets `cgAnnotatedSessionEventTap` while listener uses `cgSessionEventTap` (P2)

- Files: `BlitzText/Hotkeys/HotkeyManager.swift:52`, `BlitzText/Insertion/TextInserter.swift:25-26`
- Issue: Different tap locations means our own posted ⌘V can re-enter our flagsChanged handler with `.maskCommand` flag transitions, briefly muddling the modifier state machine. Currently survives because flag combos require fn, but it is a latent footgun.

### `WhisperAPIClient.makeMultipartBody` loads full audio with `Data(contentsOf:)` (P2, memory)

- File: `BlitzText/Transcription/WhisperAPIClient.swift:73`
- Issue: Reads the entire WAV into memory, then concatenates into another `Data` for the request body. For a 60 s recording at 16 kHz/16-bit/mono ≈ 1.9 MB, fine. For longer recordings or future multi-channel formats, this doubles memory.
- Fix approach: Streaming `URLSessionUploadTask(fromFile:)` with a multipart body file, or chunked body builder.

### `EigennamenAISuggester` swallows JSON shape errors silently (P3)

- File: `BlitzText/ProperNouns/EigennamenAISuggester.swift:41-50`
- Issue: A single guard with five conditions returns `[]` for any failure mode, including the API returning a different schema than expected. No logging differentiates between "model returned empty array" and "schema drift".
- Fix approach: Split the guards, log at debug which step failed.

### `OpenAIChatClient` has no retry / backoff (P2)

- File: `BlitzText/Rewrite/OpenAIChatClient.swift`
- Issue: `RISKS.md` row 4 promises "Retry mit Backoff", but neither `WhisperAPIClient` nor `OpenAIChatClient` retries on 429/5xx/transient network errors. A single Wi-Fi flicker = user-visible error toast.
- Fix approach: Wrap session calls in 2–3 attempts with exponential backoff for 5xx and 429 (respect `Retry-After`).

### History persists raw transcripts forever in plain JSON (P1, privacy)

- File: `BlitzText/History/HistoryStore.swift:27,69-76`
- Issue: Up to 100 dictation entries stored at `~/Library/Application Support/BlitzText/history.json` in cleartext (raw + polished). For a dictation tool used in personal/business contexts, this is sensitive.
- Impact: Same exfiltration surface as the API key in plist. A user revoking microphone permission later still has all old transcripts on disk.
- Fix approach: (a) make history opt-in; (b) encrypt at rest with a Keychain-stored data-protection key; (c) add explicit "auto-purge after N days" setting; (d) add "Clear All" button reachable without opening the History window.

---

## Security & Privacy

### App runs without sandbox in MVP (P1, accepted)

- Files: `ARCHITECTURE.md:56`, `BlitzText.xcodeproj/project.pbxproj` (entitlements), `project.yml`
- Risk: No file-system / network jail. A compromised dependency (e.g. a malicious WhisperKit / FluidAudio update) has full user-context access.
- Current mitigation: Documented as MVP trade-off in architecture.
- Recommendation: Track switching to a sandboxed build with Accessibility/Mic exceptions before any external distribution.

### API key shipped in cleartext to `api.openai.com` (P2, expected)

- Files: `BlitzText/Transcription/WhisperAPIClient.swift:22`, `BlitzText/Rewrite/OpenAIChatClient.swift:21`, `BlitzText/ProperNouns/EigennamenAISuggester.swift:31`
- Risk: Standard OpenAI auth — fine. But the same key is sent from three different code paths: the AI-suggester path bypasses any future retry/circuit-breaker we'd add to the central client.
- Recommendation: Centralize OpenAI HTTP through one client (rate limit, key validation, single retry policy).

### No URL pinning / certificate validation override (P3, info)

- Files: `BlitzText/Transcription/WhisperAPIClient.swift:6`, `BlitzText/Rewrite/OpenAIChatClient.swift:6`
- Behavior: Uses default `URLSession.shared`. Acceptable for `api.openai.com`. Worth noting for any future MITM-on-corp-proxy users — currently no `URLSessionDelegate` to handle self-signed enterprise CAs.

### Audio temp files in unprotected `NSTemporaryDirectory()` (P2)

- Files: `BlitzText/Audio/AudioRecorder.swift:29-30`, cleanup in `BlitzText/App/AppDelegate.swift:112-119`, deletion in `BlitzText/Modes/ModeProcessor.swift:100`
- Risk: Recording is written to `tmp/blitztext-<uuid>.wav` before upload. File lifetime is short (deleted in `defer` after pipeline) but exists during transcription. A crash mid-pipeline leaves cleartext audio on disk until next launch (cleanup runs at start).
- Mitigation already in place: per-launch cleanup (`cleanupTempFiles()`).
- Recommendation: Use `Data Protection` class file when writing (`.completeFileProtection`) to require user-unlocked session. Consider in-memory `Data` for short recordings to avoid disk altogether.

### Single-instance check uses informational alert but doesn't kill old PID (P3)

- File: `BlitzText/App/AppDelegate.swift:28-47`
- Risk: New instance exits, old keeps its tap. Fine. But the alert text says "Diese Instanz wird beendet" — confusing on first read; user might assume the OLD instance is killed.
- Fix approach: Reword or offer a "Replace" option.

---

## Performance Bottlenecks

### Cold-start of WhisperKit CoreML compile is 1–3 min, blocking on first dictation (P1, UX)

- Files: `BlitzText/Transcription/LocalWhisperClient.swift:78-84`, `BlitzText/App/AppDelegate.swift:79`
- Cause: First-ever load of any CoreML model has to compile shaders for the device. WhisperKit logs this; we preload at app start to absorb it. But preload only runs if a model is *already activated*. First-time users who pick a model in Settings face the 1–3 min wait on their next dictation unless they also wait for `onActivate` preload to finish.
- Improvement path: HUD progress for `manager.isPreloading`/`preloadedID` — already plumbed into `LocalModelManager`, but verify the SettingsView surfaces it clearly, and disable transcription buttons until `preloadedID` matches `activeID`.

### Parakeet `AudioConverter().resampleAudioFile(audioURL)` runs on the calling actor (P2)

- File: `BlitzText/Transcription/ParakeetClient.swift:32`
- Cause: `transcribe(...)` is called from `ModeProcessor` whose pipeline is `@MainActor` … wait, `runPipeline` is called inside an `await` chain, so the actual work happens off-main only if FluidAudio's `AsrManager.transcribe` is properly async. Resampling is synchronous and happens before the async boundary.
- Impact: Up to a few hundred ms of resample time can briefly tie up the main actor for medium-length recordings.
- Improvement path: Wrap the resample + transcribe in a `Task.detached` that returns the string, keeping `ModeProcessor` on main only for state mutation.

### Diarization model download is ~80 MB and silent (P1, UX)

- File: `BlitzText/Transcription/ParakeetClient.swift:131-138`
- Cause: `DiarizerModels.downloadIfNeeded()` is opaque — the user toggles "Diarization" in Settings and the next transcription stalls while ~80 MB downloads. There's no UI progress, no failure recovery beyond the catch in `transcribe(...)`.
- Improvement path: Mirror what `LocalModelManager` does for Whisper (pre-download with progress). Either expose a "Diarization aktivieren — lädt 80 MB" button in Settings that runs `DiarizerModels.downloadIfNeeded()` with progress, or block the toggle until the download completes.

### `currentLevel` updated via `Task { @MainActor }` per audio buffer (P2)

- File: `BlitzText/Audio/AudioRecorder.swift:122-130`
- Cause: Every input tap callback (4096 samples ≈ 256 ms at 16 kHz; less at native 48 kHz) hops to MainActor to update `@Published currentLevel`. Negligible at this rate, but if buffer size is ever lowered this becomes a hot spot.
- Improvement path: Throttle to ~30 Hz via timestamp gate.

---

## Fragile Areas

### State coupling between `HotkeyManager`, `ModeProcessor`, and `AudioRecorder` (P1)

- Files: `BlitzText/Hotkeys/HotkeyManager.swift:108-123`, `BlitzText/Modes/ModeProcessor.swift:59-95`
- Why fragile: Three separate state machines (hotkey `currentMode`, processor `activeMode`, recorder `startedAt`/`fileURL`) must agree. The `start/stop/toggle` glue lives in the AppDelegate closure (`AppDelegate.swift:65-73`).
- Failure mode: A `start` followed by user releasing fn before the async `recorder.start()` completes can produce a "stop without start" or a leaked recording (start succeeds after stop already returned).
- Safe modification: Don't modify any of the three classes without re-checking the three-machine invariants. Add an integration test (mock recorder + scripted hotkey events) before refactoring.

### `RecordingHUDController` not in test surface (P2)

- File: `BlitzText/UI/RecordingHUDController.swift`
- Why fragile: HUD lifecycle (show on `.recording`, hide on `.idle`) is driven by `@Published state`. There is no test rig — `Mocks/` exists at root but no automated tests exercise the HUD.
- Safe modification: Manual smoke test: trigger fn+Shift, fn+Control, fn+Option, abort mid-recording, error mid-transcription. Each must show/hide HUD correctly.

### `applyDiarization` fallback when token timings missing (P2)

- File: `BlitzText/Transcription/ParakeetClient.swift:59-113`
- Why fragile: If `asr.tokenTimings` is empty (newer FluidAudio version, or a rare zero-token result), we silently return raw text without speaker labels. The user has Diarization "on" and gets no labels with no UI indication.
- Safe modification: Log + surface "Diarization unavailable for this clip" hint in HUD.

### Hallucination filter is a static substring list (P2, maintenance)

- File: `BlitzText/Modes/ModeProcessor.swift:227-245`
- Why fragile: New Whisper hallucinations ("untertitel.tv", "© 2024 …") aren't caught. List is hand-curated and German-centric.
- Safe modification: When adding a phrase, ensure case-insensitive, lowercase-the needle. Consider supplementing with a length+entropy heuristic: short transcripts that are exactly one of N common silence outputs.

### Settings JSON schema has no version field (P1, future)

- File: `BlitzText/Settings/SettingsStore.swift:58-92`
- Why fragile: `Snapshot` decode uses optional fields (`aiSuggestProperNouns?`, `parakeetDiarization?`) for backwards compatibility, but there's no `schemaVersion` int. Future field renames or enum value renames (e.g. adding a new `TranscriptionBackend` case) will fail decoding silently — `guard ... else { return }` returns defaults.
- Safe modification: Add `schemaVersion: Int = 1` to `Snapshot`. Migrate explicitly when reading.

### `TranscriptionBackend` enum stored by raw string in JSON (P2)

- File: `BlitzText/Settings/SettingsStore.swift:116-128`
- Why fragile: Renaming a case (e.g. `local` → `whisperLocal`) breaks decode of every existing user's settings, falling back to defaults (and silently losing their backend choice and API key reference … wait, key is separate, but mode/style/glossary all reset).
- Safe modification: Never rename enum cases without a migration step.

---

## Test Coverage Gaps

The repo has `Mocks/` at root but appears to have **no automated test target** referenced from `BlitzText.xcodeproj` (verify before adding tests). Below: the highest-value gaps.

### Hotkey state machine has no tests (P1)

- File: `BlitzText/Hotkeys/HotkeyManager.swift`
- What's not tested: hold-mode transitions, toggle-mode debounce, mode-switch mid-press (fn+Shift → fn+Control without releasing fn).
- Risk: Any change here can ship a regression that only manifests on real keyboards.
- Priority: High — this is the most fragile + most user-visible component.

### Pipeline error paths in `ModeProcessor` (P1)

- File: `BlitzText/Modes/ModeProcessor.swift:99-173`
- What's not tested: transcription failure cleanup, rewrite failure with raw transcript still in clipboard (does it land?), hallucination filter false-positives.

### Settings round-trip + migration (P2)

- File: `BlitzText/Settings/SettingsStore.swift`
- What's not tested: `Snapshot.encode` → `decode` round-trip for every enum case, missing-field migration paths.

### `applyDiarization` edge cases (P2)

- File: `BlitzText/Transcription/ParakeetClient.swift:59-113`
- What's not tested: zero segments, single-speaker collapse, token straddling segment boundary.

### Auto-paste self-paste guard (P2)

- File: `BlitzText/Insertion/TextInserter.swift:14-27`
- What's not tested: bundle-id comparison.

---

## Missing / Deferred Critical Features

### No retry/backoff for OpenAI calls

- Documented in `RISKS.md` row 4, **not implemented**. See "Known Bugs" above.

### No cost telemetry / monthly cap

- `RISKS.md` row 10 notes "API-Kosten unkontrolliert" with "Limit-Setting (später)". Currently nothing tracks monthly OpenAI spend. A user with autoInsert + a stuck hotkey could rack up cost.
- Priority: P2 once the app sees more use.

### No update mechanism

- Acknowledged in `RISKS.md`. Sparkle integration is a roadmap item.

### No onboarding for permission flow

- First-run UX is "Settings opens if no API key". Accessibility & Microphone prompts come implicitly. A first user who declines a prompt has no in-app guidance to reopen System Settings (despite `PermissionsHelper.openAccessibilitySettings()` existing — verify it's wired into the SettingsView).

---

*Concerns audit: 2026-04-30*
