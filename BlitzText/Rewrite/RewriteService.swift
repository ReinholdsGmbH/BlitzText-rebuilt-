import Foundation

protocol RewriteService: Sendable {
    func rewrite(input: String, systemPrompt: String, model: String) async throws -> String
}
