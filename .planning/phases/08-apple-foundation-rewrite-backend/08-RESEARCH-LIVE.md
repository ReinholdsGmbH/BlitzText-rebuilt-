# Phase 8 — Research Live-Verification Addendum

**Verified:** 2026-05-04
**Host:** macOS 26.4.1 (Build 25E253), Xcode 26.4.1, Swift 6.3.1 (target arm64-apple-macosx26.0)
**SDK:** `MacOSX26.4.sdk` → `FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-macos.swiftinterface`
**Probe-Method:** Mini-Snippets unter `/tmp/blitz-probes/*.swift` mit `swiftc -typecheck` gegen aktuelles SDK; zusätzlich direkte Inspektion der `swiftinterface` (kanonische Apple-Declaration). Probe-Files wurden nach Verifikation gelöscht (`rm -rf /tmp/blitz-probes`); keine Pollution unter `BlitzText/Rewrite/`.
**Build-Probe-Logs:** `/tmp/probe-A1-A2.log`, `/tmp/probe-A1-strict.log`, `/tmp/probe-A2-full.log`, `/tmp/probe-A2-type.log`, `/tmp/probe-A6.log`

---

## A1 — LanguageModelSession Concurrency

**Status:** verified

**Result:** plain `final class`, kein `@MainActor`, kein `actor` — A1-Hypothese verifiziert. Init und `respond(to:)` sind aus non-isolated Funktionen aufrufbar; `swiftc -strict-concurrency=complete` meldet weder Fehler noch Warnings.

**Quick-Help-Snippet (aus `arm64e-apple-macos.swiftinterface` Zeile 321):**

```swift
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
final public class LanguageModelSession {

  // Init-Varianten (Zeile 339–342):
  @_disfavoredOverload convenience public init(
      model: SystemLanguageModel = .default,
      tools: [any Tool] = [],
      instructions: String? = nil)
  convenience public init(
      model: SystemLanguageModel = .default,
      tools: [any Tool] = [],
      @InstructionsBuilder instructions: () throws -> Instructions) rethrows
  convenience public init(
      model: SystemLanguageModel = .default,
      tools: [any Tool] = [],
      instructions: Instructions? = nil)

  // respond-Variante (Zeile 354) — non-MainActor, "nonisolated(nonsending)":
  nonisolated(nonsending) final public func respond(
      to prompt: Prompt,
      options: GenerationOptions = GenerationOptions()
  ) async throws -> Response<String>
}
```

**Begründung — warum non-MainActor:**

- Class-Declaration enthält keine `@MainActor`-, `@globalActor`- oder `actor`-Annotation.
- `respond(...)` ist explizit `nonisolated(nonsending)` annotiert — moderne Swift-6.3-Form, die garantiert keine Actor-Isolation einführt (das ist sogar **stärker** als die Hypothese aus 08-RESEARCH.md A2: nicht nur "kein MainActor", sondern explizit non-isolated).
- Live-Probe `swiftc -typecheck -strict-concurrency=complete /tmp/blitz-probes/A1_concurrency.swift` → exit 0, keine Diagnostiken (siehe `/tmp/probe-A1-strict.log`).

**PIN für Wave 1:** `// PIN(A1): LanguageModelSession is final class, non-MainActor, respond is nonisolated(nonsending) — re-evaluate if API changes`

**Konsequenz für Wave 1 (LanguageModelInferring.swift Live-Impl):**

- `struct LiveLanguageModelInferring: LanguageModelInferring` darf `LanguageModelSession(instructions: { instructions })` direkt aus jeder Methode aufrufen — **kein** `await MainActor.run { ... }`-Hop nötig.
- `final class AppleFoundationRewriteClient: RewriteService, @unchecked Sendable` ist die korrekte Form (Bestand-Konvention analog `OpenAIChatClient`).

---

## A2 — GenerationError Case-Spelling + .type-Property

**Status:** corrected

**Result:**

- ✅ `exceededContextWindowSize` mit "ed" — Hypothese verifiziert.
- ✅ `guardrailViolation`, `unsupportedLanguageOrLocale`, `assetsUnavailable`, `rateLimited`, `decodingFailure` — alle Hypothese-Cases existieren.
- ⚠ **Korrektur 1:** ALLE Cases tragen einen assoziierten `Context`-Wert (für `refusal`: `(Refusal, Context)`). Pattern-Matching ohne Tuple (`case .exceededContextWindowSize:`) funktioniert zwar, aber Mapper kann den `Context`-Wert für Diagnostik nutzen (`debugDescription`).
- ⚠ **Korrektur 2:** Es gibt **drei zusätzliche, in 08-RESEARCH.md NICHT gelistete Cases** — `unsupportedGuide(Context)`, `concurrentRequests(Context)`, `refusal(Refusal, Context)`. Mapper-Switch im `AppleFoundationError.from(GenerationError)` muss diese auch abdecken.
- ❌ **`.type`-Property existiert NICHT.** Direkter Zugriff `err.type` schlägt mit Compiler-Fehler `value of type 'LanguageModelSession.GenerationError' has no member 'type'` fehl. Switch über die Cases ist der einzige Weg.
- ✅ Enum ist non-frozen — `@unknown default` ist erforderlich (Compiler verlangt es: `note: handle unknown values using "@unknown default"`).

**Quick-Help-Snippet (aus `arm64e-apple-macos.swiftinterface` Zeile 405–432, gekürzt):**

```swift
public enum GenerationError : Swift.Error, Foundation.LocalizedError {
    public struct Context : Swift.Sendable {
        public let debugDescription: Swift.String
        public init(debugDescription: Swift.String)
    }
    public struct Refusal : Swift.Sendable {
        public init(transcriptEntries: [Transcript.Entry])
        public var explanation: LanguageModelSession.Response<String> { get async throws }
        public var explanationStream: LanguageModelSession.ResponseStream<String> { get }
    }
    case exceededContextWindowSize(Context)
    case assetsUnavailable(Context)
    case guardrailViolation(Context)
    case unsupportedGuide(Context)
    case unsupportedLanguageOrLocale(Context)
    case decodingFailure(Context)
    case rateLimited(Context)
    case concurrentRequests(Context)
    case refusal(Refusal, Context)
}
```

**Compiler-Diagnostik aus Live-Probe (`/tmp/probe-A2-full.log`):**

```text
error: switch must be exhaustive
  note: add missing case: '.assetsUnavailable(_)'
  note: add missing case: '.guardrailViolation(_)'
  note: add missing case: '.unsupportedGuide(_)'
  note: add missing case: '.unsupportedLanguageOrLocale(_)'
  note: add missing case: '.decodingFailure(_)'
  note: add missing case: '.rateLimited(_)'
  note: add missing case: '.concurrentRequests(_)'
  note: add missing case: '.refusal(_, _)'
  note: handle unknown values using "@unknown default"
```

**Compiler-Diagnostik für `.type` (`/tmp/probe-A2-type.log`):**

```text
error: value of type 'LanguageModelSession.GenerationError' has no member 'type'
```

**PIN für Wave 1:** `// PIN(A2): GenerationError cases all carry (Context); add unsupportedGuide(_), concurrentRequests(_), refusal(_, _); .type does not exist — use switch with @unknown default — re-evaluate if API changes`

**Konsequenz für Wave 1 (`AppleFoundationError.from(_:)` Mapper):**
Die Wave-1-Mapper-Skizze aus 08-PATTERNS.md (Shared Pattern 1) muss um diese drei Cases erweitert werden. Empfehlung als Vorlage:

```swift
extension AppleFoundationError {
    static func from(_ generation: LanguageModelSession.GenerationError) -> AppleFoundationError {
        switch generation {
        case .exceededContextWindowSize:    return .exceededContextWindow
        case .assetsUnavailable:            return .assetsUnavailable
        case .guardrailViolation:           return .guardrailViolation
        case .unsupportedGuide:             return .decodingFailure  // Schema-Bug, Dev-side
        case .unsupportedLanguageOrLocale:  return .unsupportedLanguage
        case .decodingFailure:              return .decodingFailure
        case .rateLimited:                  return .rateLimited
        case .concurrentRequests:           return .rateLimited      // semantisch ähnlich für User
        case .refusal:                      return .guardrailViolation
        @unknown default:                   return .unknown("Unbekannter Apple-Fehler")
        }
    }
}
```

Das Wave-1-`AppleFoundationError`-Enum braucht (gegenüber RESEARCH.md Code Examples) **keine** zusätzlichen Cases — `unsupportedGuide` mappt sinnvoll auf `decodingFailure` (Schema-Mismatch), `concurrentRequests` auf `rateLimited` (User-Erfahrung praktisch identisch), `refusal` auf `guardrailViolation`. Plan kann unverändert bleiben, nur der Mapper bekommt drei zusätzliche `case`-Zeilen.


> **Task 2 Status:** A6 + Wave 0 Sign-Off pending — wird im nächsten Commit ergänzt.
