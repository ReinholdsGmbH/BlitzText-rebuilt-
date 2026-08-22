import Foundation

/// OpenAI Chat-Completions-Client. Default-Modell: gpt-4o-mini.
final class OpenAIChatClient: RewriteService, @unchecked Sendable {

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let settings: SettingsStore
    private let session: URLSession

    init(settings: SettingsStore, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func rewrite(input: String, systemPrompt: String, model: String) async throws -> String {
        let key = settings.apiKey
        guard !key.isEmpty else { throw TranscriptionError.missingAPIKey }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Message: Encodable { let role: String; let content: String }
        struct Body: Encodable {
            let model: String
            let messages: [Message]
            let temperature: Double
        }
        let body = Body(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: wrapTranscriptForPrompt(input))
            ],
            temperature: 0.0
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw TranscriptionError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        struct Choice: Decodable { let message: MessageResp }
        struct MessageResp: Decodable { let content: String }
        struct Resp: Decodable { let choices: [Choice] }
        let parsed = try JSONDecoder().decode(Resp.self, from: data)
        return parsed.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
