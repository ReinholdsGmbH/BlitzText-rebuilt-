import Foundation
import FluidAudio

/// Persists FluidAudio `Speaker` profiles to `~/Library/Application Support/BlitzText/speakers.json`.
/// Thread-safe for concurrent reads; atomic file writes prevent corruption on concurrent saves.
final class SpeakerProfileStore: @unchecked Sendable {
    private let url: URL

    /// Wird nach jeder Session-Sicherung aufgerufen. Liefert vollständige Speaker-Liste
    /// und die IDs der in dieser Session aktiven Sprecher.
    /// Wird aus einem Background-Task aufgerufen — Empfänger muss selbst auf MainActor hoppen.
    var onSessionSaved: (([Speaker], [String]) -> Void)?

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BlitzText", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        // Nur-Besitzer-Zugriff: Stimm-Embeddings sind biometrische Daten (DSGVO Art. 9).
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
        self.url = support.appendingPathComponent("speakers.json")
    }

    init(url: URL) {
        self.url = url
    }

    func loadSpeakers() -> [Speaker] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Speaker].self, from: data)) ?? []
    }

    func saveSpeakers(_ speakers: [Speaker]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(speakers)
            try data.write(to: url, options: .atomic)
            // Nur-Besitzer-Lesezugriff auf die Embeddings.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Log.write("SpeakerProfileStore: Speichern fehlgeschlagen — \(error.localizedDescription)")
        }
    }

    /// Speichert nach einer abgeschlossenen Diarization-Session.
    /// Nur permanente (enrollte) Sprecher werden auf Disk geschrieben — anonyme Session-Sprecher
    /// werden NICHT persistiert, um Verwechslungen in Folgesessions zu verhindern.
    /// `onSessionSaved` erhält die vollständige Liste inkl. anonymer für die UI-Anzeige.
    func saveSession(speakers: [Speaker], sessionSpeakerIDs: [String]) {
        saveSpeakers(speakers.filter { $0.isPermanent })
        onSessionSaved?(speakers, sessionSpeakerIDs)
    }
}
