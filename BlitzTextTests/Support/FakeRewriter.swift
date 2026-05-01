import Foundation
@testable import BlitzText

/// Konfigurierbare RewriteService-Fake fuer Pipeline-Tests.
/// Liefert beim Aufruf den vorab konfigurierten `Result` und protokolliert den Aufrufzaehler.
final class FakeRewriter: RewriteService, @unchecked Sendable {
    let result: Result<String, Error>
    private(set) var callCount: Int = 0
    private(set) var lastInput: String?
    private(set) var lastSystemPrompt: String?
    private(set) var lastModel: String?

    init(_ result: Result<String, Error>) { self.result = result }

    func rewrite(input: String, systemPrompt: String, model: String) async throws -> String {
        callCount += 1
        lastInput = input
        lastSystemPrompt = systemPrompt
        lastModel = model
        return try result.get()
    }
}
