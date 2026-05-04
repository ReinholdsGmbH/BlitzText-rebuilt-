import Foundation
import FoundationModels

/// Test-Seam für `SystemLanguageModel.default.availability`. Production-Default ist
/// `SystemLanguageModelAvailabilityProvider`; Tests injizieren `FakeFoundationAvailabilityProvider`.
/// Pattern analog `DiarizerLoaderProtocol` (DI-Seam ohne Hardware-Abhängigkeit).
protocol FoundationAvailabilityProviding: Sendable {
    func currentAvailability() -> FoundationAvailability
}

/// Drei-zustandiges Availability-Modell (verifiziert PIN(A2) — Apple liefert
/// `.available` oder `.unavailable(SystemLanguageModel.Availability.UnavailableReason)`).
/// Der `@unknown default`-Fall mappt konservativ auf `.deviceNotEligible`
/// (RESEARCH.md Pitfall 2: kein stillschweigender Auto-Fallback bei neuen Apple-Cases).
enum FoundationAvailability: Equatable, Sendable {
    case available
    case unavailable(Reason)

    enum Reason: Equatable, Sendable {
        case appleIntelligenceNotEnabled
        case modelNotReady
        case deviceNotEligible
    }
}

/// Production-Implementation. Spiegelt `SystemLanguageModel.default.availability`
/// 1:1 in unser internes `FoundationAvailability`-Modell.
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
            @unknown default:                  return .unavailable(.deviceNotEligible)
            }
        }
    }
}
