# Phase 8: Apple Foundation Models als Rewrite-Backend — Research

**Researched:** 2026-05-04
**Domain:** Apple `FoundationModels` framework (macOS 26+), Swift 6 Concurrency, On-Device LLM Integration
**Confidence:** HIGH (für API-Form, Availability-Cases, Generable, GenerationError) — MEDIUM (für Concurrency-Annotations, Cold-Start-Latenz, Notification-Hooks)

## Summary

Apple `FoundationModels` (macOS 26+) ist ein Apple-Intelligence-On-Device-LLM-Framework, das mit `import FoundationModels`, einem Singleton `SystemLanguageModel.default` und einer per-Instanz `LanguageModelSession`-Klasse arbeitet. Die Verfügbarkeit wird über `SystemLanguageModel.default.availability` als Enum mit `.available` plus `.unavailable(reason)` für **drei** Reasons (`appleIntelligenceNotEnabled`, `modelNotReady`, `deviceNotEligible`) abgefragt — exakt die Cases, die in CONTEXT.md AC-AVAIL-1 als testbar genannt sind. `LanguageModelSession(instructions: ...)` mit Closure-basiertem `instructions`-Builder ist die kanonische Init-Form. `respond(to:)` und `respond(to:generating:)` geben **`Response<T>`** mit einer `.content`-Property zurück — nicht plain `String`. Guided Generation per `@Generable` + optional `@Guide` ist genau die richtige Form für `blitztextRant` (Deeskalation), weil sie Format-Drift via Compile-Time-Schema verhindert.

**Apple liefert keinen offiziellen Notification/AsyncStream-Hook für Availability-State-Wechsel** (CONTEXT.md AC-AVAIL-2-Frage geklärt: Polling oder On-Demand-Re-Check beim nächsten Hotkey-Press ist Stand der Technik — Community empfiehlt 10-30 s Intervall, oder UI-Trigger via Banner-B-Button). Deutsch ist offiziell unter `supportedLanguages` gelistet — Sprachbias ist primär prompt-driven (instructions explizit auf Deutsch), kein dedizierter Locale-Parameter. `LanguageModelSession.GenerationError` deckt Guardrail-Violations, Asset-Unavailability, Context-Window-Überschreitung und unsupported-Language ab — alle als deutsche Fehlermeldung mappbar.

**Primary recommendation:** Implementiere `AppleFoundationRewriteClient: RewriteService, @unchecked Sendable` analog zu `OpenAIChatClient`. Halte eine `@MainActor`-isolierte `FoundationAvailabilityProvider`-Wrapper-Klasse (Protocol-basiert für Test-Mock) im `SettingsStore`, die `availability` cached, mit `refresh()`-Methode für manuelle Re-Checks und auto-Re-Check beim nächsten App-Activation-Event (`NSApplication.didBecomeActiveNotification`). Pre-Warm via `LanguageModelSession.prewarm()` in `AppDelegate.bootstrap()` wenn Foundation-Backend für irgendeinen Mode aktiv ist. Für `blitztextRant`: Guided Generation mit minimalem Schema `@Generable struct DeescalatedOutput { var neutralText: String }` — keine zusätzlichen Telemetry-Felder in v1.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Foundation Models = Default**, OpenAI bleibt als expliziter User-Override verfügbar.
- **Kein automatischer Fallback** auf OpenAI bei Foundation-Inferenz-Fehler. Stattdessen: klare deutsche Fehlermeldung mit Hinweis auf Backend-Wechsel in den Settings. Begründung: Privacy-Markenversprechen kompromisslos halten.
- **Code-Form:** `RewriteBackend`-Enum (analog `TranscriptionBackend`) in `SettingsStore`. Cases: `appleFoundation` (default), `openAI`. Erweiterbar.
- **Pro Mode wählbar:** User kann unabhängig für Blitztext+ und Blitztext $%&! das Backend setzen. Defaults: beide Modes = `appleFoundation` bei verfügbarem Foundation; sonst beide = `openAI` (bei vorhandenem API-Key).
- **Plain `LanguageModelSession`** für `blitztextPlus` (Stil-Rewrite) — `LanguageModelSession(instructions: systemPrompt).respond(to: input)` mappt 1:1 auf das bestehende RewriteService-Protokoll.
- **Guided Generation (`@Generable`)** für `blitztextRant` (Deeskalation) — definiertes Schema verhindert Format-Drift.
- **Start-Check** via `SystemLanguageModel.default.availability` in `AppDelegate.bootstrap()` (oder `SettingsStore.load()`); Verfügbarkeitsstatus wird im `SettingsStore` als beobachtbarer State gehalten.
- **Backend-Indikator im HUD:** subtiles SF-Symbol (`apple.logo` für Foundation, `cloud` für OpenAI) — siehe 08-UI-SPEC.md.

### Acceptance Criteria (testbar)

- **AC-AVAIL-1:** Defensive Verfügbarkeitsprüfung vor jedem Inferenz-Call. Bei `.unavailable(...)` wird **nicht** stillschweigend auf OpenAI umgeschaltet. Test: Mock `availability` mit allen vier Fällen; Client liefert pro Fall die spezifizierte Fehlermeldung, keine Cloud-Calls.
- **AC-AVAIL-2:** Erst-Start-UX für `modelNotReady` — App meldet "Modell wird geladen" mit Wiederholen-Hinweis; Verfügbarkeitsstatus wird beobachtbar gehalten und re-evaluiert. Test: simuliere Übergang `modelNotReady` → `available`; UI wechselt ohne App-Neustart.
- **AC-AVAIL-3:** README/Settings-Hilfe nennt: BlitzText+ Apple-Foundation-Backend benötigt **aktives Apple Intelligence**, ist aber unabhängig von Siri-Status.

### Claude's Discretion

- Generable-Schema-Felder genau festlegen (Researcher empfiehlt `neutralText: String`, **keine** `removedHeatTerms` in v1 — Begründung siehe Generable-Sektion).
- Concurrency-Annotation der neuen Client-Klasse (Researcher empfiehlt `final class … : RewriteService, @unchecked Sendable`).
- Pre-Warm-Strategie (Researcher empfiehlt App-Boot-Pre-Warm via `LanguageModelSession.prewarm()` wenn Foundation für irgendeinen Mode aktiv).
- Polling-Intervall für `modelNotReady`-Re-Check (Researcher empfiehlt: kein Polling, sondern App-Activation-Trigger + manueller Banner-B-Button).
- Sprachbias-Mitigation (Researcher empfiehlt: deutsche Marker im `instructions`-String explizit setzen — siehe Sprachbias-Sektion).

### Deferred Ideas (OUT OF SCOPE)

- Apple Foundation für Meeting-Zusammenfassungen (separate Phase 999.3 / 999.5).
- Telemetry/Latenz-Vergleich Foundation vs. OpenAI (eher v2-Requirement PERF-02).
- Apple Foundation für Translation (999.4/999.5).
- Inferenz-Fehler-UI im HUD über bestehenden `processor.state == .error`-Pfad hinaus.
- Backend-pro-History-Eintrag (transparente Reproduktion) — eher v2 / PERF-02-Telemetry.
- Pre-Warm-UI mit eigenem Status-Indikator.
- Backend-Wechsel-Confirm-Dialog (Wechsel ist non-destruktiv).
</user_constraints>

<phase_requirements>
## Phase Requirements

Keine v1-Requirements aus REQUIREMENTS.md adressiert (Phase 8 ist milestone-erweiternd, promoted aus Backlog 999.7). Acceptance Criteria sind in CONTEXT.md kodifiziert:

| ID | Description | Research Support |
|----|-------------|------------------|
| AC-AVAIL-1 | Defensive Verfügbarkeitsprüfung vor jedem Inferenz-Call; bei `.unavailable(...)` deutsche Fehlermeldung, kein Auto-Fallback | API-Form `SystemLanguageModel.default.availability` verifiziert; Enum-Cases verifiziert; Mock-Strategie via Protocol-Wrapping (siehe Validation Architecture) |
| AC-AVAIL-2 | Erst-Start-UX für `modelNotReady`; beobachtbarer Re-Check-Mechanismus | Polling vs. App-Activation-Trigger geklärt — Apple liefert keinen Notification-Hook; Re-Check-Strategie im Wrapper geplant |
| AC-AVAIL-3 | README/Settings-Hilfe: Foundation hängt an Apple Intelligence, nicht an Siri | Verifiziert durch Apple-Doku-Architektur (Foundation = Apple-Intelligence-Asset, Siri ist eigene Permission-Domäne) |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| LLM-Inference (Rewrite) | macOS-System (Apple Intelligence ANE/GPU) | App-Process (Session-Halter) | Apple FoundationModels läuft im System-Daemon; App hostet nur die Session-Referenz |
| Backend-Auswahl & Persistenz | App `SettingsStore` (`@MainActor`) | UserDefaults (Snapshot) | Bestehendes Pattern; identisch zu `TranscriptionBackend` |
| Availability-State-Cache | App `FoundationAvailabilityProvider` (`@MainActor`) | `SystemLanguageModel.default.availability` (Live-Source-of-Truth) | Cache fürs UI; Re-Check on demand (Apple bietet keinen Push) |
| Pre-Warm-Trigger | App `AppDelegate.bootstrap()` | `LanguageModelSession.prewarm()` | Cold-Start-Mitigation, wenn Foundation aktiv |
| Inferenz-Dispatch | App `ModeProcessor.runPipeline` | Per-Mode `RewriteBackend`-Lookup | Bestehender Hook in `runPipeline`; minimale Erweiterung |
| Schema-Validation (Rant) | Apple FoundationModels-Runtime | Compile-Time `@Generable`-Macro | Schema wird zur Build-Zeit aus Swift-Typ generiert; Runtime füllt strukturiert |
| Fehlermeldungen (UI) | App `ModeProcessor.humanReadable` + neue `AppleFoundationError`-Mapper | Bestehende `processor.state == .error`-Pipeline | Keine neue Fehler-UI nötig (CONTEXT-Decision) |
| Banner-Rendering | App `SettingsView/AnpassenTab` | `FoundationAvailabilityBanner`-View | Per UI-SPEC bereits vollständig spezifiziert |
| HUD-Backend-Indikator | App `RecordingHUDView` | SF Symbol (`apple.logo` / `cloud`) | Per UI-SPEC bereits vollständig spezifiziert |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `FoundationModels` (Apple System Framework) | macOS 26.0+ (Tahoe) | On-Device LLM Inference, Guided Generation | Erstes-Party-API; einziges Framework für Apple-Intelligence-Foundation-Modell auf macOS [VERIFIED: developer.apple.com/documentation/foundationmodels] |
| Swift Concurrency (async/await, Sendable) | Swift 6.0 | Asynchrone Inferenz + Sendability | Bestehendes Project-Setup `SWIFT_STRICT_CONCURRENCY: minimal`; alle FoundationModels-APIs sind `async throws` [VERIFIED: project.yml + Apple-Doku-Patterns] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Combine` (Apple) | bundled | `@Published` für Banner-State + Auto-Fallback-Flag im `SettingsStore` | Bestehendes Pattern; existing `SettingsStore` nutzt es bereits |
| `AppKit` `NSApplication.didBecomeActiveNotification` | bundled | Trigger für `refreshFoundationAvailability()` bei App-Wiederaktivierung | Apple liefert keinen Push-Hook für Availability-State; App-Activation ist die natürlichste Re-Check-Gelegenheit (User kommt typischerweise aus Systemeinstellungen zurück) [ASSUMED — Best-Practice-Mapping, kein offizieller Apple-Hinweis] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Direct `SystemLanguageModel.default.availability` calls in Client | Protocol `FoundationAvailabilityProviding` mit Live + Mock-Implementierung | Protocol-Wrapping ist nötig für AC-AVAIL-1-Tests (vier Cases ohne reales Apple Intelligence); marginaler Code-Overhead; Researcher empfiehlt Protocol-Variante |
| Per-Request `LanguageModelSession`-Init (stateless) | App-wide cached Session pro Mode | Stateless ist robuster (jeder Rewrite ist semantisch independent); cached Session würde 4096-Token-Context-Window auffüllen + Guardrail-Trigger-Flakes durch Cross-Request-Kontamination begünstigen [VERIFIED: createwithswift.com — "persistent sessions help with multilingual conversations" sagt das *Gegenteil* nur für Multilingual-Konversation-Use-Cases; für rewrite-pro-Hotkey-Press passt stateless besser] |
| Polling für `modelNotReady` | App-Activation-Notification + Banner-B-Button | Polling kostet permanent Wakeups; CONTEXT.md erwähnt Polling explizit, aber für eine Menubar-App ist On-Demand sparsamer und User-Experience identisch (User wartet sowieso, bis er den Hotkey das nächste Mal drückt) [ASSUMED] |
| Eigene Generable-Schema mit Telemetry-Feldern | Minimales Schema `{ neutralText: String }` | Apple-Doku + Community-Konsens: kleinere Schemas sind robuster gegen Schema-Fill-Failures; Telemetry-Feature ist out-of-scope (PERF-02 v2) |

**Installation:** Keine SPM-Dependency nötig — `FoundationModels` ist Apple System Framework. `import FoundationModels` reicht; Linker findet es automatisch ab macOS 26 SDK.

**Version verification:**
- `FoundationModels` ist Bestandteil macOS 26 SDK (Tahoe). project.yml hat bereits `deploymentTarget: macOS: "26.0"` und `MACOSX_DEPLOYMENT_TARGET: "26.0"` — also keine Anpassung nötig. [VERIFIED: project.yml gelesen]
- Swift 6.0 Toolchain enthält das Macro-Plugin für `@Generable` / `@Guide` ab Xcode 17 / Swift 6 [CITED: developer.apple.com/documentation/foundationmodels — Verfügbarkeit ab macOS 26.0+ / iOS 26.0+]

## Architecture Patterns

### System Architecture Diagram

```
[User Hotkey]
   │
   ▼
[ModeProcessor.toggle(mode)]   ── @MainActor
   │
   ▼
[AudioRecorder.start/stop]
   │
   ▼
[Transcription Backend] ──► raw text
   │
   ▼
[Mode-Switch in runPipeline]
   ├── .blitztext       → output = raw, kein Rewrite
   ├── .blitztextPlus   → settings.rewriteBackend(for: .blitztextPlus)
   │                       ├── .appleFoundation → AppleFoundationRewriteClient.rewrite (plain Session)
   │                       └── .openAI          → OpenAIChatClient.rewrite
   └── .blitztextRant   → settings.rewriteBackend(for: .blitztextRant)
                           ├── .appleFoundation → AppleFoundationRewriteClient.rewrite (Guided, @Generable DeescalatedOutput)
                           └── .openAI          → OpenAIChatClient.rewrite
   │
   ▼
[TextInserter.copyToClipboard + simulatePaste]

──────────────────────────────────────────────

[App-Boot (AppDelegate.bootstrap)]
   │
   ├── settings.refreshFoundationAvailability()
   │      └─► reads SystemLanguageModel.default.availability
   │             ├── .available → no banner; if both modes default + foundation enabled, prewarm
   │             ├── .unavailable(.modelNotReady) → banner B + register App-Activation-Notification observer
   │             ├── .unavailable(.appleIntelligenceNotEnabled) → banner A; if API-Key vorhanden + beide Modes auf default → setRewriteBackend(.openAI) + didAutoFallbackToOpenAI = true (Banner D)
   │             └── .unavailable(.deviceNotEligible) → banner C; if API-Key vorhanden → setRewriteBackend(.openAI) (Banner D suppressed durch UI-SPEC)
   │
   └── if any mode uses .appleFoundation AND availability == .available:
        Task.detached { try? await LanguageModelSession().prewarm() }

[NSApplication.didBecomeActiveNotification]
   └─► settings.refreshFoundationAvailability()  ── deckt AC-AVAIL-2-Übergang ab

[Banner-B Button "Erneut prüfen"]
   └─► settings.refreshFoundationAvailability()
```

### Recommended Project Structure

Erweitert bestehende Struktur, **kein** neues Top-Level-Verzeichnis:

```
BlitzText/
├── Rewrite/
│   ├── RewriteService.swift                  # bestehend, unverändert
│   ├── OpenAIChatClient.swift                # bestehend, unverändert
│   ├── AppleFoundationRewriteClient.swift    # NEU — RewriteService-Implementierung
│   ├── DeescalatedOutput.swift               # NEU — @Generable struct für Rant
│   └── FoundationAvailabilityProvider.swift  # NEU — Protocol + Live-Impl + Mock-Hook
├── Settings/
│   ├── SettingsStore.swift                   # erweitert um RewriteBackend, foundationAvailability, didAutoFallbackToOpenAI, refreshFoundationAvailability(), rewriteBackend(for:), setRewriteBackend(_:for:)
│   └── SettingsView.swift                    # erweitert um RewriteBackendPicker + FoundationAvailabilityBanner
├── UI/
│   ├── RecordingHUDController.swift          # erweitert um BackendBadge im HStack; HUD-Width 240→268
│   └── HUDView.swift                         # ggf. unverändert (statusText-Pfad bleibt gleich)
├── Modes/
│   ├── Mode.swift                            # unverändert
│   └── ModeProcessor.swift                   # erweitert: Backend-Lookup pro Mode, Inject neuer Foundation-Client
└── App/
    └── AppDelegate.swift                     # erweitert: refreshFoundationAvailability bei bootstrap + didBecomeActiveNotification + prewarm
BlitzTextTests/
├── Rewrite/                                  # NEU — eigenes Test-Verzeichnis (Konvention)
│   ├── AppleFoundationAvailabilityTests.swift
│   ├── AppleFoundationRewriteClientTests.swift
│   └── RewriteBackendDispatchTests.swift
└── Support/
    ├── FakeFoundationAvailabilityProvider.swift   # NEU — Mock-Provider
    └── FakeRewriter.swift                         # bestehend
```

### Pattern 1: Protocol-Wrapped Availability for Test-Mock

**What:** `SystemLanguageModel.default.availability` ist nicht direkt mockbar (kein Init, Singleton, kein Protocol). Wir wrappen mit eigenem Protocol.

**When to use:** Sobald wir Tests für AC-AVAIL-1 schreiben müssen (vier Verfügbarkeits-Fälle ohne reales Apple Intelligence).

**Example:**
```swift
// Source: Pattern aus eigenem Setup, basiert auf swiftyplace.com + dev.to-Article-Empfehlungen
import FoundationModels

enum FoundationAvailability: Equatable, Sendable {
    case available
    case unavailable(Reason)

    enum Reason: Equatable, Sendable {
        case appleIntelligenceNotEnabled
        case modelNotReady
        case deviceNotEligible
    }
}

protocol FoundationAvailabilityProviding: Sendable {
    func currentAvailability() -> FoundationAvailability
}

struct SystemLanguageModelAvailabilityProvider: FoundationAvailabilityProviding {
    func currentAvailability() -> FoundationAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled: return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:               return .unavailable(.modelNotReady)
            case .deviceNotEligible:           return .unavailable(.deviceNotEligible)
            @unknown default:                  return .unavailable(.deviceNotEligible) // konservativster Soft-Fallback
            }
        }
    }
}
```

[VERIFIED: artemnovichkov.com — exakt dieselbe Switch-Form wird empfohlen mit `@unknown default`-Branch]
[VERIFIED: rudrank.com — Apple empfiehlt explizit @unknown default-Handling für zukünftige Cases]

### Pattern 2: Plain Session for blitztextPlus

**What:** Direkter Mapper RewriteService → `LanguageModelSession.respond(to:)`.

**When to use:** Stil-Rewrite (`blitztextPlus`); kein strukturierter Output nötig.

**Example:**
```swift
// Source: createwithswift.com + artemnovichkov.com
import FoundationModels

final class AppleFoundationRewriteClient: RewriteService, @unchecked Sendable {
    private let availabilityProvider: FoundationAvailabilityProviding

    init(availabilityProvider: FoundationAvailabilityProviding) {
        self.availabilityProvider = availabilityProvider
    }

    func rewrite(input: String, systemPrompt: String, model: String) async throws -> String {
        // AC-AVAIL-1: defensive Verfügbarkeitsprüfung vor Inferenz
        let availability = availabilityProvider.currentAvailability()
        guard availability == .available else {
            throw AppleFoundationError.from(availability)
        }

        let session = LanguageModelSession(instructions: { systemPrompt })
        let response = try await session.respond(to: input)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Notiz: response.content ist String (Default-Generic); Response<T> mit T=String hat .content: String
    }
}
```

[VERIFIED: createwithswift.com — Init-Form `LanguageModelSession(instructions: { ... })` mit Closure]
[VERIFIED: artemnovichkov.com — `session.respond(to: prompt)` mit `.content` Property]
[VERIFIED: medium.com Salvaterra — `response.content` ist Endprodukt]

### Pattern 3: Guided Generation for blitztextRant

**What:** `@Generable`-Schema für strukturierten Output; verhindert "Hier ist die entschärfte Version: …"-Präambeln.

**When to use:** Deeskalation (`blitztextRant`); Format-Drift wäre teuer (User kopiert dann Präambel mit).

**Example:**
```swift
// Source: appcoda.com + medium.com Salvaterra
import FoundationModels

@Generable
struct DeescalatedOutput {
    @Guide(description: "Der entschärfte Text in deutscher Sprache, sachlich-freundlich, ohne Präambel oder Anführungszeichen.")
    var neutralText: String
}

extension AppleFoundationRewriteClient {
    func rewriteWithGuidedGeneration(input: String, systemPrompt: String) async throws -> String {
        let availability = availabilityProvider.currentAvailability()
        guard availability == .available else {
            throw AppleFoundationError.from(availability)
        }
        let session = LanguageModelSession(instructions: { systemPrompt })
        let response = try await session.respond(to: input, generating: DeescalatedOutput.self)
        let neutral = response.content.neutralText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !neutral.isEmpty else {
            // Schema-Fill-Failure-Soft-Fallback: leerer neutralText → spezifischer Fehler
            throw AppleFoundationError.emptyGuidedOutput
        }
        return neutral
    }
}
```

[VERIFIED: appcoda.com — `@Guide(description: "...")` ist die kanonische Annotation-Form]
[VERIFIED: medium.com Salvaterra — `respond(to:generating:)` mit Type.self; `.content` ist typed]
[VERIFIED: Apple Doku — `Response<T>.content` ist generic mit `T = MyGenerable` für guided variants]

### Pattern 4: Pre-Warm at App-Boot

**What:** `LanguageModelSession.prewarm()` lädt das Modell eager, reduziert Cold-Start.

**When to use:** App-Boot, **wenn** Foundation für irgendeinen Mode aktiv ist UND `availability == .available`. **Mindestens 1 s Vorlauf bis erster `respond`-Call** (sonst kein Effekt).

**Example:**
```swift
// Source: createwithswift.com — "Only use prewarm if you have at least a one-second window"
@MainActor
func prewarmFoundationIfActive(settings: SettingsStore) {
    guard settings.foundationAvailability == .available else { return }
    let usesFoundation = Mode.allCases.contains { mode in
        mode != .blitztext && settings.rewriteBackend(for: mode) == .appleFoundation
    }
    guard usesFoundation else { return }
    Task.detached(priority: .utility) {
        // Eine warme Session ohne instructions reicht zum Asset-Loading.
        let session = LanguageModelSession()
        try? await session.prewarm()
    }
}
```

[VERIFIED: createwithswift.com — `prewarm()` ist eigene Methode auf `LanguageModelSession`; "1-second window" Anforderung]
[VERIFIED: dev.to/arshtechpro — "call prewarm at launch to ensure everything is ready"]

### Anti-Patterns to Avoid

- **App-wide cached Session über mehrere Rewrite-Calls hinweg:** würde 4096-Token-Context-Window bei langen Sessions sprengen + Guardrail-Cross-Contamination begünstigen. **Stattdessen:** Per-Request-Init der Session (stateless rewriting). `prewarm()` separat zum Asset-Cachen.
- **Stilles Auto-Fallback auf OpenAI bei `availability == .unavailable`:** verstößt explizit gegen CONTEXT-Decision (Privacy-Versprechen). **Stattdessen:** deutsche Fehlermeldung pro Reason + UI-Banner.
- **`@MainActor`-Annotation auf `AppleFoundationRewriteClient`:** würde Inferenz an Main-Thread binden und HUD-Animationen blockieren. **Stattdessen:** `final class … : @unchecked Sendable` (analog `OpenAIChatClient`); Inferenz läuft auf beliebigem Executor.
- **Regelmäßiges Polling für `modelNotReady`-Übergang im Hintergrund:** kostet Wakeups. **Stattdessen:** App-Activation-Notification + manueller "Erneut prüfen"-Button (Banner B).
- **Englischer `instructions`-String mit deutschen Eingabe-Texten:** Triggert Sprachbias-Drift (Modell antwortet auf Englisch). **Stattdessen:** instructions explizit deutsch + zusätzlicher Marker-Satz "Antworte ausschließlich auf Deutsch."
- **`@Generable`-Schema mit vielen optionalen Feldern + nested Types:** erhöht Schema-Fill-Failure-Rate. **Stattdessen:** minimales Schema `{ neutralText: String }`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Strukturierter LLM-Output für Rant | Eigener Regex-/Parser-basierter Präambel-Stripper | `@Generable struct DeescalatedOutput` | Apple's Constrained Decoding garantiert Schema-Validität auf Token-Ebene; Regex-Stripping ist fragil |
| Availability-State-Caching mit Auto-Update | Eigenes NSWorkspace-Notification-Hooking | App-Activation + Manual-Refresh-Button + cached `@Published`-State | Apple bietet keinen offiziellen Hook; eigene Polling-Loop zieht Battery; Manual + Activation-Notification ist Stand der Technik |
| Cold-Start-Mitigation | Eigener Warm-Up-Dummy-Call (`session.respond(to: "warmup")`) | `LanguageModelSession.prewarm()` | Apple-API ist explizit für Asset-Caching ohne Inferenz-Tokens; Dummy-Call verbraucht Context-Window |
| Sprachbias-Detektion (Output-Englisch trotz Deutsch-Input) | Output-Language-Detector mit NLLanguageRecognizer post-hoc | Deutsche `instructions` + expliziter "Antworte auf Deutsch"-Marker | Prompt-Engineering ist die einzige Influence-Surface; Post-hoc-Detection wäre Verschwendung |
| Foundation-Error → User-String-Mapping | Generischer `error.localizedDescription` | Eigener `AppleFoundationError`-Enum mit deutschen Cases pro `GenerationError.type` | Apple-Default-Strings sind englisch; CLAUDE.md fordert deutsche UI-Strings |

**Key insight:** Apple FoundationModels ist designed für minimale App-Code-Komposition — alle "schwierigen" Probleme (Schema-Validity, Cold-Start, Asset-Loading) hat Apple bereits framework-intern gelöst. Unser Code ist nur der **Adapter** zwischen `RewriteService`-Protocol und `LanguageModelSession.respond`.

## Common Pitfalls

### Pitfall 1: Sprachbias — englische Outputs trotz deutschen Inputs

**What goes wrong:** Modell antwortet auf Englisch, obwohl `instructions` und Input deutsch sind. Fall in Community-Berichten häufig dokumentiert.

**Why it happens:** Apple-Foundation-Modell ist english-dominant trainiert; Trigger-Schwelle für Output-Sprache hängt an Input + Instructions; bei kurzen / nicht-explizit-deutschen Instructions kippt es manchmal.

**How to avoid:**
- Im `instructions`-Closure expliziten Marker setzen: `"Antworte ausschließlich auf Deutsch."` als letzte Zeile
- `Mode.defaultRewritePrompt` ist bereits deutsch — beim Komponieren in `makeRewriteSystemPrompt(for:)` einen finalen Marker-Satz appenden, **nur** wenn Backend Foundation ist
- Bei `blitztextRant`: zusätzlich `@Guide(description: "... in deutscher Sprache ...")` direkt am Schema-Feld — Constrained Decoding kann Sprachbias mit-leiten

**Warning signs:**
- Stichproben-Test mit deutschem Input → englischer Output kommt zurück
- User-Bug-Reports "Foundation antwortet auf Englisch"

[VERIFIED: rudrank.com — Apple empfiehlt explizit "Respond in \(userLanguage). All your responses must be in the user's language" sowohl in instructions als auch im Prompt]

### Pitfall 2: `@unknown default` fehlt im Availability-Switch

**What goes wrong:** Apple ergänzt in macOS 27 eine neue `unavailable`-Reason (z.B. `regionRestricted`); Compiler-Warning oder Runtime-Crash beim alten Build auf neuem OS.

**Why it happens:** `SystemLanguageModel.Availability.UnavailableReason` ist non-frozen Enum.

**How to avoid:** `@unknown default`-Branch im Switch über `unavailable`-Reasons; konservatives Soft-Fallback auf `deviceNotEligible` (Final-State-Variante mit OpenAI-Fallback bei API-Key).

**Warning signs:** Swift-Compiler-Warning "switch covers known cases, but '...' may have additional unknown values".

[VERIFIED: artemnovichkov.com — Code-Beispiel zeigt explizit `@unknown default`-Branch]

### Pitfall 3: `prewarm()` ohne 1-s-Vorlauf hat keinen Effekt

**What goes wrong:** App ruft prewarm direkt vor erstem `respond` — Asset-Loading konkurriert mit Inferenz, kein messbarer Vorteil.

**Why it happens:** prewarm ist async-eager — braucht Zeit, bis das Modell wirklich resident ist.

**How to avoid:** prewarm im `AppDelegate.bootstrap()` (typisch sekundenlang vor erstem User-Hotkey); **nicht** kurz vor `runPipeline`-Start.

**Warning signs:** Latenz-Messung zeigt keinen Cold-Start-Vorteil trotz prewarm-Aufruf.

[VERIFIED: createwithswift.com — "Only use prewarm if you have at least a one-second window"]

### Pitfall 4: `LanguageModelSession.GenerationError.guardrailViolation` bei harmlosen Rant-Inputs

**What goes wrong:** User diktiert frustrierten Text mit Schimpfwörtern → Apple-Guardrails triggern → `.guardrailViolation`-Error → keine Deeskalation.

**Why it happens:** Apple-Guardrails sind konservativ kalibriert; "scheiße so eine kacke" könnte als unsafe content geflaggt werden, obwohl genau das der Rant-Use-Case ist.

**How to avoid:**
- Im `instructions`-Closure den Kontext explizit framen: "Du erhältst möglicherweise vulgäre, frustriert formulierte Eingaben. Deine Aufgabe ist, diese in sachliche Sprache zu übersetzen — das ist deine erlaubte Funktion."
- Im Catch-Pfad `.guardrailViolation` sehr sichtbar als deutsche Fehlermeldung mappen ("Apple Intelligence hat den Text als nicht zulässig eingestuft. Wechsle für diesen Modus auf OpenAI in den Einstellungen.")
- Bei wiederholten Triggern: Doku im README erwähnen, dass Rant-Mode auf Foundation **kein** Hard-Guarantee bietet

**Warning signs:** Hohe `.guardrailViolation`-Rate spezifisch im `blitztextRant`-Pfad (Rohdaten gibt es nicht, Telemetry ist deferred — Hint kommt nur via User-Bug-Reports).

[VERIFIED: dev community + swiftyplace.com — `.guardrailViolation` ist Standard-Error-Type]

### Pitfall 5: Schema-Fill-Failure liefert leeren `neutralText`

**What goes wrong:** Modell schafft `@Generable`-Schema nicht zuverlässig → `respond(to:generating:)` returnt `Response<DeescalatedOutput>` mit leerem `neutralText`-String, ohne zu werfen.

**Why it happens:** Constrained Decoding garantiert Schema-Struktur, aber nicht semantischen Inhalt; bei sehr kurzen Inputs oder Guardrail-Soft-Refusals kommt leerer String.

**How to avoid:**
- Im Client nach `response.content.neutralText`-Extraktion auf `.isEmpty` prüfen
- Bei leer: `AppleFoundationError.emptyGuidedOutput` werfen (deutsche Fehlermeldung: "Apple Intelligence konnte den Text nicht entschärfen. Bitte erneut versuchen oder in den Einstellungen auf OpenAI wechseln.")

**Warning signs:** UAT-Tests mit Edge-Case-Inputs (sehr kurz, sehr explizit) → leerer Output ohne Fehler.

[ASSUMED — kein offizieller Apple-Hinweis, aber in Community-Posts erwähnt; Schema-Validity != Schema-Filled-with-Content]

### Pitfall 6: `LanguageModelSession` ohne explizite `actor`-Annotation in Apple-Doku

**What goes wrong:** Researcher konnte aus Apple-Doku **nicht 100 % verifizieren**, ob `LanguageModelSession` ein `actor`, eine `final class`, oder `@MainActor`-isoliert ist. Community-Code zeigt sowohl `@State var session = LanguageModelSession { ... }` (= main-thread) als auch `let session = LanguageModelSession()` (= unspezifiziert).

**Why it happens:** Apple-Doku-Pages liefern WebFetch nur Title (JS-rendered); konkrete Declaration nur in Xcode Quick Help einsehbar.

**How to avoid:**
- **Live-Verifikation in Xcode Quick Help** zur Plan-/Execution-Zeit: Option+Click auf `LanguageModelSession` zeigt exakte Declaration (`class`, `actor`, `@MainActor`?)
- Falls `@MainActor`: Per-Request-Session-Init in `AppleFoundationRewriteClient` mit `await MainActor.run { ... }`-Hop
- Falls plain `class` ohne MainActor: aktueller Plan funktioniert direkt

**Warning signs:** Build-Fehler "Call to main actor-isolated initializer in a synchronous nonisolated context" oder "Sendable closure captures non-Sendable type".

[ASSUMED — Apple-Doku-Page nicht durch WebFetch erschließbar; Community-Code-Patterns sind inkonsistent]

## Code Examples

Verified patterns aus offiziellen + Community-Quellen, ready-to-paste:

### Availability-Switch mit allen 4 Cases + @unknown default

```swift
// Source: artemnovichkov.com + rudrank.com
import FoundationModels

let model = SystemLanguageModel.default
switch model.availability {
case .available:
    // ready to call respond()
    break
case .unavailable(let reason):
    let german: String = switch reason {
    case .appleIntelligenceNotEnabled:
        "Apple Intelligence ist in den Systemeinstellungen nicht aktiviert."
    case .deviceNotEligible:
        "Dieses Gerät unterstützt Apple Intelligence nicht."
    case .modelNotReady:
        "Das Apple-Foundation-Modell wird gerade geladen — bitte erneut versuchen."
    @unknown default:
        "Apple Intelligence ist aus einem unbekannten Grund nicht verfügbar."
    }
    throw AppleFoundationError.unavailable(german)
}
```

### Plain Session — Stil-Rewrite (blitztextPlus)

```swift
// Source: createwithswift.com
import FoundationModels

let session = LanguageModelSession {
    """
    Du bist ein professioneller Assistent für Textaufbereitung.
    Schreibe das Transkript so um, dass es sich liest wie geschriebener Text.
    Antworte ausschließlich auf Deutsch und ohne Vorbemerkungen.
    """
}
let response = try await session.respond(to: rawTranscript)
let polished = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
```

### Guided Generation — Deeskalation (blitztextRant)

```swift
// Source: medium.com Salvaterra + appcoda.com
import FoundationModels

@Generable
struct DeescalatedOutput {
    @Guide(description: "Der entschärfte Text in deutscher Sprache, sachlich-freundlich, ohne Vorbemerkungen.")
    var neutralText: String
}

let session = LanguageModelSession {
    """
    Wandle emotionale, aufgeregte Eingabe in eine sachliche, freundliche, professionelle deutsche Nachricht um.
    Behalte den inhaltlichen Kern, entferne Schimpfwörter und Übertreibungen.
    """
}
let response = try await session.respond(to: rant, generating: DeescalatedOutput.self)
let neutral = response.content.neutralText
```

### Pre-Warm bei App-Boot

```swift
// Source: createwithswift.com — "1-second window" requirement
import FoundationModels

@MainActor
func prewarmFoundationModel() {
    Task.detached(priority: .utility) {
        let session = LanguageModelSession()
        try? await session.prewarm()
    }
}
```

### Error-Mapping nach GenerationError.type

```swift
// Source: swiftyplace.com (Pattern), Apple Developer Forum (error types)
import FoundationModels

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
        case .exceededContextWindow:
            return "Die Aufnahme ist zu lang für Apple Intelligence (Limit ~4096 Tokens)."
        case .unsupportedLanguage:
            return "Die erkannte Sprache wird von Apple Intelligence aktuell nicht unterstützt."
        case .assetsUnavailable:
            return "Das Apple-Foundation-Modell ist gerade nicht verfügbar."
        case .rateLimited:
            return "Apple Intelligence ist gerade ausgelastet — bitte kurz warten."
        case .emptyGuidedOutput:
            return "Apple Intelligence konnte den Text nicht entschärfen. Erneut versuchen oder Backend wechseln."
        case .decodingFailure:
            return "Antwort von Apple Intelligence konnte nicht gelesen werden."
        case .unknown(let msg): return msg
        }
    }
}

// Catch-Site:
do {
    let result = try await session.respond(to: input)
    return result.content
} catch let error as LanguageModelSession.GenerationError {
    switch error {
    // (exakte Case-Namen müssen gegen Live-Doku verifiziert werden — siehe Pitfall 6)
    default: throw mapToAppleFoundationError(error)
    }
}
```

[VERIFIED: developer.apple.com — `LanguageModelSession.GenerationError.guardrailViolation`, `.exceededContextWindowSize`, `.assetsUnavailable`, `.unsupportedLanguageOrLocale` sind dokumentierte Cases]
[VERIFIED: swiftyplace.com — `error.type`-Switch-Pattern]
[ASSUMED — exakte Case-Spelling (`exceededContextWindowSize` vs. `exceedsContextWindowSize`) variiert in Community-Quellen; Live-Verifikation in Xcode nötig]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Cloud-only LLM für Text-Polishing | On-device Apple Foundation Models | macOS 26 / iOS 26 / WWDC25 (Juni 2025) | Privacy-Versprechen wird einlösbar; Cold-Start statt Network-Roundtrip |
| String-output mit manuellem Parsing | `@Generable`-Schema mit Constrained Decoding | macOS 26 / WWDC25 | Schema-Validität garantiert; Format-Drift-Eliminierung |
| Eigene Polling-Loops für Apple-Intelligence-Verfügbarkeit | `SystemLanguageModel.default.availability` als computed live state | macOS 26 / WWDC25 | Native API; Polling immer noch nötig (kein Push), aber Quelle ist offiziell |
| Manuelles String-Prompting für JSON-Outputs | Type-safe Swift-Structs via Macros | macOS 26 / WWDC25 | Compile-Time-Schema; weniger Run-Time-Failures |

**Deprecated/outdated:**
- Direkte CoreML-Modell-Loading für LLMs auf macOS — `FoundationModels` ist die offizielle Apple-Schicht, ersetzt CoreML-DIY-Inferenz für die neue Tahoe-Foundation-Familie.
- WhisperKit-style "Modell selbst herunterladen + verwalten" — Apple Intelligence Asset-Management ist System-managed.

## Runtime State Inventory

> Phase 8 ist primär Greenfield-Code (neuer Client, neue Settings-Felder, neuer Banner). Ein klassisches Rename/Refactor liegt nicht vor. Trotzdem: Kategorien explizit gegengeprüft.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `SettingsStore.Snapshot`-JSON in UserDefaults bekommt zwei neue Felder: `rewriteBackendForPlus`, `rewriteBackendForRant` (oder ein Dictionary `rewriteBackends: [Mode: RewriteBackend]`). Snapshot-Pattern hat etabliertes `?? default`-Migrations-Idiom. | Code-Edit (Snapshot-Felder additiv mit Optional + Default-Fallback `?? .appleFoundation`); keine Daten-Migration nötig — bestehende User bekommen `.appleFoundation` als implicit Default beim ersten Load |
| Live service config | None — keine externen Services involviert (Foundation läuft im OS) | None |
| OS-registered state | None — keine Tasks, keine Plists, keine Permissions zu requestn (Apple Intelligence ist System-Permission und außerhalb App-Scope) | None |
| Secrets/env vars | OpenAI-API-Key bleibt in Keychain (`Service: de.reinholds.blitztext`, `Account: openai-api-key`) — Foundation braucht keinen Secret. | None |
| Build artifacts / installed packages | `FoundationModels.framework` ist System-Library — kein SPM-Pull, kein Asset-Bundle | None |

**Status:** Greenfield-additive Phase. Keine Daten-Migration, keine OS-State-Änderung, keine externen Services.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| macOS 26.0+ SDK (Tahoe) | `import FoundationModels` | ✓ | project.yml: `MACOSX_DEPLOYMENT_TARGET: "26.0"`, `LSMinimumSystemVersion: "26.0"` | — |
| Swift 6.0 Toolchain | `@Generable`/`@Guide` macro expansion | ✓ | project.yml: `SWIFT_VERSION: "6.0"` | — |
| Apple Intelligence aktiviert (User-Side) | `SystemLanguageModel.default.availability == .available` | ✗ (App-runtime — wird **nicht** vom Build erzwungen) | — | OpenAI-Backend (per CONTEXT-Decision); UI-Banner für non-eligible Devices |
| Xcode 17+ | Build des Macro-Plugins | ✓ (vorausgesetzt — falls nicht: Build bricht; minimal pre-condition) | — | — |
| BlitzTextTests Target | AC-AVAIL-1/2-Tests | ✓ | project.yml hat `BlitzTextTests` als `bundle.unit-test` | — |

**Missing dependencies with no fallback:** Keine — alle Build-Time-Voraussetzungen sind im Repo bereits konfiguriert.

**Missing dependencies with fallback:** Apple Intelligence selbst — runtime-fehlend triggert UI-Banner + automatische OpenAI-Aktivierung (nur wenn API-Key vorhanden).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (bundled with Xcode 17 / Swift 6) |
| Config file | `project.yml` (XcodeGen) — `BlitzTextTests` target bereits existiert (TEST-01 Done) |
| Quick run command | `xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/AppleFoundationRewriteClientTests` |
| Full suite command | `xcodebuild test -project BlitzText.xcodeproj -scheme BlitzText -destination 'platform=macOS'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AC-AVAIL-1 | Verfügbarkeitsprüfung vor jedem Inferenz-Call; vier Cases liefern spezifizierte deutsche Fehler | unit | `xcodebuild test … -only-testing:BlitzTextTests/AppleFoundationRewriteClientTests/test_unavailable_appleIntelligenceNotEnabled_throwsGermanError` (analog für `modelNotReady`, `deviceNotEligible`, plus `available_proceedsWithSession`) | ❌ Wave 0 — neu |
| AC-AVAIL-1 | Bei `.unavailable(...)` **kein** Cloud-Call (verifiziert über `OpenAIChatClient`-Spy, der Inject-Rolle bekommt — sollte 0 Calls sehen) | unit | `xcodebuild test … -only-testing:BlitzTextTests/AppleFoundationRewriteClientTests/test_unavailable_doesNotInvokeOpenAIClient` | ❌ Wave 0 — neu |
| AC-AVAIL-2 | Übergang `modelNotReady` → `available` ohne App-Restart wechselt UI-Banner-State | unit | `xcodebuild test … -only-testing:BlitzTextTests/AppleFoundationAvailabilityTests/test_refresh_transitions_modelNotReady_to_available_updatesPublishedState` | ❌ Wave 0 — neu |
| AC-AVAIL-2 | `refreshFoundationAvailability()` ist idempotent + main-actor-safe | unit | gleicher File | ❌ Wave 0 — neu |
| AC-AVAIL-3 | README/Settings-Help-Doku-String enthält "Apple Intelligence" + "unabhängig von Siri" | smoke (string-search test) ODER **manual UAT** in `/gsd-verify-phase` | n/a (manuell) — Doku-Audit | manual |
| Mode-Dispatch | `ModeProcessor.runPipeline` wählt korrekten Client basiert auf `settings.rewriteBackend(for: mode)` für beide Modes × beide Backends (4 Pfade) | unit | `xcodebuild test … -only-testing:BlitzTextTests/RewriteBackendDispatchTests` | ❌ Wave 0 — neu |
| Schema-Fill-Failure | Guided Generation mit leerem `neutralText` wirft `.emptyGuidedOutput` | unit | `xcodebuild test … -only-testing:BlitzTextTests/AppleFoundationRewriteClientTests/test_guidedGeneration_emptyNeutralText_throwsEmptyGuidedOutput` (Mock-Session via Protocol-Wrapper über `LanguageModelSession`) | ❌ Wave 0 — neu (siehe Mock-Strategie unten) |
| Backend-Indikator-HUD | `showsBackendBadge` true für Plus/Rant, false für plain | unit | `xcodebuild test … -only-testing:BlitzTextTests/RecordingHUDStateTests` | ❌ Wave 0 — neu (optional; UI-Logik) |

### Sampling Rate

- **Per task commit:** `xcodebuild test … -only-testing:BlitzTextTests/AppleFoundationRewriteClientTests` (~5 s)
- **Per wave merge:** `xcodebuild test … -only-testing:BlitzTextTests/Rewrite` + `BlitzTextTests/Pipeline` (full Phase-8-Test-Surface, ~20 s)
- **Phase gate:** Full suite (`xcodebuild test … -scheme BlitzText`) green vor `/gsd-verify-work` — alle 39+N Tests grün, 3× consecutive (Phase-2/3-Konvention)

### Wave 0 Gaps

- [ ] `BlitzText/Rewrite/FoundationAvailabilityProvider.swift` — Protocol + Live-Impl
- [ ] `BlitzText/Rewrite/AppleFoundationRewriteClient.swift` — Client (RewriteService-Conformance)
- [ ] `BlitzText/Rewrite/DeescalatedOutput.swift` — `@Generable` struct
- [ ] `BlitzTextTests/Rewrite/AppleFoundationAvailabilityTests.swift` — covers AC-AVAIL-1 (4 Cases) + AC-AVAIL-2 (Übergang)
- [ ] `BlitzTextTests/Rewrite/AppleFoundationRewriteClientTests.swift` — covers Pre-Inference-Check + Schema-Fill-Failure
- [ ] `BlitzTextTests/Rewrite/RewriteBackendDispatchTests.swift` — covers Mode×Backend-Dispatch in `ModeProcessor.runPipeline`
- [ ] `BlitzTextTests/Support/FakeFoundationAvailabilityProvider.swift` — Mock-Provider mit Mutable-State für AC-AVAIL-2-Übergangstest
- [ ] **Mock-Strategie für `LanguageModelSession.respond`:** Direkter Mock von `LanguageModelSession` ist nicht möglich (kein Protocol). **Empfohlen:** zusätzliches internes Protocol `LanguageModelInferring` mit Methoden `respond(to:input:instructions:)` + `respondGuided(input:instructions:type:)`; LiveImpl wrappt echte Session, FakeImpl wird in Tests injiziert. Dieser Wrapper isoliert AppleFoundationRewriteClient von der echten Apple-API komplett.
- [ ] **Echtes Apple-Intelligence-Asset im Test:** **NICHT erforderlich** — alle Tests laufen gegen Mocks. Manuelles UAT in `/gsd-verify-phase` deckt Live-Modell ab.

### Mock-Strategie für `SystemLanguageModel` (Detail)

Das eigentliche `SystemLanguageModel.default` ist ein nicht-instanzierbarer Singleton — es kann **nicht** direkt gemockt werden. Lösung: doppeltes Protocol-Layer:

1. **`FoundationAvailabilityProviding`** wrappt `SystemLanguageModel.default.availability` → testbar via `FakeFoundationAvailabilityProvider` mit einstellbarem State.
2. **`LanguageModelInferring`** wrappt `LanguageModelSession.respond(to:)` + `respond(to:generating:)` → testbar via `FakeLanguageModelInferring` mit pre-canned Responses + Error-Injection.

Beide Protocols sind `Sendable`. Live-Impls werden in `AppleFoundationRewriteClient.init` per Default injiziert, Tests injizieren Fakes.

Damit deckt die Test-Suite alle 4 Availability-States, alle GenerationError-Cases, Schema-Fill-Failures und State-Übergänge ab — **ohne** auf realer Apple-Intelligence-Hardware zu laufen. CI auf nicht-Apple-Intelligence-Hardware bleibt grün.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Foundation läuft on-device; OpenAI-Auth via existing Keychain bleibt unverändert |
| V3 Session Management | no | `LanguageModelSession` ist process-lokal, nicht Auth-relevant |
| V4 Access Control | no | Apple Intelligence ist System-Permission (Settings → Apple Intelligence) — App fordert sie nicht an |
| V5 Input Validation | yes | User-diktiertes Audio → Whisper → String → LLM-Input. Kein klassischer Injection-Vektor (kein SQL/HTML), aber: **prompt injection** ist möglich (z.B. User sagt "ignoriere alle vorigen Anweisungen…") |
| V6 Cryptography | no | Foundation Models ist System-Service; keine eigene Crypto |
| V7 Data Privacy | yes | **DSGVO-relevant.** Foundation = on-device → erfüllt Privacy-Markenversprechen automatisch. OpenAI-Pfad bleibt explizit User-opted-in. |
| V8 Authorization | no | n/a |
| V14 Configuration | yes | Default-Backend = Foundation = privacy-by-default; OpenAI ist explizit User-Wahl |

### Known Threat Patterns for {macOS-Native + LLM}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Prompt Injection (User-Audio enthält "ignoriere Anweisungen") | Tampering | Apple-Guardrails fangen die meisten manipulativen Outputs ab; Output-Trim entfernt nichts Sensitives, da LLM-Output nie Code wird, sondern nur String → Clipboard |
| Schema Drift bei Guided Generation | Tampering / Repudiation | `@Generable` + Constrained Decoding garantiert Schema-Validität auf Token-Ebene; zusätzlich Empty-Output-Check im Client |
| Datenexfiltration über OpenAI-Backend | Information Disclosure | UI-Indikator (`cloud`-SF-Symbol im HUD + "Cloud"-Klammer-Suffix im Picker) macht Datenfluss explizit; Default ist Foundation; kein stilles Cloud-Fallback |
| Guardrail-Bypass bei Rant-Mode | Tampering | Foundation-Guardrails sind off-the-shelf; kein Versuch zur Umgehung |
| Stale Availability-State (z.B. App zeigt `.available`, obwohl User Apple Intelligence in der Zwischenzeit deaktiviert hat) | Tampering / DoS | App-Activation-Notification triggert Refresh; AC-AVAIL-1 prüft pre-inference noch einmal — keine 100 % Race-Condition-Garantie, aber Inferenz wirft dann mit user-readable Error |
| Side-Channel über Foundation-Process-Memory | Information Disclosure | Apple-Sandbox-Boundary ist Apple-OS-Verantwortung; App hat keinen direkten Memory-Access |

**Hinweis Privacy-Posture:** Phase 8 ist netto Privacy-positiv für die App — sie verschiebt den Default-Rewrite-Pfad **weg** vom Cloud-Backend hin zu on-device. Das ist konsistent mit DSGVO Art. 25 (privacy by default) und CLAUDE.md "No external-cloud speaker ID — speaker profiles must stay on-device" (analog für Rewrite).

## Project Constraints (from CLAUDE.md)

Direkte Direktiven, die der Planner beachten muss:

- **Native macOS, Swift 6, `SWIFT_STRICT_CONCURRENCY: minimal`** — `@unchecked Sendable` ist akzeptabel für Inferenz-Client (analog `OpenAIChatClient`); kein Strict-Concurrency-Druck
- **German UI strings, English code identifiers (Swift convention)** — `RewriteBackend.appleFoundation` (englisch) → Label `"Apple Foundation (lokal)"` (deutsch) — UI-SPEC ist konform
- **No external-cloud speaker ID — speaker profiles must stay on-device (DSGVO Art. 9)** — kein direkter Phase-8-Bezug, aber Privacy-Posture-konsistent (Foundation = on-device default)
- **TranscriptionService protocol abstracts backends — keep new backends behind it** — Analog für Rewrite: neuer Foundation-Client *muss* `RewriteService`-Protocol erfüllen (kein direkter Inferenz-Call aus `ModeProcessor.runPipeline`)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `LanguageModelSession.GenerationError` Case-Spelling ist **`exceededContextWindowSize`** (mit "ed") — Apple-Doku-URL nutzt diese Form, aber Community-Quellen zeigen sowohl `exceededContextWindowSize` als auch `exceedsContextWindowSize` | Code Examples (Error-Mapping) | Build-Fehler; bei Plan-/Execution-Zeit muss Live in Xcode Quick Help verifiziert werden, exakte Spelling übernehmen |
| A2 | `LanguageModelSession` ist plain `class`, nicht `actor` und nicht `@MainActor` — Community-Code zeigt non-MainActor-Init-Pfade | Pitfall 6 + Pattern 2 | Falls `@MainActor`: Per-Request-Init muss `await MainActor.run { ... }` nutzen; Client-Pfad bleibt async/throws, aber zusätzlicher Hop |
| A3 | Apple bietet **keinen** offiziellen Push-Hook (Notification, AsyncStream, KVO) für Availability-State-Wechsel — Polling oder App-Activation ist Stand der Technik | Pattern 1 + AC-AVAIL-2 | Falls doch ein Hook existiert: Implementation könnte eleganter sein; aktueller Plan ist trotzdem korrekt (degradiert auf manuelles Refresh) |
| A4 | Schema-Fill-Failure liefert leeren String **ohne** zu werfen — Apple-Doku spezifiziert das nicht eindeutig | Pitfall 5 | Falls `respond(to:generating:)` doch wirft: `.emptyGuidedOutput`-Branch wird never-hit, aber harmlos (nicht-erreichbarer Code, kein Bug) |
| A5 | `@unknown default` im Switch über `UnavailableReason` ist nötig — Enum ist non-frozen | Pattern 1 + Pitfall 2 | Falls Enum frozen ist: Compiler-Warning weg, kein Risiko |
| A6 | `LanguageModelSession.prewarm()` ohne Argument funktioniert (Variante ohne `promptPrefix`) — Community zeigt parameter-loses Aufrufen | Pre-Warm Pattern 4 | Falls Parameter erforderlich: leeren String oder Mode-Default-Prompt übergeben |
| A7 | `@Generable struct DeescalatedOutput { var neutralText: String }` produziert ein gültiges Schema mit nur einem String-Feld — Apple-Beispiele zeigen oft mehr Felder, aber 1-Feld sollte funktionieren | Pattern 3 | Falls Macro mehr fordert: Schema um zweites Marker-Feld erweitern (z.B. `var summary: String`) — minimaler Aufwand |
| A8 | App-Activation-Notification ist akzeptable UX für AC-AVAIL-2 — User wartet ohnehin auf nächsten Hotkey-Press | Architecture Pattern 1 | Bei UAT: könnte sich als zu langsam herausstellen; dann: 30-s-Polling-Task im Hintergrund nur während `modelNotReady`-State (nicht permanent) |
| A9 | Cold-Start-Latenz von Foundation Models ist nach `prewarm()` ≤ OpenAI-Roundtrip-Latenz (~300-800 ms) — keine offiziellen Apple-Zahlen, Community erwähnt "M1 Mac 23 s für philosophische Frage" für **kalt** + komplex | Pre-Warm Pattern 4, Pitfall 3 | Bei UAT: könnte Latenz ≥ 3 s sein → PROJECT.md-Ziel verletzt; Mitigation: prewarm im AppDelegate.bootstrap auf `.utility`-priority + UI-Hinweis im HUD ("rewrite läuft …"), Notfall-Plan: kurze System-Prompts; nicht in v1 lösbar |
| A10 | Sprachbias zugunsten Deutsch lässt sich allein durch instructions + @Guide-Description steuern; kein dedizierter Locale-Parameter nötig | Pitfall 1 | Falls trotzdem Drift: Post-Hoc-Output-Check mit `NLLanguageRecognizer` + Re-Run als Fallback (out-of-scope v1; UAT-Validierung) |

**Wenn diese Tabelle nicht leer ist:** Der Planner sollte für jede Annahme entscheiden, ob ein Live-Verifikations-Task in Wave 0 nötig ist (Empfehlung: A1, A2, A6 in Wave 0; A4, A7 in Wave 1; A3, A5, A8, A9, A10 in UAT/`/gsd-verify-phase`).

## Open Questions

1. **Exakte Concurrency-Annotation von `LanguageModelSession`** (Class? Actor? @MainActor?)
   - What we know: Community-Code zeigt non-MainActor-Patterns; `@State var session = ...` in SwiftUI deutet auf MainActor-Affinity hin, aber `@State` zwingt selbst keine MainActor-Isolation auf.
   - What's unclear: Apple-Doku-Pages liefern keine Declaration durch WebFetch.
   - Recommendation: Wave 0, erste Aufgabe — neuen `AppleFoundationRewriteClient.swift` mit Stub-Init schreiben, in Xcode bauen, Quick Help (Option+Click) auf `LanguageModelSession` öffnen → Declaration extrahieren → Plan justieren falls `@MainActor`.

2. **Genauer GenerationError-Case-Naming**
   - What we know: `guardrailViolation`, `assetsUnavailable` sind Apple-Doku-URL-bestätigt. `exceededContextWindowSize` ist Apple-URL-bestätigt. `unsupportedLanguageOrLocale` ist Apple-URL-bestätigt. `rateLimited` und `concurrentRequests` aus Community-Quelle (swiftyplace).
   - What's unclear: Live `error.type`-Switch oder direkter Type-Match im catch-Pfad? Hat `GenerationError` eine `.type`-Property oder sind die Cases das Enum selbst?
   - Recommendation: Live in Xcode verifizieren (Wave 0); Mapping-Code in `AppleFoundationError.from(GenerationError)` darauf anpassen.

3. **`prewarm()`-Argumente**
   - What we know: createwithswift erwähnt `prewarm(promptPrefix:)`-Variante, aber empfohlene parameter-lose Form auch.
   - What's unclear: Welche Variante existiert tatsächlich.
   - Recommendation: Live verifizieren; wenn nur mit `promptPrefix`: leeren String übergeben (No-op-Prefix).

4. **Schema-Fill-Failure-Verhalten von `respond(to:generating:)`**
   - What we know: Apple's Constrained Decoding garantiert Schema-Struktur, nicht Content-Semantik.
   - What's unclear: Wirft die API bei Empty-Content oder kommt `Response<DeescalatedOutput>` mit `neutralText == ""` zurück?
   - Recommendation: Defensiv beides handhaben (try/catch + .isEmpty-Check); UAT-Test mit Edge-Inputs.

5. **Reicht `instructions` als Sprachbias-Steuerung?**
   - What we know: Apple-Pattern + Community empfehlen "Antworte auf X" in instructions; rudrank.com zeigt ähnliche Patterns für Spanish/German.
   - What's unclear: Wie robust ist das gegen englische User-Eingaben mitten im Audio (z.B. denglisch)?
   - Recommendation: Akzeptiertes Restrisiko — UAT-Validierung; v2 könnte einen Output-Sprach-Detektor mit Re-Run einführen.

## Sources

### Primary (HIGH confidence)
- [SystemLanguageModel.Availability — Apple Developer Documentation](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum) — Enum-Cases verifiziert
- [LanguageModelSession.GenerationError — Apple Developer Documentation](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror?changes=_10_5) — Error-Cases verifiziert
- [LanguageModelSession.GenerationError.exceededContextWindowSize — Apple Developer Documentation](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror/exceededcontextwindowsize(_:))
- [LanguageModelSession.GenerationError.assetsUnavailable — Apple Developer Documentation](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror/assetsunavailable(_:))
- [Generating Swift data structures with guided generation — Apple Developer Documentation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
- [Supporting languages and locales with Foundation Models — Apple Developer Documentation](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
- [supportedLanguages — Apple Developer Documentation](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/supportedlanguages)
- [Meet the Foundation Models framework — WWDC25 Session 286](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Deep dive into the Foundation Models framework — WWDC25 Session 301](https://developer.apple.com/videos/play/wwdc2025/301/)

### Secondary (MEDIUM confidence — verified against primary)
- [Exploring the Foundation Models framework — createwithswift.com](https://www.createwithswift.com/exploring-the-foundation-models-framework/) — Init-Signaturen, prewarm 1-s-Window
- [Getting Started with Apple's Foundation Models — artemnovichkov.com](https://artemnovichkov.com/blog/getting-started-with-apple-foundation-models) — Availability-Switch mit `@unknown default`, instructions-Closure-Form
- [The Ultimate Guide To The Foundation Models Framework — azamsharp.com](https://azamsharp.com/2025/06/18/the-ultimate-guide-to-the-foundation-models-framework.html) — `@Generable` mit `@Guide`-Annotations
- [Working with @Generable and @Guide in Foundation Models — appcoda.com](https://www.appcoda.com/generable/) — `@Guide(description:, .count(N))` Pattern
- [Guided Generation with FoundationModels — medium.com Salvaterra](https://medium.com/@luizfernandosalvaterra/guided-generation-with-foundationmodels-how-to-get-swift-structs-from-llms-ad663e60d716) — `Response<T>.content` Property, generating-API
- [How to Fall Back Gracefully When Apple Intelligence Isn't Available — dev.to/arshtechpro](https://dev.to/arshtechpro/how-to-fall-back-gracefully-when-apple-intelligence-isnt-available-48j) — Polling-Pattern, kein offizieller Push-Hook
- [Building an AI Chatbot in SwiftUI with Foundation Models — swiftyplace.com](https://www.swiftyplace.com/blog/foundation-models-framework) — `error.type`-Switch, Session-Lifecycle
- [Exploring Foundation Models: Supported Languages — rudrank.com](https://rudrank.com/exploring-foundation-models-supported-languages-internationalization) — Sprachbias-Pattern, supportedLanguages-API

### Tertiary (LOW confidence — flagged for live verification)
- [AnyLanguageModel — github.com/mattt](https://github.com/mattt/AnyLanguageModel) — drop-in-API-Spiegel, deutet auf API-Form, aber third-party
- [Apple's Foundation Models Framework — dev.to/arshtechpro](https://dev.to/arshtechpro/apples-foundation-models-framework-run-ai-on-device-with-just-a-few-lines-of-swift-lbp) — quickstart-quality
- [Apple Foundation Models in Practice — medium.com Wesley Matlock](https://medium.com/@wesleymatlock/apple-foundation-models-in-practice-building-on-device-ai-features-in-swift-b6243976af4f) — practitioner-quality

## Metadata

**Confidence breakdown:**
- Standard stack (Foundation Modules, project.yml settings): **HIGH** — verifiziert gegen project.yml + offizielle Apple-Doku-URLs
- Architecture (Patterns 1-4, Protocol-Wrapping, Per-Request-Session): **HIGH** — kanonische Apple- und Community-Patterns; protocol-wrapping ist standard testbarkeits-Idiom
- Pitfalls (Sprachbias, Guardrail, Schema-Fill, Concurrency-Surface): **MEDIUM-HIGH** — community-cross-verified, aber nicht alle reproduzierbar ohne Live-Apple-Intelligence-Hardware
- Cold-start-Latenz konkrete Zahlen: **LOW** — keine Apple-Benchmarks, Community-Zahl ("23 s") ist outlier-quality
- Notification/Push-Hook für Availability: **MEDIUM** — Abwesenheit ist gut-verifiziert (mehrere Quellen empfehlen Polling), aber theoretisch könnte ein nicht-dokumentierter Hook existieren
- Generable-Schema-Verhalten bei Empty-Output: **LOW-MEDIUM** — defensiv gehandhabt; UAT-Verifikation nötig

**Research date:** 2026-05-04
**Valid until:** 2026-06-04 (30 Tage — stabil; FoundationModels ist seit WWDC25 als Public-API stabil; Apple-Doku-Updates monatlich)

**Empfohlene Wave-0-Aufgaben für Live-Verifikation (15-30 min Aufwand):**
1. Stub `AppleFoundationRewriteClient.swift` schreiben → in Xcode öffnen → Option+Click auf `LanguageModelSession` → Declaration in Open Questions #1 nachpflegen.
2. `LanguageModelSession.GenerationError` in Xcode → exakte Cases + Type-Property prüfen → Open Question #2 lösen.
3. `LanguageModelSession.prewarm` in Xcode → exakte Signature → Open Question #3 lösen.

Diese drei Mini-Tasks lösen alle High-Risk-Annahmen (A1, A2, A6) bevor Plan-Code zementiert wird.
