@testable import BlitzText
import FoundationModels
import XCTest

/// Tests für `AppleFoundationRewriteClient` — Plain-Pfad (`rewrite`) für
/// `blitztextPlus` und Guided-Pfad (`rewriteGuided`) für `blitztextRant`.
///
/// AC-AVAIL-1 (Pre-Inference-Guard): drei `unavailable`-Cases werfen deutsche
/// `AppleFoundationError`-Strings UND lösen KEINEN Inferenz-Call aus
/// (defensive Verfügbarkeitsprüfung vor jeder Anfrage).
///
/// Plain + Guided Pfad: positive Cases (Trim-Result), Empty-Guided-Output-Pfad.
@MainActor
final class AppleFoundationRewriteClientTests: XCTestCase {

    // MARK: - AC-AVAIL-1: Pre-Inference-Guard, drei unavailable-Cases

    func test_unavailable_appleIntelligenceNotEnabled_throwsGermanError() async {
        let provider = FakeFoundationAvailabilityProvider(state: .unavailable(.appleIntelligenceNotEnabled))
        let inferring = FakeLanguageModelInferring()
        let client = AppleFoundationRewriteClient(availabilityProvider: provider, inferring: inferring)

        do {
            _ = try await client.rewrite(input: "test", systemPrompt: "x", model: "y")
            XCTFail("Erwartet: Throw — bekam: kein Fehler")
        } catch let error as AppleFoundationError {
            let msg = error.errorDescription ?? ""
            XCTAssertTrue(
                msg.contains("Apple Intelligence") && msg.contains("Systemeinstellungen"),
                "Erwartet deutscher Marker — bekam: \(msg)"
            )
        } catch {
            XCTFail("Erwartet AppleFoundationError — bekam: \(error)")
        }
        XCTAssertEqual(inferring.respondCallCount, 0, "AC-AVAIL-1: kein Inferenz-Call bei unavailable")
        XCTAssertEqual(inferring.respondGuidedCallCount, 0)
    }

    func test_unavailable_modelNotReady_throwsGermanError() async {
        let provider = FakeFoundationAvailabilityProvider(state: .unavailable(.modelNotReady))
        let inferring = FakeLanguageModelInferring()
        let client = AppleFoundationRewriteClient(availabilityProvider: provider, inferring: inferring)

        do {
            _ = try await client.rewrite(input: "x", systemPrompt: "y", model: "z")
            XCTFail("Throw erwartet")
        } catch let error as AppleFoundationError {
            XCTAssertTrue(
                (error.errorDescription ?? "").contains("wird gerade geladen"),
                "Erwartet 'wird gerade geladen' — bekam: \(error.errorDescription ?? "")"
            )
        } catch {
            XCTFail("AppleFoundationError erwartet — bekam: \(error)")
        }
        XCTAssertEqual(inferring.respondCallCount, 0)
    }

    func test_unavailable_deviceNotEligible_throwsGermanError() async {
        let provider = FakeFoundationAvailabilityProvider(state: .unavailable(.deviceNotEligible))
        let inferring = FakeLanguageModelInferring()
        let client = AppleFoundationRewriteClient(availabilityProvider: provider, inferring: inferring)

        do {
            _ = try await client.rewrite(input: "x", systemPrompt: "y", model: "z")
            XCTFail("Throw erwartet")
        } catch let error as AppleFoundationError {
            XCTAssertTrue(
                (error.errorDescription ?? "").contains("Gerät unterstützt"),
                "Erwartet 'Gerät unterstützt' — bekam: \(error.errorDescription ?? "")"
            )
        } catch {
            XCTFail("AppleFoundationError erwartet — bekam: \(error)")
        }
        XCTAssertEqual(inferring.respondCallCount, 0)
    }

    // MARK: - Plain-Pfad (blitztextPlus): respond

    func test_available_plain_dispatchesToRespond() async throws {
        let provider = FakeFoundationAvailabilityProvider(state: .available)
        let inferring = FakeLanguageModelInferring()
        inferring.response = .success("  Hallo Welt  ")
        let client = AppleFoundationRewriteClient(availabilityProvider: provider, inferring: inferring)

        let out = try await client.rewrite(input: "in", systemPrompt: "sys", model: "m")
        XCTAssertEqual(out, "Hallo Welt", "Output muss getrimmt sein")
        XCTAssertEqual(inferring.respondCallCount, 1)
        XCTAssertEqual(inferring.respondGuidedCallCount, 0)
        XCTAssertEqual(inferring.lastInput, "in")
        XCTAssertEqual(inferring.lastInstructions, "sys")
    }

    // MARK: - Guided-Pfad (blitztextRant): respondGuided<DeescalatedOutput>

    func test_available_guided_dispatchesToRespondGuided() async throws {
        let provider = FakeFoundationAvailabilityProvider(state: .available)
        let inferring = FakeLanguageModelInferring()
        inferring.guidedResponse = .success(DeescalatedOutput(neutralText: "  Sachlicher Text  "))
        let client = AppleFoundationRewriteClient(availabilityProvider: provider, inferring: inferring)

        let out = try await client.rewriteGuided(input: "in", systemPrompt: "sys")
        XCTAssertEqual(out, "Sachlicher Text", "Guided-Output muss getrimmt sein")
        XCTAssertEqual(inferring.respondGuidedCallCount, 1)
        XCTAssertEqual(inferring.respondCallCount, 0)
        XCTAssertEqual(inferring.lastInput, "in")
        XCTAssertEqual(inferring.lastInstructions, "sys")
    }

    func test_guided_emptyNeutralText_throwsEmptyGuidedOutput() async {
        let provider = FakeFoundationAvailabilityProvider(state: .available)
        let inferring = FakeLanguageModelInferring()
        inferring.guidedResponse = .success(DeescalatedOutput(neutralText: "   "))
        let client = AppleFoundationRewriteClient(availabilityProvider: provider, inferring: inferring)
        do {
            _ = try await client.rewriteGuided(input: "in", systemPrompt: "sys")
            XCTFail("Throw erwartet")
        } catch AppleFoundationError.emptyGuidedOutput {
            // expected
        } catch {
            XCTFail("AppleFoundationError.emptyGuidedOutput erwartet — bekam: \(error)")
        }
    }
}
