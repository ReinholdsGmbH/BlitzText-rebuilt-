import Foundation

enum OllamaError: LocalizedError {
    case notRunning
    var errorDescription: String? {
        "Ollama läuft nicht. Starte Ollama mit «ollama serve» und versuche es erneut."
    }
}

/// Rewrite über eine lokale Ollama-Instanz (OpenAI-kompatible Chat-Completions-API).
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
                Message(role: "user", content: wrapTranscriptForPrompt(input))
            ],
            temperature: 0.0,
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
