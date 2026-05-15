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
                Message(role: "user", content: input)
            ],
            temperature: 0.3
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

// MARK: - Ollama

enum OllamaError: LocalizedError {
    case notRunning
    var errorDescription: String? {
        "Ollama läuft nicht. Starte Ollama mit «ollama serve» und versuche es erneut."
    }
}

final class OllamaRewriteClient: RewriteService, @unchecked Sendable {

    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func rewrite(input: String, systemPrompt: String, model: String) async throws -> String {
        let base = settings.ollamaBaseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let endpoint = URL(string: "\(base)/v1/chat/completions") else {
            throw TranscriptionError.decoding
        }

        var req = URLRequest(url: endpoint, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Message: Encodable { let role: String; let content: String }
        struct Body: Encodable {
            let model: String; let messages: [Message]
            let temperature: Double; let stream: Bool
        }
        req.httpBody = try JSONEncoder().encode(Body(
            model: settings.ollamaModel,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: input)
            ],
            temperature: 0.3,
            stream: false
        ))

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost {
            throw OllamaError.notRunning
        }

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
