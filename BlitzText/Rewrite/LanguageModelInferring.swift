import Foundation
import FoundationModels

/// Test-Seam für `LanguageModelSession`. Production-Default wrappt echte Sessions
/// per-Request (stateless, RESEARCH.md Anti-Pattern: keine app-wide cached Session).
/// Tests injizieren `FakeLanguageModelInferring` mit pre-canned Responses.
///
/// PIN(A1) verifiziert in 08-RESEARCH-LIVE.md: `LanguageModelSession` ist
/// `final class`, **non-MainActor**; `respond(to:)` ist `nonisolated(nonsending)` —
/// kein `@MainActor.run`-Hop nötig.
protocol LanguageModelInferring: Sendable {
    func respond(input: String, instructions: String) async throws -> String
    func respondGuided<T: Generable>(input: String, instructions: String, type: T.Type) async throws -> T
}

/// Production-Implementation. Allokiert eine frische `LanguageModelSession`
/// pro Request — stateless, kein Caching app-wide.
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
