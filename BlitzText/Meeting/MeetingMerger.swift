import AVFoundation
import Foundation

/// Führt mehrere Teile eines Termins zu einem Meeting zusammen, etwa wenn ein Termin durch
/// eine Pause oder einen anderen Anruf geteilt wurde.
///
/// Die Teile werden in zeitlicher Reihenfolge aneinandergehängt, versetzt um die Dauer der
/// vorigen Teile (nicht um die Uhrzeit: Pausen landen nicht als Stille in der Tonspur).
/// Tonspuren werden genauso aneinandergehängt, damit Hörproben und Abspielen weiter passen.
/// Sprecher mit gleichem Namen werden eine Person; unbenannte Stimmen bleiben je Teil getrennt,
/// weil ihre Nummern nur innerhalb eines Teils etwas bedeuten.
enum MeetingMerger {

    struct Part {
        let folder: URL
        let document: MeetingDocument
    }

    enum MergeError: LocalizedError {
        case tooFewParts
        case mixedKinds

        var errorDescription: String? {
            switch self {
            case .tooFewParts: return "Zum Zusammenführen mindestens zwei Meetings markieren."
            case .mixedKinds: return "Aufnahmen und importierte Mischspuren lassen sich nicht zusammenführen."
            }
        }
    }

    /// Tonspuren je Art des Meetings: Aufnahme (Mikrofon + Gegenseite) oder Import (Mischspur).
    static func trackFiles(for diarizedTrack: String) -> [String] {
        diarizedTrack == MeetingArchive.mixedTrackFile
            ? [MeetingArchive.mixedTrackFile]
            : [MeetingArchive.microphoneTrackFile, MeetingArchive.othersTrackFile]
    }

    // MARK: Dokument

    /// Reine Logik: das zusammengeführte Dokument aus den Teilen und ihren Längen.
    /// `lengths[i]` ist die Länge der Tonspuren von Teil i (Versatz für die folgenden Teile).
    static func mergedDocument(_ parts: [MeetingDocument], lengths: [TimeInterval]) throws -> MeetingDocument {
        guard parts.count >= 2, parts.count == lengths.count else { throw MergeError.tooFewParts }
        guard Set(parts.map(\.diarizedTrack)).count == 1 else { throw MergeError.mixedKinds }

        var lines: [TranscriptLine] = []
        var names: [String: String] = [:]
        var sources: [String: MeetingDocument.NameSource] = [:]
        /// Ein Name, eine Stimme über alle Teile.
        var idForName: [String: String] = [:]
        var offset: TimeInterval = 0

        for (index, part) in parts.enumerated() {
            var mapping: [String: String] = [:]
            for id in part.speakerIDs {
                if let name = part.speakerNames[id] {
                    let key = SpeakerNaming.key(name)
                    let merged = idForName[key] ?? "\(index + 1)-\(id)"
                    idForName[key] = merged
                    mapping[id] = merged
                    names[merged] = names[merged] ?? name
                    if let source = strongest(sources[merged], part.nameSources[id]) { sources[merged] = source }
                } else {
                    mapping[id] = "\(index + 1)-\(id)"
                }
            }
            for line in part.lines {
                lines.append(TranscriptLine(speaker: line.speaker, start: line.start + offset, end: line.end + offset,
                                            text: line.text, speakerID: line.speakerID.flatMap { mapping[$0] }))
            }
            offset += lengths[index]
        }

        let first = parts[0]
        var document = MeetingDocument(
            startedAt: first.startedAt,
            duration: offset,
            sourceNames: parts.flatMap(\.sourceNames).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } },
            lines: lines.sorted { $0.start < $1.start },
            summary: nil,
            notes: [partsNote(parts, lengths: lengths)] + parts.flatMap(\.notes),
            speakerNames: names,
            nameSources: sources,
            diarizedTrack: first.diarizedTrack
        )
        document.userNotes = mergedUserNotes(parts)
        if let chosen = parts.first(where: { $0.projectChosenByUser == true }) {
            document.project = chosen.project
            document.projectChosenByUser = true
        }
        return document
    }

    /// Bestätigt schlägt Profil schlägt von Hand schlägt Meeting-App.
    private static func strongest(_ a: MeetingDocument.NameSource?, _ b: MeetingDocument.NameSource?) -> MeetingDocument.NameSource? {
        let rank: [MeetingDocument.NameSource: Int] = [.confirmed: 4, .profile: 3, .manual: 2, .meetingApp: 1]
        return [a, b].compactMap { $0 }.max { (rank[$0] ?? 0) < (rank[$1] ?? 0) }
    }

    private static func partsNote(_ parts: [MeetingDocument], lengths: [TimeInterval]) -> String {
        let list = zip(parts, lengths).map { part, length in
            "\(MeetingMarkdown.stamp(part.startedAt, timeSeparator: ":")) (\(MeetingMarkdown.clock(length, alwaysHours: false)))"
        }
        return "Zusammengeführt aus \(parts.count) Teilen: " + list.joined(separator: ", ")
    }

    /// Eigene Notizen: eine bleibt, wie sie ist; mehrere bekommen je Teil eine Überschrift.
    private static func mergedUserNotes(_ parts: [MeetingDocument]) -> String? {
        let withNotes = parts.filter { !($0.userNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !withNotes.isEmpty else { return nil }
        if withNotes.count == 1 { return withNotes[0].userNotes }
        return withNotes.map { part in
            "Teil \(MeetingMarkdown.stamp(part.startedAt, timeSeparator: ":")):\n\(part.userNotes ?? "")"
        }.joined(separator: "\n\n")
    }

    // MARK: Dateien

    /// Legt das zusammengeführte Meeting als neuen Ordner an und liefert ihn zurück.
    /// Die Teile bleiben unangetastet; Aufräumen übernimmt der Aufrufer.
    static func merge(_ parts: [Part], into archive: MeetingArchive) throws -> URL {
        let sorted = parts.sorted { $0.document.startedAt < $1.document.startedAt }
        guard sorted.count >= 2 else { throw MergeError.tooFewParts }
        guard Set(sorted.map(\.document.diarizedTrack)).count == 1 else { throw MergeError.mixedKinds }
        let files = trackFiles(for: sorted[0].document.diarizedTrack)

        // Länge je Teil: die längste Tonspur, mindestens die gespeicherte Dauer.
        let lengths = sorted.map { part in
            files.map { duration(of: part.folder.appendingPathComponent($0)) }.reduce(part.document.duration, max)
        }
        let document = try mergedDocument(sorted.map(\.document), lengths: lengths)

        let folder = try archive.makeFolder(startedAt: document.startedAt, sourceName: "Zusammengeführt")
        do {
            for file in files {
                try concatenate(sorted.map { $0.folder.appendingPathComponent(file) }, lengths: lengths,
                                into: folder.appendingPathComponent(file))
            }
            _ = try archive.writeProtocol(document, in: folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }

    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// Hängt Spuren aneinander; jede wird mit Stille auf ihre Teil-Länge aufgefüllt, fehlende
    /// Spuren werden ganz zu Stille. Format wie die erste vorhandene Spur (16 kHz mono).
    static func concatenate(_ inputs: [URL], lengths: [TimeInterval], into output: URL) throws {
        let template = inputs.lazy.compactMap { try? AVAudioFile(forReading: $0) }.first
        let settings: [String: Any] = template?.fileFormat.settings ?? [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false
        ]
        let sampleRate = template?.fileFormat.sampleRate ?? 16_000
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false) else { return }
        let writer = try AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = AVAudioFramePosition(1 << 18)

        for (input, length) in zip(inputs, lengths) {
            var remaining = AVAudioFramePosition(length * sampleRate)
            if let reader = try? AVAudioFile(forReading: input, commonFormat: .pcmFormatFloat32, interleaved: false),
               reader.processingFormat.sampleRate == sampleRate, reader.processingFormat.channelCount == 1 {
                while remaining > 0, reader.framePosition < reader.length {
                    let wanted = AVAudioFrameCount(min(chunk, remaining))
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: wanted) else { break }
                    try reader.read(into: buffer, frameCount: wanted)
                    guard buffer.frameLength > 0 else { break }
                    try writer.write(from: buffer)
                    remaining -= AVAudioFramePosition(buffer.frameLength)
                }
            }
            // Auffüllen bis zur Teil-Länge, damit die Zeiten der folgenden Teile stimmen.
            while remaining > 0 {
                let count = AVAudioFrameCount(min(chunk, remaining))
                guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { break }
                silence.frameLength = count
                try writer.write(from: silence)
                remaining -= AVAudioFramePosition(count)
            }
        }
    }
}
