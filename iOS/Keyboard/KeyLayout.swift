import UIKit

enum KeyboardLayer: Equatable {
    case letters, numbers, symbols
    /// Großer Ziffernblock für reine Zahlenfelder; `decimal` mit Komma statt ABC-Taste.
    case numberPad(decimal: Bool)
}

enum ShiftState { case off, on, locked }

enum KeyAction: Equatable {
    case character(String)
    case shift
    case backspace
    /// Rücktaste lange gehalten: so viele ganze Wörter löschen.
    case deleteWords(Int)
    /// Cursor-Steuerung: echten Cursor auf diesen Zeichenindex im Modell der Vorschau setzen.
    case cursorTo(Int)
    /// Cursor-Steuerung steht am Rand des bekannten Textausschnitts: Kontext neu lesen.
    case cursorReload
    /// Cursor-Steuerung über die Leertaste beginnt bzw. endet.
    case cursorBegan
    case cursorEnded
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
    /// Große Beschriftung (Ziffernblock).
    var large = false

    /// Kleiner Hinweis oben rechts auf der Taste: die Ziffer beim langen Druck.
    var hint: String? {
        guard let alternate, alternate.count == 1, alternate.first?.isLetter == false else { return nil }
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
                     digits: Blitz.DigitsMode = .off, urlField: Bool = false) -> [[KeySpec]] {
        switch layer {
        case .letters: letters(shift: shift, returnLabel: returnLabel, showGlobe: showGlobe, digits: digits, urlField: urlField)
        case .numbers: numbers(returnLabel: returnLabel, showGlobe: showGlobe)
        case .symbols: symbols(returnLabel: returnLabel, showGlobe: showGlobe)
        case .numberPad(let decimal): numberPad(decimal: decimal)
        }
    }

    /// Ziffern beim langen Druck auf die obere Reihe, wie auf vielen Android-Tastaturen.
    static let digitAlternates: [Character: String] = [
        "q": "1", "w": "2", "e": "3", "r": "4", "t": "5", "z": "6", "u": "7", "i": "8", "o": "9", "p": "0",
    ]

    private static func letters(shift: ShiftState, returnLabel: String, showGlobe: Bool, digits: Blitz.DigitsMode,
                                urlField: Bool) -> [[KeySpec]] {
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
            bottomRow(switchLabel: "123", switchTo: .numbers, returnLabel: returnLabel, showGlobe: showGlobe, urlField: urlField),
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

    /// 3 × 4 wie die iOS-Zahlentastatur. Links unten bei Dezimalfeldern das Dezimalzeichen,
    /// sonst „ABC“ zurück zu den Buchstaben (etwa für Codes mit Buchstaben).
    private static func numberPad(decimal: Bool) -> [[KeySpec]] {
        let width = unitsPerRow / 3
        func digit(_ text: String) -> KeySpec { var key = KeySpec.char(text); key.width = width; key.large = true; return key }
        let separator = Locale.current.decimalSeparator ?? ","
        let left: KeySpec = decimal ? digit(separator) : .special(.layer(.letters), label: "ABC", width: width)
        return ["123", "456", "789"].map { $0.map { digit(String($0)) } }
            + [[left, digit("0"), .special(.backspace, symbol: "delete.left", width: width)]]
    }

    /// Ziffern- und Zeichenreihen haben 10 statt 11 Tasten: auf volle Breite ziehen.
    private static func widen(_ row: [KeySpec]) -> [KeySpec] {
        let total = row.reduce(0) { $0 + $1.width }
        guard total < unitsPerRow, total > 0 else { return row }
        let factor = unitsPerRow / total
        return row.map { var key = $0; key.width *= factor; return key }
    }

    /// In URL-Feldern stehen „/“ links und „.“ (lang „:“) rechts neben der Leertaste.
    private static func bottomRow(switchLabel: String, switchTo: KeyboardLayer, returnLabel: String, showGlobe: Bool,
                                  urlField: Bool = false) -> [KeySpec] {
        var row: [KeySpec] = [.special(.layer(switchTo), label: switchLabel, width: 1.4),
                              .special(.emoji, symbol: "face.smiling", width: 1.2)]
        if showGlobe { row.append(.special(.globe, symbol: "globe", width: 1.2)) }
        let returnKey = KeySpec.special(.returnKey, label: returnLabel, width: 2.4)
        let beside: (left: KeySpec, right: KeySpec)? = urlField ? (.char("/"), .char(".", alternate: ":")) : nil
        let used = row.reduce(0) { $0 + $1.width } + returnKey.width
            + (beside.map { $0.left.width + $0.right.width } ?? 0)
        if let beside { row.append(beside.left) }
        row.append(KeySpec(action: .space, label: "Leerzeichen", symbol: nil, width: unitsPerRow - used, alternate: nil))
        if let beside { row.append(beside.right) }
        row.append(returnKey)
        return row
    }
}
