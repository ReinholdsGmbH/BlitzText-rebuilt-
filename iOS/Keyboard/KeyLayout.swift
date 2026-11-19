import UIKit

enum KeyboardLayer { case letters, numbers, symbols }

enum ShiftState { case off, on, locked }

enum KeyAction: Equatable {
    case character(String)
    case shift
    case backspace
    /// Rücktaste lange gehalten: ganzes Wort löschen.
    case deleteWord
    /// Leertaste lange gehalten und gezogen: Cursor um so viele Zeichen verschieben.
    case moveCursor(Int)
    /// Leertaste gehalten und nach oben/unten gezogen: eine Zeile hoch (-1) oder runter (+1).
    case moveCursorLine(Int)
    case space
    case returnKey
    case globe
    /// Emoji-Auswahl öffnen.
    case emoji
    case layer(KeyboardLayer)
}

struct KeySpec {
    let action: KeyAction
    let label: String?
    let symbol: String?
    /// Breite in Tasten-Einheiten (eine Buchstabentaste = 1).
    var width: CGFloat
    /// Langer Druck fügt diesen Text ein (z. B. s → ß).
    var alternate: String?

    /// Kleiner Hinweis oben rechts auf der Taste: die Ziffer beim langen Druck.
    var hint: String? {
        guard let alternate, alternate.count == 1, alternate.first?.isNumber == true else { return nil }
        return alternate
    }

    var isSpecial: Bool {
        if case .character = action { return false }
        if case .space = action { return false }
        return true
    }

    var letter: String? {
        if case .character(let text) = action, text.count == 1, text.first?.isLetter == true { return text.lowercased() }
        return nil
    }

    static func char(_ text: String, alternate: String? = nil) -> KeySpec {
        KeySpec(action: .character(text), label: text, symbol: nil, width: 1, alternate: alternate)
    }

    static func special(_ action: KeyAction, label: String? = nil, symbol: String? = nil, width: CGFloat) -> KeySpec {
        KeySpec(action: action, label: label, symbol: symbol, width: width, alternate: nil)
    }
}

/// Deutsches QWERTZ-Layout mit Umlauten in den Reihen wie bei Apple, ß per langem Druck auf s.
enum KeyLayout {
    static let unitsPerRow: CGFloat = 11

    static func rows(layer: KeyboardLayer, shift: ShiftState, returnLabel: String, showGlobe: Bool,
                     digits: Blitz.DigitsMode = .off) -> [[KeySpec]] {
        switch layer {
        case .letters: letters(shift: shift, returnLabel: returnLabel, showGlobe: showGlobe, digits: digits)
        case .numbers: numbers(returnLabel: returnLabel, showGlobe: showGlobe)
        case .symbols: symbols(returnLabel: returnLabel, showGlobe: showGlobe)
        }
    }

    /// Ziffern beim langen Druck auf die obere Reihe, wie auf vielen Android-Tastaturen.
    static let digitAlternates: [Character: String] = [
        "q": "1", "w": "2", "e": "3", "r": "4", "t": "5", "z": "6", "u": "7", "i": "8", "o": "9", "p": "0",
    ]

    private static func letters(shift: ShiftState, returnLabel: String, showGlobe: Bool, digits: Blitz.DigitsMode) -> [[KeySpec]] {
        let upper = shift != .off
        func keys(_ string: String) -> [KeySpec] {
            string.map { character in
                let text = upper ? String(character).uppercased() : String(character)
                var alternate = character == "s" ? (upper ? "SS" : "ß") : nil
                if digits == .longPress, let digit = digitAlternates[character] { alternate = digit }
                return .char(text, alternate: alternate)
            }
        }
        let digitRow = digits == .row ? [widen("1234567890".map { KeySpec.char(String($0)) })] : []
        let shiftSymbol = switch shift {
        case .off: "shift"
        case .on: "shift.fill"
        case .locked: "capslock.fill"
        }
        return digitRow + [
            keys("qwertzuiopü"),
            keys("asdfghjklöä"),
            [.special(.shift, symbol: shiftSymbol, width: 2)] + keys("yxcvbnm") + [.special(.backspace, symbol: "delete.left", width: 2)],
            bottomRow(switchLabel: "123", switchTo: .numbers, returnLabel: returnLabel, showGlobe: showGlobe),
        ]
    }

    private static func numbers(returnLabel: String, showGlobe: Bool) -> [[KeySpec]] {
        [
            "1234567890".map { KeySpec.char(String($0)) },
            ["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""].map { KeySpec.char($0) },
            [.special(.layer(.symbols), label: "#+=", width: 1.5)] + [".", ",", "?", "!", "'", "ß"].map { KeySpec.char($0) }
                + [.special(.backspace, symbol: "delete.left", width: 1.5)],
            bottomRow(switchLabel: "ABC", switchTo: .letters, returnLabel: returnLabel, showGlobe: showGlobe),
        ].map(widen)
    }

    private static func symbols(returnLabel: String, showGlobe: Bool) -> [[KeySpec]] {
        [
            ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { KeySpec.char($0) },
            ["_", "\\", "|", "~", "<", ">", "$", "£", "§", "•"].map { KeySpec.char($0) },
            [.special(.layer(.numbers), label: "123", width: 1.5)] + [".", ",", "?", "!", "'", "…"].map { KeySpec.char($0) }
                + [.special(.backspace, symbol: "delete.left", width: 1.5)],
            bottomRow(switchLabel: "ABC", switchTo: .letters, returnLabel: returnLabel, showGlobe: showGlobe),
        ].map(widen)
    }

    /// Ziffern- und Zeichenreihen haben 10 statt 11 Tasten: auf volle Breite ziehen.
    private static func widen(_ row: [KeySpec]) -> [KeySpec] {
        let total = row.reduce(0) { $0 + $1.width }
        guard total < unitsPerRow, total > 0 else { return row }
        let factor = unitsPerRow / total
        return row.map { var key = $0; key.width *= factor; return key }
    }

    private static func bottomRow(switchLabel: String, switchTo: KeyboardLayer, returnLabel: String, showGlobe: Bool) -> [KeySpec] {
        var row: [KeySpec] = [.special(.layer(switchTo), label: switchLabel, width: 1.4),
                              .special(.emoji, symbol: "face.smiling", width: 1.2)]
        if showGlobe { row.append(.special(.globe, symbol: "globe", width: 1.2)) }
        let returnKey = KeySpec.special(.returnKey, label: returnLabel, width: 2.4)
        let used = row.reduce(0) { $0 + $1.width } + returnKey.width
        row.append(KeySpec(action: .space, label: "Leerzeichen", symbol: nil, width: unitsPerRow - used, alternate: nil))
        row.append(returnKey)
        return row
    }
}
