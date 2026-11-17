import Foundation

/// Zeitabschnitt mit Sprache innerhalb einer Spur, in Sekunden ab Spurbeginn.
struct SpeechSpan: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    var duration: TimeInterval { end - start }
}

/// Zerlegt eine Spur anhand der Lautstärke in Sprechabschnitte.
///
/// Wozu: Parakeet liefert für eine ganze Datei nur Text ohne Zeitstempel. Um zwei Spuren
/// zu einem Gesprächsverlauf zu verschränken, braucht jeder Satz eine Startzeit. Kurze
/// Abschnitte lösen das und halten nebenbei den Speicherbedarf bei einstündigen
/// Meetings klein, weil nie die ganze Spur auf einmal ins Modell geht.
///
/// Arbeitet auf vorab berechneten RMS-Werten je Frame, nicht auf Samples. So muss eine
/// Stunde Audio nie komplett im Speicher liegen, und die Logik bleibt ohne Audiodateien
/// testbar.
struct SpeechSegmenter {
    /// Länge eines RMS-Frames.
    var frameDuration: TimeInterval = 0.03
    /// Ab dieser Pause endet ein Abschnitt.
    var minPause: TimeInterval = 0.8
    /// Längere Abschnitte werden an der leisesten Stelle geteilt.
    var maxSegment: TimeInterval = 25
    /// Kürzere Abschnitte sind Klicks oder Räuspern und fallen weg.
    var minSegment: TimeInterval = 0.4
    /// Zugabe vor und nach jedem Abschnitt, damit keine Silbe abgeschnitten wird.
    var padding: TimeInterval = 0.2
    /// Untergrenze für „Sprache", unabhängig vom Grundrauschen.
    var absoluteFloor: Float = 0.01
    /// Sprache muss so viel lauter sein als das Grundrauschen der Spur.
    var noiseFactor: Float = 3
    /// Obergrenze der Schwelle. Spricht jemand fast ohne Pause, liegt das geschätzte
    /// Grundrauschen auf Sprachniveau, und ohne Deckel fiele die ganze Spur als Stille weg.
    var maxThreshold: Float = 0.03

    func spans(frameRMS rms: [Float]) -> [SpeechSpan] {
        guard !rms.isEmpty else { return [] }
        let threshold = max(absoluteFloor, min(maxThreshold, noiseFloor(of: rms) * noiseFactor))
        let pauseFrames = max(1, Int(minPause / frameDuration))
        let maxFrames = max(2, Int(maxSegment / frameDuration))

        var ranges: [Range<Int>] = []
        var start: Int?
        var lastVoiced = 0

        for index in rms.indices {
            let voiced = rms[index] > threshold
            if let open = start {
                if voiced { lastVoiced = index }
                if index - lastVoiced >= pauseFrames {
                    ranges.append(open..<(lastVoiced + 1))
                    start = nil
                } else if index - open >= maxFrames {
                    let cut = quietestFrame(in: rms, from: open + maxFrames / 2, to: index)
                    ranges.append(open..<cut)
                    start = cut
                    lastVoiced = max(lastVoiced, cut)
                }
            } else if voiced {
                start = index
                lastVoiced = index
            }
        }
        if let open = start { ranges.append(open..<(lastVoiced + 1)) }

        let total = TimeInterval(rms.count) * frameDuration
        return ranges.compactMap { range in
            let length = TimeInterval(range.count) * frameDuration
            guard length >= minSegment else { return nil }
            let begin = max(0, TimeInterval(range.lowerBound) * frameDuration - padding)
            let end = min(total, TimeInterval(range.upperBound) * frameDuration + padding)
            return SpeechSpan(start: begin, end: end)
        }
    }

    /// 20. Perzentil der Frame-Pegel: robust gegen Sprachanteile, solange in der Spur
    /// überhaupt Pausen vorkommen.
    private func noiseFloor(of rms: [Float]) -> Float {
        let sorted = rms.sorted()
        return sorted[min(sorted.count - 1, sorted.count / 5)]
    }

    private func quietestFrame(in rms: [Float], from lower: Int, to upper: Int) -> Int {
        guard lower < upper else { return upper }
        var best = lower
        for index in lower..<upper where rms[index] < rms[best] { best = index }
        return max(best, lower + 1)
    }
}
