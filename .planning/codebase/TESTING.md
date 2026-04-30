# Testing Patterns

**Analysis Date:** 2026-04-30

## Current State: NO AUTOMATED TESTS

**There is no test target, no test framework, and no test code in this project.**

Verified:

- `project.yml` declares a single target `BlitzText` of `type: application`. No `BlitzTextTests`, no `*UITests`, no test bundle.
- `BlitzText.xcodeproj/project.pbxproj` contains no PBXTargetDependency to a test target; only `ENABLE_TESTABILITY = YES` is set on the app target (default Xcode build setting, not a signal of existing tests).
- `grep -rn "XCTest\|@testable\|XCTAssert\|@Test "` across `BlitzText/**/*.swift` returns zero matches.
- No `*Tests*.swift`, `*Spec*.swift`, or `*Test.swift` files exist anywhere in the repo (excluding `build/` artefacts).

## The `Mocks/` Folder Is NOT Test Mocks

`/Users/t.raba/VsCode/BlitzText/Mocks/` contains **UI design screenshots** (PNGs named `Bildschirmfoto 2026-04-29 um HH.MM.SS.png`) used as visual references for the SwiftUI Settings, HUD, and History windows. These are reference images for matching the original UI look, not test fixtures.

**Do not put XCTest mocks in `Mocks/`** — pick a different folder if/when tests are introduced (e.g. `BlitzTextTests/Mocks/`).

## Test Framework

**None configured.** When tests are added, recommended choice:

- **Swift Testing** (`@Test` / `#expect`) — modern, ships with Swift 6, fits the codebase's Swift 6 stance
- Fall back to **XCTest** only if interop with macOS UI testing or older tooling is required

## Recommended Test Target Setup

When introducing tests, edit `project.yml`:

```yaml
targets:
  BlitzText: { ... existing ... }
  BlitzTextTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "26.0"
    sources:
      - path: BlitzTextTests
    dependencies:
      - target: BlitzText
    settings:
      base:
        SWIFT_VERSION: "6.0"
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/BlitzText.app/Contents/MacOS/BlitzText"
```

Then re-run XcodeGen.

## Test Coverage Gaps (current = 100% gap)

Every module is untested. Prioritize as follows when tests get added.

### High-Priority Targets (Pure Logic, Easy to Test)

| Area | File | Why |
|------|------|-----|
| Hallucination filter | `BlitzText/Modes/ModeProcessor.swift:227-245` (`isLikelyHallucination`) | Pure string predicate, regression-prone (Whisper updates change halluc patterns) |
| Eigennamen analyzer | `BlitzText/ProperNouns/EigennamenAnalyzer.swift` | Pure functions over String; NER + diff heuristics |
| Mode prompts | `BlitzText/Modes/Mode.swift` (`defaultRewritePrompt`, `WritingStyle.promptHint`) | String composition, easy snapshot tests |
| Settings JSON snapshot | `BlitzText/Settings/SettingsStore.swift` (`Snapshot` codec round-trip) | Persistence regression risk on schema changes — test forward/backward compat with old JSON blobs |
| TranscriptionError mapping | `BlitzText/Transcription/TranscriptionService.swift` (`errorDescription`) | German strings must stay stable for users |
| Whisper-prompt composition | `BlitzText/Modes/ModeProcessor.swift:177-187` (`makeWhisperPrompt`) | Combines context + proper nouns deterministically |
| Rewrite-prompt composition | `BlitzText/Modes/ModeProcessor.swift:189-212` (`makeRewriteSystemPrompt`) | Concatenates style + context + proper nouns |
| HistoryEntry codec | `BlitzText/History/HistoryStore.swift` | ISO8601 round-trip; `finalText` selection (raw vs polished) |

### Medium-Priority (Networking — Use URLProtocol Stubs)

| Area | File | Strategy |
|------|------|----------|
| OpenAI Whisper client | `BlitzText/Transcription/WhisperAPIClient.swift` | Inject a `URLSession` with `URLProtocol` stub (constructor already accepts `session:`) — assert multipart body shape, error mapping for 401/429/5xx |
| OpenAI Chat client | `BlitzText/Rewrite/OpenAIChatClient.swift` | Same pattern; assert request body JSON, response parsing, error mapping |
| Eigennamen AI suggester | `BlitzText/ProperNouns/EigennamenAISuggester.swift` | Network — same URLProtocol approach |

Both clients already accept `session: URLSession = .shared` in their initializers (`WhisperAPIClient.swift:10`, `OpenAIChatClient.swift:10`) — this is the seam for tests.

### Low-Priority (Hard to Unit-Test, Need Integration Harness)

| Area | File | Why hard |
|------|------|----------|
| Audio recording | `BlitzText/Audio/AudioRecorder.swift` | AVAudioEngine + microphone permission |
| Hotkey tap | `BlitzText/Hotkeys/HotkeyManager.swift` | CGEventTap requires Accessibility TCC permission |
| Text insertion | `BlitzText/Insertion/TextInserter.swift` | Posts CGEvents into the window server |
| Local model clients | `BlitzText/Transcription/LocalWhisperClient.swift`, `ParakeetClient.swift` | Pull large CoreML models, run on-device inference |
| Single-instance enforcement | `BlitzText/App/AppDelegate.swift:28-47` | Calls `exit(0)` and `NSAlert.runModal` |

For these: write smoke / integration tests that spin up the real app with stubbed dependencies, or skip and rely on manual QA.

## Suggested File Layout (When Tests Land)

```
BlitzTextTests/
├── Modes/
│   ├── HallucinationFilterTests.swift
│   ├── PromptCompositionTests.swift
│   └── ModeRewritePromptTests.swift
├── Settings/
│   ├── SettingsStoreSnapshotTests.swift
│   └── KeychainTests.swift           // round-trip with a unique service prefix
├── ProperNouns/
│   ├── EigennamenAnalyzerTests.swift
│   └── EigennamenAISuggesterTests.swift
├── Transcription/
│   ├── WhisperAPIClientTests.swift   // URLProtocol stub
│   └── TranscriptionErrorTests.swift
├── Rewrite/
│   └── OpenAIChatClientTests.swift   // URLProtocol stub
├── History/
│   └── HistoryStoreCodecTests.swift
└── Support/
    ├── URLProtocolStub.swift         // shared test double
    └── Fixtures/                     // sample Whisper JSON, sample audio, ...
```

## Recommended Conventions for Future Tests

When tests are introduced, follow these conventions to match the rest of the codebase:

- Use Swift Testing (`import Testing`) preferred, XCTest as fallback
- Mirror the source folder hierarchy under `BlitzTextTests/`
- Test names describe behaviour, not implementation: `func hallucinationFilter_dropsAmaraOrgPhrase()` over `func test1()`
- Mark tests `@MainActor` if they touch MainActor-isolated types (`ModeProcessor`, `HistoryStore`, `AppDelegate`)
- Use `URLProtocol` stubs (not third-party HTTP mocking libraries) — keep zero new dependencies
- For `Keychain` tests, use a unique `service:` like `"de.reinholds.blitztext.test.\(UUID())"` and clean up in `tearDown` to avoid polluting the user's login keychain
- For `HistoryStore` / `SettingsStore` tests, override the persistence URL/UserDefaults suite — currently both are hardcoded to `Application Support` / `UserDefaults.standard`, so refactoring to inject a path is a prerequisite
- Snapshot golden test JSONs (settings, history) under `BlitzTextTests/Support/Fixtures/` and compare via `XCTAssertEqual` on decoded structs — never byte-compare formatted JSON

## Coverage Tooling

Once a test target exists, enable coverage in the scheme: `Edit Scheme → Test → Options → Code Coverage → Gather coverage for: BlitzText`. View with:

```bash
xcodebuild test -scheme BlitzText -destination 'platform=macOS' -enableCodeCoverage YES
xcrun xccov view --report --files-for-target BlitzText path/to/result.xcresult
```

No coverage threshold enforced today.

## Manual QA Today

Until tests exist, the project relies on:

- Logs at `~/Library/Logs/BlitzText.log` (`BlitzText/App/Log.swift`) — grep for failures, hallucination drops, hotkey tap status
- The `Mocks/` screenshot set as a visual diff reference
- `RISKS.md` and `ARCHITECTURE.md` at the repo root document known fragile areas

---

*Testing analysis: 2026-04-30*
