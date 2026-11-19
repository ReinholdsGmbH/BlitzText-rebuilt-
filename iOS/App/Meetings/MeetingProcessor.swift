import FluidAudio
import Foundation

/// Sprechertrennung für Meetings. Das Modell (~80 MB) lädt beim ersten Meeting herunter.
/// Kein Actor: `DiarizerManager` ist nicht Sendable. Aufgerufen wird nur nacheinander vom
/// MainActor-`MeetingProcessor`, deshalb @unchecked Sendable.
final class MeetingDiarizer: @unchecked Sendable {
    private var manager: DiarizerManager?

    func segments(for samples: [Float]) async throws -> [TimedSpeakerSegment] {
        if manager == nil {
            let models = try await DiarizerModels.downloadIfNeeded()
            let diarizer = DiarizerManager(config: .default)
            diarizer.initialize(models: models)
            manager = diarizer
        }
        guard let manager else { return [] }
        return try await manager.performCompleteDiarization(samples).segments
    }
}

/// Baut aus den Wort-Zeitstempeln Abschnitte mit Zeit und Sprecher, wie sie der Mac als
/// Protokollzeilen kennt. Neuer Abschnitt bei Sprecherwechsel, nach einer Pause oder wenn ein
/// Abschnitt lang wird. Text: bei mehreren Stimmen „Sprecher N: …“-Absätze, sonst Fließtext.
enum TranscriptBuilder {
    static let pauseBreak: TimeInterval = 1.5
    static let maxWords = 60

    static func build(asr: ASRResult, speakers: [TimedSpeakerSegment]) -> (text: String, segments: [TranscriptSegment]) {
        let plain = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timings = asr.tokenTimings, !timings.isEmpty else {
            return (plain, plain.isEmpty ? [] : [TranscriptSegment(speaker: nil, start: 0, end: asr.duration, text: plain)])
        }
        let multiple = Set(speakers.map(\.speakerId)).count >= 2

        func speaker(at time: TimeInterval) -> String? {
            guard multiple else { return nil }
            if let hit = speakers.first(where: { Double($0.startTimeSeconds) <= time && time <= Double($0.endTimeSeconds) }) {
                return hit.speakerId
            }
            return speakers.min(by: { distance($0, time) < distance($1, time) })?.speakerId
        }

        var raw: [(speaker: String?, start: TimeInterval, end: TimeInterval, text: String)] = []
        var current: (speaker: String?, start: TimeInterval, end: TimeInterval, text: String)?
        for timing in timings {
            let startsWord = timing.token.hasPrefix(" ") || current == nil
            if startsWord, var open = current {
                let next = speaker(at: timing.startTime)
                let words = open.text.split(separator: " ").count
                let pause = timing.startTime - open.end
                if next != open.speaker || pause >= pauseBreak || words >= maxWords {
                    open.text = open.text.trimmingCharacters(in: .whitespaces)
                    if !open.text.isEmpty { raw.append(open) }
                    current = (next, timing.startTime, timing.endTime, timing.token)
                    continue
                }
                open.text += timing.token
                open.end = timing.endTime
                current = open
            } else if var open = current {
                open.text += timing.token
                open.end = timing.endTime
                current = open
            } else {
                current = (speaker(at: timing.startTime), timing.startTime, timing.endTime, timing.token)
            }
        }
        if var open = current {
            open.text = open.text.trimmingCharacters(in: .whitespaces)
            if !open.text.isEmpty { raw.append(open) }
        }

        // Sprecher in Reihenfolge des ersten Auftretens durchnummerieren: „1“, „2“, …
        var numbers: [String: Int] = [:]
        for part in raw { if let id = part.speaker, numbers[id] == nil { numbers[id] = numbers.count + 1 } }
        let segments = raw.map { part in
            TranscriptSegment(speaker: part.speaker.flatMap { numbers[$0] }.map(String.init),
                              start: part.start, end: part.end, text: part.text)
        }
        guard multiple else { return (plain, segments) }

        var paragraphs: [(speaker: String, text: String)] = []
        for segment in segments {
            let label = "Sprecher \(segment.speaker ?? "?")"
            if paragraphs.last?.speaker == label {
                paragraphs[paragraphs.count - 1].text += " " + segment.text
            } else {
                paragraphs.append((label, segment.text))
            }
        }
        return (paragraphs.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n\n"), segments)
    }

    private static func distance(_ segment: TimedSpeakerSegment, _ time: TimeInterval) -> Double {
        min(abs(Double(segment.startTimeSeconds) - time), abs(Double(segment.endTimeSeconds) - time))
    }
}

/// Ablauf nach dem Stopp: Audio auf 16 kHz, Parakeet, Sprechertrennung, Notizen.
@MainActor
final class MeetingProcessor {
    private let store: MeetingStore
    private let history: DictationHistory
    private let parakeet: ParakeetEngine
    private let diarizer = MeetingDiarizer()
    private let summarizer = MeetingSummarizer()
    private let log: (String) -> Void
    private let sharedFolder: SharedFolder

    init(store: MeetingStore, history: DictationHistory, parakeet: ParakeetEngine, sharedFolder: SharedFolder,
         log: @escaping (String) -> Void) {
        self.sharedFolder = sharedFolder
        self.store = store
        self.history = history
        self.parakeet = parakeet
        self.log = log
    }

    func process(_ id: UUID) async {
        let urls = store.audioURLs(for: id)
        store.update(id) { $0.status = .transcribing }
        do {
            // Alle Teile (bei „Fortsetzen“) hintereinander, mit einer halben Sekunde Stille dazwischen.
            let samples = try await Task.detached(priority: .userInitiated) {
                var all: [Float] = []
                for (index, url) in urls.enumerated() {
                    if index > 0 { all += [Float](repeating: 0, count: 8_000) }
                    all += try AudioConverter().resampleAudioFile(url)
                }
                return all
            }.value
            guard samples.count >= 16_000 else {
                store.update(id) { $0.status = .failed("Aufnahme zu kurz") }
                return
            }
            let started = Date()
            let asr = try await parakeet.transcribe(samples: samples)
            log(String(format: "Meeting: Parakeet %.1f s für %.0f s Audio", Date().timeIntervalSince(started),
                       Double(samples.count) / 16_000))
            store.update(id) { $0.status = .diarizing }
            var speakers: [TimedSpeakerSegment] = []
            do {
                speakers = try await diarizer.segments(for: samples)
                log("Meeting: \(Set(speakers.map(\.speakerId)).count) Stimmen erkannt")
            } catch {
                log("Meeting: Sprechertrennung fehlgeschlagen, Text ohne Sprecher (\(error.localizedDescription))")
            }
            let built = TranscriptBuilder.build(asr: asr, speakers: speakers)
            let transcript = built.text

            store.update(id) { $0.transcript = transcript; $0.segments = built.segments; $0.status = .summarizing }
            // Nur den Zuwachs zählen: erneut verarbeiten oder fortsetzen zählt nichts doppelt.
            let words = WordCounter.count(transcript)
            let already = store.meeting(id)?.countedWords ?? 0
            if words > already { history.addMeetingWords(words - already) }
            store.update(id) { $0.countedWords = max(words, already) }

            let notes = await summarizer.notes(for: transcript)
            store.update(id) { meeting in
                if let title = notes.title, !title.isEmpty { meeting.title = title }
                meeting.summary = notes.markdown
                meeting.status = .done
            }
            if sharedFolder.autoDeliver, sharedFolder.isConfigured {
                await sharedFolder.deliver(id, store: store, log: log)
            }
        } catch {
            store.update(id) { $0.status = .failed(error.localizedDescription) }
            log("Meeting-Fehler: \(error.localizedDescription)")
        }
    }
}
