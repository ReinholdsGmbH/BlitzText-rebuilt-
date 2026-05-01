import Foundation
@testable import BlitzText

/// Konfigurierbare TranscriptionService-Fake fuer Pipeline-Tests.
/// Liefert beim Aufruf den vorab konfigurierten `Result` und protokolliert die Inputs.
/// Kein Netzwerk, keine Side-Effects.
final class FakeTranscriptionService: TranscriptionService, @unchecked Sendable {
    let result: Result<String, Error>
    private(set) var callCount: Int = 0
    private(set) var lastAudioURL: URL?
    private(set) var lastLanguage: String?
    private(set) var lastPrompt: String?

    init(_ result: Result<String, Error>) { self.result = result }

    func transcribe(audioURL: URL, language: String?, prompt: String?) async throws -> String {
        callCount += 1
        lastAudioURL = audioURL
        lastLanguage = language
        lastPrompt = prompt
        return try result.get()
    }
}
