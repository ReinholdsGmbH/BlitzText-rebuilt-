import UIKit

/// Eine Taste. Optik an Apples Tastatur angelehnt: helle Buchstaben, dunklere Funktionstasten.
final class KeyCap: UIView {
    let spec: KeySpec
    private let label = UILabel()
    private let icon = UIImageView()

    private static let letterColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white }
    private static let specialColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1) }

    init(spec: KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        layer.cornerRadius = 7
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        isUserInteractionEnabled = false
        if let symbol = spec.symbol {
            icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
            icon.tintColor = .label
            icon.contentMode = .center
            addSubview(icon)
        } else {
            label.text = spec.label
            label.textAlignment = .center
            label.textColor = .label
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            label.font = spec.isSpecial || spec.action == .space ? .systemFont(ofSize: 16) : .systemFont(ofSize: 24)
            addSubview(label)
        }
        setHighlighted(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 0)
        icon.frame = bounds
    }

    func setHighlighted(_ highlighted: Bool) {
        let base = spec.isSpecial ? Self.specialColor : Self.letterColor
        let pressed = spec.isSpecial ? Self.letterColor : Self.specialColor
        backgroundColor = highlighted ? pressed : base
    }
}

/// Tastenfeld mit eigener Touch-Auswertung: Tippen, langer Druck, Löschen mit Wiederholung, Swipe.
final class KeyboardView: UIView {
    var onAction: ((KeyAction) -> Void)?
    var onInsertAlternate: ((String) -> Void)?
    /// Swipe fertig: besuchte Buchstaben in Reihenfolge und die Ecken der Spur.
    var onSwipe: ((_ path: [String], _ corners: [String]) -> Void)?
    var swipeEnabled = true

    var rows: [[KeySpec]] = [] { didSet { rebuild() } }
    var layer_: KeyboardLayer = .letters

    private var caps: [[KeyCap]] = []
    private let trail = CAShapeLayer()
    private let gap: CGFloat = 6
    private let rowGap: CGFloat = 11

    private var activeCap: KeyCap?
    private var startPoint: CGPoint = .zero
    private var points: [CGPoint] = []
    private var swipeLetters: [String] = []
    private var isSwiping = false
    private var longPressFired = false
    private var longPressTimer: Timer?
    private var repeatTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        trail.fillColor = UIColor.clear.cgColor
        trail.strokeColor = UIColor.systemOrange.withAlphaComponent(0.55).cgColor
        trail.lineWidth = 7
        trail.lineCap = .round
        trail.lineJoin = .round
        layer.addSublayer(trail)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func rebuild() {
        caps.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        caps = rows.map { row in row.map { KeyCap(spec: $0) } }
        caps.flatMap { $0 }.forEach { insertSubview($0, at: 0) }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !caps.isEmpty else { return }
        let side: CGFloat = 3
        let slot = (bounds.width - 2 * side) / KeyLayout.unitsPerRow
        let rowHeight = bounds.height / CGFloat(caps.count)
        for (rowIndex, row) in caps.enumerated() {
            let rowUnits = row.reduce(0) { $0 + $1.spec.width }
            var x = (bounds.width - rowUnits * slot) / 2
            let y = CGFloat(rowIndex) * rowHeight + rowGap / 2
            for cap in row {
                let width = cap.spec.width * slot
                cap.frame = CGRect(x: x + gap / 2, y: y, width: width - gap, height: rowHeight - rowGap)
                x += width
            }
        }
        trail.frame = bounds
    }

    /// Taste unter dem Finger; zwischen Tasten zählt die nächstgelegene in der Reihe.
    private func cap(at point: CGPoint) -> KeyCap? {
        guard !caps.isEmpty, bounds.height > 0 else { return nil }
        let rowHeight = bounds.height / CGFloat(caps.count)
        let rowIndex = min(max(Int(point.y / rowHeight), 0), caps.count - 1)
        return caps[rowIndex].min { abs($0.frame.midX - point.x) < abs($1.frame.midX - point.x) }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self), let cap = cap(at: point) else { return }
        reset()
        activeCap = cap
        startPoint = point
        points = [point]
        if let letter = cap.spec.letter { swipeLetters = [letter] }
        cap.setHighlighted(true)
        switch cap.spec.action {
        case .backspace:
            onAction?(.backspace)
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.startRepeating() }
            }
        default:
            if let alternate = cap.spec.alternate {
                longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.longPressFired = true
                        self?.activeCap?.setHighlighted(false)
                        self?.onInsertAlternate?(alternate)
                    }
                }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        points.append(point)
        let slot = bounds.width / KeyLayout.unitsPerRow
        if !isSwiping, !longPressFired, swipeEnabled, layer_ == .letters, activeCap?.spec.letter != nil,
           hypot(point.x - startPoint.x, point.y - startPoint.y) > slot * 0.9 {
            isSwiping = true
            longPressTimer?.invalidate()
            activeCap?.setHighlighted(false)
        }
        if isSwiping {
            if let letter = cap(at: point)?.spec.letter, letter != swipeLetters.last { swipeLetters.append(letter) }
            let path = UIBezierPath()
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
            trail.path = path.cgPath
        } else if repeatTimer == nil, !longPressFired, let cap = cap(at: point), cap !== activeCap {
            longPressTimer?.invalidate()
            activeCap?.setHighlighted(false)
            activeCap = cap
            cap.setHighlighted(true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isSwiping {
            if swipeLetters.count >= 2 {
                onSwipe?(swipeLetters, corners())
            } else if let letter = swipeLetters.first {
                onAction?(.character(letter))
            }
        } else if !longPressFired, let cap = activeCap, cap.spec.action != .backspace {
            onAction?(cap.spec.action)
        }
        reset()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { reset() }

    private func startRepeating() {
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onAction?(.backspace) }
        }
    }

    private func reset() {
        longPressTimer?.invalidate(); longPressTimer = nil
        repeatTimer?.invalidate(); repeatTimer = nil
        activeCap?.setHighlighted(false)
        activeCap = nil
        isSwiping = false
        longPressFired = false
        swipeLetters = []
        points = []
        trail.path = nil
    }

    /// Ecken der Spur: Punkte mit deutlichem Richtungswechsel, plus Anfang und Ende.
    private func corners() -> [String] {
        var sampled: [CGPoint] = []
        for point in points {
            if let last = sampled.last, hypot(point.x - last.x, point.y - last.y) < 12 { continue }
            sampled.append(point)
        }
        var result: [String] = []
        func add(_ point: CGPoint) {
            if let letter = cap(at: point)?.spec.letter, letter != result.last { result.append(letter) }
        }
        guard let first = sampled.first, let last = sampled.last else { return result }
        add(first)
        if sampled.count > 4 {
            for index in 2..<(sampled.count - 2) {
                let a = sampled[index - 2], b = sampled[index], c = sampled[index + 2]
                let v1 = CGVector(dx: b.x - a.x, dy: b.y - a.y), v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
                let angle = abs(atan2(v1.dx * v2.dy - v1.dy * v2.dx, v1.dx * v2.dx + v1.dy * v2.dy))
                if angle > .pi / 3.5 { add(b) }
            }
        }
        add(last)
        return result
    }
}
