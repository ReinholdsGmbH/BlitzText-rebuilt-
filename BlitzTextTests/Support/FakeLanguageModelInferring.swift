import Foundation
import FoundationModels
@testable import BlitzText

/// Test-Fake für `LanguageModelInferring`. Konfigurierbare `Result`-Antworten
/// für `respond` (Plus) und `respondGuided` (Rant); Aufruf-Zähler + Last-Args
/// für Wave-1-Tests, die Prompt-Composition prüfen.
final class FakeLanguageModelInferring: LanguageModelInferring, @unchecked Sendable {
    var response: Result<String, Error> = .success("FAKE_OUT")
    var guidedResponse: Result<Any, Error> = .success(DeescalatedOutput(neutralText: "FAKE_GUIDED"))
    private(set) var respondCallCount: Int = 0
    private(set) var respondGuidedCallCount: Int = 0
    private(set) var lastInput: String?
    private(set) var lastInstructions: String?

    func respond(input: String, instructions: String) async throws -> String {
        respondCallCount += 1
        lastInput = input
        lastInstructions = instructions
        return try response.get()
    }

    func respondGuided<T: Generable>(input: String, instructions: String, type: T.Type) async throws -> T {
        respondGuidedCallCount += 1
        lastInput = input
        lastInstructions = instructions
        guard let value = try guidedResponse.get() as? T else {
            throw NSError(
                domain: "FakeLanguageModelInferring",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Generic-Type-Mismatch im Fake"]
            )
        }
        return value
    }
}
