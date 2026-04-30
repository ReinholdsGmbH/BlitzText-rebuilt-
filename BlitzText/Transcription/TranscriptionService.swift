import Foundation

protocol TranscriptionService: Sendable {
    /// Liefert Roh-Transkript. `prompt` kann ein Glossar / Kontext sein (verbessert die Diktion).
    func transcribe(audioURL: URL, language: String?, prompt: String?) async throws -> String
}

enum TranscriptionError: LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case network(Error)
    case decoding
    case backendNotAvailable

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Kein OpenAI-API-Key hinterlegt. Bitte unter Einstellungen → Zugang setzen."
        case .http(let code, let body): return "OpenAI-Fehler \(code): \(body)"
        case .network(let e): return "Netzwerk: \(e.localizedDescription)"
        case .decoding: return "Antwort der API konnte nicht gelesen werden."
        case .backendNotAvailable: return "Lokales Modell ist noch nicht verfügbar."
        }
    }
}
