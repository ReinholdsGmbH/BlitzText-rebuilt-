import Foundation

/// User-facing Error-Mapper für Apple FoundationModels-Fehler.
/// Liefert deutsche `errorDescription`-Strings für Banner/Toast in der UI.
///
/// Mapping-Strategie:
/// - `unavailable(String)` trägt die exakte Banner-Variante (siehe `from(_ availability:)`).
/// - Inferenz-Fehler (`guardrailViolation`, `exceededContextWindow`, …) werden in Wave 1
///   aus `LanguageModelSession.GenerationError`-Cases gemappt (PIN(A2): 9 Cases).
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
        case .unavailable(let msg):
            return msg
        case .guardrailViolation:
            return "Apple Intelligence hat den Text nicht zugelassen. Versuche es erneut oder wechsle in den Einstellungen auf OpenAI."
        case .exceededContextWindow:
            return "Der Text ist zu lang für Apple Foundation. Kürze die Eingabe oder wechsle auf OpenAI."
        case .unsupportedLanguage:
            return "Apple Foundation unterstützt diese Sprache nicht. Wechsle auf OpenAI."
        case .assetsUnavailable:
            return "Apple-Foundation-Modell-Assets sind nicht verfügbar. Stelle sicher, dass Apple Intelligence aktiv ist."
        case .rateLimited:
            return "Apple Foundation ist temporär ausgelastet. Versuche es in wenigen Sekunden erneut."
        case .emptyGuidedOutput:
            return "Apple Foundation lieferte ein leeres Schema. Versuche es erneut oder wechsle auf OpenAI."
        case .decodingFailure:
            return "Apple-Foundation-Antwort konnte nicht ausgewertet werden."
        case .unknown(let msg):
            return msg
        }
    }

    /// Mappt `FoundationAvailability` auf user-facing Banner-Variante.
    /// Marker-Substrings ("Apple Intelligence", "Systemeinstellungen") sind
    /// in AppleFoundationAvailabilityTests (08-02 Task 3) und Wave-1-Tests
    /// als Test-Asserts verankert — bei Änderung Tests anpassen.
    static func from(_ availability: FoundationAvailability) -> AppleFoundationError {
        switch availability {
        case .available:
            return .unknown("Foundation .available — sollte nicht hier landen")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence ist in den Systemeinstellungen nicht aktiviert. Aktiviere es, um lokal zu rewriten.")
        case .unavailable(.modelNotReady):
            return .unavailable("Das Apple-Foundation-Modell wird gerade geladen — bitte erneut versuchen.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("Dieses Gerät unterstützt Apple Intelligence nicht. Wechsle in den Einstellungen auf OpenAI.")
        }
    }
}
