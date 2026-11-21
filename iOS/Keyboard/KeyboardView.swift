import UIKit

/// Eine Taste. Optik an Apples Tastatur angelehnt: helle Buchstaben, dunklere Funktionstasten.
final class KeyCap: UIView {
    let spec: KeySpec
    private let label = UILabel()
    private let icon = UIImageView()
    private let hintLabel = UILabel()

    private static let letterColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white }
    static let specialColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1) }

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
            label.font = spec.large ? .systemFont(ofSize: 28) : (spec.isSpecial || spec.action == .space ? .systemFont(ofSize: 16) : .systemFont(ofSize: 24))
            addSubview(label)
        }
        if let hint = spec.hint {
            hintLabel.text = hint
            hintLabel.font = .systemFont(ofSize: 10, weight: .medium)
            hintLabel.textColor = .secondaryLabel
            addSubview(hintLabel)
        }
        setHighlighted(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 0)
        icon.frame = bounds
        hintLabel.frame = CGRect(x: bounds.width - 10, y: 2, width: 8, height: 12)
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
    var onSwipe: ((_ path: [String], _ corners: [String], _ points: [CGPoint]) -> Void)?

    /// Mitte jeder Buchstabentaste und Breite einer Buchstabentaste, für den Swipe-Decoder.
    var letterGeometry: (centers: [Character: CGPoint], keyWidth: CGFloat) {
        var centers: [Character: CGPoint] = [:]
        var width: CGFloat = 0
        for cap in caps.flatMap({ $0 }) {
            guard let letter = cap.spec.letter?.first else { continue }
            centers[letter] = CGPoint(x: cap.frame.midX, y: cap.frame.midY)
            width = max(width, cap.frame.width + gap)
        }
        return (centers, width)
    }
    var swipeEnabled = true

    var rows: [[KeySpec]] = [] { didSet { rebuild() } }
    var layer_: KeyboardLayer = .letters
    /// Erste Reihe flacher (Ziffernleiste über den Buchstaben).
    var compactFirstRow = false { didSet { setNeedsLayout() } }
    private static let compactWeight: CGFloat = 0.72

    private var caps: [[KeyCap]] = []
    private let trail = CAShapeLayer()
    /// Spur wird fortgeschrieben statt bei jeder Bewegung neu aufgebaut.
    private var trailPath = CGMutablePath()
    private let gap: CGFloat = 6
    private let rowGap: CGFloat = 11

    private var activeCap: KeyCap?
    /// Der Finger, der gerade ausgewertet wird. Weitere Finger beim schnellen Tippen lösen den
    /// vorigen Anschlag sofort aus, statt verloren zu gehen.
    private weak var activeTouch: UITouch?
    private var startPoint: CGPoint = .zero
    private var points: [CGPoint] = []
    private var swipeLetters: [String] = []
    private var isSwiping = false
    private var longPressFired = false
    private var longPressTimer: Timer?
    private var repeatTimer: Timer?

    // Cursor-Steuerung über die Leertaste: waagerecht wie ein Trackpad mit Beschleunigung,
    // senkrecht wie ein Joystick. Die Auslenkung über oder unter dem Startpunkt bestimmt das Tempo
    // in Zeilen pro Sekunde; zurück auf Höhe des Startpunkts heißt Stopp.
    private var cursorMode = false
    private var cursorLast: CGPoint = .zero
    private var cursorLastTime: TimeInterval = 0
    private var joystickTimer: Timer?
    private var joystickLastTick: TimeInterval = 0
    private let cursorPreview = CursorPreviewView()
    /// Zeilenhöhe der Vorschau; das Joystick-Tempo ist in Zeilen pro Sekunde angegeben.
    private static let previewLineHeight: CGFloat = 24
    /// Ruhezone um den Startpunkt: so weit darf der Finger senkrecht wackeln, ohne dass etwas läuft.
    private static let joystickDeadZone: CGFloat = 14
    private var cursorStartY: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        trail.fillColor = UIColor.clear.cgColor
        trail.strokeColor = UIColor.systemOrange.withAlphaComponent(0.55).cgColor
        trail.lineWidth = 7
        trail.lineCap = .round
        trail.lineJoin = .round
        layer.addSublayer(trail)
        cursorPreview.isHidden = true
        addSubview(cursorPreview)

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
        let bands = rowBands()
        for (rowIndex, row) in caps.enumerated() {
            let rowUnits = row.reduce(0) { $0 + $1.spec.width }
            var x = (bounds.width - rowUnits * slot) / 2
            let band = bands[rowIndex]
            for cap in row {
                let width = cap.spec.width * slot
                cap.frame = CGRect(x: x + gap / 2, y: band.minY + rowGap / 2, width: width - gap, height: band.height - rowGap)
                x += width
            }
        }
        trail.frame = bounds
    }

    /// Senkrechte Bereiche der Reihen; bei Ziffernleiste ist die erste flacher.
    private func rowBands() -> [(minY: CGFloat, height: CGFloat)] {
        let weights = caps.indices.map { $0 == 0 && compactFirstRow ? Self.compactWeight : 1 }
        let unit = bounds.height / weights.reduce(0, +)
        var y: CGFloat = 0
        return weights.map { weight in
            defer { y += weight * unit }
            return (y, weight * unit)
        }
    }

    /// Taste unter dem Finger; zwischen Tasten zählt die nächstgelegene in der Reihe.
    private func cap(at point: CGPoint) -> KeyCap? {
        guard !caps.isEmpty, bounds.height > 0 else { return nil }
        let bands = rowBands()
        let rowIndex = bands.firstIndex { point.y < $0.minY + $0.height } ?? caps.count - 1
        return caps[rowIndex].min { abs($0.frame.midX - point.x) < abs($1.frame.midX - point.x) }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { begin(touch) }
    }

    private func begin(_ touch: UITouch) {
        let point = touch.location(in: self)
        guard let cap = cap(at: point) else { return }
        if activeTouch != nil {
            // Cursorfahrt gehört einem Finger. Ein laufender Swipe oder Anschlag wird abgeschlossen,
            // sobald der nächste Finger aufsetzt (Wischen mit zwei Daumen, schnelles Tippen).
            if cursorMode { return }
            finishActive()
        }
        reset()
        activeTouch = touch
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
        case .space:
            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.beginCursorMode(at: self.points.last ?? self.startPoint)
                }
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
        guard let touch = activeTouch, touches.contains(touch) else { return }
        let point = touch.location(in: self)
        // Alle Zwischenpunkte (120 Hz) übernehmen, sonst fehlen bei schnellem Wischen die Bögen.
        let samples = event?.coalescedTouches(for: touch)?.map { $0.location(in: self) } ?? [point]
        points.append(contentsOf: samples.isEmpty ? [point] : samples)
        if cursorMode {
            moveCursor(to: point, at: touch.timestamp)
            return
        }
        let slot = bounds.width / KeyLayout.unitsPerRow
        let distance = hypot(point.x - startPoint.x, point.y - startPoint.y)
        // Leertaste ziehen startet die Cursorfahrt sofort, ohne erst lange zu halten.
        if activeCap?.spec.action == .space, distance > slot * 0.5 {
            beginCursorMode(at: point)
            cursorLastTime = touch.timestamp
            return
        }
        // Sichtbares Ziehen bricht den langen Druck für Umlaute ab, sonst stirbt ein langsam
        // begonnener Swipe am Timer.
        if !longPressFired, distance > slot * 0.35 { longPressTimer?.invalidate() }
        if !isSwiping, !longPressFired, swipeEnabled, layer_ == .letters, activeCap?.spec.letter != nil,
           distance > slot * 0.75 {
            isSwiping = true
            longPressTimer?.invalidate()
            activeCap?.setHighlighted(false)
        }
        if isSwiping {
            for sample in samples {
                if let letter = cap(at: sample)?.spec.letter, letter != swipeLetters.last { swipeLetters.append(letter) }
            }
            if trailPath.isEmpty {
                trailPath.move(to: points[0])
                points.dropFirst().forEach { trailPath.addLine(to: $0) }
            } else {
                samples.forEach { trailPath.addLine(to: $0) }
            }
            trail.path = trailPath.copy()
        } else if repeatTimer == nil, !longPressFired, let cap = cap(at: point), cap !== activeCap {
            longPressTimer?.invalidate()
            activeCap?.setHighlighted(false)
            activeCap = cap
            cap.setHighlighted(true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        finishActive()
        reset()
    }

    /// Schließt ab, was der aktive Finger begonnen hat: Cursorfahrt, Swipe oder Anschlag.
    private func finishActive() {
        if cursorMode {
            onAction?(.cursorEnded)
        } else if isSwiping {
            if swipeLetters.count >= 2 {
                onSwipe?(swipeLetters, corners(), points)
            } else if let letter = swipeLetters.first {
                onAction?(.character(letter))
            }
        } else {
            commitActiveKey()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        if cursorMode { onAction?(.cursorEnded) }
        reset()
    }

    /// Normaler Anschlag beim Loslassen (oder wenn schon der nächste Finger aufsetzt).
    private func commitActiveKey() {
        guard !longPressFired, let cap = activeCap, cap.spec.action != .backspace else { return }
        onAction?(cap.spec.action)
    }

    // MARK: - Cursorfahrt

    private func beginCursorMode(at point: CGPoint) {
        guard !cursorMode else { return }
        longPressTimer?.invalidate()
        cursorMode = true
        cursorLast = point
        // Ruhepunkt ist, wo der Finger auf der Leertaste aufgesetzt hat, nicht wo die Fahrt erkannt wurde.
        cursorStartY = startPoint.y
        cursorLastTime = CACurrentMediaTime()
        joystickLastTick = CACurrentMediaTime()
        activeCap?.setHighlighted(false)
        caps.flatMap { $0 }.forEach { $0.alpha = CursorPreviewView.showsText ? 0.06 : 0.35 }
        onAction?(.cursorBegan)
        joystickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.joystickTick() }
        }
    }

    /// Schnelle Bewegung zählt mehr: langsam zeichengenau, zügig quer durch den Text.
    private static func gain(speed: CGFloat) -> CGFloat {
        1 + min(max(speed - 150, 0) / 350, 3)
    }

    func showCursorPreview(_ model: CursorNavigator, keepingX: Bool = false) {
        cursorPreview.frame = bounds
        cursorPreview.show(model, keepingX: keepingX)
    }

    private var lastContextReload: TimeInterval = 0
    /// Abstand zwischen zwei Neu-Lese-Versuchen am Textrand; die Ziel-App braucht einen Moment,
    /// bis ihr Kontext nach einer Cursor-Verschiebung stimmt.
    private static let contextReloadInterval: TimeInterval = 0.25

    private func apply(_ move: CursorPreviewView.Move) {
        if let position = move.position { onAction?(.cursorTo(position)) }
        let now = CACurrentMediaTime()
        if move.pushesEdge, now - lastContextReload > Self.contextReloadInterval {
            lastContextReload = now
            onAction?(.cursorReload)
        }
    }

    private func moveCursor(to point: CGPoint, at time: TimeInterval) {
        let dt = max(time - cursorLastTime, 0.004)
        let dx = point.x - cursorLast.x
        cursorLast = point
        cursorLastTime = time
        // Waagerecht nur, solange der Joystick ruht: beim Hoch- und Runterfahren soll ein schräger
        // Finger die waagerechte Position nicht verschieben.
        guard linesPerSecond(at: point.y) == 0 else { return }
        apply(cursorPreview.moveCaret(dx: dx * Self.gain(speed: abs(dx) / dt), dy: 0))
    }

    /// Joystick-Tempo: negativ nach oben, positiv nach unten, null in der Ruhezone. Nach oben ist
    /// viel Platz (bis über die Tasten), nach unten nur wenige Punkt bis zum Displayrand, daher
    /// steigt das Tempo dort steiler.
    private func linesPerSecond(at y: CGFloat) -> CGFloat {
        let offset = y - cursorStartY
        let beyond = abs(offset) - Self.joystickDeadZone
        guard beyond > 0 else { return 0 }
        if offset < 0 { return -min(1.5 + beyond * 0.1, 30) }
        return min(1.5 + beyond * 0.4, 20)
    }

    private func joystickTick() {
        let now = CACurrentMediaTime()
        let dt = now - joystickLastTick
        joystickLastTick = now
        let rate = cursorMode ? linesPerSecond(at: cursorLast.y) : 0
        guard rate != 0 else { return }
        // Stufenlos: der Cursor gleitet mit dem Tempo durch die Zeilen, statt von Zeile zu Zeile zu springen.
        apply(cursorPreview.moveCaret(dx: 0, dy: CGFloat(dt) * rate * Self.previewLineHeight))
    }

    /// Löschen wiederholt Zeichen für Zeichen; nach 2 s Halten ganze Wörter, wie bei Apple.
    /// Danach wird es schneller: ab 3 s zwei, ab 4 s drei Wörter je Schritt.
    private func startRepeating() {
        let pressedAt = Date().addingTimeInterval(-0.45)
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Date().timeIntervalSince(pressedAt) >= 2 {
                    self.repeatTimer?.invalidate()
                    self.onAction?(.deleteWords(1))
                    self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated {
                            let held = Date().timeIntervalSince(pressedAt)
                            let words = held >= 4 ? 3 : held >= 3 ? 2 : 1
                            self?.onAction?(.deleteWords(words))
                        }
                    }
                } else {
                    self.onAction?(.backspace)
                }
            }
        }
    }

    private func reset() {
        longPressTimer?.invalidate(); longPressTimer = nil
        repeatTimer?.invalidate(); repeatTimer = nil
        joystickTimer?.invalidate(); joystickTimer = nil
        activeTouch = nil
        activeCap?.setHighlighted(false)
        activeCap = nil
        isSwiping = false
        longPressFired = false
        if cursorMode { caps.flatMap { $0 }.forEach { $0.alpha = 1 } }
        cursorPreview.hide()
        cursorMode = false
        swipeLetters = []
        points = []
        trail.path = nil
        trailPath = CGMutablePath()
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
