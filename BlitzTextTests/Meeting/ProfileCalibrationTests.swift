import FluidAudio
import Foundation
import Testing
@testable import BlitzText

/// Misst Abstände zwischen den Stimmen einer echten Aufnahme und gespeicherten Profilen.
/// Nur mit TEST_RUNNER_BLITZTEXT_CALIB_TRACK und …_CALIB_PROFILES; liest beides nur.
@MainActor
struct ProfileCalibrationTests {
    nonisolated static let env = ProcessInfo.processInfo.environment

    @Test("Abstände Stimme ↔ Profil", .enabled(if: env["BLITZTEXT_CALIB_TRACK"] != nil), .timeLimit(.minutes(10)))
    func distances() async throws {
        let track = URL(fileURLWithPath: try #require(Self.env["BLITZTEXT_CALIB_TRACK"]))
        let store = SpeakerProfileStore(url: URL(fileURLWithPath: try #require(Self.env["BLITZTEXT_CALIB_PROFILES"])))
        let profiles = store.loadSpeakers().filter(\.isPermanent)
        let manager = DiarizerManager(config: .default)
        let modelManager = DiarizerModelManager()
        _ = await modelManager.ensureInstalled()
        manager.initialize(models: try #require(await modelManager.modelsIfInstalled))
        let samples = try AudioConverter().resampleAudioFile(track)
        let result = try await manager.performCompleteDiarization(samples)
        let clusters = MeetingProfileMatcher.clusters(from: result.segments)
        for cluster in clusters.sorted(by: { $0.duration > $1.duration }) {
            let ranked = profiles.map { ($0.name, SpeakerUtilities.cosineDistance(cluster.embedding, $0.currentEmbedding)) }
                .sorted { $0.1 < $1.1 }.prefix(4)
                .map { "\($0.0)=\(String(format: "%.3f", $0.1))" }.joined(separator: "  ")
            print("KALIB \(cluster.id): \(Int(cluster.duration)) s  \(ranked)")
        }
    }
}
