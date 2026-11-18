import AVFoundation
import Foundation

/// Transkribiert beide Spuren eines Meetings abschnittsweise.
///
/// Jede Spur wird zuerst in Sprechabschnitte zerlegt (`SpeechSegmenter`), jeder Abschnitt
/// einzeln durch das lokale Modell geschickt. Das liefert die Startzeiten, die das
/// Verschränken beider Spuren braucht, und hält den Speicher klein.
final class MeetingTranscriber: @unchecked Sendable {

    struct Track {
        let url: URL
        let speaker: TranscriptLine.Speaker
        /// Vorgegebene Abschnitte aus der Sprechertrennung. `nil` heißt: am Pegel schneiden.
        var spans: [LabeledSpan]? = nil
    }

    struct LabeledSpan: Equatable {
        let span: SpeechSpan
        let speakerID: String?
    }

    /// Macht aus Diarisierungs-Abschnitten Schnittgrenzen für die Transkription:
    /// Nachbarn derselben Stimme mit kurzer Lücke zusammenziehen, Überlanges teilen,
    /// Schnipsel verwerfen.
    static func spans(
        from segments: [DiarizedSegment],
        joinGap: TimeInterval = 1.0,
        maxLength: TimeInterval = 25,
        minLength: TimeInterval = 0.4,
        padding: TimeInterval = 0.15
    ) -> [LabeledSpan] {
        var merged: [DiarizedSegment] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, last.speakerID == segment.speakerID, segment.start - last.end <= joinGap {
                merged[merged.count - 1] = DiarizedSegment(speakerID: last.speakerID, start: last.start, end: max(last.end, segment.end))
            } else {
                merged.append(segment)
            }
        }
        var result: [LabeledSpan] = []
        for segment in merged where segment.end - segment.start >= minLength {
            var start = segment.start
            while start < segment.end {
                let end = min(segment.end, start + maxLength)
                if end - start >= minLength {
                    result.append(LabeledSpan(
                        span: SpeechSpan(start: max(0, start - padding), end: end + padding),
                        speakerID: segment.speakerID
                    ))
                }
                start = end
            }
        }
        return result
    }

    enum TranscriberError: LocalizedError {
        case allSegmentsFailed(String)

        var errorDescription: String? {
            switch self {
            case .allSegmentsFailed(let reason):
                return "Kein Abschnitt ließ sich transkribieren: \(reason)"
            }
        }
    }

    private let transcriber: TranscriptionService
    private let segmenter: SpeechSegmenter
    private let language: String?

    init(transcriber: TranscriptionService, segmenter: SpeechSegmenter = SpeechSegmenter(), language: String?) {
        self.transcriber = transcriber
        self.segmenter = segmenter
        self.language = language
    }

    /// - Parameter progress: (fertige Abschnitte, Abschnitte gesamt), vom Hintergrund aus gerufen.
    func transcribe(
        _ tracks: [Track],
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [TranscriptLine] {
        var work: [(Track, LabeledSpan)] = []
        for track in tracks {
            let spans: [LabeledSpan]
            if let given = track.spans {
                spans = given
            } else {
                let rms = try Self.frameRMS(of: track.url, frameDuration: segmenter.frameDuration)
                spans = segmenter.spans(frameRMS: rms).map { LabeledSpan(span: $0, speakerID: nil) }
            }
            Log.write("MeetingTranscriber: \(track.speaker.rawValue) — \(spans.count) Abschnitte")
            work += spans.map { (track, $0) }
        }
        progress(0, work.count)

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-meeting-segments-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var lines: [TranscriptLine] = []
        var lastError: Error?
        for (index, (track, labeled)) in work.enumerated() {
            try Task.checkCancellation()
            let span = labeled.span
            let segmentURL = scratch.appendingPathComponent("\(index).wav")
            do {
                try Self.extract(span, from: track.url, to: segmentURL)
                let text = try await transcriber.transcribe(audioURL: segmentURL, language: language, prompt: nil)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    lines.append(TranscriptLine(speaker: track.speaker, start: span.start, end: span.end,
                                                text: text, speakerID: labeled.speakerID))
                }
            } catch {
                lastError = error
                Log.write("MeetingTranscriber: Abschnitt \(index) übersprungen — \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: segmentURL)
            progress(index + 1, work.count)
        }

        if lines.isEmpty, let lastError {
            throw TranscriberError.allSegmentsFailed(lastError.localizedDescription)
        }
        return lines
    }

    // MARK: - Audio

    /// RMS je Frame, blockweise gelesen, damit lange Spuren nicht komplett im Speicher liegen.
    static func frameRMS(of url: URL, frameDuration: TimeInterval) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameLength = max(1, AVAudioFrameCount(format.sampleRate * frameDuration))
        let blockFrames = frameLength * 1000
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockFrames) else { return [] }

        var result: [Float] = []
        result.reserveCapacity(Int(Double(file.length) / Double(frameLength)) + 1)
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: blockFrames)
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
            var offset = 0
            let available = Int(buffer.frameLength)
            while offset < available {
                let count = min(Int(frameLength), available - offset)
                var sum: Float = 0
                for i in offset..<(offset + count) { sum += channel[i] * channel[i] }
                result.append((sum / Float(count)).squareRoot())
                offset += count
            }
        }
        return result
    }

    /// Schreibt einen Zeitabschnitt der Spur als eigene WAV-Datei im Format der Quelle.
    static func extract(_ span: SpeechSpan, from source: URL, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let startFrame = AVAudioFramePosition(span.start * format.sampleRate)
        let frameCount = AVAudioFrameCount(max(0, span.duration) * format.sampleRate)
        guard startFrame < input.length, frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return }

        input.framePosition = startFrame
        try input.read(into: buffer, frameCount: min(frameCount, AVAudioFrameCount(input.length - startFrame)))

        let output = try AVAudioFile(
            forWriting: destination,
            settings: input.fileFormat.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try output.write(from: buffer)
    }
}
