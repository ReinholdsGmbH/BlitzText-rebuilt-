import CoreGraphics

/// Textmodell für die Cursor-Steuerung über die Leertaste.
///
/// iOS gibt der Tastatur nur einen Ausschnitt des Textes und Zeichen-Verschiebungen, aber nicht
/// das Layout des Textfelds. Die sichtbaren Zeilen werden daher nachgebildet: Umbruch an
/// Wortgrenzen bei `lineWidth` Punkt, gemessen mit den echten Zeichenbreiten der Systemschrift.
/// Die Cursorposition führt das Modell selbst, weil der Textkontext der Ziel-App nach einer
/// Verschiebung oft verzögert stimmt.
struct CursorNavigator {
    struct Line: Equatable {
        let start: Int
        /// Letzte mögliche Cursorposition in der Zeile (vor dem Umbruch-Leerzeichen).
        let end: Int
    }

    let text: [Character]
    let lines: [Line]
    let lineWidth: CGFloat
    let advance: (Character) -> CGFloat
    /// Wo der echte Cursor in der Ziel-App steht, als Zeichenindex in `text`.
    var position: Int

    init(before: String, after: String, lineWidth: CGFloat, advance: @escaping (Character) -> CGFloat) {
        text = Array(before + after)
        position = before.count
        self.lineWidth = max(lineWidth, 40)
        self.advance = advance
        lines = Self.wrap(text, width: self.lineWidth, advance: advance)
    }

    /// Zeile, in der eine Cursorposition liegt.
    func lineIndex(of position: Int) -> Int {
        lines.lastIndex { $0.start <= position } ?? 0
    }

    /// Waagerechte Lage einer Cursorposition in ihrer Zeile, in Punkt ab Zeilenanfang.
    func x(of position: Int) -> CGFloat {
        let line = lines[lineIndex(of: position)]
        return text[line.start..<min(position, text.count)].reduce(0) { $0 + advance($1) }
    }

    /// Cursorposition in Zeile `index`, die der waagerechten Lage `goal` am nächsten liegt.
    func nearest(to goal: CGFloat, inLine index: Int) -> Int {
        let line = lines[min(max(index, 0), lines.count - 1)]
        var x: CGFloat = 0
        var position = line.start
        while position < line.end {
            let width = advance(text[position])
            if x + width / 2 > goal { break }
            x += width
            position += 1
        }
        return position
    }

    /// Umbruch wie in einem Textfeld: Absätze an "\n", darin nach dem letzten Leerzeichen, das
    /// noch passt; Leerzeichen dürfen über den Rand hängen. Ohne Leerzeichen hart umbrechen.
    static func wrap(_ text: [Character], width: CGFloat, advance: (Character) -> CGFloat) -> [Line] {
        var lines: [Line] = []
        var paragraphStart = 0
        while true {
            let paragraphEnd = text[paragraphStart...].firstIndex(of: "\n") ?? text.count
            var start = paragraphStart
            var index = start
            var x: CGFloat = 0
            var lastSpace: Int?
            while index < paragraphEnd {
                let character = text[index]
                let charWidth = advance(character)
                if character != " ", x + charWidth > width, index > start {
                    let breakAt = lastSpace.map { $0 + 1 } ?? index
                    lines.append(Line(start: start, end: breakAt - 1))
                    start = breakAt
                    index = breakAt
                    x = 0
                    lastSpace = nil
                    continue
                }
                if character == " " { lastSpace = index }
                x += charWidth
                index += 1
            }
            lines.append(Line(start: start, end: paragraphEnd))
            guard paragraphEnd < text.count else { break }
            paragraphStart = paragraphEnd + 1
        }
        return lines
    }
}
