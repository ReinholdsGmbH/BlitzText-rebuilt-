import Foundation

/// Variante 3: KI-basierte Eigennamen-Extraktion, über OpenAI (gpt-4o-mini) oder einen
/// Cloud-Anbieter im OpenAI-Format (Requesty, OpenRouter).
/// Statisch, damit ohne Sendable-Probleme aus Detached-Tasks aufrufbar.
enum EigennamenAISuggester {

    /// Über Requesty oder OpenRouter, mit dem Modell aus deren Zugangskarte.
    static func extract(from text: String, using chat: OpenAICompatibleChat) async -> [String] {
        guard text.count >= 10 else { return [] }
        do {
            let answer = try await chat.complete(system: systemPrompt, user: text)
            return parse(answer)
        } catch {
            Log.write("EigennamenAISuggester (\(chat.provider.rawValue)): \(error.localizedDescription)")
            return []
        }
    }

    /// Antwort des Modells: JSON mit `eigennamen`, notfalls in einem Markdown-Codeblock.
    static func parse(_ answer: String) -> [String] {
        guard let start = answer.firstIndex(of: "{"), let end = answer.lastIndex(of: "}"),
              let data = String(answer[start...end]).data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let names = parsed["eigennamen"] as? [String] else { return [] }
        return names.filter { !$0.isEmpty && $0.count >= 2 }
    }

    static let systemPrompt = """
        Du extrahierst Eigennamen aus deutschsprachigen Transkripten.
        Eigennamen sind: Personennamen, Firmennamen, Produktnamen, Ortsnamen, technische Begriffe.
        KEINE Eigennamen sind: Wochentage, Monate, generische Substantive, gebräuchliche Begriffe.

        Antwortformat: JSON-Objekt mit Schlüssel 'eigennamen' (Array). Beispiel: {"eigennamen": ["Hannes"]}.
        Keine Erklärungen, kein Markdown.
        """

    static func extract(from text: String, apiKey: String) async -> [String] {
        guard !apiKey.isEmpty, text.count >= 10 else { return [] }

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                Log.write("EigennamenAISuggester: HTTP-Fehler")
                return []
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  let contentData = content.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
                  let names = parsed["eigennamen"] as? [String] else {
                return []
            }
            return names.filter { !$0.isEmpty && $0.count >= 2 }
        } catch {
            Log.write("EigennamenAISuggester error: \(error)")
            return []
        }
    }
}
