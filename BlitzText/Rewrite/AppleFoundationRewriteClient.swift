import Foundation
import FoundationModels

/// Apple Foundation Models Rewrite-Client (macOS 26+). Plain Session für `blitztextPlus`,
/// Guided Generation (`@Generable`/`DeescalatedOutput`) für `blitztextRant`.
///
/// AC-AVAIL-1: defensive Verfügbarkeitsprüfung **vor jedem** Inferenz-Call —
/// `currentAvailability() != .available` führt zu sofortigem Throw OHNE Inferenz.
/// Die zwei Pfade (`rewrite` plain / `rewriteGuided` schema) leben hier nebeneinander;
/// `ModeProcessor` wählt den passenden Pfad pro Mode (Plain für Plus, Guided für Rant).
///
/// Sendable-Form `final class … @unchecked Sendable` analog `OpenAIChatClient`
/// (Bestand-Konvention; PIN(A1) verifiziert: `LanguageModelSession` ist non-MainActor).
final class AppleFoundationRewriteClient: RewriteService, @unchecked Sendable {

    private let availabilityProvider: FoundationAvailabilityProviding
    private let inferring: LanguageModelInferring

    init(
        availabilityProvider: FoundationAvailabilityProviding = SystemLanguageModelAvailabilityProvider(),
        inferring: LanguageModelInferring = LiveLanguageModelInferring()
    ) {
        self.availabilityProvider = availabilityProvider
        self.inferring = inferring
    }

    // MARK: - RewriteService (Plain-Pfad für blitztextPlus)

    func rewrite(input: String, systemPrompt: String, model: String) async throws -> String {
        // AC-AVAIL-1: pre-inference availability check.
        let availability = availabilityProvider.currentAvailability()
        guard availability == .available else {
            throw AppleFoundationError.from(availability)
        }
        do {
            let raw = try await inferring.respond(input: input, instructions: systemPrompt)
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let err as LanguageModelSession.GenerationError {
            throw mapGenerationError(err)
        }
    }

    // MARK: - Guided-Pfad für blitztextRant

    /// Wird von `ModeProcessor` für `.blitztextRant + .appleFoundation` aufgerufen
    /// (separate Methode, weil `RewriteService.rewrite(...)` keinen Mode-Parameter
    /// hat und Guided Generation einen anderen Pfad hat als Plain Session).
    /// Wirft `AppleFoundationError.emptyGuidedOutput`, wenn das Schema-Feld
    /// `neutralText` nach dem Trim leer ist (T-08-03-03).
    func rewriteGuided(input: String, systemPrompt: String) async throws -> String {
        // AC-AVAIL-1: pre-inference availability check.
        let availability = availabilityProvider.currentAvailability()
        guard availability == .available else {
            throw AppleFoundationError.from(availability)
        }
        do {
            let result = try await inferring.respondGuided(
                input: input,
                instructions: systemPrompt,
                type: DeescalatedOutput.self
            )
            let trimmed = result.neutralText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw AppleFoundationError.emptyGuidedOutput }
            return trimmed
        } catch let err as LanguageModelSession.GenerationError {
            throw mapGenerationError(err)
        }
    }

    // MARK: - GenerationError → AppleFoundationError-Mapping

    /// Mappt `LanguageModelSession.GenerationError` (9 Cases per PIN(A2) in
    /// 08-RESEARCH-LIVE.md) auf user-facing `AppleFoundationError`-Cases.
    /// `@unknown default` schützt gegen zukünftige Apple-API-Drift (T-08-03-05).
    private func mapGenerationError(_ err: LanguageModelSession.GenerationError) -> AppleFoundationError {
        switch err {
        case .exceededContextWindowSize:    return .exceededContextWindow
        case .assetsUnavailable:            return .assetsUnavailable
        case .guardrailViolation:           return .guardrailViolation
        case .unsupportedGuide:             return .decodingFailure   // Schema-Bug, Dev-side
        case .unsupportedLanguageOrLocale:  return .unsupportedLanguage
        case .decodingFailure:              return .decodingFailure
        case .rateLimited:                  return .rateLimited
        case .concurrentRequests:           return .rateLimited       // semantisch ähnlich für User
        case .refusal:                      return .guardrailViolation
        @unknown default:                   return .unknown(err.localizedDescription)
        }
    }
}
