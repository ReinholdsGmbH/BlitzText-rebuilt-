import Foundation

/// Umformulieren über OpenRouter oder Requesty, beide im OpenAI-Format. Schlüssel und Modell
/// kommen aus den Zugängen unter Einstellungen › Modelle, dieselben wie für die
/// Meeting-Zusammenfassung.
struct ProviderRewriteClient: RewriteService {
    let provider: SummaryProvider
    let apiKey: String
    let model: String

    func rewrite(input: String, systemPrompt: String, model _: String) async throws -> String {
        try await OpenAICompatibleChat(provider: provider, apiKey: apiKey, model: model)
            .complete(system: systemPrompt, user: wrapTranscriptForPrompt(input))
    }
}
