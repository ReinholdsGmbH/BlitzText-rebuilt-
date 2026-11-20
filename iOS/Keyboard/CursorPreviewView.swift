import UIKit

/// Vorschau während der Cursor-Steuerung: zeigt den Text rund um den Cursor in den nachgebildeten
/// Zeilen und einen Cursor, der stufenlos unter dem Finger gleitet. Eine fremde Tastatur kann den
/// Cursor in der Ziel-App nur zeichenweise versetzen; das flüssige Gleiten gibt es nur hier.
/// Der echte Cursor folgt dem nächstgelegenen Zeichen.
final class CursorPreviewView: UIView {
    private static let font = UIFont.systemFont(ofSize: 17)
    private static let lineHeight: CGFloat = 24
    /// So viel Abstand hält der gleitende Cursor zum oberen und unteren Rand, bevor gescrollt wird.
    private static let scrollMargin: CGFloat = 36
    /// Text im Tastaturbereich anzeigen. Aus, weil sich die Steuerung ohne sichtbaren Text im Test
    /// besser anfühlte; der gleitende Cursor rechnet trotzdem weiter und führt den echten Cursor.
    static let showsText = false

    private var model: CursorNavigator?
    /// Gleitender Cursor: x ab Zeilenanfang, y als Mitte der Zeile, beides in Punkt im Gesamttext.
    private var caret = CGPoint.zero
    private var snapped = 0
    private var scrollOffset: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// `keepingX`: nach dem Nachladen am Rand die waagerechte Lage des gleitenden Cursors behalten.
    func show(_ model: CursorNavigator, keepingX: Bool = false) {
        let previousX = caret.x
        self.model = model
        snapped = model.position
        caret = CGPoint(x: keepingX ? previousX : model.x(of: model.position),
                        y: (CGFloat(model.lineIndex(of: model.position)) + 0.5) * Self.lineHeight)
        scrollOffset = caret.y - bounds.height / 2
        clampScroll()
        isHidden = !Self.showsText
        setNeedsDisplay()
    }

    func hide() {
        model = nil
        isHidden = true
    }

    struct Move {
        /// Neue Zeichenposition, wenn der Cursor ein anderes Zeichen erreicht hat.
        var position: Int?
        /// Der Cursor steht an der ersten oder letzten bekannten Zeile und soll weiter: Die Tastatur
        /// kennt nur einen Ausschnitt des Textes, also muss neu gelesen werden.
        var pushesEdge = false
    }

    /// Verschiebt den gleitenden Cursor.
    func moveCaret(dx: CGFloat, dy: CGFloat) -> Move {
        guard let model else { return Move() }
        let firstLineY = Self.lineHeight / 2
        let lastLineY = (CGFloat(model.lines.count - 1) + 0.5) * Self.lineHeight
        let pushesEdge = (dy < 0 && caret.y <= firstLineY) || (dy > 0 && caret.y >= lastLineY)
        caret.x = min(max(caret.x + dx, 0), model.lineWidth)
        caret.y = min(max(caret.y + dy, firstLineY), lastLineY)
        if caret.y - scrollOffset < Self.scrollMargin { scrollOffset = caret.y - Self.scrollMargin }
        if caret.y - scrollOffset > bounds.height - Self.scrollMargin {
            scrollOffset = caret.y - bounds.height + Self.scrollMargin
        }
        clampScroll()
        setNeedsDisplay()
        let line = Int(caret.y / Self.lineHeight)
        var position = model.nearest(to: caret.x, inLine: line)
        // Über die erste oder letzte bekannte Zeile hinaus: echten Cursor ein Zeichen über den Rand
        // des Ausschnitts setzen. Erst dann liefert die Ziel-App beim Nachladen den Text dahinter.
        if pushesEdge { position = dy < 0 ? -1 : model.text.count + 1 }
        guard position != snapped else { return Move(pushesEdge: pushesEdge) }
        snapped = position
        return Move(position: position, pushesEdge: pushesEdge)
    }

    private func clampScroll() {
        guard let model else { return }
        let content = CGFloat(model.lines.count) * Self.lineHeight
        scrollOffset = min(max(scrollOffset, 0), max(content - bounds.height, 0))
    }

    override func draw(_ rect: CGRect) {
        guard let model else { return }
        let left = max((bounds.width - model.lineWidth) / 2, 12)
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: UIColor.label]
        let first = max(Int(scrollOffset / Self.lineHeight), 0)
        let last = min(Int((scrollOffset + bounds.height) / Self.lineHeight), model.lines.count - 1)
        if first <= last {
            for index in first...last {
                let line = model.lines[index]
                let string = String(model.text[line.start..<min(line.end, model.text.count)])
                let top = CGFloat(index) * Self.lineHeight - scrollOffset
                let y = top + (Self.lineHeight - Self.font.lineHeight) / 2
                (string as NSString).draw(at: CGPoint(x: left, y: y), withAttributes: attributes)
            }
        }
        // Wo der echte Cursor landet: dünn und grau.
        let snappedLine = model.lineIndex(of: snapped)
        let snappedTop = CGFloat(snappedLine) * Self.lineHeight - scrollOffset
        UIColor.secondaryLabel.setFill()
        UIRectFill(CGRect(x: left + model.x(of: snapped) - 0.5, y: snappedTop + 3, width: 1, height: Self.lineHeight - 6))
        // Gleitender Cursor unter dem Finger.
        let caretRect = CGRect(x: left + caret.x - 1.5, y: caret.y - scrollOffset - Self.lineHeight / 2 + 1,
                               width: 3, height: Self.lineHeight - 2)
        tintColor.setFill()
        UIBezierPath(roundedRect: caretRect, cornerRadius: 1.5).fill()
    }
}
