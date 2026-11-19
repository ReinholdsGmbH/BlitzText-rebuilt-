import CoreGraphics
import Foundation

/// Swipe-Erkennung nach dem SHARK2-Prinzip (Kristensson & Zhai): Die Spur wird mit der idealen
/// Linie jedes Wortes über die Tastenmitten verglichen, nach Lage und nach Form, und mit der
/// Häufigkeit des Wortes gewichtet. Am Mac mit nachgebildeten Spuren erprobt: 99 % Treffer bei
/// normaler, 85 % bei grober Ungenauigkeit, rund 5 ms je Wort.
final class SwipeDecoder: @unchecked Sendable {
    struct Entry {
        let word: String
        let letters: [Character]
        let prior: Double
    }

    static let samples = 40
    private var byFirst: [Character: [Entry]] = [:]
    private(set) var wordCount = 0

    /// Lexikon „Wort<TAB>Wert“ je Zeile, dazu eigene Wörter mit hohem Gewicht.
    init(lexicon text: String, extraWords: [String]) {
        var best: [String: (word: String, score: Double)] = [:]
        func add(_ word: String, _ score: Double) {
            let key = word.lowercased()
            if let existing = best[key] {
                // Gibt es das Wort klein und groß, gewinnt die kleine Form; Großschreibung regelt Shift.
                let isLower = word == key
                let keepWord = isLower ? word : existing.word
                best[key] = (keepWord, max(existing.score, score))
            } else {
                best[key] = (word, score)
            }
        }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let score = Double(parts[1]) else { continue }
            add(String(parts[0]), score)
        }
        let top = best.values.map(\.score).max() ?? 1
        for word in extraWords { add(word, top * 0.5) }
        for (_, value) in best {
            let letters = Self.collapse(Self.keyLetters(value.word))
            guard letters.count >= 2, let first = letters.first else { continue }
            byFirst[first, default: []].append(Entry(word: value.word, letters: letters, prior: value.score / top))
        }
        wordCount = best.count
    }

    /// Buchstaben, wie sie auf den Tasten liegen: klein, ß wie s, Akzente weg, Umlaute bleiben.
    static func keyLetters(_ word: String) -> [Character] {
        word.lowercased().compactMap { character in
            if character == "ß" { return "s" }
            if "äöü".contains(character) { return character }
            let folded = String(character).folding(options: .diacriticInsensitive, locale: nil)
            return folded.first.flatMap { $0.isLetter ? $0 : nil }
        }
    }

    static func collapse(_ letters: [Character]) -> [Character] {
        letters.reduce(into: []) { result, letter in if result.last != letter { result.append(letter) } }
    }

    /// - Parameters:
    ///   - points: Spur in Tastatur-Koordinaten.
    ///   - centers: Mitte jeder Buchstabentaste.
    ///   - keyWidth: Breite einer Buchstabentaste (Maßstab für Abstände).
    func decode(points raw: [CGPoint], centers: [Character: CGPoint], keyWidth: CGFloat,
                usage: [String: Int] = [:], limit: Int = 4) -> [String] {
        guard raw.count >= 2, let first = raw.first, let last = raw.last, keyWidth > 0 else { return [] }
        let width = Double(keyWidth)
        let gesture = Self.resample(raw, Self.samples)
        let gestureShape = Self.normalizeShape(gesture)
        let gestureLength = Self.length(raw)
        let starts = Self.keys(near: first, centers: centers, radius: 1.25 * keyWidth)
        let ends = Set(Self.keys(near: last, centers: centers, radius: 1.25 * keyWidth))

        var results: [(word: String, cost: Double)] = []
        for start in starts {
            for entry in byFirst[start] ?? [] {
                guard let lastLetter = entry.letters.last, ends.contains(lastLetter) else { continue }
                let path = entry.letters.compactMap { centers[$0] }
                guard path.count == entry.letters.count else { continue }
                let ratio = gestureLength / max(Self.length(path), width * 0.5)
                guard ratio > 0.55, ratio < 1.9 else { continue }
                let template = Self.resample(path, Self.samples)
                let location = zip(gesture, template).map { Double(hypot($0.x - $1.x, $0.y - $1.y)) }.reduce(0, +)
                    / Double(Self.samples) / width
                let shape = zip(gestureShape, Self.normalizeShape(template)).map { Double(hypot($0.x - $1.x, $0.y - $1.y)) }.reduce(0, +)
                    / Double(Self.samples)
                // Eigene Gewohnheit: oft benutzte Wörter rücken nach vorn.
                let habit = 0.35 * log(1 + Double(usage[entry.word.lowercased()] ?? 0))
                results.append((entry.word, location + 2.0 * shape - 0.12 * log(entry.prior + 1e-4) - habit))
            }
        }
        results.sort { $0.cost < $1.cost }
        var seen = Set<String>()
        var words: [String] = []
        for result in results where seen.insert(result.word.lowercased()).inserted {
            words.append(result.word)
            if words.count == limit { break }
        }
        return words
    }

    private static func keys(near point: CGPoint, centers: [Character: CGPoint], radius: CGFloat) -> [Character] {
        centers.filter { hypot($0.value.x - point.x, $0.value.y - point.y) <= radius }.map(\.key)
    }

    static func length(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).map { Double(hypot($1.x - $0.x, $1.y - $0.y)) }.reduce(0, +)
    }

    /// Gleichmäßig verteilte Punkte entlang der Linie.
    static func resample(_ points: [CGPoint], _ count: Int) -> [CGPoint] {
        let total = length(points)
        guard total > 0, let firstPoint = points.first else { return Array(repeating: points.first ?? .zero, count: count) }
        let step = total / Double(count - 1)
        var output = [firstPoint]
        var accumulated = 0.0
        var previous = firstPoint
        var remaining = Array(points.dropFirst())
        while !remaining.isEmpty, output.count < count {
            let current = remaining[0]
            let distance = Double(hypot(current.x - previous.x, current.y - previous.y))
            if accumulated + distance >= step, distance > 0 {
                let t = CGFloat((step - accumulated) / distance)
                let point = CGPoint(x: previous.x + t * (current.x - previous.x), y: previous.y + t * (current.y - previous.y))
                output.append(point)
                previous = point
                accumulated = 0
            } else {
                accumulated += distance
                previous = current
                remaining.removeFirst()
            }
        }
        while output.count < count { output.append(points[points.count - 1]) }
        return output
    }

    /// Form ohne Lage und Größe: mittig und auf die längere Kante 1 skaliert.
    static func normalizeShape(_ points: [CGPoint]) -> [CGPoint] {
        let xs = points.map(\.x), ys = points.map(\.y)
        let scale = max((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0), 0.000_001)
        let cx = xs.reduce(0, +) / CGFloat(points.count), cy = ys.reduce(0, +) / CGFloat(points.count)
        return points.map { CGPoint(x: ($0.x - cx) / scale, y: ($0.y - cy) / scale) }
    }
}
