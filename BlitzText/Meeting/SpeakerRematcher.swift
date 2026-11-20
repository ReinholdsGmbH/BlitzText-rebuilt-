import FluidAudio
import Foundation

/// Gleicht die Stimmen eines vorhandenen Meetings nachträglich ab, etwa nach dem
/// Zusammenführen oder wenn inzwischen neue Stimmprofile gelernt wurden.
///
/// Zwei Stufen, beide mit den strengen Schwellen von `MeetingProfileMatcher`:
/// 1. Unbenannte Stimmen gegen die gespeicherten Profile. Gibt es den Namen im Meeting
///    schon, wird die Stimme dort eingegliedert, sonst bekommt sie den Namen.
/// 2. Übrige unbenannte Stimmen gegen die bekannten Stimmen dieses Meetings und gegen
///    einander: Klingen zwei eindeutig gleich, werden sie eine.
/// Was nicht eindeutig ist, bleibt unbenannt und erscheint unter „Wer spricht hier?“.
enum SpeakerRematcher {

    struct Voice: Equatable {
        let id: String
        let duration: Float
        let embedding: [Float]
        let name: String?
    }

    struct Plan: Equatable {
        /// Stimme bekommt einen Namen aus den Profilen.
        var names: [String: String] = [:]
        /// Stimme wird in eine andere eingegliedert.
        var merges: [String: String] = [:]

        var isEmpty: Bool { names.isEmpty && merges.isEmpty }
    }

    static func plan(voices: [Voice], profiles: [(name: String, embedding: [Float])],
                     excluding: Set<String> = []) -> Plan {
        var plan = Plan()
        let named = voices.filter { $0.name != nil }
        let unnamed = voices.filter { $0.name == nil && !$0.embedding.isEmpty }
        let idForName = Dictionary(named.map { (SpeakerNaming.key($0.name ?? ""), $0.id) }, uniquingKeysWith: { a, _ in a })

        // Stufe 1: Profile.
        let clusters = unnamed.map { MeetingProfileMatcher.Cluster(id: $0.id, duration: $0.duration, embedding: $0.embedding) }
        for (id, name) in MeetingProfileMatcher.match(clusters, profiles: profiles, excluding: excluding) {
            if let existing = idForName[SpeakerNaming.key(name)] { plan.merges[id] = existing } else { plan.names[id] = name }
        }

        // Stufe 2: untereinander. Vertreter sind die bekannten Stimmen, dann neu erkannte.
        var representatives = named.filter { !$0.embedding.isEmpty }.map { (id: $0.id, embedding: $0.embedding) }
        representatives += unnamed.filter { plan.names[$0.id] != nil }.map { (id: $0.id, embedding: $0.embedding) }
        for voice in unnamed.sorted(by: { $0.duration > $1.duration })
        where plan.names[voice.id] == nil && plan.merges[voice.id] == nil {
            let ranked = representatives
                .filter { $0.embedding.count == voice.embedding.count }
                .map { (id: $0.id, distance: SpeakerUtilities.cosineDistance(voice.embedding, $0.embedding)) }
                .sorted { $0.distance < $1.distance }
            let second = ranked.dropFirst().first?.distance ?? .infinity
            if voice.duration >= MeetingProfileMatcher.minimumSeconds, let best = ranked.first,
               best.distance <= MeetingProfileMatcher.maximumDistance,
               second - best.distance >= MeetingProfileMatcher.minimumMargin {
                plan.merges[voice.id] = best.id
            } else {
                representatives.append((id: voice.id, embedding: voice.embedding))
            }
        }
        return plan
    }
}

extension MeetingDocument {
    /// Wendet einen Abgleich an: Namen setzen, Stimmen umhängen.
    func applying(_ plan: SpeakerRematcher.Plan) -> MeetingDocument {
        var document = self
        for (id, name) in plan.names {
            document.speakerNames[id] = name
            document.nameSources[id] = .profile
        }
        document.lines = lines.map { line in
            guard let id = line.speakerID, let target = plan.merges[id] else { return line }
            return TranscriptLine(speaker: line.speaker, start: line.start, end: line.end, text: line.text, speakerID: target)
        }
        for id in plan.merges.keys {
            document.speakerNames[id] = nil
            document.nameSources[id] = nil
        }
        return document
    }
}

extension MeetingDocument {
    /// Baut die Zuordnung aus einer frischen Sprechertrennung neu auf: Jeder Beitrag der
    /// Gegenseite geht an die Stimme, die zeitlich am meisten mit ihm überlappt. Namen gibt
    /// es danach nur noch aus eindeutig passenden Profilen.
    func resettingSpeakers(to diarization: MeetingDiarization, excludingSelf: Bool) -> MeetingDocument {
        var document = self
        document.lines = lines.map { line in
            guard canReassign(line) else { return line }
            return TranscriptLine(speaker: line.speaker, start: line.start, end: line.end, text: line.text,
                                  speakerID: Self.speaker(for: line, in: diarization.segments))
        }
        document.speakerNames = [:]
        document.nameSources = [:]
        for (id, name) in diarization.knownNames where !(excludingSelf && SpeakerNaming.isSelf(name)) {
            document.speakerNames[id] = name
            document.nameSources[id] = .profile
        }
        document.learnedSamples = nil
        return document
    }

    /// Stimme mit dem größten zeitlichen Überlapp; ohne Überlapp der nächste Abschnitt.
    static func speaker(for line: TranscriptLine, in segments: [DiarizedSegment]) -> String? {
        var overlap: [String: TimeInterval] = [:]
        for segment in segments {
            let shared = min(segment.end, line.end) - max(segment.start, line.start)
            if shared > 0 { overlap[segment.speakerID, default: 0] += shared }
        }
        if let best = overlap.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
            return best.key
        }
        let middle = (line.start + line.end) / 2
        func distance(_ segment: DiarizedSegment) -> TimeInterval {
            middle < segment.start ? segment.start - middle : max(0, middle - segment.end)
        }
        return segments.min { distance($0) < distance($1) }?.speakerID
    }
}
