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
        // Frisch pro Meeting: Sprecher-IDs aus früheren Meetings sollen nicht durchsickern.
        await speakers.reset()
        await speakers.setSpeakerThreshold(threshold())
        let profiles = store.loadSpeakers().filter(\.isPermanent)
        if !profiles.isEmpty {
            await speakers.initializeKnownSpeakers(profiles, mode: .skip)
        }

        let samples = try AudioConverter().resampleAudioFile(track)
        Log.write("MeetingDiarizer: \(String(format: "%.0f", Double(samples.count) / 16_000)) s Audio, \(profiles.count) Profile")
        let result = try await manager.performCompleteDiarization(samples)

        let segments = result.segments.map {
            DiarizedSegment(speakerID: $0.speakerId, start: TimeInterval($0.startTimeSeconds), end: TimeInterval($0.endTimeSeconds))
        }
        let profileIDs = Set(profiles.map(\.id))
        let runtime = await speakers.getSpeakerList()
        var known: [String: String] = [:]
        for speaker in runtime where profileIDs.contains(speaker.id) && segments.contains(where: { $0.speakerID == speaker.id }) {
            known[speaker.id] = speaker.name
        }

        // Nachgeschärfte Profile zurückschreiben. Nur permanente — unbenannte Stimmen bleiben flüchtig.
        let refined = ParakeetClient.mergePersistedNames(runtime, from: store).filter(\.isPermanent)
        if !refined.isEmpty { store.saveSpeakers(Self.merge(refined, into: store.loadSpeakers())) }

        Log.write("MeetingDiarizer: \(Set(segments.map(\.speakerID)).count) Sprecher, \(known.count) davon bekannt")
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
