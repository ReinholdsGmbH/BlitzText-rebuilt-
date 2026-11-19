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

/// Ordnet die Wörter des Transkripts über ihre Zeitstempel den Sprechersegmenten zu.
/// Ergebnis wie am Mac: Absätze „Sprecher 1: …“. Nur eine Stimme: nil (Text bleibt ohne Sprecher).
enum SpeakerLabeler {
    static func label(asr: ASRResult, segments: [TimedSpeakerSegment]) -> String? {
        guard let timings = asr.tokenTimings, !timings.isEmpty,
              Set(segments.map(\.speakerId)).count >= 2 else { return nil }

        func speaker(at time: TimeInterval) -> String? {
            if let hit = segments.first(where: { Double($0.startTimeSeconds) <= time && time <= Double($0.endTimeSeconds) }) {
                return hit.speakerId
            }
            return segments.min(by: { distance($0, time) < distance($1, time) })?.speakerId
        }

        var paragraphs: [(speaker: String, text: String)] = []
        var currentSpeaker: String?
        var currentText = ""
        for timing in timings {
            let startsWord = timing.token.hasPrefix(" ") || currentText.isEmpty
            if startsWord, let next = speaker(at: timing.startTime), next != currentSpeaker {
                if let currentSpeaker, !currentText.trimmingCharacters(in: .whitespaces).isEmpty {
                    paragraphs.append((currentSpeaker, currentText))
                    currentText = ""
                }
                currentSpeaker = next
            }
            currentText += timing.token
        }
        if let currentSpeaker, !currentText.trimmingCharacters(in: .whitespaces).isEmpty {
            paragraphs.append((currentSpeaker, currentText))
        }

        var numbers: [String: Int] = [:]
        for paragraph in paragraphs where numbers[paragraph.speaker] == nil {
            numbers[paragraph.speaker] = numbers.count + 1
        }
        return paragraphs
            .map { "Sprecher \(numbers[$0.speaker] ?? 0): \($0.text.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "\n\n")
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

    init(store: MeetingStore, history: DictationHistory, parakeet: ParakeetEngine, log: @escaping (String) -> Void) {
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
            var transcript = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)

            store.update(id) { $0.status = .diarizing }
            do {
                let segments = try await diarizer.segments(for: samples)
                if let labeled = SpeakerLabeler.label(asr: asr, segments: segments) { transcript = labeled }
                log("Meeting: \(Set(segments.map(\.speakerId)).count) Stimmen erkannt")
            } catch {
                log("Meeting: Sprechertrennung fehlgeschlagen, Text ohne Sprecher (\(error.localizedDescription))")
            }

            store.update(id) { $0.transcript = transcript; $0.status = .summarizing }
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
        } catch {
            store.update(id) { $0.status = .failed(error.localizedDescription) }
            log("Meeting-Fehler: \(error.localizedDescription)")
        }
    }
}
