import Foundation
@testable import BlitzText

/// Test-Fake für `FoundationAvailabilityProviding`. Mutable `state` für
/// State-Transitions (AC-AVAIL-2: modelNotReady → available ohne App-Restart);
/// `callCount` für DI-Verification.
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
