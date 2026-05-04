# Phase 8: Apple Foundation Rewrite-Backend — Pattern Map

**Mapped:** 2026-05-04
**Files analyzed:** 13 (3 NEW Rewrite/, 1 NEW Settings/Banner, 4 MODIFY core, 4–5 NEW Tests + Support)
**Analogs found:** 13 / 13 (alle mit konkretem Bestand-Vorbild)

> **Project context:** Native macOS Swift 6 App. `SWIFT_STRICT_CONCURRENCY: minimal`. Deutsche UI-Strings, englische Code-Identifier (CLAUDE.md). `@unchecked Sendable` für Inferenz-Clients ist etabliert (siehe `OpenAIChatClient`).

---

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| **NEW** `BlitzText/Rewrite/AppleFoundationRewriteClient.swift` | service (RewriteService-Conformance) | request-response (async/throws) | `BlitzText/Rewrite/OpenAIChatClient.swift` | **exact** (gleiches Protocol, gleiche Sendable-Form, analoge Struct/Init/Throw-Logik) |
| **NEW** `BlitzText/Rewrite/FoundationAvailabilityProvider.swift` (Protocol + LiveImpl) | seam / utility | request-response (sync read, optional async refresh) | `BlitzText/Transcription/DiarizerLoaderProtocol.swift` (Protocol + `FluidAudioDiarizerLoader` Live-Impl) | **exact** (Protocol-Wrapping mit Live-Singleton + Mock-Hook für Tests) |
| **NEW** `BlitzText/Rewrite/LanguageModelInferring.swift` (Protocol seam für `LanguageModelSession.respond`) | seam / utility | request-response (async/throws) | `BlitzText/Transcription/DiarizerLoaderProtocol.swift` (gleiches Idiom) + `RewriteService` (Sendable-Protocol-Form) | **exact** |
| **NEW** `BlitzText/Rewrite/DeescalatedOutput.swift` (`@Generable` struct) | model (Schema) | transform (Constrained Decoding) | `BlitzText/Modes/Mode.swift` (kleine `enum`/`struct` mit deutschen Doc-Kommentaren) | role-match (kein direkter `@Generable`-Bestand; Stil + Doc-Form übernehmen) |
| **MODIFY** `BlitzText/Settings/SettingsStore.swift` — neuer `RewriteBackend`-Enum + per-Mode-Mapping + `foundationAvailability`-State + `didAutoFallbackToOpenAI`-Flag + `refreshFoundationAvailability()` | model + service (state holder) | event-driven + CRUD (Snapshot persist) | **inline-Analog im selben File:** `TranscriptionBackend`-Enum + zugehöriges `@Published var backend` + Snapshot-Migration; **außerdem:** `parakeetDiarization`-Toggle mit Side-Effect-`didSet` als Vorbild für Auto-Fallback-Trigger | **exact** |
| **MODIFY** `BlitzText/Modes/ModeProcessor.swift` — Backend-Lookup + zweiter Rewriter-Slot | service (orchestrator) | request-response (Branch-Switch) | **inline-Analog im selben File:** existierender `runPipeline`-Switch über `settings.backend` (Transcription) und `mode`-switch für Rewrite-Aufruf; existierende `_injectedRewriter`-DI-Slot | **exact** |
| **MODIFY** `BlitzText/Settings/SettingsView.swift` — zwei Backend-Picker je `BLITZTEXT+`/`BLITZTEXT $%&!`-Section + `FoundationAvailabilityBanner`-Mount oben | view (SwiftUI) | event-driven (Binding + EnvironmentObject) | **inline-Analog im selben File:** `LokalTab`-`Picker("Backend", selection: $settings.backend)` (Zeile 338–340) für Picker-Form; `LokalTab`-`HStack(ProgressView+Text)` (Zeile 346–350) für Loading-Hint; `permissionRow` (Zeile 274–285) für Banner-HStack-Layout | **exact** |
| **NEW** `BlitzText/Settings/FoundationAvailabilityBanner.swift` | view (SwiftUI) | event-driven (state-driven 4-Variant-Render) | `SettingsView.swift` `permissionRow` (`HStack(spacing: 12){ Image, VStack{ Text, Text(caption) }, Spacer, Button }`) + `DiarizerStatusBlock` (Zeile 505–601, vier-State-Switch) | **exact** (Vier-State-Switch ist 1:1 das Phase-3-Pattern) |
| **MODIFY** `BlitzText/UI/RecordingHUDController.swift` — `BackendBadge` neben `langBadge` + Window-Width 240→268 | view (SwiftUI/AppKit hybrid) | event-driven (state-driven Capsule) | **inline-Analog im selben File:** existierende `langBadge`-Capsule (Zeile 101–107) | **exact** |
| **MODIFY** `BlitzText/App/AppDelegate.swift` — Bootstrap: `refreshFoundationAvailability()` + Auto-Fallback + Pre-Warm + `didBecomeActiveNotification`-Observer | app-lifecycle (controller) | event-driven (notification observer + bootstrap-once) | **inline-Analog im selben File:** existierende `bootstrap()` mit `preloadLocalModelIfActive()` (Zeile 96), Diarization-Pre-Warm-Block (Zeile 100–104), `needsOpenAIKey()`-Check (Zeile 134–139) | **exact** |
| **NEW** `BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift` | test (unit, pure-function-style) | request-response (sync mock state assertions) | `BlitzTextTests/Hotkeys/HotkeyStateMachineTests.swift` (deterministisch, injizierte Inputs, keine Sleeps) | **exact** |
| **NEW** `BlitzTextTests/Rewrite/AppleFoundationRewriteClientTests.swift` | test (unit, async) | request-response (async mock injection + assertions) | `BlitzTextTests/Pipeline/PipelineErrorPathTests.swift` (Fake-Service-Injection, `await mp.start/stop`, deutsche-Marker-Substring-Asserts) | **exact** |
| **NEW** `BlitzTextTests/Rewrite/RewriteBackendDispatchTests.swift` | test (unit, integration über ModeProcessor) | request-response (4-Pfad-Branch-Test) | `PipelineErrorPathTests.makeProcessor` (DI-Helper für `ModeProcessor` mit injizierten Fakes) | **exact** |
| **NEW** `BlitzTextTests/Support/FakeFoundationAvailabilityProvider.swift` + `FakeLanguageModelInferring.swift` | test fixture | n/a | `BlitzTextTests/Support/FakeRewriter.swift` (Result-basierter Fake mit `callCount`) + `FakeDiarizerLoader.swift` (mutable State + Failure-Injection) | **exact** |

---

## Pattern Assignments

### NEW `BlitzText/Rewrite/AppleFoundationRewriteClient.swift` (service, request-response)

**Analog:** `BlitzText/Rewrite/OpenAIChatClient.swift` (vollständige Vorlage, 52 LOC)

**Imports + Top-Doc-Comment + Class-Form** (`OpenAIChatClient.swift:1-13`):
```swift
import Foundation

/// OpenAI Chat-Completions-Client. Default-Modell: gpt-4o-mini.
final class OpenAIChatClient: RewriteService, @unchecked Sendable {

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let settings: SettingsStore
    private let session: URLSession

    init(settings: SettingsStore, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }
```

**Spiegeln für AppleFoundationRewriteClient:**
- `import Foundation` + `import FoundationModels`
- Doc-Kommentar: `/// Apple Foundation Models Rewrite-Client (macOS 26+). Plain Session für Plus, Guided Generation für Rant.`
- Class-Form: `final class AppleFoundationRewriteClient: RewriteService, @unchecked Sendable { ... }` — **identisches Sendable-Idiom wie OpenAIChatClient** (Anti-Pattern in RESEARCH.md: kein `@MainActor`).
- Properties: `private let availabilityProvider: FoundationAvailabilityProviding`, `private let inferring: LanguageModelInferring` (beides Protocols für Mock-Injection).
- Init mit Default-Argument: `init(availabilityProvider: FoundationAvailabilityProviding = SystemLanguageModelAvailabilityProvider(), inferring: LanguageModelInferring = LiveLanguageModelInferring())` — analog `init(settings:, session: URLSession = .shared)`.

**Pre-Inference-Guard + Throw-Pattern** (analog `OpenAIChatClient.swift:15-18`):
```swift
func rewrite(input: String, systemPrompt: String, model: String) async throws -> String {
    let key = settings.apiKey
    guard !key.isEmpty else { throw TranscriptionError.missingAPIKey }
```

**Spiegeln für AC-AVAIL-1:**
```swift
func rewrite(input: String, systemPrompt: String, model: String) async throws -> String {
    let availability = availabilityProvider.currentAvailability()
    guard availability == .available else {
        throw AppleFoundationError.from(availability)
    }
    // ... dispatch nach mode (plain vs. guided) — siehe RESEARCH.md Pattern 2 + 3
}
```

**Decode + Trim Result** (`OpenAIChatClient.swift:48-49`):
```swift
let parsed = try JSONDecoder().decode(Resp.self, from: data)
return parsed.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
```

**Spiegeln:** `return response.content.trimmingCharacters(in: .whitespacesAndNewlines)` (plain) bzw. `return response.content.neutralText.trimmingCharacters(in: .whitespacesAndNewlines)` (guided) — gleiche Trim-Konvention.

**Was NEU vs. Analog:**
- Kein `URLSession`/`URLRequest` — stattdessen `LanguageModelInferring`-Aufruf.
- Mode-Auswahl plain vs. guided: Da `RewriteService.rewrite(input:, systemPrompt:, model:)` keinen `Mode`-Parameter hat, muss der Client den Mode aus dem `model`-String oder via separater Methode unterscheiden. **Empfehlung Researcher:** zwei `LanguageModelInferring`-Methoden (`respond(input:, instructions:)` und `respondGuided(input:, instructions:, type:)`); `ModeProcessor` ruft je nach Mode unterschiedlichen Pfad — entweder via separates Protocol oder via Heuristik im Client. Plan-Detail; **konkret-Empfehlung:** der Client bekommt eine zweite (interne) Methode `rewriteGuided(input:, systemPrompt:)` die explizit aus `ModeProcessor` für `.blitztextRant` aufgerufen wird (Branch im `runPipeline`-Switch).

---

### NEW `BlitzText/Rewrite/FoundationAvailabilityProvider.swift` (Protocol + LiveImpl)

**Analog:** `BlitzText/Transcription/DiarizerLoaderProtocol.swift` (Zeile 1–75, Protocol + Live-Impl im selben File)

**Protocol-Form mit Doc-Kommentar** (`DiarizerLoaderProtocol.swift:1-20`):
```swift
import Foundation
import FluidAudio

/// Test-Seam für `DiarizerModelManager`. Production-Default ist
/// `FluidAudioDiarizerLoader`; Tests injizieren `FakeDiarizerLoader`.
/// Pattern analog Phase-2-`RecorderProtocol` (DI-Seam ohne Netzwerk).
protocol DiarizerLoaderProtocol: Sendable {
    func downloadIfNeeded(progressHandler: (@Sendable (Double) -> Void)?) async throws -> DiarizerModels
    func isInstalled() -> Bool
    func clearCache()
}
```

**Spiegeln:**
```swift
import Foundation
import FoundationModels

/// Test-Seam für `SystemLanguageModel.default.availability`. Production-Default ist
/// `SystemLanguageModelAvailabilityProvider`; Tests injizieren `FakeFoundationAvailabilityProvider`.
/// Pattern analog `DiarizerLoaderProtocol` (DI-Seam ohne Hardware-Abhängigkeit).
protocol FoundationAvailabilityProviding: Sendable {
    func currentAvailability() -> FoundationAvailability
}

enum FoundationAvailability: Equatable, Sendable {
    case available
    case unavailable(Reason)

    enum Reason: Equatable, Sendable {
        case appleIntelligenceNotEnabled
        case modelNotReady
        case deviceNotEligible
    }
}
```

**Live-Impl-Struct-Form** (`DiarizerLoaderProtocol.swift:24-75`):
```swift
struct FluidAudioDiarizerLoader: DiarizerLoaderProtocol {
    // ... static private helpers ...
    func downloadIfNeeded(...) async throws -> DiarizerModels { ... }
    func isInstalled() -> Bool { ... }
    func clearCache() { ... }
}
```

**Spiegeln:** `struct SystemLanguageModelAvailabilityProvider: FoundationAvailabilityProviding { ... }` — exakter Switch über `SystemLanguageModel.default.availability` mit `@unknown default`-Branch (RESEARCH.md Pattern 1, Pitfall 2).

**Was NEU vs. Analog:**
- Kein File-System-Side-Effect (`isInstalled` checkt Disk; hier reiner API-Read).
- Kein `clearCache` — Apple-Foundation hat keinen App-erreichbaren Cache.
- Zusätzlicher Enum `FoundationAvailability` + Reason im selben File (entspricht Bestand-Konvention: `TranscriptionBackend` lebt im selben File wie `SettingsStore`).

---

### NEW `BlitzText/Rewrite/LanguageModelInferring.swift` (Protocol seam für Inferenz)

**Analog:** Kombination von `RewriteService.swift` (Protocol-Form) + `DiarizerLoaderProtocol` (Live + Fake-Hook)

**RewriteService-Style Protocol-Form** (`RewriteService.swift:1-5`, vollständig):
```swift
import Foundation

protocol RewriteService: Sendable {
    func rewrite(input: String, systemPrompt: String, model: String) async throws -> String
}
```

**Spiegeln (Bridge-Protocol über `LanguageModelSession.respond` + `respond(to:generating:)`):**
```swift
import Foundation
import FoundationModels

/// Test-Seam für `LanguageModelSession`. Production-Default wrappt echte Sessions
/// per-Request (stateless, RESEARCH.md Anti-Pattern: keine app-wide cached Session).
/// Tests injizieren `FakeLanguageModelInferring` mit pre-canned Responses.
protocol LanguageModelInferring: Sendable {
    func respond(input: String, instructions: String) async throws -> String
    func respondGuided<T: Generable>(input: String, instructions: String, type: T.Type) async throws -> T
}
```

**Live-Impl** (struct, analog `FluidAudioDiarizerLoader`):
```swift
struct LiveLanguageModelInferring: LanguageModelInferring {
    func respond(input: String, instructions: String) async throws -> String {
        let session = LanguageModelSession(instructions: { instructions })
        let response = try await session.respond(to: input)
        return response.content
    }

    func respondGuided<T: Generable>(input: String, instructions: String, type: T.Type) async throws -> T {
        let session = LanguageModelSession(instructions: { instructions })
        let response = try await session.respond(to: input, generating: T.self)
        return response.content
    }
}
```

**Was NEU vs. Analog:**
- Generic-Method (`<T: Generable>`) — bei `RewriteService` und `DiarizerLoaderProtocol` nicht vorhanden, aber Sendable-Form bleibt erhalten.
- **Verifikationsbedarf (RESEARCH.md Open Question 1):** `LanguageModelSession` Concurrency-Annotation per Xcode Quick Help live prüfen (Wave 0); falls `@MainActor`, Methoden-Signatur um `await MainActor.run`-Hop ergänzen.

---

### NEW `BlitzText/Rewrite/DeescalatedOutput.swift` (`@Generable` Schema)

**Analog:** `BlitzText/Modes/Mode.swift` (kleine Enum/Struct mit deutschen Doc-Kommentaren)

**Doc-Comment-Stil** (`Mode.swift:34-54`):
```swift
/// Default-System-Prompt für den Rewrite-Schritt. `.blitztext` rewritet nicht.
var defaultRewritePrompt: String {
    switch self {
    case .blitztext: return ""
    case .blitztextPlus:
        return """
        Du bist ein professioneller Assistent für Textaufbereitung.
        ...
        """
    case .blitztextRant:
        return """
        Der folgende Text wurde emotional und aufgeregt eingesprochen. ...
        """
    }
}
```

**Spiegeln (RESEARCH.md Pattern 3 + Pitfall 5):**
```swift
import Foundation
import FoundationModels

/// `@Generable`-Schema für den Deeskalations-Output von `blitztextRant`.
/// Constrained Decoding garantiert Schema-Validität auf Token-Ebene und
/// verhindert "Hier ist die entschärfte Version: …"-Präambeln.
/// Schema bleibt minimal (1 Feld), siehe RESEARCH.md Pitfall 5.
@Generable
struct DeescalatedOutput {
    @Guide(description: "Der entschärfte Text in deutscher Sprache, sachlich-freundlich, ohne Vorbemerkungen oder Anführungszeichen.")
    var neutralText: String
}
```

**Was NEU vs. Analog:**
- Macro-Annotationen (`@Generable`, `@Guide`) sind völlig neu im Projekt.
- Deutscher `description:`-String — Sprachbias-Mitigation per RESEARCH.md Pitfall 1.

---

### MODIFY `BlitzText/Settings/SettingsStore.swift` (model + state holder)

**Analog (inline im selben File):** `TranscriptionBackend`-Enum (Zeile 153–165) + `@Published var backend: TranscriptionBackend = .openAI` (Zeile 19) + Snapshot-Migration (Zeile 95–149)

**TranscriptionBackend-Enum-Vorlage** (`SettingsStore.swift:153-165`):
```swift
enum TranscriptionBackend: String, CaseIterable, Codable, Identifiable {
    case openAI
    case local
    case parakeet
    var id: String { rawValue }
    var label: String {
        switch self {
        case .openAI:   return "OpenAI Whisper (Cloud)"
        case .local:    return "Whisper (Lokal)"
        case .parakeet: return "Parakeet TDT v3 (Lokal)"
        }
    }
}
```

**Spiegeln (UI-SPEC Picker-Item-Labels):**
```swift
enum RewriteBackend: String, CaseIterable, Codable, Identifiable {
    case appleFoundation
    case openAI
    var id: String { rawValue }
    var label: String {
        switch self {
        case .appleFoundation: return "Apple Foundation (lokal)"
        case .openAI:          return "OpenAI gpt-4o-mini (Cloud)"
        }
    }
}
```

**@Published-Fields-Vorlage** (`SettingsStore.swift:9-20`):
```swift
@Published var triggerMode: TriggerMode = .hold
@Published var styleForPlus: WritingStyle = .neutral
...
@Published var backend: TranscriptionBackend = .openAI
```

**Spiegeln (per-Mode-Mapping):** Researcher empfiehlt **zwei separate Felder** statt Dictionary (siehe Snapshot-Form gleich):
```swift
@Published var rewriteBackendForPlus: RewriteBackend = .appleFoundation
@Published var rewriteBackendForRant: RewriteBackend = .appleFoundation
@Published var foundationAvailability: FoundationAvailability = .unavailable(.modelNotReady)
@Published var didAutoFallbackToOpenAI: Bool = false
```

**Lookup-Helper-Methoden** (UI-SPEC Manager-/State-Surface, Zeile 308–312):
```swift
func rewriteBackend(for mode: Mode) -> RewriteBackend {
    switch mode {
    case .blitztextPlus: return rewriteBackendForPlus
    case .blitztextRant: return rewriteBackendForRant
    case .blitztext:     return .appleFoundation  // Default; nicht aufgerufen, kein Rewrite
    }
}

func setRewriteBackend(_ backend: RewriteBackend, for mode: Mode) {
    switch mode {
    case .blitztextPlus: rewriteBackendForPlus = backend
    case .blitztextRant: rewriteBackendForRant = backend
    case .blitztext:     break
    }
}
```

**Side-Effect-Pattern (Auto-Fallback-Trigger via `didSet`)** (`SettingsStore.swift:24-36`):
```swift
@Published var parakeetDiarization: Bool = false {
    didSet {
        guard parakeetDiarization, !oldValue else { return }
        Task { @MainActor [weak diarizerManager] in
            diarizerManager?.start()
        }
    }
}
```

**Spiegeln (Refresh-Hook):** `refreshFoundationAvailability()` wird **nicht** in einem `didSet` aufgerufen, sondern explizit aus `AppDelegate.bootstrap()` und `didBecomeActiveNotification`-Observer. Inline-Code:
```swift
private let availabilityProvider: FoundationAvailabilityProviding

func refreshFoundationAvailability() {
    let new = availabilityProvider.currentAvailability()
    if new != foundationAvailability {
        foundationAvailability = new
        applyAutoFallbackIfNeeded()
    }
}

private func applyAutoFallbackIfNeeded() {
    // Nur wenn unavailable + API-Key vorhanden + beide Modes noch auf default Foundation:
    guard foundationAvailability != .available, !apiKey.isEmpty else { return }
    let switched = rewriteBackendForPlus == .appleFoundation || rewriteBackendForRant == .appleFoundation
    if switched {
        rewriteBackendForPlus = .openAI
        rewriteBackendForRant = .openAI
        didAutoFallbackToOpenAI = true
    }
}
```

**Snapshot-Codable mit Optional-Migration** (`SettingsStore.swift:95-129`):
```swift
private struct Snapshot: Codable {
    var triggerMode: TriggerMode
    ...
    var aiSuggestProperNouns: Bool?       // ← Optional für additive Migration
    var parakeetDiarization: Bool?
}

private func load() {
    guard let data = ..., let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
    ...
    aiSuggestProperNouns = snap.aiSuggestProperNouns ?? true
    parakeetDiarization = snap.parakeetDiarization ?? false
}
```

**Spiegeln (additive RewriteBackend-Felder):**
```swift
private struct Snapshot: Codable {
    ...
    var rewriteBackendForPlus: RewriteBackend?   // additiv, Default beim ersten Load
    var rewriteBackendForRant: RewriteBackend?
}

// in load():
rewriteBackendForPlus = snap.rewriteBackendForPlus ?? .appleFoundation
rewriteBackendForRant = snap.rewriteBackendForRant ?? .appleFoundation
```

**Was NEU vs. Analog:**
- `foundationAvailability` und `didAutoFallbackToOpenAI` sind **Runtime-Only** — **nicht** in `Snapshot` persistieren (sie werden bei jedem Bootstrap neu evaluiert).
- `availabilityProvider` als Init-Parameter mit Default — analog der Phase-3-DI-Seam in `DiarizerModelManager.init(loader:)`.

---

### MODIFY `BlitzText/Modes/ModeProcessor.swift` (orchestrator)

**Analog (inline im selben File):** existierender `runPipeline`-Switch (Zeile 146–195) + `_injectedRewriter` DI-Slot (Zeile 32, 51–53, 70, 81)

**DI-Slot-Pattern** (`ModeProcessor.swift:28-56`):
```swift
private let _injectedRewriter: RewriteService?
private lazy var defaultRewriter: RewriteService = OpenAIChatClient(settings: settings)
private var rewriter: RewriteService {
    _injectedRewriter ?? defaultRewriter
}
```

**Spiegeln (zweiter Slot für Foundation-Client):**
```swift
private let _injectedFoundationRewriter: RewriteService?
private lazy var defaultFoundationRewriter: RewriteService = AppleFoundationRewriteClient()
private var foundationRewriter: RewriteService {
    _injectedFoundationRewriter ?? defaultFoundationRewriter
}

// neuer Init-Parameter (additiv, default = nil):
init(
    settings: SettingsStore,
    history: HistoryStore,
    modelManager: LocalModelManager,
    diarizerManager: DiarizerModelManager,
    openAITranscriber: TranscriptionService? = nil,
    localTranscriber: TranscriptionService? = nil,
    parakeetTranscriber: TranscriptionService? = nil,
    rewriter: RewriteService? = nil,                    // bleibt = OpenAI-Slot
    foundationRewriter: RewriteService? = nil,          // NEU
    recorder: RecorderProtocol? = nil
) { ... }
```

**Existierender Backend-Switch (Vorbild)** (`ModeProcessor.swift:146-152`):
```swift
let transcriber: TranscriptionService = {
    switch settings.backend {
    case .openAI:   return openAITranscriber
    case .local:    return localTranscriber
    case .parakeet: return parakeetTranscriber
    }
}()
```

**Spiegeln (Rewrite-Backend-Switch im `mode`-Branch)** (`ModeProcessor.swift:177-195`):
```swift
case .blitztextPlus, .blitztextRant:
    state = .rewriting(mode)
    do {
        let activeRewriter: RewriteService = {
            switch settings.rewriteBackend(for: mode) {
            case .appleFoundation: return foundationRewriter
            case .openAI:          return rewriter
            }
        }()
        let p = try await activeRewriter.rewrite(
            input: raw,
            systemPrompt: makeRewriteSystemPrompt(for: mode),
            model: settings.rewriteModel
        )
        output = p
        polished = p
    } catch {
        state = .error(humanReadable(error))
        return
    }
```

**`humanReadable`-Erweiterung** (`ModeProcessor.swift:293-301`):
```swift
private func humanReadable(_ error: Error) -> String {
    if let e = error as? TranscriptionError, let msg = e.errorDescription { return msg }
    if let e = error as? AudioRecorder.RecorderError {
        switch e {
        case .micDenied: return "Mikrofon-Zugriff verweigert. ..."
        }
    }
    return error.localizedDescription
}
```

**Spiegeln:** zusätzliche `if let e = error as? AppleFoundationError { return e.errorDescription ?? ... }`-Branch — nutzt `AppleFoundationError: LocalizedError` aus RESEARCH.md Code Examples.

**Was NEU vs. Analog:**
- Zweiter Rewriter-Slot statt Single-Slot (analog der drei Transcriber-Slots).
- Sprachbias-Marker beim Foundation-Backend in `makeRewriteSystemPrompt(for:)` appenden — Bedingung: nur wenn `settings.rewriteBackend(for: mode) == .appleFoundation`. **Plan-Detail:** Marker-String `"Antworte ausschließlich auf Deutsch."` als letzte Zeile (RESEARCH.md Pitfall 1).

---

### MODIFY `BlitzText/Settings/SettingsView.swift` (view)

**Analog (inline im selben File):** mehrere lokale Patterns

**Picker-Form** (`SettingsView.swift:336-340`):
```swift
VStack(alignment: .leading, spacing: 8) {
    Text("BACKEND-WAHL").font(.caption).foregroundStyle(.secondary).bold()
    Picker("Backend", selection: $settings.backend) {
        ForEach(TranscriptionBackend.allCases) { Text($0.label).tag($0) }
    }
}
```

**Spiegeln (zwei neue Picker am Ende von BLITZTEXT+ und BLITZTEXT $%&!-Sections, UI-SPEC Surface 1, Zeile 117–149):**
```swift
// am Ende der BLITZTEXT+-section:
Text("Backend").font(.subheadline).padding(.top, 6)
Picker("Backend", selection: $settings.rewriteBackendForPlus) {
    ForEach(RewriteBackend.allCases) { Text($0.label).tag($0) }
}
.frame(maxWidth: 280)
if settings.rewriteBackendForPlus == .openAI && settings.foundationAvailability == .available {
    Text("Rewrite für diesen Mode läuft über die OpenAI-Cloud.")
        .font(.caption2).foregroundStyle(.tertiary)
}
```

(Identische Block für `BLITZTEXT $%&!`-Section mit `$settings.rewriteBackendForRant`.)

**Section-Helper-Form** (`SettingsView.swift:139-145`):
```swift
@ViewBuilder
private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.caption).foregroundStyle(.secondary).bold()
        content()
    }
}
```

**Banner-Mount-Point in `AnpassenTab.body`** (`SettingsView.swift:54-130`): direkt vor `section("MODUS")`-Block einfügen:
```swift
var body: some View {
    VStack(alignment: .leading, spacing: 18) {
        section("TASTENKÜRZEL") { ... }

        // NEU — UI-SPEC Surface 2:
        if settings.foundationAvailability != .available {
            section("APPLE INTELLIGENCE") {
                FoundationAvailabilityBanner()
                    .environmentObject(settings)
            }
        }

        section("MODUS") { ... }
        section("BLITZTEXT+") { ... + Backend-Picker ... }
        section("BLITZTEXT $%&!") { ... + Backend-Picker ... }
        ...
    }
}
```

**Was NEU vs. Analog:**
- Picker-Item-Label-Strings: deutsche Klammer-Privacy-Hint (`"(lokal)"` / `"(Cloud)"`) — UI-SPEC Locked.
- Conditional `.caption2`-Tertiary-Hinweis nur sichtbar bei OpenAI + verfügbarem Foundation — neue Pattern-Variante.

---

### NEW `BlitzText/Settings/FoundationAvailabilityBanner.swift` (view)

**Analog 1 — Banner-HStack-Layout:** `SettingsView.swift:274-285` (`permissionRow`)
```swift
@ViewBuilder
private func permissionRow(title: String, subtitle: String, granted: Bool, actionLabel: String, action: @escaping () -> Void) -> some View {
    HStack(spacing: 12) {
        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(granted ? .green : .orange)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).bold()
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button(actionLabel, action: action)
    }
}
```

**Analog 2 — Vier-State-Switch:** `SettingsView.swift:505-577` (`DiarizerStatusBlock`)
```swift
@ViewBuilder
private var content: some View {
    switch diarizerManager.state {
    case .notInstalled:
        toggleAndSubtitle
    case .downloading(let progress, let eta):
        downloadingView(progress: progress, eta: eta)
        Text("...").font(.caption2).foregroundStyle(.tertiary)
    case .installed:
        ...
    case .failed(let message):
        errorView(message: message)
    }
}
```

**Spiegeln (UI-SPEC Surface 2, vier Varianten A/B/C + D-Overlay):**
```swift
struct FoundationAvailabilityBanner: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if shouldShowAutoFallbackHint {
                autoFallbackRow
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch settings.foundationAvailability {
        case .available:
            EmptyView()
        case .unavailable(.appleIntelligenceNotEnabled):
            variantA
        case .unavailable(.modelNotReady):
            variantB
        case .unavailable(.deviceNotEligible):
            variantC
        }
    }

    @ViewBuilder
    private var variantA: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Intelligence ist nicht aktiviert").font(.subheadline)
                Text("Aktiviere Apple Intelligence in den Systemeinstellungen, um BlitzText+ und BlitzText $%&! lokal zu rewriten — ohne Cloud.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Systemeinstellungen öffnen …",
                     destination: URL(string: "x-apple.systempreferences:com.apple.preference.appleintelligence")!)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var variantB: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Apple-Foundation-Modell wird geladen …").font(.subheadline)
                    ProgressView().controlSize(.small)
                }
                Text("Das passiert einmalig nach Aktivierung von Apple Intelligence. BlitzText prüft regelmäßig, ob das Modell bereit ist.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Erneut prüfen") { settings.refreshFoundationAvailability() }
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
    }

    // variantC analog (orange-Symbol, kein Action-Button, longerDetail)
    // autoFallbackRow analog DiarizerStatusBlock-errorView-Pattern, aber .orange + .caption
}
```

**Auto-Fallback-Zeile (Variante D, UI-SPEC Surface 2)** — Analog inline `LokalTab:341-343`:
```swift
if settings.backend == .local && modelManager.activeID == nil {
    Text("Lokales Backend gewählt, aber kein Modell aktiviert. ...")
        .font(.caption).foregroundStyle(.orange)
}
```

**Spiegeln:**
```swift
@ViewBuilder
private var autoFallbackRow: some View {
    HStack(spacing: 4) {
        Image(systemName: "cloud").foregroundStyle(.orange)
        Text("OpenAI als Fallback aktiv. Aktiviere Apple Intelligence, um lokal zu rewriten.")
            .font(.caption).foregroundStyle(.orange)
    }
}

private var shouldShowAutoFallbackHint: Bool {
    guard settings.didAutoFallbackToOpenAI else { return false }
    // UI-SPEC: bei Variante C unterdrückt
    if case .unavailable(.deviceNotEligible) = settings.foundationAvailability { return false }
    return true
}
```

**Was NEU vs. Analog:**
- Erstmals `Link(destination:)` aus dem `x-apple.systempreferences:`-Schema-Bereich (deeplinks zu Settings-Pane).
- Vier-State-Pattern mit Overlay-Variante D — analog Phase-3-`DiarizerStatusBlock`-Struktur, aber mit zusätzlicher konditional-überlagernder Zeile.

---

### MODIFY `BlitzText/UI/RecordingHUDController.swift` (view)

**Analog (inline im selben File):** existierende `langBadge`-Capsule (Zeile 101–107)

**Capsule-Badge-Form** (`RecordingHUDController.swift:101-107`):
```swift
Text(langBadge)
    .font(.system(size: 10, weight: .bold, design: .monospaced))
    .foregroundStyle(.white.opacity(0.85))
    .tracking(1)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(.white.opacity(0.12), in: Capsule())
```

**Spiegeln (UI-SPEC Surface 3, Symbol-only-Capsule):**
```swift
if showsBackendBadge {
    Image(systemName: backendSymbol)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.white.opacity(0.85))
        .frame(width: 12, height: 12)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.white.opacity(0.12), in: Capsule())
        .help(backendTooltip)
}
```

**Window-Width-Constant** (`RecordingHUDController.swift:36, 58`):
```swift
NSRect(x: 0, y: 0, width: 240, height: 56)
...
let w: CGFloat = 240, h: CGFloat = 56
```

**Spiegeln:** beide `240` → `268` ändern (UI-SPEC Spacing-Scale, HUD-Window-Width).

**Computed Properties im RecordingHUDView** (analog `langBadge` Computed Property, Zeile 78–85):
```swift
private var showsBackendBadge: Bool {
    // UI-SPEC Surface 3 Tabelle: nicht für plain blitztext
    guard let mode = activeMode, mode != .blitztext else { return false }
    return true
}

private var activeMode: Mode? {
    if case .recording(let m) = processor.state { return m }
    if case .transcribing(let m) = processor.state { return m }
    if case .rewriting(let m) = processor.state { return m }
    return nil
}

private var backendSymbol: String {
    guard let mode = activeMode else { return "questionmark" }
    switch settings.rewriteBackend(for: mode) {
    case .appleFoundation: return "apple.logo"
    case .openAI:          return "cloud"
    }
}
```

**Was NEU vs. Analog:**
- `RecordingHUDView` braucht zusätzlichen Parameter `processor: ModeProcessor` (oder `@ObservedObject`) — bisher nur `recorder` und `settings`.
- Parametrisiertes Show-Verhalten: HUD wird derzeit nur bei `.recording` gezeigt (Zeile 24–26). UI-SPEC fordert Backend-Badge auch während `.transcribing` und `.rewriting` sichtbar — die `processor.$state`-Sink-Logik in `init` muss erweitert werden (alle drei States zeigen das HUD).

---

### MODIFY `BlitzText/App/AppDelegate.swift` (app-lifecycle)

**Analog (inline im selben File):** `bootstrap()` (Zeile 54–128) mit Pre-Warm-Block (96–104) und API-Key-Check (134–139)

**Pre-Warm-Pattern** (`AppDelegate.swift:96-104`):
```swift
// Lokales Modell beim App-Start vorladen — sonst würde die erste Aufnahme
// 1–3 min CoreML-Compile-Zeit kosten. Läuft im Hintergrund, blockiert nicht.
modeProcessor.preloadLocalModelIfActive()

// D-13/D-14: Wenn Diarization aktiv persistiert war, Modell im Hintergrund prewarmen.
if settingsStore.parakeetDiarization {
    Task { [diarizerManager] in
        await MainActor.run { diarizerManager.prewarm() }
    }
}
```

**Spiegeln (in `bootstrap()` nach Hotkey-Setup einfügen, RESEARCH.md Pattern 4):**
```swift
// Phase 8: Foundation-Verfügbarkeit prüfen + ggf. Auto-Fallback + Pre-Warm
settingsStore.refreshFoundationAvailability()

if settingsStore.foundationAvailability == .available {
    let usesFoundation = Mode.allCases.contains { mode in
        mode != .blitztext && settingsStore.rewriteBackend(for: mode) == .appleFoundation
    }
    if usesFoundation {
        Task.detached(priority: .utility) {
            let session = LanguageModelSession()
            try? await session.prewarm()
        }
    }
}

// AC-AVAIL-2: Re-Check bei App-Reaktivierung
NotificationCenter.default.addObserver(
    forName: NSApplication.didBecomeActiveNotification,
    object: nil,
    queue: .main
) { [weak settingsStore] _ in
    Task { @MainActor in
        settingsStore?.refreshFoundationAvailability()
    }
}
```

**API-Key-Check-Pattern** (`AppDelegate.swift:134-139`) — bleibt unverändert; `applyAutoFallbackIfNeeded` läuft im SettingsStore und ist orthogonal.

**Was NEU vs. Analog:**
- `NotificationCenter.addObserver` für `didBecomeActiveNotification` — neues Idiom (Bestand nutzt nur `objectWillChange`-Sinks).
- `Task.detached(priority: .utility)` mit `LanguageModelSession.prewarm()` — analog dem existierenden `Task.detached { await client.warmUp() }` aus `ModeProcessor.preloadLocalModelIfActive`.
- Lifecycle-Position: vor `hotkeyManager.start()` einfügen (damit erster Hotkey-Press bereits warmen State sieht — RESEARCH.md Pitfall 3 "1-second window").

---

### NEW `BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift` (test, unit)

**Analog:** `BlitzTextTests/Hotkeys/HotkeyStateMachineTests.swift` (Zeile 1–60)

**Test-Class-Form mit Doc-Kommentar** (`HotkeyStateMachineTests.swift:1-14`):
```swift
@testable import BlitzText
import XCTest

/// Tests fuer die pure State-Machine `HotkeyManager.decideTransition(...)`.
///
/// Test-Seam wurde in Plan 02-01 (Wave 0) eingefuehrt:
///   - `decideTransition` ist `internal`, akzeptiert injizierten `now: Date`.
/// Determinismus: Jeder Aufruf bekommt explizit `Date(timeIntervalSince1970: T)`.
@MainActor
final class HotkeyStateMachineTests: XCTestCase {

    private func makeManager() -> HotkeyManager {
        let settings = SettingsStore()
        return HotkeyManager(settings: settings, onTrigger: { _, _ in })
    }
```

**Spiegeln:**
```swift
@testable import BlitzText
import XCTest

/// Tests für `SettingsStore.refreshFoundationAvailability()` und Auto-Fallback-Logik.
///
/// AC-AVAIL-1 / AC-AVAIL-2: Verfügbarkeitsprüfung deckt alle 4 States ab und
/// State-Übergang `modelNotReady → available` ohne App-Restart.
/// Determinismus: `FakeFoundationAvailabilityProvider` mit mutable State.
@MainActor
final class AppleFoundationAvailabilityTests: XCTestCase {

    private func makeStore(initial: FoundationAvailability) -> (SettingsStore, FakeFoundationAvailabilityProvider) {
        let provider = FakeFoundationAvailabilityProvider(state: initial)
        let store = SettingsStore(availabilityProvider: provider)
        return (store, provider)
    }

    func test_refresh_modelNotReady_to_available_updatesPublishedState() {
        let (store, provider) = makeStore(initial: .unavailable(.modelNotReady))
        store.refreshFoundationAvailability()
        XCTAssertEqual(store.foundationAvailability, .unavailable(.modelNotReady))

        provider.state = .available
        store.refreshFoundationAvailability()
        XCTAssertEqual(store.foundationAvailability, .available)
    }
    // ... weitere Tests pro Case + Auto-Fallback-Trigger ...
}
```

**Was NEU vs. Analog:**
- `SettingsStore.init` braucht neuen `availabilityProvider:`-Parameter mit Default — analog `DiarizerModelManager.init(loader:)`.
- Tests prüfen `@Published`-Werte direkt (vergleichbar mit `PipelineErrorPathTests`-State-Asserts).

---

### NEW `BlitzTextTests/Rewrite/AppleFoundationRewriteClientTests.swift` (test, unit async)

**Analog:** `BlitzTextTests/Pipeline/PipelineErrorPathTests.swift` (Fake-Injection + State-Marker-Asserts)

**Marker-Substring-Assert-Form** (`PipelineErrorPathTests.swift:99-103`):
```swift
XCTAssertTrue(
    msg.contains("Netzwerk:") || msg.contains("OpenAI-Fehler"),
    "Erwartet einen Whisper-Marker (\"Netzwerk:\" oder \"OpenAI-Fehler\") — bekam: \(msg)"
)
XCTAssertEqual(transcriber.callCount, 1, "Fake-Transcriber muss genau einmal aufgerufen worden sein")
```

**Spiegeln (AC-AVAIL-1, vier Cases):**
```swift
@MainActor
final class AppleFoundationRewriteClientTests: XCTestCase {

    func test_unavailable_appleIntelligenceNotEnabled_throwsGermanError() async {
        let provider = FakeFoundationAvailabilityProvider(state: .unavailable(.appleIntelligenceNotEnabled))
        let inferring = FakeLanguageModelInferring()
        let client = AppleFoundationRewriteClient(availabilityProvider: provider, inferring: inferring)

        do {
            _ = try await client.rewrite(input: "test", systemPrompt: "x", model: "y")
            XCTFail("Erwartet: Throw — bekam: kein Fehler")
        } catch let error as AppleFoundationError {
            let msg = error.errorDescription ?? ""
            XCTAssertTrue(
                msg.contains("Apple Intelligence") && msg.contains("Systemeinstellungen"),
                "Erwartet deutscher Marker zu Systemeinstellungen — bekam: \(msg)"
            )
        } catch {
            XCTFail("Erwartet AppleFoundationError — bekam: \(error)")
        }
        XCTAssertEqual(inferring.respondCallCount, 0, "AC-AVAIL-1: kein Inferenz-Call bei unavailable")
    }

    // analog für .modelNotReady, .deviceNotEligible, .available (positive case)
}
```

**Was NEU vs. Analog:**
- Async-Throw-Pattern statt Pipeline-State-Pattern (PipelineErrorPathTests prüft `mp.state`, hier direktes Throw-Catch).
- Mock zählt Inferenz-Aufrufe statt Transcriber-Aufrufe — gleiche `callCount`-Idee wie `FakeRewriter.callCount`.

---

### NEW `BlitzTextTests/Rewrite/RewriteBackendDispatchTests.swift` (test, integration)

**Analog:** `PipelineErrorPathTests.makeProcessor` (Zeile 39–65) — DI-Helper für `ModeProcessor`

**ModeProcessor-DI-Helper-Form** (`PipelineErrorPathTests.swift:39-65`):
```swift
private func makeProcessor(
    backend: TranscriptionBackend,
    openAITranscriber: TranscriptionService? = nil,
    parakeetTranscriber: TranscriptionService? = nil,
    recorder: RecorderProtocol
) -> ModeProcessor {
    let settings = SettingsStore()
    settings.backend = backend
    let history = HistoryStore()
    let modelManager = LocalModelManager()
    let diarizerManager = DiarizerModelManager(loader: FakeDiarizerLoader())
    return ModeProcessor(
        settings: settings, history: history, modelManager: modelManager, diarizerManager: diarizerManager,
        openAITranscriber: openAITranscriber, localTranscriber: nil,
        parakeetTranscriber: parakeetTranscriber, rewriter: nil, recorder: recorder
    )
}
```

**Spiegeln (mit zwei Rewriter-Slots):**
```swift
private func makeProcessor(
    rewriteBackend: RewriteBackend,
    forMode mode: Mode,
    openAIRewriter: FakeRewriter,
    foundationRewriter: FakeRewriter,
    transcriber: TranscriptionService,
    recorder: RecorderProtocol
) -> ModeProcessor {
    let settings = SettingsStore()
    settings.setRewriteBackend(rewriteBackend, for: mode)
    settings.backend = .openAI  // Transcription orthogonal
    return ModeProcessor(
        settings: settings,
        history: HistoryStore(),
        modelManager: LocalModelManager(),
        diarizerManager: DiarizerModelManager(loader: FakeDiarizerLoader()),
        openAITranscriber: transcriber,
        rewriter: openAIRewriter,
        foundationRewriter: foundationRewriter,
        recorder: recorder
    )
}

func test_blitztextPlus_appleFoundation_dispatchesToFoundationRewriter() async throws {
    // 4-Pfad-Matrix: 2 Modes × 2 Backends
    let openAI = FakeRewriter(.success("OPENAI_OUT"))
    let foundation = FakeRewriter(.success("FOUNDATION_OUT"))
    let mp = makeProcessor(
        rewriteBackend: .appleFoundation,
        forMode: .blitztextPlus,
        openAIRewriter: openAI,
        foundationRewriter: foundation,
        transcriber: FakeTranscriptionService(.success("hallo")),
        recorder: FakeAudioRecorder(fixtureURL: try makeFixtureURL())
    )

    await mp.start(mode: .blitztextPlus)
    await mp.stop()

    XCTAssertEqual(foundation.callCount, 1)
    XCTAssertEqual(openAI.callCount, 0)
}
```

**Was NEU vs. Analog:**
- Zweiter `FakeRewriter` (Foundation-Slot) — analog dem Pattern, aber mit zwei separaten Instances zur Dispatch-Verifikation.

---

### NEW `BlitzTextTests/Support/FakeFoundationAvailabilityProvider.swift` (+ `FakeLanguageModelInferring.swift`)

**Analog 1:** `BlitzTextTests/Support/FakeRewriter.swift` (vollständige Vorlage, 22 LOC)
```swift
final class FakeRewriter: RewriteService, @unchecked Sendable {
    let result: Result<String, Error>
    private(set) var callCount: Int = 0
    private(set) var lastInput: String?
    private(set) var lastSystemPrompt: String?
    private(set) var lastModel: String?

    init(_ result: Result<String, Error>) { self.result = result }

    func rewrite(input: String, systemPrompt: String, model: String) async throws -> String {
        callCount += 1
        lastInput = input
        lastSystemPrompt = systemPrompt
        lastModel = model
        return try result.get()
    }
}
```

**Analog 2:** `BlitzTextTests/Support/FakeDiarizerLoader.swift` (mutable State + Failure-Injection)
```swift
final class FakeDiarizerLoader: DiarizerLoaderProtocol, @unchecked Sendable {
    var installed: Bool = false
    var failure: Error?
    var progressTicks: [Double] = []
    private(set) var downloadCallCount: Int = 0
    ...
}
```

**Spiegeln (`FakeFoundationAvailabilityProvider`):**
```swift
import Foundation
@testable import BlitzText

final class FakeFoundationAvailabilityProvider: FoundationAvailabilityProviding, @unchecked Sendable {
    var state: FoundationAvailability
    private(set) var callCount: Int = 0

    init(state: FoundationAvailability = .available) {
        self.state = state
    }

    func currentAvailability() -> FoundationAvailability {
        callCount += 1
        return state
    }
}
```

**Spiegeln (`FakeLanguageModelInferring`):**
```swift
import Foundation
import FoundationModels
@testable import BlitzText

final class FakeLanguageModelInferring: LanguageModelInferring, @unchecked Sendable {
    var response: Result<String, Error> = .success("FAKE_OUT")
    var guidedResponse: Result<Any, Error> = .success("FAKE_GUIDED")
    private(set) var respondCallCount: Int = 0
    private(set) var respondGuidedCallCount: Int = 0
    private(set) var lastInput: String?
    private(set) var lastInstructions: String?

    func respond(input: String, instructions: String) async throws -> String {
        respondCallCount += 1
        lastInput = input
        lastInstructions = instructions
        return try response.get()
    }

    func respondGuided<T: Generable>(input: String, instructions: String, type: T.Type) async throws -> T {
        respondGuidedCallCount += 1
        lastInput = input
        lastInstructions = instructions
        guard let value = try guidedResponse.get() as? T else {
            throw NSError(domain: "FakeLanguageModelInferring", code: -1)
        }
        return value
    }
}
```

**Was NEU vs. Analog:**
- Generic-Method-Mock (`<T: Generable>`) — `Any`-Cast-Pattern für vorgefertigte Generic-Returns. Plan-Detail: tatsächlich nur für `DeescalatedOutput` aufgerufen, daher reicht ein `Any`-Bucket.

---

## Shared Patterns

### 1. Deutsche Fehler-Strings via `LocalizedError`-Conformance

**Source:** `BlitzText/Transcription/TranscriptionError.swift` (über `errorDescription`-Property, in PipelineErrorPathTests verwendet als Marker-Substring `"Netzwerk:"`/`"Lokales Modell"`)

**Apply to:** `AppleFoundationRewriteClient` (über neue `AppleFoundationError`-Enum), `ModeProcessor.humanReadable` (Erweiterung um `as? AppleFoundationError`-Branch).

**Pattern (RESEARCH.md Code Examples):**
```swift
enum AppleFoundationError: LocalizedError {
    case unavailable(String)
    case guardrailViolation
    case exceededContextWindow
    case unsupportedLanguage
    case assetsUnavailable
    case rateLimited
    case emptyGuidedOutput
    case decodingFailure
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let msg): return msg
        case .guardrailViolation:
            return "Apple Intelligence hat den Text nicht zugelassen. Versuche es erneut oder wechsle in den Einstellungen auf OpenAI."
        // ... siehe RESEARCH.md
        }
    }

    static func from(_ availability: FoundationAvailability) -> AppleFoundationError {
        switch availability {
        case .available:
            return .unknown("Foundation .available — sollte nicht hier landen")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence ist in den Systemeinstellungen nicht aktiviert.")
        case .unavailable(.modelNotReady):
            return .unavailable("Das Apple-Foundation-Modell wird gerade geladen — bitte erneut versuchen.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("Dieses Gerät unterstützt Apple Intelligence nicht.")
        }
    }
}
```

### 2. DI-Slot-mit-Default-Pattern für Test-Seams

**Source:** `BlitzText/Modes/ModeProcessor.swift:28-56` (Test-Seams + Lazy-Defaults), `BlitzText/Transcription/DiarizerModelManager.swift:34-44` (DI-init mit Default-FactoryArg)

**Apply to:** alle neuen Klassen mit Hardware-/Apple-API-Bindung (`AppleFoundationRewriteClient`, `SettingsStore`-Erweiterung).

**Idiom:**
```swift
private let injected: SomeProtocol?
private lazy var defaultImpl: SomeProtocol = LiveImpl(...)
private var active: SomeProtocol { injected ?? defaultImpl }

init(..., injected: SomeProtocol? = nil) { ... }
```

Bei Structs (`SystemLanguageModelAvailabilityProvider`, `LiveLanguageModelInferring`): `init(provider: ... = LiveImpl())` direkt — analog `OpenAIChatClient.init(settings:, session: URLSession = .shared)`.

### 3. `@unchecked Sendable` für API-Adapter-Klassen

**Source:** `OpenAIChatClient.swift:4` (`final class OpenAIChatClient: RewriteService, @unchecked Sendable`), `FakeRewriter.swift:6`, `FakeDiarizerLoader.swift:9`

**Apply to:** `AppleFoundationRewriteClient`, alle neuen Fakes in `BlitzTextTests/Support/`.

**Begründung (RESEARCH.md Anti-Patterns):** `@MainActor` würde Inferenz an Main-Thread binden; `@unchecked Sendable` ist Bestand-Konvention bei Adapter-Klassen ohne mutierten State (oder mit privatem State, der nicht cross-thread-shared wird).

### 4. Snapshot-Migration mit Optional + `?? default`

**Source:** `SettingsStore.swift:107-108, 127-128`
```swift
var aiSuggestProperNouns: Bool?
var parakeetDiarization: Bool?
// in load():
aiSuggestProperNouns = snap.aiSuggestProperNouns ?? true
parakeetDiarization = snap.parakeetDiarization ?? false
```

**Apply to:** `Snapshot.rewriteBackendForPlus: RewriteBackend?` und `rewriteBackendForRant: RewriteBackend?` mit Default `?? .appleFoundation`. Keine Daten-Migration nötig, keine Versions-Number — additiv.

### 5. SwiftUI-Section-Helper + Sub-Header-Pattern

**Source:** `SettingsView.swift:139-145` (`section(_:content:)`-ViewBuilder-Helper) und `Text("Schreibstil").font(.subheadline)` (Zeile 71) als Sub-Header innerhalb einer Section.

**Apply to:** Phase-8-Backend-Picker fügen als neue Zeile am Ende der `BLITZTEXT+`/`BLITZTEXT $%&!`-Sections an: `Text("Backend").font(.subheadline).padding(.top, 6)` + `Picker(...)`. Banner mountet als eigene `section("APPLE INTELLIGENCE")`.

### 6. Deterministischer Test-Stil (kein Sleep, injizierte Inputs)

**Source:** `HotkeyStateMachineTests.swift:23-25` (`Date(timeIntervalSince1970: T)`) + `PipelineErrorPathTests.swift` (synchrone Asserts auf `mp.state` nach `await stop()`)

**Apply to:** alle Phase-8-Tests. Keine echten Apple-Intelligence-Calls, keine `Task.sleep` außer für progressTicks-Pattern (`FakeDiarizerLoader.swift:32` — 5 ms Schlaf zur Tick-Trennung; nur falls Banner-B-Übergang explizit getestet wird, sonst weglassen).

---

## No Analog Found

| File | Role | Reason |
|------|------|--------|
| `BlitzText/Rewrite/DeescalatedOutput.swift` (`@Generable`-Macro-Annotation) | model | Erstmals `@Generable`/`@Guide` im Projekt — keine bestehende Macro-Anwendung. Doc-Comment-Stil + struct-Form aus `Mode.swift` übernehmen, Macro-Syntax aus RESEARCH.md Pattern 3. **Bei Plan-Zeit:** Macro-Expansion in Xcode live verifizieren (RESEARCH.md Open Question 4). |
| `Link(destination: URL(string: "x-apple.systempreferences:..."))` im FoundationAvailabilityBanner | view | Bestand nutzt nur `PermissionsHelper.openAccessibilitySettings()` (über NSWorkspace). SwiftUI-`Link` in Settings ist neu — Apple-HIG-konform, aber kein Code-Vorbild im Projekt. Plan: direkt aus UI-SPEC übernehmen (Standard-SwiftUI-API). |
| `LanguageModelSession.prewarm()`-Aufruf | app-lifecycle | Kein bestehender Apple-Foundation-Code. RESEARCH.md Pattern 4 + Pitfall 3 sind die Vorlage. Existierendes `Task.detached { await client.warmUp() }`-Pattern in `ModeProcessor.preloadLocalModelIfActive` ist die nächstgelegene Form. |

---

## Metadata

**Analog search scope:**
- `BlitzText/Rewrite/` (RewriteService.swift, OpenAIChatClient.swift)
- `BlitzText/Settings/` (SettingsStore.swift, SettingsView.swift)
- `BlitzText/Modes/` (Mode.swift, ModeProcessor.swift)
- `BlitzText/UI/` (RecordingHUDController.swift, HUDView.swift — letzteres nicht Phase-8-relevant)
- `BlitzText/Transcription/` (DiarizerLoaderProtocol.swift, DiarizerModelManager.swift)
- `BlitzText/App/` (AppDelegate.swift)
- `BlitzTextTests/Pipeline/`, `BlitzTextTests/Hotkeys/`, `BlitzTextTests/Support/`

**Files scanned:** 13 Source + 5 Test-Files + 5 Test-Support-Files = 23.

**Pattern extraction date:** 2026-05-04

**Key pattern density:**
- 4 / 4 NEW Source-Files haben einen exakt-Analog im Bestand (Protocol-Pattern aus Phase 3, Adapter-Pattern aus Phase 1).
- 3 / 3 MODIFY-Files haben **inline-Analoge im selben File** (TranscriptionBackend-Vorlage in SettingsStore, langBadge-Vorlage in HUDController, runPipeline-Switch-Vorlage in ModeProcessor) — minimaler Cognitive-Switch-Aufwand für den Executor.
- 3 / 3 NEW Test-Files mappen 1:1 auf Phase-2-/Phase-3-Test-Konventionen (HotkeyStateMachineTests, PipelineErrorPathTests).
- Vier-State-Banner-Pattern aus Phase 3 (`DiarizerStatusBlock`) ist die direkte Vorlage für Phase-8-`FoundationAvailabilityBanner` — gleiche Switch-Form, gleiche Image-VStack-Spacer-Geometrie.

**Wave-0-Verifikation (Plan-Empfehlung):** Vor Code-Zementierung Researcher-Open-Questions A1, A2, A6 in Xcode Quick Help live klären (RESEARCH.md Empfohlene Wave-0-Aufgaben, ~15–30 min).
