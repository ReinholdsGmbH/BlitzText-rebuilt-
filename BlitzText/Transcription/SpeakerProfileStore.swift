import Foundation
import FluidAudio

/// Persists FluidAudio `Speaker` profiles to `~/Library/Application Support/BlitzText/speakers.json`.
/// Thread-safe for concurrent reads; atomic file writes prevent corruption on concurrent saves.
final class SpeakerProfileStore: @unchecked Sendable {
    private let url: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BlitzText", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
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
        guard let data = try? encoder.encode(speakers) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
