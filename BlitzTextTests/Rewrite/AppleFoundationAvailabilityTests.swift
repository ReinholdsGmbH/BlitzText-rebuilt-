@testable import BlitzText
import XCTest

/// Tests für AC-AVAIL-1 (vier Availability-Cases) + AC-AVAIL-2 (Übergang ohne
/// App-Restart) + Self-Idempotency (WARNING 7 / T-08-02-07).
///
/// **BLOCKER 2 / T-08-02-06:** Kein Test schreibt jemals einen real-aussehenden
/// API-Key in die Keychain. Tests verwenden ausschließlich
/// `store._testApiKeyOverride = "sk-test-123"` (DEBUG-internal in-memory hook).
@MainActor
final class AppleFoundationAvailabilityTests: XCTestCase {

    private func makeStore(initial: FoundationAvailability, apiKey: String = "") -> (SettingsStore, FakeFoundationAvailabilityProvider) {
        let provider = FakeFoundationAvailabilityProvider(state: initial)
        let store = SettingsStore(availabilityProvider: provider)
        // BLOCKER 2 / T-08-02-06: Override IMMER setzen — auch auf leeren String —
        // damit der Keychain-Pfad nie betreten wird. Ohne dieses Override würde
        // `apiKey == ""`-Testbranch einen echten Keychain-Read auslösen, der auf
        // Dev-/CI-Maschinen mit existierendem Key falsch-positiv den Auto-Fallback
        // auslöst (Rule-1-Bug, gefangen beim ersten Test-Run am 2026-05-04).
        store._testApiKeyOverride = apiKey
        return (store, provider)
    }

    func test_refresh_initial_modelNotReady_setsPublishedState() {
        let (store, _) = makeStore(initial: .unavailable(.modelNotReady))
        store.refreshFoundationAvailability()
        XCTAssertEqual(store.foundationAvailability, .unavailable(.modelNotReady))
        XCTAssertFalse(store.didAutoFallbackToOpenAI)  // kein API-Key, kein Fallback
    }

    func test_refresh_modelNotReady_to_available_updatesPublishedState() {
        let (store, provider) = makeStore(initial: .unavailable(.modelNotReady))
        store.refreshFoundationAvailability()
        XCTAssertEqual(store.foundationAvailability, .unavailable(.modelNotReady))

        provider.state = .available
        store.refreshFoundationAvailability()
        XCTAssertEqual(store.foundationAvailability, .available, "AC-AVAIL-2: Übergang ohne App-Restart")
    }

    func test_refresh_appleIntelligenceNotEnabled_withApiKey_triggersAutoFallback() {
        let (store, _) = makeStore(initial: .unavailable(.appleIntelligenceNotEnabled), apiKey: "sk-test-123")
        store.refreshFoundationAvailability()
        XCTAssertTrue(store.didAutoFallbackToOpenAI, "AC-AVAIL-1: bei API-Key + unavailable → Auto-Fallback")
        XCTAssertEqual(store.rewriteBackendForPlus, .openAI)
        XCTAssertEqual(store.rewriteBackendForRant, .openAI)
    }

    func test_refresh_appleIntelligenceNotEnabled_withoutApiKey_doesNotAutoFallback() {
        let (store, _) = makeStore(initial: .unavailable(.appleIntelligenceNotEnabled), apiKey: "")
        store.refreshFoundationAvailability()
        XCTAssertFalse(store.didAutoFallbackToOpenAI, "ohne API-Key bleibt User auf Foundation-Default")
        XCTAssertEqual(store.rewriteBackendForPlus, .appleFoundation)
        XCTAssertEqual(store.rewriteBackendForRant, .appleFoundation)
    }

    func test_refresh_deviceNotEligible_withApiKey_triggersAutoFallback() {
        let (store, _) = makeStore(initial: .unavailable(.deviceNotEligible), apiKey: "sk-test-123")
        store.refreshFoundationAvailability()
        XCTAssertTrue(store.didAutoFallbackToOpenAI)
        XCTAssertEqual(store.rewriteBackendForPlus, .openAI)
        XCTAssertEqual(store.rewriteBackendForRant, .openAI)
    }

    func test_refresh_idempotent_doesNotReTriggerOnSameState() {
        let (store, provider) = makeStore(initial: .unavailable(.modelNotReady), apiKey: "sk-test-123")
        store.refreshFoundationAvailability()
        store.didAutoFallbackToOpenAI = false  // Reset für Re-Trigger-Check
        provider.state = .unavailable(.modelNotReady)  // gleicher State
        store.refreshFoundationAvailability()
        XCTAssertFalse(store.didAutoFallbackToOpenAI, "kein Re-Trigger bei identischem State")
    }

    /// WARNING-7-Verifikation: applyAutoFallbackIfNeeded ist self-idempotent —
    /// auch bei zwei aufeinanderfolgenden refresh-Aufrufen, in denen der State zwischendurch
    /// fließend von available → unavailable → unavailable wandert, wird der Flag nur einmal gesetzt.
    func test_applyAutoFallback_calledTwiceDirectly_setsFlagOnce() {
        let (store, provider) = makeStore(initial: .available, apiKey: "sk-test-123")
        store.refreshFoundationAvailability()                  // → state-equality, kein Fallback
        XCTAssertFalse(store.didAutoFallbackToOpenAI)

        provider.state = .unavailable(.modelNotReady)
        store.refreshFoundationAvailability()                  // 1. Fallback
        XCTAssertTrue(store.didAutoFallbackToOpenAI)
        XCTAssertEqual(store.rewriteBackendForPlus, .openAI)

        // Simuliere multi-fire didBecomeActiveNotification:
        // State wandert weiter zu einem anderen unavailable-Reason; Flag bleibt bereits gesetzt.
        // Der Self-Idempotency-Guard `guard !didAutoFallbackToOpenAI` MUSS greifen.
        provider.state = .unavailable(.appleIntelligenceNotEnabled)
        store.refreshFoundationAvailability()
        XCTAssertTrue(store.didAutoFallbackToOpenAI, "Flag bleibt true (kein zweiter Set-Pass)")
        XCTAssertEqual(store.rewriteBackendForPlus, .openAI, "Backend bleibt OpenAI (kein redundanter Switch)")
    }
}
