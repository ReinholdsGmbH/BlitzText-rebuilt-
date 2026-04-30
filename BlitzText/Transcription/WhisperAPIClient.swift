import Foundation

/// OpenAI Whisper-API Client. POST multipart/form-data an /v1/audio/transcriptions.
final class WhisperAPIClient: TranscriptionService, @unchecked Sendable {

    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let settings: SettingsStore
    private let session: URLSession

    init(settings: SettingsStore, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func transcribe(audioURL: URL, language: String?, prompt: String?) async throws -> String {
        let key = settings.apiKey
        guard !key.isEmpty else { throw TranscriptionError.missingAPIKey }

        let boundary = "blitztext-\(UUID().uuidString)"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try makeMultipartBody(
            boundary: boundary,
            audioURL: audioURL,
            model: settings.transcriptionModel,
            language: language,
            prompt: prompt
        )
        req.httpBody = body

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw TranscriptionError.decoding }
            guard (200..<300).contains(http.statusCode) else {
                let bodyString = String(data: data, encoding: .utf8) ?? ""
                throw TranscriptionError.http(http.statusCode, bodyString)
            }
            struct Resp: Decodable { let text: String }
            let parsed = try JSONDecoder().decode(Resp.self, from: data)
            return parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.network(error)
        }
    }

    private func makeMultipartBody(
        boundary: String,
        audioURL: URL,
        model: String,
        language: String?,
        prompt: String?
    ) throws -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"

        func addField(_ name: String, _ value: String) {
            body.append(boundaryPrefix)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append(value)
            body.append("\r\n")
        }

        addField("model", model)
        if let language, !language.isEmpty { addField("language", language) }
        if let prompt, !prompt.isEmpty { addField("prompt", prompt) }
        addField("response_format", "json")

        let audioData = try Data(contentsOf: audioURL)
        body.append(boundaryPrefix)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }
}
