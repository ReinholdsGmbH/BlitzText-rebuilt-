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

    func show(_ model: CursorNavigator) {
        self.model = model
        snapped = model.position
        caret = CGPoint(x: model.x(of: model.position),
                        y: (CGFloat(model.lineIndex(of: model.position)) + 0.5) * Self.lineHeight)
        scrollOffset = caret.y - bounds.height / 2
        clampScroll()
        isHidden = false
        setNeedsDisplay()
    }

    func hide() {
        model = nil
        isHidden = true
    }

    /// Verschiebt den gleitenden Cursor. Liefert die neue Zeichenposition, wenn der Cursor dabei
    /// ein anderes Zeichen erreicht hat, sonst nil.
    func moveCaret(dx: CGFloat, dy: CGFloat) -> Int? {
        guard let model else { return nil }
        let lastLineY = (CGFloat(model.lines.count - 1) + 0.5) * Self.lineHeight
        caret.x = min(max(caret.x + dx, 0), model.lineWidth)
        caret.y = min(max(caret.y + dy, Self.lineHeight / 2), lastLineY)
        if caret.y - scrollOffset < Self.scrollMargin { scrollOffset = caret.y - Self.scrollMargin }
        if caret.y - scrollOffset > bounds.height - Self.scrollMargin {
            scrollOffset = caret.y - bounds.height + Self.scrollMargin
        }
        clampScroll()
        setNeedsDisplay()
        let line = Int(caret.y / Self.lineHeight)
        let position = model.nearest(to: caret.x, inLine: line)
        guard position != snapped else { return nil }
        snapped = position
        return position
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
