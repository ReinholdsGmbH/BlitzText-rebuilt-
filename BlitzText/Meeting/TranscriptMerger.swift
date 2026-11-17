import Foundation

/// Ein Redebeitrag im Protokoll.
struct TranscriptLine: Equatable, Codable {
    /// Aus welcher Spur der Beitrag stammt.
    enum Speaker: String, Equatable, Codable {
        case me = "Ich"
        case others = "Andere"
    }

    let speaker: Speaker
    /// Sekunden ab Aufnahmebeginn.
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    /// Sprecher-ID aus der Diarisierung der Gegenseite. `nil` beim eigenen Mikrofon oder
    /// wenn keine Sprechertrennung lief.
    var speakerID: String? = nil
}

/// Verschränkt die Beiträge beider Spuren zu einem Gesprächsverlauf.
enum TranscriptMerger {

    /// - Parameters:
    ///   - echoSimilarity: Ab diesem Wortüberlapp gilt ein Mikrofon-Beitrag als Echo der
    ///     Gegenseite. Ohne Kopfhörer nimmt das Mikrofon die Lautsprecher mit auf, und
    ///     derselbe Satz stünde sonst doppelt im Protokoll, einmal fälschlich als „Ich".
    ///   - joinGap: Aufeinanderfolgende Beiträge derselben Seite mit kleinerer Pause
    ///     werden zu einem Absatz zusammengezogen.
    static func merge(
        _ lines: [TranscriptLine],
        echoSimilarity: Double = 0.6,
        joinGap: TimeInterval = 8
    ) -> [TranscriptLine] {
        let others = lines.filter { $0.speaker == .others }
        let withoutEcho = lines.filter { line in
            guard line.speaker == .me else { return true }
            return !others.contains { isEcho(line, of: $0, threshold: echoSimilarity) }
        }

        let ordered = withoutEcho
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }

        var merged: [TranscriptLine] = []
        for line in ordered {
            if let last = merged.last, last.speaker == line.speaker, last.speakerID == line.speakerID,
               line.start - last.end <= joinGap {
                merged[merged.count - 1] = TranscriptLine(
                    speaker: last.speaker,
                    start: last.start,
                    end: max(last.end, line.end),
                    text: last.text + " " + line.text,
                    speakerID: last.speakerID
                )
            } else {
                merged.append(line)
            }
        }
        return merged
    }

    /// Ein Echo läuft zeitgleich mit dem Original: Mindestens die Hälfte des eigenen
    /// Abschnitts muss sich mit dem der Gegenseite decken. Kurze Antworten unter drei
    /// Wörtern gelten nie als Echo, sonst fiele ein „Hallo" auf „Hallo zusammen" weg.
    static func isEcho(_ mine: TranscriptLine, of other: TranscriptLine, threshold: Double) -> Bool {
        let overlap = min(mine.end, other.end) - max(mine.start, other.start)
        let length = mine.end - mine.start
        guard length > 0, overlap >= length * 0.5 else { return false }
        guard min(words(mine.text).count, words(other.text).count) >= 3 else { return false }
        return similarity(mine.text, other.text) >= threshold
    }

    /// Anteil der Wörter des kürzeren Textes, die auch im längeren vorkommen. Bewusst
    /// nicht Jaccard: Ein Echo-Abschnitt ist oft nur ein Teil des Originalsatzes.
    static func similarity(_ a: String, _ b: String) -> Double {
        let wordsA = words(a), wordsB = words(b)
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0 }
        let (small, large) = wordsA.count <= wordsB.count ? (wordsA, wordsB) : (wordsB, wordsA)
        return Double(small.intersection(large).count) / Double(small.count)
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 })
    }
}
