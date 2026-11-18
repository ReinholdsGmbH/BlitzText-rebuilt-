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

        var errorDescription: String? {
            switch self {
            case .tooFewParts: return "Zum Zusammenführen mindestens zwei Meetings markieren."
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
            diarizedTrack: targetTrack(for: parts)
        )
        document.userNotes = mergedUserNotes(parts)
        if let chosen = parts.first(where: { $0.projectChosenByUser == true }) {
            document.project = chosen.project
            document.projectChosenByUser = true
        }
        return document
    }

    /// Gleiche Art: bleibt, wie sie ist. Gemischt (Aufnahme mit Spurpaar und Import mit
    /// Mischspur): Das Ergebnis wird eine Mischspur, Spurpaare werden dafür zusammengemischt.
    static func targetTrack(for parts: [MeetingDocument]) -> String {
        let kinds = Set(parts.map(\.diarizedTrack))
        return kinds.count == 1 ? parts[0].diarizedTrack : MeetingArchive.mixedTrackFile
    }

    /// Welche Dateien eines Teils in eine Zielspur fließen.
    static func sources(for target: String, in part: MeetingDocument) -> [String] {
        guard target == MeetingArchive.mixedTrackFile, part.diarizedTrack != MeetingArchive.mixedTrackFile else { return [target] }
        return [MeetingArchive.microphoneTrackFile, MeetingArchive.othersTrackFile]
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
        let documents = sorted.map(\.document)
        let targets = trackFiles(for: targetTrack(for: documents))

        // Länge je Teil: die längste seiner Tonspuren, mindestens die gespeicherte Dauer.
        let lengths = sorted.map { part in
            trackFiles(for: part.document.diarizedTrack)
                .map { duration(of: part.folder.appendingPathComponent($0)) }
                .reduce(part.document.duration, max)
        }
        let document = try mergedDocument(documents, lengths: lengths)

        let folder = try archive.makeFolder(startedAt: document.startedAt, sourceName: "Zusammengeführt")
        do {
            for target in targets {
                let inputs = sorted.map { part in
                    sources(for: target, in: part.document).map { part.folder.appendingPathComponent($0) }
                }
                try concatenate(inputs, lengths: lengths, into: folder.appendingPathComponent(target))
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

    /// Hängt Teile aneinander. Ein Teil kann aus mehreren Spuren bestehen, die dann
    /// zusammengemischt werden (Mikrofon plus Gegenseite zur Mischspur). Jeder Teil wird mit
    /// Stille auf seine Länge aufgefüllt; fehlende Spuren zählen als Stille.
    static func concatenate(_ parts: [[URL]], lengths: [TimeInterval], into output: URL) throws {
        let template = parts.joined().lazy.compactMap { try? AVAudioFile(forReading: $0) }.first
        let settings: [String: Any] = template?.fileFormat.settings ?? [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false
        ]
        let sampleRate = template?.fileFormat.sampleRate ?? 16_000
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false) else { return }
        let writer = try AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = AVAudioFramePosition(1 << 18)

        for (inputs, length) in zip(parts, lengths) {
            let readers = inputs.compactMap { url -> AVAudioFile? in
                guard let reader = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
                      reader.processingFormat.sampleRate == sampleRate, reader.processingFormat.channelCount == 1 else { return nil }
                return reader
            }
            var remaining = AVAudioFramePosition(length * sampleRate)
            while remaining > 0 {
                let count = AVAudioFrameCount(min(chunk, remaining))
                guard let mix = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
                      let out = mix.floatChannelData?[0] else { break }
                mix.frameLength = count
                out.update(repeating: 0, count: Int(count))
                for reader in readers where reader.framePosition < reader.length {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: count) else { continue }
                    try reader.read(into: buffer, frameCount: count)
                    guard let samples = buffer.floatChannelData?[0] else { continue }
                    for i in 0..<Int(buffer.frameLength) { out[i] += samples[i] }
                }
                // Beim Zusammenmischen nicht übersteuern.
                if readers.count > 1 { for i in 0..<Int(count) { out[i] = max(-1, min(1, out[i])) } }
                try writer.write(from: mix)
                remaining -= AVAudioFramePosition(count)
            }
        }
    }
}
