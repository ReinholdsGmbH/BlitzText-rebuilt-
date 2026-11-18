import AVFoundation
import FluidAudio
import Foundation

/// Ein Sprecherabschnitt der Gegenseite.
struct DiarizedSegment: Equatable {
    let speakerID: String
    let start: TimeInterval
    let end: TimeInterval
}

struct MeetingDiarization: Equatable {
    let segments: [DiarizedSegment]
    /// Sprecher-ID → Name für Stimmen, die zu einem gespeicherten Profil passten.
    let knownNames: [String: String]
}

protocol MeetingDiarizing: Sendable {
    /// Trennt die Stimmen einer Spur und gleicht sie mit den gespeicherten Profilen ab.
    func diarize(track: URL) async throws -> MeetingDiarization
    /// Legt aus den Abschnitten eines Sprechers ein Profil an oder schärft ein vorhandenes
    /// gleichen Namens nach.
    func learnProfile(name: String, from track: URL, spans: [SpeechSpan]) async throws
    /// Namen aller gespeicherten Profile, für die Vorschläge beim Tippen.
    func knownSpeakerNames() -> [String]
}

enum MeetingDiarizerError: LocalizedError {
    case modelUnavailable
    case notEnoughSpeech(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Das Modell für die Sprechertrennung ist nicht installiert (Einstellungen → Sprecher)."
        case .notEnoughSpeech(let seconds):
            return "Zu wenig Sprache für ein Stimmprofil (\(Int(seconds)) s, nötig sind mindestens 4 s)."
        }
    }
}

/// Sprechertrennung für Meetings über FluidAudio, komplett auf dem Gerät.
///
/// Lernen über die Zeit: Vor jeder Trennung werden die gespeicherten Profile geladen.
/// Erkennt FluidAudio eine Stimme wieder, mittelt `assignSpeaker` die neuen Stimmproben
/// gleitend ins Profil ein (EMA). Danach werden die Profile zurückgeschrieben. So wird jedes
/// Profil mit jedem Meeting genauer.
///
/// Was nicht passiert: Unbenannte Stimmen werden nicht gespeichert. Stimmprofile sind
/// biometrische Daten (DSGVO Art. 9), und hier wären es die von Kolleginnen und Kollegen.
/// Ein Profil entsteht erst, wenn der Nutzer einem Sprecher einen Namen gibt.
final class FluidMeetingDiarizer: MeetingDiarizing, @unchecked Sendable {
    private let modelManager: DiarizerModelManager
    private let store: SpeakerProfileStore
    private let threshold: () -> Float
    private let lock = NSLock()
    private var loaded: DiarizerManager?

    /// Profile mit Mindestsprechzeit. Darunter ist ein Embedding zu unzuverlässig.
    static let minimumProfileSeconds: TimeInterval = 4
    /// Mehr als eine Minute Sprache bringt für ein Profil nichts mehr.
    static let maximumProfileSeconds: TimeInterval = 60

    init(modelManager: DiarizerModelManager, store: SpeakerProfileStore, threshold: @escaping () -> Float) {
        self.modelManager = modelManager
        self.store = store
        self.threshold = threshold
    }

    private func diarizer() async throws -> DiarizerManager {
        if let existing = lock.withLock({ loaded }) { return existing }
        let installed = await modelManager.ensureInstalled()
        guard installed, let models = await modelManager.modelsIfInstalled else {
            throw MeetingDiarizerError.modelUnavailable
        }
        let manager = DiarizerManager(config: .default)
        manager.initialize(models: models)
        lock.withLock { loaded = manager }
        return manager
    }

    func diarize(track: URL) async throws -> MeetingDiarization {
        let manager = try await diarizer()
        let speakers = manager.speakerManager
        // Frisch pro Meeting und ohne vorgeladene Profile: Vorgeladen hat FluidAudio eine
        // einzige Stimme in fünf zerlegt und jedem Teil irgendein Profil gegeben. Die Profile
        // werden erst danach und streng zugeordnet (`MeetingProfileMatcher`).
        await speakers.reset()
        await speakers.setSpeakerThreshold(threshold())
        let profiles = store.loadSpeakers().filter(\.isPermanent)

        let samples = try AudioConverter().resampleAudioFile(track)
        Log.write("MeetingDiarizer: \(String(format: "%.0f", Double(samples.count) / 16_000)) s Audio, \(profiles.count) Profile")
        let result = try await manager.performCompleteDiarization(samples)

        let segments = result.segments.map {
            DiarizedSegment(speakerID: $0.speakerId, start: TimeInterval($0.startTimeSeconds), end: TimeInterval($0.endTimeSeconds))
        }
        let clusters = MeetingProfileMatcher.clusters(from: result.segments)
        let known = MeetingProfileMatcher.match(clusters, profiles: profiles.map { ($0.name, $0.currentEmbedding) })
        // Kein automatisches Nachschärfen mehr: Ein falscher Treffer hat sonst das Profil einer
        // Person mit der Stimme einer anderen überschrieben. Profile lernen nur aus Namen, die
        // der Nutzer vergibt oder bestätigt (`learnProfile`).
        Log.write("MeetingDiarizer: \(clusters.count) Sprecher, \(known.count) davon bekannt")
        return MeetingDiarization(segments: segments, knownNames: known)
    }

    func knownSpeakerNames() -> [String] {
        store.loadSpeakers().filter(\.isPermanent).map(\.name)
    }

    func learnProfile(name: String, from track: URL, spans: [SpeechSpan]) async throws {
        let manager = try await diarizer()
        let samples = try Self.samples(of: spans, in: track, limit: Self.maximumProfileSeconds)
        let seconds = Double(samples.count) / 16_000
        guard seconds >= Self.minimumProfileSeconds else { throw MeetingDiarizerError.notEnoughSpeech(seconds) }

        let embedding = try manager.extractSpeakerEmbedding(from: samples)
        var all = store.loadSpeakers()
        if let index = all.firstIndex(where: { $0.isPermanent && SpeakerNaming.key($0.name) == SpeakerNaming.key(name) }) {
            all[index].updateMainEmbedding(duration: Float(seconds), embedding: embedding, segmentId: UUID(), alpha: 0.7)
            Log.write("MeetingDiarizer: Profil nachgeschärft (\(String(format: "%.0f", seconds)) s)")
        } else {
            all.append(Speaker(name: name, currentEmbedding: embedding, duration: Float(seconds), isPermanent: true))
            Log.write("MeetingDiarizer: neues Profil angelegt (\(String(format: "%.0f", seconds)) s)")
        }
        store.saveSpeakers(all)
        if let manager = lock.withLock({ loaded }) {
            await manager.speakerManager.reset()
        }
    }

    /// Ersetzt gleichnamige IDs im gespeicherten Bestand, behält alle übrigen Profile.
    static func merge(_ refined: [Speaker], into stored: [Speaker]) -> [Speaker] {
        var byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for speaker in refined { byID[speaker.id] = speaker }
        return stored.map { byID[$0.id] ?? $0 } + refined.filter { r in !stored.contains { $0.id == r.id } }
    }

    /// Hängt die Abschnitte eines Sprechers aneinander, 16 kHz mono.
    static func samples(of spans: [SpeechSpan], in track: URL, limit: TimeInterval) throws -> [Float] {
        let file = try AVAudioFile(forReading: track)
        let format = file.processingFormat
        let rate = format.sampleRate
        var out: [Float] = []
        let maxSamples = Int(limit * 16_000)
        for span in spans.sorted(by: { $0.duration > $1.duration }) where out.count < maxSamples {
            let start = AVAudioFramePosition(span.start * rate)
            let count = AVAudioFrameCount(max(0, span.duration) * rate)
            guard start < file.length, count > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { continue }
            file.framePosition = start
            try file.read(into: buffer, frameCount: min(count, AVAudioFrameCount(file.length - start)))
            guard let channel = buffer.floatChannelData?[0] else { continue }
            // Spuren im Archiv sind 16 kHz; andere Raten grob ausdünnen statt abzubrechen.
            let step = max(1, Int((rate / 16_000).rounded()))
            for i in stride(from: 0, to: Int(buffer.frameLength), by: step) { out.append(channel[i]) }
        }
        return Array(out.prefix(maxSamples))
    }
}

/// Ordnet Namen aus der Meeting-App den Stimmen zu.
///
/// Während der Aufnahme liest `ActiveSpeakerPoller` jede Sekunde, wer laut Teams oder Zoom
/// gerade spricht. Hier wird gezählt, in welchen Sprecherabschnitten welcher Name auftaucht.
/// Ein Name gilt erst, wenn er klar dominiert. Die Diarisierung trennt die Stimmen, die App
/// liefert die Namen.
enum SpeakerNameSuggester {

    static func suggest(
        segments: [DiarizedSegment],
        hints: [SpeakerHint],
        minimumVotes: Int = 3,
        minimumShare: Double = 0.6
    ) -> [String: String] {
        var votes: [String: [String: Int]] = [:]
        for hint in hints {
            guard let segment = segments.first(where: { $0.start - 0.5 <= hint.time && hint.time <= $0.end + 0.5 }) else { continue }
            votes[segment.speakerID, default: [:]][hint.name, default: 0] += 1
        }

        var candidates: [(id: String, name: String, count: Int)] = []
        for (id, names) in votes {
            let total = names.values.reduce(0, +)
            guard let best = names.max(by: { $0.value < $1.value }),
                  best.value >= minimumVotes,
                  Double(best.value) / Double(total) >= minimumShare else { continue }
            candidates.append((id, best.key, best.value))
        }
        // Ein Name nur für eine Stimme: bei Konflikt gewinnt die mit mehr Belegen.
        var result: [String: String] = [:]
        var taken = Set<String>()
        for candidate in candidates.sorted(by: { $0.count > $1.count }) where !taken.contains(candidate.name) {
            result[candidate.id] = candidate.name
            taken.insert(candidate.name)
        }
        return result
    }
}

/// Zu welchem Zeitpunkt die Meeting-App welchen Namen als aktiven Sprecher zeigte.
struct SpeakerHint: Equatable, Codable {
    /// Sekunden ab Aufnahmebeginn.
    let time: TimeInterval
    let name: String
}

/// Ordnet getrennte Stimmen gespeicherten Profilen zu, erst nach der Trennung und streng.
///
/// Früher lud BlitzText die Profile in FluidAudio vor. Dort reicht ein Abstand unter der
/// Schwelle, und bei 15 Profilen passt fast immer irgendeines: Im Call am 18.11.2026 bekam
/// der Hauptsprecher das Profil einer anderen Person, drei Minischnipsel weitere Namen.
/// Jetzt gilt:
/// - Eine Stimme braucht `minimumSeconds` Sprechzeit, sonst ist ihr Embedding zu unscharf.
/// - Das beste Profil muss nah genug (`maximumDistance`) und deutlich näher als das zweitbeste
///   sein (`minimumMargin`).
/// - Jedes Profil geht an höchstens eine Stimme, die nächste gewinnt.
/// - Ausgeschlossene Namen (die eigene Person auf der Gegenseite) werden nie vergeben.
enum MeetingProfileMatcher {
    static let minimumSeconds: Float = 15
    static let maximumDistance: Float = 0.5
    static let minimumMargin: Float = 0.08

    struct Cluster {
        let id: String
        let duration: Float
        let embedding: [Float]
    }

    static func clusters(from segments: [TimedSpeakerSegment]) -> [Cluster] {
        Dictionary(grouping: segments, by: \.speakerId).compactMap { id, segs in
            guard let size = segs.first(where: { !$0.embedding.isEmpty })?.embedding.count else { return nil }
            var sum = [Float](repeating: 0, count: size)
            var weight: Float = 0
            for seg in segs where seg.embedding.count == size {
                let w = max(seg.durationSeconds, 0.01)
                for i in 0..<size { sum[i] += seg.embedding[i] * w }
                weight += w
            }
            let duration = segs.reduce(0) { $0 + $1.durationSeconds }
            return Cluster(id: id, duration: duration, embedding: weight > 0 ? sum.map { $0 / weight } : [])
        }
    }

    /// Stimmen-ID → Profilname.
    static func match(_ clusters: [Cluster], profiles: [(name: String, embedding: [Float])], excluding: Set<String> = []) -> [String: String] {
        let usable = profiles.filter { !$0.embedding.isEmpty && !excluding.contains(SpeakerNaming.key($0.name)) }
        var candidates: [(cluster: String, name: String, distance: Float)] = []
        for cluster in clusters where cluster.duration >= minimumSeconds && !cluster.embedding.isEmpty {
            let ranked = usable
                .filter { $0.embedding.count == cluster.embedding.count }
                .map { (name: $0.name, distance: SpeakerUtilities.cosineDistance(cluster.embedding, $0.embedding)) }
                .sorted { $0.distance < $1.distance }
            guard let best = ranked.first, best.distance <= maximumDistance else { continue }
            let second = ranked.dropFirst().first?.distance ?? .infinity
            guard second - best.distance >= minimumMargin else { continue }
            candidates.append((cluster.id, best.name, best.distance))
        }
        var result: [String: String] = [:]
        var used = Set<String>()
        for candidate in candidates.sorted(by: { $0.distance < $1.distance })
        where !used.contains(candidate.name) && result[candidate.cluster] == nil {
            result[candidate.cluster] = candidate.name
            used.insert(candidate.name)
        }
        return result
    }
}
