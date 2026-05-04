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
        // 08-03 Rule-1 Fix: Test-Isolation gegen UserDefaults-Pollution.
        // SettingsStore.load() liest persistierte Defaults — wenn ein anderer Test
        // (oder ein vorheriger Suite-Run) `rewriteBackendForPlus = .openAI`
        // persistiert hat, würde der Default-State-Erwartungs-Assert hier fehlschlagen.
        // Wir setzen die Backend-Slots explizit auf den Test-Default (.appleFoundation)
        // UND clearen das Self-Idempotency-Flag (Runtime-Only, aber paranoid).
        store.rewriteBackendForPlus = .appleFoundation
        store.rewriteBackendForRant = .appleFoundation
        store.didAutoFallbackToOpenAI = false
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

    // MARK: - CR-02 Regression Tests

    /// CR-02 Regression: Initial-State == Provider-Result == .modelNotReady
    /// darf den Auto-Fallback NICHT verschlucken.
    ///
    /// Bug: `refreshFoundationAvailability()` prüfte `if new != foundationAvailability`
    /// — beim Cold-Boot (Initial-State hardcoded `.unavailable(.modelNotReady)`) und
    /// Provider-Result identisch feuerte der Inequality-Check nicht → kein Fallback.
    func test_refresh_initialBootstrap_unavailableMatchesInitialState_triggersAutoFallback() {
        let provider = FakeFoundationAvailabilityProvider(state: .unavailable(.modelNotReady))
        let store = SettingsStore(availabilityProvider: provider)
        store._testApiKeyOverride = "sk-test-coldboot"
        // Sanity: Default-Backend nach makeStore-Reset ist .appleFoundation für beide Modi.
        store.rewriteBackendForPlus = .appleFoundation
        store.rewriteBackendForRant = .appleFoundation
        store.didAutoFallbackToOpenAI = false
        XCTAssertEqual(store.rewriteBackendForPlus, .appleFoundation)
        XCTAssertEqual(store.rewriteBackendForRant, .appleFoundation)
        XCTAssertFalse(store.didAutoFallbackToOpenAI)

        store.refreshFoundationAvailability()

        XCTAssertEqual(store.rewriteBackendForPlus, .openAI,
            "Cold-Boot mit Initial==Provider==modelNotReady muss Auto-Fallback triggern (CR-02)")
        XCTAssertEqual(store.rewriteBackendForRant, .openAI,
            "Cold-Boot Auto-Fallback muss beide Modi schalten (CR-02)")
        XCTAssertTrue(store.didAutoFallbackToOpenAI,
            "Self-Idempotency-Marker muss nach Auto-Fallback gesetzt sein")
    }

    /// CR-02 Reset: Wenn Foundation wieder .available wird, muss
    /// didAutoFallbackToOpenAI zurückgesetzt werden, damit ein späterer
    /// erneuter Verlust wieder einen Auto-Fallback auslösen kann.
    func test_refresh_returnsToAvailable_resetsAutoFallbackMarker() {
        let provider = FakeFoundationAvailabilityProvider(state: .unavailable(.modelNotReady))
        let store = SettingsStore(availabilityProvider: provider)
        store._testApiKeyOverride = "sk-test-recover"
        store.rewriteBackendForPlus = .appleFoundation
        store.rewriteBackendForRant = .appleFoundation
        store.didAutoFallbackToOpenAI = false
        store.refreshFoundationAvailability()
        XCTAssertTrue(store.didAutoFallbackToOpenAI)

        // Foundation kommt zurück.
        provider.state = .available
        store.refreshFoundationAvailability()

        XCTAssertEqual(store.foundationAvailability, .available)
        XCTAssertFalse(store.didAutoFallbackToOpenAI,
            "Recovery zu .available muss didAutoFallbackToOpenAI zurücksetzen (CR-02)")
        // Privacy-Invariante: User-Backend-Wahl wird durch den Reset NICHT
        // automatisch zurückgeändert — User hat .openAI explizit (per Auto-Fallback)
        // und behält diese Wahl bis zur manuellen Änderung.
        XCTAssertEqual(store.rewriteBackendForPlus, .openAI)
        XCTAssertEqual(store.rewriteBackendForRant, .openAI)
    }

    // MARK: - WARNING-7 Self-Idempotency

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
