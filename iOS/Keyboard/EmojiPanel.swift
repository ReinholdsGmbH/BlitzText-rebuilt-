import CoreText
import UIKit

/// Emoji-Auswahl der Tastatur: alle Apple-Emojis in Kategorien, waagerecht durchgehend
/// scrollbar wie bei Apple, unten eine Leiste aus „ABC“, Kategorien und Löschen. Hautfarben per langem Druck, die
/// gewählte Farbe gilt danach als Standard für diese Figur.
/// Apples eigene Emoji-Tastatur lässt sich aus einer fremden Tastatur nicht einblenden.
final class EmojiPanel: UIView {
    var onInsert: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onClose: (() -> Void)?
    /// Suchfeld oben angetippt.
    var onSearch: (() -> Void)?

    private static let recentKey = "recentEmojis"
    /// Gewählte Hautfarbe je Figur, wie bei Apple: Grundform → Variante.
    private static let toneKey = "emojiSkinTones"
    /// Variante → Grundform, damit auch ein Emoji aus „Zuletzt verwendet“ die Auswahl öffnet.
    private static let toneBase: [String: String] = {
        var map: [String: String] = [:]
        for (base, variants) in EmojiCatalog.skinTones { for variant in variants { map[variant] = base } }
        return map
    }()
    private var preferredTones: [String: String] = [:]
    private static let recentLimit = 32
    private static let perRow: CGFloat = 8
    private static let minRowHeight: CGFloat = 40
    private static let sectionGap: CGFloat = 12

    /// Kategorien ohne Emojis, die das installierte iOS nicht zeichnen kann. Die Liste kommt aus
    /// dem neuesten Unicode-Stand; was iOS noch nicht kennt, würde als Kästchen erscheinen.
    private var categories: [EmojiCatalog.Category] = []
    private var recents: [String] = []
    private var loading = false

    private let categoryBar = UIStackView()
    private let collection: UICollectionView
    private var tonePicker: UIView?
    private var selected = -1
    private var deleteTimer: Timer?
    private let bottomBar = TouchBar()

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.scrollDirection = .horizontal
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Beim Einblenden: zuletzt verwendete neu lesen, beim ersten Mal die Liste aufbauen.
    func refresh() {
        recents = Blitz.defaults?.stringArray(forKey: Self.recentKey) ?? []
        preferredTones = Blitz.defaults?.dictionary(forKey: Self.toneKey) as? [String: String] ?? [:]
        hideTonePicker()
        guard categories.isEmpty else {
            collection.reloadData()
            return
        }
        guard !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let available = EmojiCatalog.categories.map { category in
                EmojiCatalog.Category(symbol: category.symbol, title: category.title,
                                      emojis: category.emojis.filter(Self.isRenderable))
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.categories = available
                self.loading = false
                self.collection.reloadData()
                self.collection.layoutIfNeeded()
                self.jump(to: self.recents.isEmpty ? 1 : 0, animated: false)
            }
        }
    }

    /// Zeichnet die Emoji-Schrift das Emoji als ein einziges Bild? Unbekannte Einzelzeichen landen
    /// in einer Ersatzschrift, unbekannte Sequenzen zerfallen in mehrere Emojis nebeneinander und
    /// werden dadurch breiter. Paare setzt Apple aus zwei halben Glyphen zusammen, daher zählt
    /// die Breite und nicht die Zahl der Glyphen.
    private nonisolated static func isRenderable(_ emoji: String) -> Bool {
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 30, nil)
        func line(_ text: String) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        }
        let measured = line(emoji)
        guard let runs = CTLineGetGlyphRuns(measured) as? [CTRun], !runs.isEmpty else { return false }
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            guard !glyphs.contains(0),
                  let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] else { return false }
            // swiftlint:disable:next force_cast
            guard (CTFontCopyPostScriptName(runFont as! CTFont) as String) == "AppleColorEmoji" else { return false }
        }
        let single = CTLineGetTypographicBounds(line("😀"), nil, nil, nil)
        return CTLineGetTypographicBounds(measured, nil, nil, nil) <= single * 1.5
    }

    /// Zuletzt verwendete Emojis, für die Suche ohne Eingabe.
    static var recentEmojis: [String] { Blitz.defaults?.stringArray(forKey: recentKey) ?? [] }

    /// Bei Figuren die zuletzt gewählte Hautfarbe, auch für Suchtreffer.
    static func withPreferredTone(_ emoji: String) -> String {
        (Blitz.defaults?.dictionary(forKey: toneKey) as? [String: String])?[emoji] ?? emoji
    }

    private func remember(_ emoji: String) { Self.remember(emoji) }

    static func remember(_ emoji: String) {
        var list = (Blitz.defaults?.stringArray(forKey: Self.recentKey) ?? []).filter { $0 != emoji }
        list.insert(emoji, at: 0)
        Blitz.defaults?.set(Array(list.prefix(Self.recentLimit)), forKey: Self.recentKey)
    }

    /// Was im Raster steht: bei Figuren die zuletzt gewählte Hautfarbe.
    private func displayed(_ emoji: String) -> String {
        preferredTones[emoji] ?? emoji
    }

    /// Hautfarbe merken und das Raster sofort darauf umstellen.
    private func choose(_ variant: String, for base: String) {
        if variant == base { preferredTones[base] = nil } else { preferredTones[base] = variant }
        Blitz.defaults?.set(preferredTones, forKey: Self.toneKey)
        collection.reloadData()
        insert(variant)
    }

    private func insert(_ emoji: String) {
        remember(emoji)
        onInsert?(emoji)
    }

    // MARK: - Aufbau

    private func build() {
        categoryBar.axis = .horizontal
        categoryBar.distribution = .fillEqually
        let symbols = ["clock"] + EmojiCatalog.categories.map(\.symbol)
        let titles = ["Zuletzt verwendet"] + EmojiCatalog.categories.map(\.title)
        for (index, symbol) in symbols.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.setPreferredSymbolConfiguration(.init(pointSize: 15, weight: .regular), forImageIn: .normal)
            button.tintColor = .secondaryLabel
            button.tag = index
            button.accessibilityLabel = titles[index]
            categoryBar.addArrangedSubview(button)
        }

        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.alwaysBounceHorizontal = true
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.id)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        longPress.minimumPressDuration = 0.35
        collection.addGestureRecognizer(longPress)

        // Eine Leiste wie bei Apple: „ABC“, Kategorien, Löschen. „ABC“ und Löschen als echte Tasten,
        // als reiner Text war „ABC“ nur etwa 30 pt breit und Tipps daneben gingen ins Leere.
        let abc = Self.bottomKey(title: "ABC")
        let delete = Self.bottomKey(symbol: "delete.left")
        let bottom = bottomBar
        [abc, categoryBar, delete].forEach(bottom.addArrangedSubview)
        bottom.axis = .horizontal
        bottom.spacing = 4
        abc.widthAnchor.constraint(equalToConstant: 50).isActive = true
        delete.widthAnchor.constraint(equalToConstant: 50).isActive = true

        // Suchfeld wie bei Apple; antippen wechselt auf die Buchstaben mit Trefferleiste.
        var searchConfig = UIButton.Configuration.filled()
        searchConfig.baseBackgroundColor = .tertiarySystemFill
        searchConfig.baseForegroundColor = .secondaryLabel
        searchConfig.background.cornerRadius = 10
        searchConfig.image = UIImage(systemName: "magnifyingglass")
        searchConfig.imagePadding = 8
        searchConfig.attributedTitle = AttributedString("Emoji suchen", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17)]))
        let search = UIButton(configuration: searchConfig)
        search.contentHorizontalAlignment = .leading
        search.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)

        for view in [search, collection, bottom] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            search.heightAnchor.constraint(equalToConstant: 34),
            collection.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 4),
            collection.leadingAnchor.constraint(equalTo: leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -4),
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            bottom.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            bottom.heightAnchor.constraint(equalToConstant: 40),
        ])
        bottom.onPress = { [weak self] index in
            guard let self else { return }
            hideTonePicker()
            switch index {
            case 0: onClose?()
            case categoryBar.arrangedSubviews.count + 1: startDeleting()
            default: jump(to: index - 1, animated: false)
            }
        }
        bottom.onRelease = { [weak self] in self?.stopDeleting() }
    }

    /// Löschen gedrückt halten wiederholt wie auf der Tastatur.
    private func startDeleting() {
        stopDeleting()
        onBackspace?()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    MainActor.assumeIsolated { self?.onBackspace?() }
                }
            }
        }
    }

    private func stopDeleting() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    override func layoutSubviews() {
        let height = collection.bounds.height
        super.layoutSubviews()
        if collection.bounds.height != height { collection.collectionViewLayout.invalidateLayout() }
    }

    /// Taste im Stil der Sondertasten der Tastatur; löst schon beim Aufsetzen aus wie dort.
    private static func bottomKey(title: String? = nil, symbol: String? = nil) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = KeyCap.specialColor
        config.baseForegroundColor = .label
        config.background.cornerRadius = 6
        if let title {
            config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 16)]))
        }
        if let symbol { config.image = UIImage(systemName: symbol) }
        config.contentInsets = .zero
        return UIButton(configuration: config)
    }

    /// Abschnitt 0 = zuletzt verwendet, 1 … = Kategorien.
    private func emojis(in section: Int) -> [String] {
        section == 0 ? recents : categories[section - 1].emojis
    }

    private func jump(to section: Int, animated: Bool) {
        hideTonePicker()
        guard section < collection.numberOfSections, collection.numberOfItems(inSection: section) > 0 else { return }
        // Läuft das Raster nach einem Wisch noch aus, überschreibt der Schwung sonst den Sprung.
        collection.setContentOffset(collection.contentOffset, animated: false)
        if let attributes = collection.layoutAttributesForItem(at: IndexPath(item: 0, section: section)) {
            let maxOffset = max(collection.contentSize.width - collection.bounds.width, 0)
            let x = min(max(attributes.frame.minX - Self.sectionGap / 2, 0), maxOffset)
            collection.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
        }
        highlight(section)
    }

    private func highlight(_ section: Int) {
        guard section != selected else { return }
        selected = section
        for case let button as UIButton in categoryBar.arrangedSubviews {
            button.tintColor = button.tag == section ? .label : .secondaryLabel
        }
    }

    // MARK: - Hautfarben

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let path = collection.indexPathForItem(at: gesture.location(in: collection)),
              let cell = collection.cellForItem(at: path) else { return }
        let emoji = emojis(in: path.section)[path.item]
        let base = Self.toneBase[emoji] ?? emoji
        guard let tones = EmojiCatalog.skinTones[base] else { return }
        showTonePicker([base] + tones, for: base, above: cell.convert(cell.bounds, to: self))
    }

    private func showTonePicker(_ options: [String], for base: String, above anchor: CGRect) {
        hideTonePicker()
        let overlay = UIControl(frame: bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.addAction(UIAction { [weak self] _ in self?.hideTonePicker() }, for: .touchUpInside)

        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        for option in options {
            let button = UIButton(type: .system)
            button.setTitle(option, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 30)
            button.addAction(UIAction { [weak self] _ in
                self?.hideTonePicker()
                self?.choose(option, for: base)
            }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        let width = CGFloat(options.count) * 44 + 8
        var x = anchor.midX - width / 2
        x = min(max(x, 4), bounds.width - width - 4)
        let y = max(anchor.minY - 52, 2)
        let bubble = UIView(frame: CGRect(x: x, y: y, width: width, height: 50))
        bubble.backgroundColor = .systemBackground
        bubble.layer.cornerRadius = 10
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.25
        bubble.layer.shadowRadius = 6
        bubble.layer.shadowOffset = CGSize(width: 0, height: 2)
        row.frame = bubble.bounds.insetBy(dx: 4, dy: 2)
        bubble.addSubview(row)
        overlay.addSubview(bubble)
        // Unter der Leiste, damit ein Tipp auf ABC oder eine Kategorie nicht nur die Auswahl schließt.
        insertSubview(overlay, belowSubview: bottomBar)
        tonePicker = overlay
    }

    private func hideTonePicker() {
        tonePicker?.removeFromSuperview()
        tonePicker = nil
    }
}

extension EmojiPanel: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        categories.isEmpty ? 0 : categories.count + 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        emojis(in: section).count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.id, for: indexPath)
        (cell as? EmojiCell)?.label.text = displayed(emojis(in: indexPath.section)[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        emojis(in: section).isEmpty ? .zero : UIEdgeInsets(top: 0, left: Self.sectionGap / 2, bottom: 0, right: Self.sectionGap / 2)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // Spalten von oben nach unten gefüllt wie bei Apple; so viele Reihen, wie in die Höhe passen.
        let height = collectionView.bounds.height
        let rows = max(floor(height / Self.minRowHeight), 1)
        return CGSize(width: floor((collectionView.bounds.width - Self.sectionGap) / Self.perRow), height: floor(height / rows))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        insert(displayed(emojis(in: indexPath.section)[indexPath.item]))
    }

    /// Die Kategorie am linken Rand des sichtbaren Bereichs hervorheben.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        hideTonePicker()
        let probe = CGPoint(x: scrollView.contentOffset.x + Self.sectionGap + 4, y: 10)
        if let path = collection.indexPathForItem(at: probe) { highlight(path.section) }
    }
}

private final class EmojiCell: UICollectionViewCell {
    static let id = "emoji"
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 30)
        label.textAlignment = .center
        label.frame = contentView.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(label)
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = .tertiarySystemFill
        selectedBackgroundView?.layer.cornerRadius = 8
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}

/// Untere Leiste mit eigener Touch-Behandlung wie die Buchstabentastatur: Ein Tipp löst sofort beim
/// Aufsetzen aus und trifft immer das nächstgelegene Feld, auch zwischen zwei Symbolen. Mit einzelnen
/// UIButtons gingen Tipps am unteren Bildschirmrand verloren.
private final class TouchBar: UIStackView {
    /// Index über alle Felder: 0 = ABC, dann die Kategorien, zuletzt Löschen.
    var onPress: ((Int) -> Void)?
    var onRelease: (() -> Void)?
    private var pressed: UIButton?

    private var targets: [UIButton] {
        arrangedSubviews.flatMap { view -> [UIButton] in
            if let stack = view as? UIStackView { return stack.arrangedSubviews.compactMap { $0 as? UIButton } }
            return (view as? UIButton).map { [$0] } ?? []
        }
    }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        subview.isUserInteractionEnabled = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let x = touch.location(in: self).x
        let all = targets
        guard let index = all.indices.min(by: {
            abs(all[$0].convert(all[$0].bounds, to: self).midX - x) < abs(all[$1].convert(all[$1].bounds, to: self).midX - x)
        }) else { return }
        pressed = all[index]
        pressed?.isHighlighted = true
        onPress?(index)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { release() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { release() }

    private func release() {
        pressed?.isHighlighted = false
        pressed = nil
        onRelease?()
    }
}
