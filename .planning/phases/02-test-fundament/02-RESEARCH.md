# Phase 2: Test-Fundament — Research

**Researched:** 2026-04-30
**Domain:** XCTest/Swift-Testing-Target-Setup auf XcodeGen + Test-Seams für Hotkey-State-Machine, Pipeline-Fehlerpfade
**Confidence:** HIGH

## Summary

Phase 2 baut ein automatisiertes Test-Fundament für eine Swift-6-Menubar-App auf, die in Phase 1 bereits stabilisiert wurde. Die Codebase hat keine Tests (`grep -rn "XCTest\|@testable\|@Test " BlitzText/` → 0 Treffer, kein Test-Target in `project.yml`). Phase 2 deckt drei der vier TEST-Requirements ab (TEST-03 ist nach Phase 4 verschoben).

Die zu testenden Komponenten haben unterschiedliche Test-Reife:

- **Hotkey-State-Machine** (`HotkeyManager.handleHoldTransition` / `handleToggleTransition`): Reine Logik, aber **derzeit `private` und nur über die CGEventTap-C-Callback-Pfad erreichbar**. Erfordert minimalen Refactor (Extraktion der State-Machine-Übergänge in eine `internal`/`@testable`-erreichbare Funktion ohne `CGEvent`-Parameter), damit synthetische Modifier-Flag-Tupel als Input dienen können.
- **Pipeline-Fehlerpfade**: `TranscriptionService` ist bereits ein sauberer Protokoll-Seam (`Sendable`, `async throws`). `ModeProcessor` kann durch das Protokoll mit Fake-Implementierungen gefüttert werden, **aber `ModeProcessor` instanziiert die Backend-Clients selbst als `private lazy`** — Test-Injektion erfordert kleinen Refactor (Init-Parameter mit Default-Argumenten, analog zum bereits existierenden Muster in `WhisperAPIClient.init(settings:session:)`).
- **`AudioRecorder`** ist tief mit `AVAudioEngine` + Mikrofon-Permission verzahnt → für TEST-04 muss der Recorder hinter einem Protokoll oder per Init-Substitution durch einen Fake ersetzbar sein, sonst aktiviert jeder Test-Run die Mikrofon-Hardware (= Flake + Permission-Prompt).

**Primary recommendation:** XCTest (nicht Swift Testing) verwenden, Test-Target via XcodeGen `type: bundle.unit-test` mit `dependencies: [target: BlitzText]`, **vor den Test-Tasks zwei kleine Refactor-Tasks** (1: State-Machine-Funktion in HotkeyManager `internal` extrahieren; 2: `ModeProcessor.init` um optionale `transcriber:`/`rewriter:`/`recorder:`-Parameter erweitern, weiterhin selbst-instanziierend per Default). Tests schreiben bei laufender Mikrofon-Permission-Sandbox-Frage **immer** unter `XCTSkipUnless`-Gate oder vermeiden den Recorder vollständig (= bevorzugt).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Test-Target Build-Pipeline | Build/Tooling (XcodeGen + xcodebuild) | — | `project.yml` ist Source-of-Truth; CI/CD existiert nicht, lokales `xcodebuild test` reicht |
| Hotkey-State-Machine-Tests | Pure Swift Logic (Hotkeys/) | — | Modifier-Flag → (Mode, Action)-Mapping ist deterministisch ohne OS-Calls, sobald aus C-Callback isoliert |
| Pipeline-Fehlerpfad-Tests | Modes/ (Orchestrator) | Transcription/ (Fake-Implementations des Service-Protokolls) | `ModeProcessor` ruft Backend → wir liefern Fakes, die definierte Errors werfen |
| Test-Doubles für Recorder | Audio/ Boundary | — | Recorder muss ersetzbar sein, sonst läuft AVAudioEngine in Tests an |
| Test-Doubles für Backends | Transcription/ Boundary | — | `TranscriptionService` Protokoll existiert bereits — Fakes leben in `BlitzTextTests/Support/` |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| XCTest | system (Xcode 26.4.1) | Unit-Test-Framework | Reift, integriert mit `xcodebuild test`, kann `@MainActor`-Methoden testen, `@testable import` funktioniert ohne Sonderkonfiguration [VERIFIED: `/usr/bin/xcodebuild -version` → Xcode 26.4.1] |
| Swift Testing (`import Testing`) | system (Swift 6.0) | Modernes Test-Framework | Optional, aber: Erfordert keine extra Build-Config in Swift 6/Xcode 16+. Kann **gleichzeitig** mit XCTest in einem Target leben [CITED: developer.apple.com/xcode/swift-testing] |
| XcodeGen | 2.45.4 | Test-Target-Generierung | Bereits Toolchain-Standard im Projekt; `bundle.unit-test`-Preset bringt korrekte `BUNDLE_LOADER`/`TEST_HOST`-Defaults [VERIFIED: `xcodegen --version` → 2.45.4] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| keine | — | URLProtocol-Stubs sind Apple-System | Für `WhisperAPIClient`-Tests (TEST-04 OpenAI-Fehler-Pfad). Bereits in `.planning/codebase/TESTING.md:73` als Strategie dokumentiert; kein neues Dependency. |

**Empfehlung — XCTest, nicht Swift Testing, für Phase 2:**

`.planning/codebase/TESTING.md:24-28` empfiehlt zwar Swift Testing, **aber:**

1. Die zu testenden Klassen sind alle `@MainActor` (`ModeProcessor`) oder `@unchecked Sendable` (`HotkeyManager`, Backend-Clients). XCTest's `@MainActor func test…() async`-Pattern ist erprobt und vermeidet Sub-Test-Discovery-Probleme, die Swift Testing in `@MainActor`-Kontexten gelegentlich noch hat.
2. Die Codebase hat **null** existierende Tests — es gibt keinen Migrationsschmerz, der Swift Testing rechtfertigt.
3. XCTest ist näher an dem, was Swift-6-strict-concurrency-relaxed-Code (`SWIFT_STRICT_CONCURRENCY: minimal`) erwartet.
4. `XCTestExpectation` für asynchrone Pipeline-Verifikation ist nach wie vor das pragmatischste Werkzeug für State-Machine-Stoßverläufe.

**Alternative:** Swift Testing einführen, falls die Discuss-Phase explizit modernen Stack will — beide Frameworks koexistieren in einem Target ([CITED: github.com/swiftlang/swift-testing]). Empfohlen: **erst XCTest, Swift Testing optional in Phase 4** (TEST-03) hinzunehmen, falls Bedarf entsteht.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| XCTest | Swift Testing | Moderne Macros (`@Test` / `#expect`) statt `XCTAssert*`, parallel-by-default — aber für 0-zu-1-Setup gewinnt Tooling-Reife von XCTest |
| URLProtocol-Stub | OHHTTPStubs / Mocker | Beides sind externe Pakete — gegen das Projekt-Prinzip "zero new SPM deps für Tests" |
| Manuelle Hotkey-Tests | swift-quickcheck Property-based | Übertrieben für 4–6 endliche State-Übergänge |

**Installation:**
Keine neuen SPM-Dependencies. XCTest ist über `import XCTest` direkt verfügbar im `bundle.unit-test`-Target.

**Version verification:**
- Xcode 26.4.1 (Build 17E202) [VERIFIED: `xcodebuild -version`]
- XcodeGen 2.45.4 [VERIFIED: `xcodegen --version`]
- Swift 6.0 (Toolchain ist Xcode-26-bundled) [VERIFIED: `project.yml:17`]

## Architecture Patterns

### System Architecture Diagram

```text
┌──────────────────────────────────────────────────────────────────────┐
│  xcodebuild test -project BlitzText.xcodeproj                        │
│       -scheme BlitzText -destination 'platform=macOS'                │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  BlitzTextTests.xctest  (bundle.unit-test, Host: BlitzText.app)      │
│  @testable import BlitzText                                          │
└──────┬─────────────────┬─────────────────┬───────────────────────────┘
       │                 │                 │
       ▼                 ▼                 ▼
┌─────────────┐  ┌──────────────────┐  ┌───────────────────────────┐
│ Hotkeys/    │  │ Modes/           │  │ Transcription/            │
│ HotkeyState │  │ ModeProcessor    │  │ TranscriptionError-Mapping│
│ MachineTests│  │ ErrorPathTests   │  │ via FakeTranscriber       │
│             │  │                  │  │                           │
│ Input:      │  │ Input:           │  │ Input:                    │
│ synthetic   │  │ FakeRecorder +   │  │ URLProtocol-Stub          │
│ flag tuples │  │ FakeTranscriber  │  │ (HTTP 401/429/5xx)        │
│ (fn/Shift/  │  │ that throws each │  │                           │
│ Ctrl/Opt)   │  │ TranscriptionErr │  │                           │
│             │  │ case             │  │                           │
│ Assert:     │  │ Assert: state =  │  │ Assert: TranscriptionError│
│ (Mode,      │  │ .error("…")      │  │ case = .http/.network     │
│ Action)     │  │ + humanReadable  │  │ /.missingAPIKey           │
│ tuples      │  │ string is German │  │                           │
└─────────────┘  └──────────────────┘  └───────────────────────────┘

Test seams (must exist before tests can run):
  • HotkeyManager exposes internal `decideTransition(flags:triggerMode:now:)`
    that is called from both the C-callback path AND the test
  • ModeProcessor accepts injected `TranscriptionService` + `RewriteService`
    + a `RecorderProtocol` (NEW) via init parameters with sensible defaults
  • A FakeRecorder conforms to RecorderProtocol and produces a tiny
    pre-existing WAV fixture without touching AVAudioEngine
```

### Recommended Project Structure

```
BlitzTextTests/                              # NEW directory at repo root
├── Hotkeys/
│   └── HotkeyStateMachineTests.swift        # TEST-02
├── Modes/
│   ├── ModeProcessorErrorPathTests.swift    # TEST-04 (Whisper error, Parakeet missing, Diarization fail)
│   ├── HallucinationFilterTests.swift       # bonus, pure logic
│   └── PromptCompositionTests.swift         # bonus, pure logic (low cost, high value)
├── Transcription/
│   ├── WhisperAPIClientTests.swift          # TEST-04 OpenAI HTTP error mapping
│   └── TranscriptionErrorMessagesTests.swift# German strings stable
└── Support/
    ├── URLProtocolStub.swift                # shared HTTP stub
    ├── FakeTranscriptionService.swift       # configurable error/success
    ├── FakeRewriteService.swift
    ├── FakeAudioRecorder.swift              # returns a fixture WAV URL
    └── Fixtures/
        └── tiny.wav                         # ~0.5 s pre-recorded silence WAV (~16 kB)
```

### Pattern 1: XcodeGen Test-Target via `bundle.unit-test`

**What:** Add a sibling test target to `BlitzText` in `project.yml`. The `bundle.unit-test` preset injects `BUNDLE_LOADER`/`TEST_HOST` plus required `LD_RUNPATH_SEARCH_PATHS` for macOS automatically.
**When to use:** Standard Apple unit-test target hosted by the app under test (we need `@testable import BlitzText`).

```yaml
# Source: github.com/yonaskolb/XcodeGen/blob/master/SettingPresets/Products/bundle.unit-test.yml
# Append to project.yml under `targets:` (next to BlitzText:):

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
        SWIFT_STRICT_CONCURRENCY: minimal     # match the app target — or test code won't compile
        GENERATE_INFOPLIST_FILE: YES
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/BlitzText.app/Contents/MacOS/BlitzText"
        # Optional: opt the test target out of code signing during xcodebuild test
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGNING_REQUIRED: "NO"
```

**Schemes:** XcodeGen by default makes the `BlitzText` scheme include the test target as a test action **if** the test target's `dependencies` include the app and the project sets `schemes` correctly. Add an explicit scheme block to be safe:

```yaml
schemes:
  BlitzText:
    build:
      targets:
        BlitzText: all
        BlitzTextTests: [test]
    test:
      gatherCoverageData: true
      coverageTargets: [BlitzText]
      targets: [BlitzTextTests]
    run:
      config: Debug
```

`xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS'` runs from the repo root.

### Pattern 2: Hotkey-State-Machine Test Seam

**What:** Extract pure logic from `HotkeyManager.handleFlagsChanged` into an `internal` (so `@testable import` reaches it) function that takes a value-typed input.
**Why a refactor is required:** Currently `handleHoldTransition` and `handleToggleTransition` are `private` and operate on mutable instance state (`currentMode`, `lastTriggerAt`). To unit-test "fn+Shift hold start, release, fn+Control press" sequences without a CGEventTap, expose:

```swift
// Add to BlitzText/Hotkeys/HotkeyManager.swift

extension HotkeyManager {
    /// Pure value-input version of the state machine for tests.
    /// Source: refactor target — extract logic from handleFlagsChanged + handleHoldTransition.
    struct FlagsInput: Equatable {
        var fn: Bool
        var shift: Bool
        var control: Bool
        var option: Bool
    }

    enum Outcome: Equatable {
        case none
        case start(Mode)
        case stop(Mode)
        case toggle(Mode)
    }

    /// Same logic as handleFlagsChanged, but pure: takes a value `now: Date`
    /// for deterministic debounce testing, and returns Outcomes instead of
    /// dispatching via DispatchQueue.main.
    internal func decideTransition(
        flags: FlagsInput,
        triggerMode: TriggerMode,
        now: Date
    ) -> [Outcome] { … }
}
```

**Test pattern:**

```swift
// File: BlitzTextTests/Hotkeys/HotkeyStateMachineTests.swift
// Source: derived from HotkeyManager.handleFlagsChanged — pure logic only

@testable import BlitzText
import XCTest

@MainActor
final class HotkeyStateMachineTests: XCTestCase {
    func test_holdMode_fnShift_thenRelease_emitsStartStop() {
        let settings = SettingsStore()
        settings.triggerMode = .hold
        let manager = HotkeyManager(settings: settings, onTrigger: { _, _ in })
        let t0 = Date()
        let press   = manager.decideTransition(flags: .init(fn: true, shift: true, control: false, option: false), triggerMode: .hold, now: t0)
        let release = manager.decideTransition(flags: .init(fn: false, shift: false, control: false, option: false), triggerMode: .hold, now: t0.addingTimeInterval(0.1))
        XCTAssertEqual(press,   [.start(.blitztext)])
        XCTAssertEqual(release, [.stop(.blitztext)])
    }

    func test_holdMode_modeSwitchMidPress_emitsStopThenStart() {
        // fn+Shift held -> while still holding fn, switch to fn+Control
        // expects: stop(.blitztext), start(.blitztextPlus)
    }

    func test_holdMode_belowDebounce_isIgnored() {
        // two start events within 50 ms -> only one start emitted
    }

    func test_toggleMode_pressOnly_emitsToggle() {
        // toggle mode ignores release; press emits .toggle(mode)
    }

    func test_toggleMode_doubleTapWithinDebounce_emitsOnce() {
        // two presses within 300 ms -> single .toggle
    }
}
```

### Pattern 3: Pipeline-Fehlerpfad Test Seam (TEST-04)

**What:** `ModeProcessor` calls a `TranscriptionService` it lazy-instantiates. To test error paths, allow init-injection (defaults preserve current production behavior).

**Required refactor (small):**

```swift
// BlitzText/Modes/ModeProcessor.swift — change the init only

init(
    settings: SettingsStore,
    history: HistoryStore,
    modelManager: LocalModelManager,
    // NEW (test seams) — production keeps existing lazy defaults:
    openAITranscriber: TranscriptionService? = nil,
    localTranscriber:  TranscriptionService? = nil,
    parakeetTranscriber: TranscriptionService? = nil,
    rewriter:          RewriteService? = nil,
    recorder:          AudioRecorder? = nil
) { … }
```

`ModeProcessor` keeps its lazy defaults if `nil`; tests pass fakes.

**Fake transcribers:**

```swift
// File: BlitzTextTests/Support/FakeTranscriptionService.swift
// Source: implements TranscriptionService protocol from BlitzText/Transcription/TranscriptionService.swift

import Foundation
@testable import BlitzText

final class FakeTranscriptionService: TranscriptionService, @unchecked Sendable {
    let result: Result<String, Error>
    init(_ result: Result<String, Error>) { self.result = result }
    func transcribe(audioURL: URL, language: String?, prompt: String?) async throws -> String {
        try result.get()
    }
}
```

**Three error-path tests (TEST-04 success criterion):**

| Requirement | Backend | Injected error | Expected `ModeProcessor.state` |
|-------------|---------|----------------|--------------------------------|
| TEST-04 (a) Whisper-API-Fehler | `.openAI` | `TranscriptionError.http(401, "{\"error\":…}")` | `.error("OpenAI-Fehler 401: …")` (from `TranscriptionError.errorDescription`) |
| TEST-04 (b) fehlendes Parakeet-Modell | `.parakeet` | `TranscriptionError.backendNotAvailable` | `.error("Lokales Modell ist noch nicht verfügbar.")` |
| TEST-04 (c) Diarization-Fehlschlag | `.parakeet` (with diarization on) | A custom error from a Fake that returns plain text but logs Diar-Fail | Pipeline still delivers text successfully (current production swallows diar fail — see `ParakeetClient.swift:51-53`). The test asserts that **diarization failure does not poison the pipeline**: `state` returns to `.idle`, raw text reaches clipboard. |

**Note on TEST-04 (c):** The current `ParakeetClient.applyDiarization` *intentionally* falls back to raw text on diarization failure (good UX). The test should pin this behavior so a future refactor doesn't accidentally turn diarization failures into hard pipeline errors.

**FakeRecorder for `AudioRecorder` substitution:**

```swift
// File: BlitzTextTests/Support/FakeAudioRecorder.swift
// Provides a fixed fixture URL so the pipeline never touches AVAudioEngine.
```

**Refactor required for AudioRecorder:** Either (a) extract a `RecorderProtocol` and have `ModeProcessor` depend on it, or (b) add a test hook that returns a deterministic fixture URL. Option (a) is cleaner; option (b) is smaller. Recommend (b) for Phase 2, defer (a) to Phase 4 if needed.

**Specifically:** `AudioRecorder.start()` calls `ensureMicrophonePermissionSync` (`AudioRecorder.swift:161`) which **blocks on a semaphore** for the AVCaptureDevice prompt. This will hang the test process if Mic permission is not pre-granted. Two safe options:

1. (Preferred) Make `ModeProcessor` accept a recorder via init (see refactor above) so tests bypass `AudioRecorder` entirely by injecting a simpler test double that conforms to a minimal protocol (read: extract a 3-method `RecorderProtocol { func start() throws -> URL; func stop() -> URL?; var currentLevel: Float { get } }`).
2. (Fallback) Skip Mic-touching tests via `try XCTSkipUnless(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, "Mic permission required")`.

### Pattern 4: URLProtocol HTTP Stub for `WhisperAPIClient`

**What:** Apple's `URLProtocol` subclass intercepts requests on a custom `URLSession`. Already-existing seam: `WhisperAPIClient.init(settings:session:)` accepts a custom session.

```swift
// File: BlitzTextTests/Support/URLProtocolStub.swift
// Source: standard pattern — see TESTING.md:73 in this repo and
//         developer.apple.com/documentation/foundation/urlprotocol

final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    override class func canInit(with: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        guard let h = Self.handler else { client?.urlProtocolDidFinishLoading(self); return }
        let (resp, data) = h(request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: cfg)
    }
}
```

### Anti-Patterns to Avoid

- **`Thread.sleep` in tests:** never. Use `XCTestExpectation` or directly drive deterministic state via `now: Date` injection (Pattern 2).
- **Tests that import live `URLSession.shared`:** flake on offline CI / corporate proxy. Always inject a stubbed session.
- **Tests of `AudioRecorder.start()` directly:** Mic-permission semaphore (`AudioRecorder.swift:161`) hangs in headless contexts. Bypass via fake.
- **Testing CGEvent dispatch:** `HotkeyManager.installEventTap` requires Accessibility TCC. Tests must call only the pure state-machine seam (Pattern 2).
- **Using `Mocks/` folder for test fixtures:** `Mocks/` contains UI screenshots (PNG). Put test fixtures in `BlitzTextTests/Support/Fixtures/` (`.planning/codebase/TESTING.md:18-21`).
- **Manual `XCTAssertEqual` on formatted JSON bytes:** decode and compare structs (`.planning/codebase/TESTING.md:129`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP mocking | A custom `URLSessionDataDelegate` | `URLProtocol` subclass | Standard Apple seam, zero deps, handles all request types |
| Test runner | A SwiftPM script that calls `swift test` | `xcodebuild test -scheme BlitzText -destination 'platform=macOS'` | App target depends on Xcode-only frameworks (AppKit, AVFoundation entitlements) — SwiftPM can't host the app |
| State-machine test harness | A "key-event simulator" with `CGEvent` synthesis | A pure `decideTransition(flags:triggerMode:now:)` extraction | Synthesizing `CGEvent`s requires the same Accessibility permission as the live tap, defeats the purpose |
| Async test waiting | `DispatchSemaphore.wait` | `XCTestExpectation` + `await fulfillment(of:timeout:)` (Swift 6 API) | Semaphores deadlock with MainActor; expectations integrate with concurrency |
| Test-double generation | Sourcery / Cuckoo / Mockingbird | Hand-written struct/class fakes (~10 lines each) | The seams are narrow (`TranscriptionService` is one method); generated mocks are overkill and add tooling debt |

**Key insight:** Apple's test stack is mature for the narrow surface this phase needs. The friction is **not** in the test framework — it's in making the production code injectable. Spend Phase 2 effort on small, surgical refactors (Patterns 2 + 3), not on new tooling.

## Common Pitfalls

### Pitfall 1: Test target doesn't link with `BlitzText` because of unsigned entitlements

**What goes wrong:** `xcodebuild test` fails with "BlitzText isn't code signed but requires entitlements" when the test bundle is loaded into the host app.
**Why it happens:** The app uses `com.apple.security.app-sandbox: false` plus `device.audio-input` entitlement; ad-hoc `-` signing combined with unsigned entitlements can break test loading.
**How to avoid:** Use the same `Scripts/build.sh`-style flow that already works:
```bash
xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```
Or sign with the existing local "BlitzText Local Dev" cert that `Scripts/create-signing-cert.sh` produces (per Phase-1 verification, this cert is what makes TCC stick across rebuilds).
**Warning signs:** "Test bundle could not be loaded" / "dyld: …" errors during test invocation.

### Pitfall 2: Mic-permission prompt during tests

**What goes wrong:** A test that exercises `ModeProcessor.start(mode:)` triggers `AudioRecorder.ensureMicrophonePermissionSync`, which blocks on a `DispatchSemaphore` until the user responds to the system Mic prompt. In headless / non-interactive test runs the prompt never appears → test hangs forever.
**Why it happens:** `AudioRecorder.start()` calls `ensureMicrophonePermissionSync()` synchronously (`AudioRecorder.swift:161`), and the prompt only fires once per app bundle ID.
**How to avoid:** Inject a `FakeRecorder` (Pattern 3) so tests never touch `AudioRecorder.start()`. As a fallback, gate Mic-touching tests with `try XCTSkipUnless(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, …)`.
**Warning signs:** Test "stalls" past a 30 s `xcodebuild test` timeout. First-run on a fresh machine triggers a Mic prompt while tests run.

### Pitfall 3: Tests against `@unchecked Sendable` classes without `@MainActor`

**What goes wrong:** Calling a method on `ModeProcessor` (a `@MainActor` class) from a non-MainActor test method either fails to compile (in `complete` strict-concurrency) or warns at runtime under `minimal`.
**Why it happens:** `SWIFT_STRICT_CONCURRENCY: minimal` is permissive but `@MainActor` is still enforced for explicit annotations.
**How to avoid:** Annotate the test class itself `@MainActor final class ModeProcessorErrorPathTests: XCTestCase` (`.planning/codebase/TESTING.md:125`). Then `await mp.start(mode: .blitztext)` works directly.
**Warning signs:** "Call to main actor-isolated instance method 'start' in a synchronous nonisolated context" compile error.

### Pitfall 4: `xcodegen generate` not run before `xcodebuild test`

**What goes wrong:** Phase-2 PR adds `BlitzTextTests/` directory + edits `project.yml`, but the `.xcodeproj` is gitignored. A reviewer runs `xcodebuild test` against a stale project file and sees "scheme not found".
**Why it happens:** `BlitzText.xcodeproj/` is generated, not committed (`.planning/codebase/STRUCTURE.md:204-207`).
**How to avoid:** Every plan step that touches `project.yml` ends with `xcodegen generate` followed by a build verification. Phase verification command should chain them: `xcodegen generate && xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS'`.
**Warning signs:** `xcodebuild: error: The project ... does not contain a scheme named "BlitzTextTests"`.

### Pitfall 5: Flakes from real Date/Time in debounce assertions

**What goes wrong:** A test that does `manager.handle(...); Thread.sleep(0.05); manager.handle(...)` is racy on busy CI.
**Why it happens:** `lastTriggerAt = Date()` is wall-clock; sleep durations vary.
**How to avoid:** Inject `now: Date` into the pure state-machine function (Pattern 2). Every test passes explicit timestamps.
**Warning signs:** "Test passes locally, fails on first xcodebuild test rerun" — i.e. failure rate > 0% across the 3 required runs.

## Code Examples

### XcodeGen test target with scheme (full snippet)

```yaml
# Source: github.com/yonaskolb/XcodeGen — bundle.unit-test preset
# Append to project.yml

targets:
  BlitzText:
    # ... existing definition unchanged ...

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
        SWIFT_STRICT_CONCURRENCY: minimal
        GENERATE_INFOPLIST_FILE: YES
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/BlitzText.app/Contents/MacOS/BlitzText"

schemes:
  BlitzText:
    build:
      targets:
        BlitzText: all
        BlitzTextTests: [test]
    test:
      gatherCoverageData: true
      coverageTargets: [BlitzText]
      targets: [BlitzTextTests]
    run:
      config: Debug
```

### One end-to-end pipeline error-path test (TEST-04 a)

```swift
// File: BlitzTextTests/Modes/ModeProcessorErrorPathTests.swift
// Source: derived from BlitzText/Modes/ModeProcessor.swift:99-173 (runPipeline)

@testable import BlitzText
import XCTest

@MainActor
final class ModeProcessorErrorPathTests: XCTestCase {
    func test_whisperHTTP401_setsStateToErrorWithGermanMessage() async throws {
        let settings = SettingsStore()
        settings.backend = .openAI
        let history = HistoryStore()           // assumes default tmp path or override
        let modelMgr = LocalModelManager()
        let fakeRec = FakeAudioRecorder(fixtureURL: try Self.tinyFixture())
        let fakeT   = FakeTranscriptionService(.failure(
            TranscriptionError.http(401, "{\"error\":\"invalid api key\"}")))
        let mp = ModeProcessor(
            settings: settings, history: history, modelManager: modelMgr,
            openAITranscriber: fakeT, recorder: fakeRec)

        await mp.start(mode: .blitztext)
        await mp.stop()

        guard case let .error(msg) = mp.state else {
            return XCTFail("Expected .error state, got \(mp.state)")
        }
        XCTAssertTrue(msg.contains("OpenAI-Fehler 401"), "Expected German error from TranscriptionError.errorDescription, got \(msg)")
    }

    private static func tinyFixture() throws -> URL {
        let url = Bundle(for: ModeProcessorErrorPathTests.self).url(
            forResource: "tiny", withExtension: "wav")!
        return url
    }
}
```

### Hotkey state-machine test (TEST-02)

```swift
// File: BlitzTextTests/Hotkeys/HotkeyStateMachineTests.swift

@testable import BlitzText
import XCTest

@MainActor
final class HotkeyStateMachineTests: XCTestCase {
    func test_holdMode_pressFnShift_thenRelease_emitsStartThenStop() {
        let settings = SettingsStore(); settings.triggerMode = .hold
        let mgr = HotkeyManager(settings: settings, onTrigger: { _, _ in })
        let t0 = Date()
        XCTAssertEqual(
            mgr.decideTransition(flags: .init(fn: true, shift: true, control: false, option: false), triggerMode: .hold, now: t0),
            [.start(.blitztext)])
        XCTAssertEqual(
            mgr.decideTransition(flags: .init(fn: false, shift: false, control: false, option: false), triggerMode: .hold, now: t0.addingTimeInterval(0.2)),
            [.stop(.blitztext)])
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| OCMock / Mockingbird mock generation | Hand-written struct fakes against narrow protocols | Always idiomatic for Swift | Tests ship without external deps |
| `XCTestExpectation` + `wait(for:)` | `await fulfillment(of:timeout:)` | Xcode 14 / Swift 5.7+ | First-class async; no semaphore deadlocks |
| XCTest only | XCTest + Swift Testing side-by-side | Xcode 16 / Swift 6.0 | New tests can use `@Test` macro; existing XCTest keeps working [CITED: developer.apple.com/xcode/swift-testing] |
| Manual code-coverage flag toggling in Xcode | `gatherCoverageData: true` in XcodeGen scheme | XcodeGen 2.x | Coverage opt-in lives in `project.yml` |

**Deprecated/outdated:**
- `XCTestCase`-instance-method-named `setUp()` / `tearDown()` without `@MainActor`: still works but lints; prefer `@MainActor override func setUp() async throws { … }` when the SUT is MainActor-isolated.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | XcodeGen 2.45.4 still emits the documented `bundle.unit-test` preset on macOS 26 deployment target | Pattern 1 | Low — preset is stable since 2.0; risk = small `LD_RUNPATH_SEARCH_PATHS` adjustment |
| A2 | `xcodebuild test` works against an unsigned/ad-hoc-signed app target without changing entitlements | Pitfall 1 | Medium — Phase-1 verification already builds with `CODE_SIGN_IDENTITY=""`; tests should follow the same pattern, but mic + accessibility-entitlement test bundles occasionally need re-signing on macOS 26 |
| A3 | `HistoryStore` can be instantiated in a test without mutating the real `~/Library/Application Support/BlitzText/history.json` — i.e. there is a way to scope the path | Pattern 3 | Medium — currently the path is hardcoded (`HistoryStore.swift:31-36`). The plan may need a tiny refactor to accept an injectable URL, OR tests skip history assertions entirely |
| A4 | `SettingsStore` can be safely instantiated in a test without polluting the real Keychain | Pattern 3 | Medium — `SettingsStore.init` calls `migrateAPIKeyFromUserDefaultsIfNeeded()` which touches the live Keychain via `Keychain.shared`. Mitigation: in tests, only read `apiKey` after explicitly setting an empty string; never test the migration path in this phase. Phase-1 already covered the migration with code-truth verification. |
| A5 | The 30 s test-suite budget (success criterion 4) is achievable given the test set above (~10 unit tests, no real network, no model loads) | Phase scope | Low — unit tests on pure logic + URLProtocol stubs run in milliseconds; 30 s is generous |
| A6 | Tests run reliably in `SWIFT_STRICT_CONCURRENCY: minimal` without warnings | Pitfall 3 | Low — the production code already runs at `minimal`; tests inheriting the same setting are no stricter |

**User confirmation suggested for:** A3 (whether HistoryStore needs path injection now or if Phase 4 is fine), A4 (whether to scope Keychain in tests via `kSecAttrService` override or leave as-is).

## Open Questions

1. **Should we use Swift Testing or XCTest?**
   - What we know: Both work in Swift 6 / Xcode 26; `.planning/codebase/TESTING.md:24` recommends Swift Testing.
   - What's unclear: Whether the discuss-phase has a strong preference. Swift Testing's `@Test` macro is nicer; XCTest's tooling is more mature for `@MainActor` types.
   - Recommendation: **XCTest for Phase 2** (zero-setup, async-tested, ubiquitous patterns). Swift Testing can be added in Phase 4 alongside TEST-03 as a low-risk experiment.

2. **Where to scope the test-only path for `HistoryStore`?**
   - What we know: `HistoryStore` reads/writes `~/Library/Application Support/BlitzText/history.json` unconditionally.
   - What's unclear: Whether to refactor the path-injection now (Phase 2) or use `XCTSkipUnless` to skip history-touching tests (defer to Phase 4).
   - Recommendation: For Phase 2 error-path tests, `state` assertions don't actually need `HistoryStore` to write — instantiate it and tolerate the side-effect, OR refactor `init(historyURL: URL = …)` (10 lines).

3. **Should TEST-04 (c) "Diarization-Fehlschlag" assert success or surface a warning?**
   - What we know: `ParakeetClient.transcribe` swallows diarization errors and returns raw text (`ParakeetClient.swift:51-53`). `RISKS.md`/`CONCERNS.md` flag this as P2 fragile (silent fallback).
   - What's unclear: Whether the test pins current behavior (success + raw text) or asserts the upcoming "show HUD warning" behavior.
   - Recommendation: Pin **current** behavior in Phase 2 (raw text returned, no error in `state`). The "Diarization unavailable" UX is a Phase 3 concern.

4. **Coverage threshold?**
   - What we know: No threshold today; `gatherCoverageData: true` collects data.
   - Recommendation: No threshold in Phase 2 — establish baseline first, set threshold in a later phase.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode / `xcodebuild` | xcodebuild test | ✓ | 26.4.1 (Build 17E202) | — |
| `xcodegen` | project.yml regeneration | ✓ | 2.45.4 | — |
| Swift 6.0 toolchain | test target compile | ✓ | bundled with Xcode 26 | — |
| Microphone TCC permission (BlitzText.app bundle) | only if a test exercises real `AudioRecorder` (we avoid this) | unknown | — | All Mic-touching tests use `FakeAudioRecorder` (Pattern 3) → no Mic dependency |
| Accessibility TCC permission (BlitzText.app bundle) | only if a test exercises real `CGEventTap` (we avoid this) | unknown | — | All Hotkey tests target the pure `decideTransition` seam (Pattern 2) → no AX dependency |
| Network access | NOT required (URLProtocol stubs intercept) | n/a | — | — |
| WhisperKit/FluidAudio model files (~80 MB + 1–3 GB) | NOT required (no real backend tests) | unknown | — | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — all Phase-2 tests are pure-logic + injected fakes; runtime permissions are not required.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (Xcode 26.4.1, Swift 6.0) |
| Config file | `project.yml` (XcodeGen) — `BlitzTextTests` target + `schemes.BlitzText.test` block |
| Quick run command | `xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/HotkeyStateMachineTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO` |
| Full suite command | `xcodegen generate && xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-01 | `BlitzTextTests` target compiles and `xcodebuild test` succeeds | smoke / build | `xcodegen generate && xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS'` | ❌ Wave 0 (test target + 1 placeholder test) |
| TEST-02 hold-mode press+release | `decideTransition` emits `[.start(mode)]` then `[.stop(mode)]` | unit | `xcodebuild test ... -only-testing:BlitzTextTests/HotkeyStateMachineTests/test_holdMode_pressFnShift_thenRelease_emitsStartThenStop` | ❌ Wave 0 |
| TEST-02 hold-mode debounce | second press within 50 ms is ignored | unit | `... -only-testing:.../test_holdMode_belowDebounce_isIgnored` | ❌ Wave 0 |
| TEST-02 hold-mode mode switch | fn+Shift → fn+Control without releasing fn → stop+start | unit | `... -only-testing:.../test_holdMode_modeSwitchMidPress_emitsStopThenStart` | ❌ Wave 0 |
| TEST-02 toggle-mode press | toggle mode emits `.toggle(mode)` on press only | unit | `... -only-testing:.../test_toggleMode_pressOnly_emitsToggle` | ❌ Wave 0 |
| TEST-02 toggle-mode debounce | double-tap within 300 ms emits one toggle | unit | `... -only-testing:.../test_toggleMode_doubleTapWithinDebounce_emitsOnce` | ❌ Wave 0 |
| TEST-02 fast release | release-during-press-without-debounce-violation produces clean stop | unit | `... -only-testing:.../test_holdMode_fastRelease_emitsStop` | ❌ Wave 0 |
| TEST-04 (a) Whisper-API-Fehler | `.openAI` backend with HTTP 401 → `state == .error` with German message | unit (with FakeTranscriber) | `... -only-testing:BlitzTextTests/ModeProcessorErrorPathTests/test_whisperHTTP401_setsStateToErrorWithGermanMessage` | ❌ Wave 0 |
| TEST-04 (b) fehlendes Parakeet-Modell | `.parakeet` backend, transcriber throws `.backendNotAvailable` → German error | unit (with FakeTranscriber) | `... -only-testing:.../test_parakeetMissingModel_setsStateToBackendNotAvailable` | ❌ Wave 0 |
| TEST-04 (c) Diarization-Fehlschlag | Parakeet transcribe succeeds, diarization swallowed → pipeline returns raw text, `state == .idle` | unit (with FakeTranscriber returning text) | `... -only-testing:.../test_parakeetDiarizationFailure_returnsRawTextSilently` | ❌ Wave 0 |
| Bonus: Hallucination filter | known phrases trigger silent discard | unit (pure) | `... -only-testing:BlitzTextTests/HallucinationFilterTests` | ❌ optional |

### Sampling Rate

- **Per task commit:** `xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/<changed-file>`
- **Per wave merge:** `xcodegen generate && xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`
- **Phase gate:** Full suite must pass three consecutive runs without flakes, total wall time < 30 s. Run via:
  ```bash
  for i in 1 2 3; do time xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO || exit 1; done
  ```

### Wave 0 Gaps

- [ ] `BlitzTextTests/Support/URLProtocolStub.swift` — shared HTTP stub
- [ ] `BlitzTextTests/Support/FakeTranscriptionService.swift` — protocol-conforming fake
- [ ] `BlitzTextTests/Support/FakeRewriteService.swift` — protocol-conforming fake
- [ ] `BlitzTextTests/Support/FakeAudioRecorder.swift` — bypasses AVAudioEngine
- [ ] `BlitzTextTests/Support/Fixtures/tiny.wav` — ~16 kB silence WAV (regenerate via `Scripts/`)
- [ ] `project.yml` — append `BlitzTextTests` target + `schemes.BlitzText.test` block
- [ ] `BlitzText/Hotkeys/HotkeyManager.swift` — extract `decideTransition(flags:triggerMode:now:)` (REFACTOR before tests)
- [ ] `BlitzText/Modes/ModeProcessor.swift` — accept injected `transcriber:`/`rewriter:`/`recorder:` via init defaults (REFACTOR before tests)
- [ ] Optional minor refactor: `BlitzText/Audio/AudioRecorder.swift` — extract a `RecorderProtocol` to make injection type-safe (else use a parent-class hack — NOT recommended)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Phase 2 is test infrastructure; no new auth surface |
| V3 Session Management | no | n/a |
| V4 Access Control | no | n/a |
| V5 Input Validation | yes (indirectly) | Tests verify that `TranscriptionError` cases produce stable user-facing strings — prevents future schema-drift attacks where a malicious API response triggers ungated decoding |
| V6 Cryptography | yes (indirectly) | A future Phase-2 test must NOT touch the real Keychain. `SettingsStore.init` calls `migrateAPIKeyFromUserDefaultsIfNeeded()` which writes to live Keychain via `Keychain.shared` — see Pitfall A4 |

### Known Threat Patterns for {test-target on macOS app with TCC + Keychain}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Test target accidentally writes to user's real Keychain (`Keychain.shared`) | Tampering | Tests never call `SettingsStore.apiKey = …` with a real value; if the migration path is exercised, override `kSecAttrService` to a unique test-prefix and clean up in `tearDown` (`.planning/codebase/TESTING.md:127`) |
| Test target accidentally writes to user's real `~/Library/Application Support/BlitzText/history.json` | Tampering | Either inject a temp directory URL into `HistoryStore`, or accept the side-effect as a known issue and document in test plan (Phase 2 simple, Phase 4 cleanup) |
| Test target leaks the user's real OpenAI API key in a CI log | Information disclosure | Tests use `URLProtocolStub` — no real `URLSession.shared` call. Never echo `settings.apiKey` to test output |
| Mic / Accessibility prompts during `xcodebuild test` (UX, not security but TCC-adjacent) | DoS via blocking semaphore | All tests bypass `AudioRecorder` and `CGEventTap` (Patterns 2 + 3) |

## Project Constraints (from CLAUDE.md)

- Swift 6 with `SWIFT_STRICT_CONCURRENCY: minimal` — test target MUST mirror this setting; do NOT raise it for the test target.
- German UI strings, English code identifiers — test names in English, asserted user-facing strings in German.
- No external-cloud speaker ID — irrelevant for Phase 2, but: tests must NOT introduce any cloud dependency for SPK code.
- `TranscriptionService` protocol abstracts backends — error injection MUST go through the protocol seam, NOT by mocking `URLSession` *except* for the dedicated `WhisperAPIClientTests` where the URLProtocol seam is the unit-under-test.

## Sources

### Primary (HIGH confidence)
- Repository code (verified by Read):
  - `project.yml` (XcodeGen config)
  - `BlitzText/Hotkeys/HotkeyManager.swift` (full file, all 182 lines)
  - `BlitzText/Modes/ModeProcessor.swift` (full file, all 258 lines)
  - `BlitzText/Transcription/TranscriptionService.swift`, `WhisperAPIClient.swift`, `LocalWhisperClient.swift`, `ParakeetClient.swift`
  - `BlitzText/Settings/SettingsStore.swift`
  - `BlitzText/Modes/Mode.swift`
  - `.planning/codebase/{STACK,ARCHITECTURE,STRUCTURE,CONVENTIONS,TESTING,CONCERNS}.md`
  - `.planning/{ROADMAP,REQUIREMENTS,STATE,config}` and `.planning/phases/01-stabilisierung-doku-drift/VERIFICATION.md`
- Tooling versions: `xcodebuild -version` → Xcode 26.4.1; `xcodegen --version` → 2.45.4

### Secondary (MEDIUM confidence)
- [XcodeGen `bundle.unit-test` preset](https://github.com/yonaskolb/XcodeGen/blob/master/SettingPresets/Products/bundle.unit-test.yml)
- [XcodeGen TestProject fixture](https://github.com/yonaskolb/XcodeGen/blob/master/Tests/Fixtures/TestProject/project.yml)
- [Swift Testing announcement (Apple Developer)](https://developer.apple.com/xcode/swift-testing/)
- [Swift Testing on swiftlang/swift-testing](https://github.com/swiftlang/swift-testing)

### Tertiary (LOW confidence)
- None — all claims derive from first-party docs or repo source.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Apple's XCTest/XcodeGen are well-documented and verified in this repo's tooling.
- Architecture (test-target structure + seams): HIGH for the test target itself; MEDIUM for the recorder/history injection refactor (small but touches live code).
- Pitfalls: HIGH — Pitfall 1 (signing) is empirically observed in this very repo's Phase-1 verification; Pitfalls 2–5 are derived from concrete code locations cited above.

**Research date:** 2026-04-30
**Valid until:** 2026-05-30 (XCTest/XcodeGen/Swift 6 are stable; only invalidated by an Xcode major version bump or strict-concurrency policy change)
