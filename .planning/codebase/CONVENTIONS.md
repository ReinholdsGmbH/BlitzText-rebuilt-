# Coding Conventions

**Analysis Date:** 2026-04-30

## Language & Toolchain

- Swift 6.0 (`SWIFT_VERSION: "6.0"` in `project.yml`)
- macOS 26.0 deployment target
- Strict concurrency level: `SWIFT_STRICT_CONCURRENCY: minimal` (deliberately relaxed — see Concurrency below)
- Project generated via XcodeGen from `project.yml`; do NOT edit `BlitzText.xcodeproj/project.pbxproj` by hand
- Xcode 26+ implied by deployment target

## Naming Patterns

**Files:**
- One primary type per file, file name == type name (e.g. `WhisperAPIClient.swift`, `SettingsStore.swift`, `ModeProcessor.swift`)
- Domain-grouped folders under `BlitzText/`: `App/`, `Audio/`, `History/`, `Hotkeys/`, `Insertion/`, `MenuBar/`, `Modes/`, `ProperNouns/`, `Resources/`, `Rewrite/`, `Settings/`, `Transcription/`, `UI/`
- German domain words allowed in identifiers when they map to a German UI concept (e.g. `Eigennamen` for "proper nouns" in `BlitzText/ProperNouns/EigennamenAnalyzer.swift`, `EigennamenAISuggester.swift`)

**Types:**
- UpperCamelCase: `SettingsStore`, `TranscriptionService`, `RecordingHUDController`
- Protocols are nouns or `-Service` suffix when they describe a capability: `TranscriptionService`, `RewriteService` (both in `BlitzText/Transcription/TranscriptionService.swift`, `BlitzText/Rewrite/RewriteService.swift`)
- Errors as nested or top-level enums conforming to `LocalizedError` or `Error`: `TranscriptionError`, `AudioRecorder.RecorderError`

**Functions / Methods / Properties:**
- lowerCamelCase: `transcribe(audioURL:language:prompt:)`, `runPipeline`, `currentLevel`
- Async functions explicitly marked `async throws` where they can fail and suspend
- Argument labels are descriptive German-or-English domain terms; keep external labels meaningful (`audioURL:`, `prompt:`, `mode:`)

**Cases:**
- Enum cases lowerCamelCase, often with raw `String` values matching the case name: `case openAI`, `case local`, `case parakeet` in `TranscriptionBackend`
- Mode case names are app-specific identifiers (`blitztext`, `blitztextPlus`, `blitztextRant`) — these are stable persistence keys, do not rename

**UI vs. code language:**
- All user-facing strings are German (`"Sprache rein. Text raus."`, `"Mikrofon-Zugriff verweigert..."`)
- Code identifiers are English with German allowed only for domain-specific nouns (`Eigennamen`, `Anpassen`, `Zugang`)
- Comments are mixed German/English — keep the existing style of the surrounding file

## Code Style

**Formatting:**
- No SwiftFormat / SwiftLint config detected — formatting is by hand convention
- 4-space indentation
- Opening brace on same line
- Trailing closures used for SwiftUI view builders and `Task { @MainActor in ... }` blocks
- Multi-line function signatures align parameters under the opening paren (see `WhisperAPIClient.makeMultipartBody` in `BlitzText/Transcription/WhisperAPIClient.swift`)

**Type clarity:**
- Prefer `final class` everywhere — every class in the codebase is `final` (`SettingsStore`, `Keychain`, `AudioRecorder`, `HotkeyManager`, `ModeProcessor`, etc.)
- Use `private let` for injected dependencies; `private var` only when state mutation is required
- Use `private(set)` to expose read-only published state (`@Published private(set) var state` in `BlitzText/Modes/ModeProcessor.swift`)

## Import Organization

- Foundation imports first, then Apple frameworks (`AppKit`, `AVFoundation`, `SwiftUI`, `Combine`, `NaturalLanguage`, `Security`, `CoreGraphics`), then third-party packages (`WhisperKit`, `FluidAudio`)
- No path aliases — Swift modules only
- Single grouped block at file top, no blank lines between imports

## Concurrency (Swift 6)

This is the most important convention in the codebase.

**Strict concurrency is set to `minimal`** (`project.yml`) by design — the app uses CGEvent C callbacks, AVAudioEngine taps, and Keychain APIs that don't yet have Sendable annotations. Going to `complete` would require massive `@unchecked` overrides anyway.

**Patterns:**

1. **`@MainActor` on owners of UI / app state:**
   - `AppDelegate` (`BlitzText/App/AppDelegate.swift:6`)
   - `ModeProcessor` (`BlitzText/Modes/ModeProcessor.swift:5`)
   - `HistoryStore` (`BlitzText/History/HistoryStore.swift:23`)
   - These types are MainActor-isolated; their methods can be called from `Task { @MainActor in ... }` blocks

2. **`nonisolated` AppDelegate callbacks bridge into MainActor:**
   ```swift
   nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
       MainActor.assumeIsolated { self.bootstrap() }
   }
   ```
   See `BlitzText/App/AppDelegate.swift:18-24, 105-110`. Use this pattern for any AppKit delegate callback that AppKit calls from a non-MainActor context.

3. **`final class Foo: @unchecked Sendable`** for classes that:
   - Hold C callback state (`HotkeyManager` — CGEventTap), or
   - Wrap thread-safe Apple APIs (`Keychain` — Security.framework), or
   - Are network clients with `URLSession` and immutable `let` properties (`WhisperAPIClient`, `OpenAIChatClient`, `LocalWhisperClient`, `ParakeetClient`)
   - Use `AVAudioEngine` with internal queue safety (`AudioRecorder`)

   When you write a new such class, document WHY the unchecked is safe in a comment (see `BlitzText/Settings/Keychain.swift:11` precedent).

4. **`@Sendable` closures** for callbacks crossing isolation boundaries:
   ```swift
   private let onTrigger: @Sendable (Mode, Action) -> Void
   ```
   See `BlitzText/Hotkeys/HotkeyManager.swift:16`.

5. **Hopping back to MainActor from background contexts:**
   ```swift
   Task { @MainActor in self.currentLevel = 0 }
   Task { @MainActor [weak self] in ... }
   ```
   See `BlitzText/Audio/AudioRecorder.swift:69, 122`. Always use `[weak self]` when the closure may outlive the recorder.

6. **`Task.detached` for fire-and-forget background work:**
   ```swift
   Task.detached { await client.warmUp() }
   ```
   See `BlitzText/Modes/ModeProcessor.swift:50, 53, 166`. Use `await MainActor.run { ... }` to come back when needed.

7. **`@MainActor @Published`** for UI-bound state that lives on a non-MainActor class:
   ```swift
   @MainActor @Published private(set) var currentLevel: Float = 0
   ```
   See `BlitzText/Audio/AudioRecorder.swift:8`.

## Error Handling

**`TranscriptionError` is the canonical app error enum** (`BlitzText/Transcription/TranscriptionService.swift:8-24`):

```swift
enum TranscriptionError: LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case network(Error)
    case decoding
    case backendNotAvailable

    var errorDescription: String? { ... German user-facing strings ... }
}
```

**Conventions:**

- All user-facing error messages are GERMAN, written into `errorDescription`
- Use `try await` everywhere for OpenAI/network calls
- Wrap unknown thrown errors in `TranscriptionError.network(error)` at the boundary:
  ```swift
  } catch let error as TranscriptionError {
      throw error
  } catch {
      throw TranscriptionError.network(error)
  }
  ```
  Pattern in `BlitzText/Transcription/WhisperAPIClient.swift:44-48`.
- HTTP non-2xx → `TranscriptionError.http(statusCode, body)` with the raw body string for debugging
- Component-local errors are nested enums: `AudioRecorder.RecorderError` (`BlitzText/Audio/AudioRecorder.swift:176`)
- `humanReadable(_:)` helper in `ModeProcessor` (`BlitzText/Modes/ModeProcessor.swift:249-257`) maps any `Error` to a German user string — extend the `if let e as ...` chain when adding new error types
- `try?` is acceptable for non-critical filesystem ops (cleanup, log writes, history persistence) — see `BlitzText/App/AppDelegate.swift:107-109`

## Logging

**`Log.write(_:)` is the single logging entrypoint** (`BlitzText/App/Log.swift`):

- Writes timestamped lines to `~/Library/Logs/BlitzText.log` (append-only)
- Also mirrors to `NSLog` via `NSLog("[BlitzText] %@", msg)` for Console.app visibility
- Format: `[yyyy-MM-dd HH:mm:ss.SSS] message\n`

**When to log:**
- Lifecycle events: `Log.write("HotkeyManager.start() — AXIsProcessTrusted = \(trusted)")` (`BlitzText/Hotkeys/HotkeyManager.swift:31`)
- Recoverable errors with status codes: `Log.write("Keychain write failed for \(account): OSStatus \(status)")` (`BlitzText/Settings/Keychain.swift:31`)
- Pipeline decisions worth auditing: silence-discard, hallucination-filter (`BlitzText/Audio/AudioRecorder.swift:89`, `BlitzText/Modes/ModeProcessor.swift:126`)
- Single-instance enforcement (`BlitzText/App/AppDelegate.swift:45`)

**When NOT to log:**
- Hot loops (audio buffer per-frame) — only on stop
- User content (transcripts) unless gated behind a debug flag — currently the hallucination filter logs the offending transcript, which is acceptable since these are short discarded fragments

**Direct `NSLog` is allowed** as a fallback when `Log` may not be available yet (e.g. very early permission callbacks: `BlitzText/App/AppDelegate.swift:90`).

## Settings & Persistence

Three storage tiers — pick the one matching the data:

1. **`UserDefaults` JSON snapshot** for app preferences (`BlitzText/Settings/SettingsStore.swift`):
   - Single `Snapshot: Codable` struct holds all `@Published` props
   - Loaded on `init`, auto-saved via `objectWillChange.debounce(150ms).sink { save }` (line 52-55)
   - Add new optional fields with `?` defaulting in `load()` for forward-compat:
     ```swift
     aiSuggestProperNouns = snap.aiSuggestProperNouns ?? true
     ```
   - Keys: `de.reinholds.blitztext.settings`, `de.reinholds.blitztext.apiKey`

2. **`UserDefaults` raw string** for the OpenAI API key (`SettingsStore.apiKey`, lines 31-42):
   - DELIBERATELY NOT in Keychain — see comment lines 27-30: self-signed dev certs trigger a Keychain prompt on every rebuild
   - For Personal-Use it is acceptable; if the app gets a real Apple Team ID, migrate to Keychain via the existing `Keychain` class

3. **`Keychain`** wrapper class exists (`BlitzText/Settings/Keychain.swift`) — `final class Keychain: @unchecked Sendable` with `write/read/delete(account:)`. Currently NOT used for the API key. Reserve for future per-account secrets.

4. **JSON file in `~/Library/Application Support/BlitzText/`** for history (`BlitzText/History/HistoryStore.swift`):
   - Structured data with potentially many entries — keep out of `UserDefaults`
   - Use `.atomic` write option, `.iso8601` date strategy, `.prettyPrinted, .sortedKeys` formatting

**Whenever you add a setting:**
1. Add `@Published var foo: T = default` to `SettingsStore`
2. Add `var foo: T` (or `T?` with nullable migration) to the private `Snapshot` struct
3. Assign in `load()` and `save()`
4. The debounced auto-save handles persistence — do not call `save()` manually

## SwiftUI Patterns

- `@EnvironmentObject` for `SettingsStore` and `LocalModelManager` injected at the window/scene root
- Tab enums nested in the view: `SettingsView.Tab` with `.anpassen`, `.zugang`, `.lokal` (German UI names)
- Sub-views as `private struct` in the same file when only used within: `private struct AnpassenTab: View` (`BlitzText/Settings/SettingsView.swift:50`)
- `@MainActor` on view models / window controllers, plain SwiftUI `View`s rely on implicit MainActor isolation

## Function Design

**Size:** Methods stay focused. `runPipeline` (~70 lines) is the longest acceptable single function — it's a sequence of clearly commented stages.

**Parameters:** Use external argument labels everywhere (`audioURL:`, `language:`, `prompt:`). Use omit-label `_` only for value-style helpers.

**Defaults:** Inject session/dependencies with default values for testability:
```swift
init(settings: SettingsStore, session: URLSession = .shared)
```
Pattern in `BlitzText/Transcription/WhisperAPIClient.swift:10`, `BlitzText/Rewrite/OpenAIChatClient.swift:10`.

## Module / File Design

- No barrel files / no umbrella `import` re-exports
- Protocols in the same file as their primary error/extension when small (`TranscriptionService` + `TranscriptionError` in one file, `BlitzText/Transcription/TranscriptionService.swift`)
- `// MARK: -` section dividers in larger files to navigate (`Public API`, `Pipeline`, `Helpers`, `Persistence`, etc.)

## Comments

- Triple-slash `///` doc comments on public types and non-trivial methods, in German when describing user-facing behavior, English when describing implementation
- Inline `//` comments explain WHY (especially for non-obvious workarounds — see Keychain ACL comment in `SettingsStore.swift:27-30`, single-instance handling in `AppDelegate.swift:26-27`)
- `// MARK: - Section Name` for in-file navigation

## What NOT to do

- Do NOT add SwiftLint or SwiftFormat without team buy-in — formatting is hand-tuned
- Do NOT switch `SWIFT_STRICT_CONCURRENCY` to `complete` without a migration plan — would require auditing all C-callback bridges
- Do NOT introduce new English UI strings — UI is German-only
- Do NOT log raw transcripts in normal flow — only on the existing hallucination/silence-discard paths
- Do NOT manually save `SettingsStore` — the Combine debounce pipeline does it
- Do NOT edit `BlitzText.xcodeproj/project.pbxproj` directly — re-run XcodeGen against `project.yml`

---

*Convention analysis: 2026-04-30*
