import CoreText
import UIKit

/// Emoji-Auswahl der Tastatur: alle Apple-Emojis in Kategorien, durchgehend scrollbar wie bei
/// Apple, oben die Sprungleiste, unten „ABC“ und Löschen. Hautfarben per langem Druck.
/// Apples eigene Emoji-Tastatur lässt sich aus einer fremden Tastatur nicht einblenden.
final class EmojiPanel: UIView {
    var onInsert: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onClose: (() -> Void)?

    private static let recentKey = "recentEmojis"
    private static let recentLimit = 32
    private static let perRow: CGFloat = 8
    private static let rowHeight: CGFloat = 42
    private static let headerHeight: CGFloat = 26

    /// Kategorien ohne Emojis, die das installierte iOS nicht zeichnen kann. Die Liste kommt aus
    /// dem neuesten Unicode-Stand; was iOS noch nicht kennt, würde als Kästchen erscheinen.
    private var categories: [EmojiCatalog.Category] = []
    private var recents: [String] = []
    private var loading = false

    private let categoryBar = UIStackView()
    private let collection: UICollectionView
    private var tonePicker: UIView?
    private var selected = -1

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionHeadersPinToVisibleBounds = false
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Beim Einblenden: zuletzt verwendete neu lesen, beim ersten Mal die Liste aufbauen.
    func refresh() {
        recents = Blitz.defaults?.stringArray(forKey: Self.recentKey) ?? []
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

    private func remember(_ emoji: String) {
        var list = (Blitz.defaults?.stringArray(forKey: Self.recentKey) ?? []).filter { $0 != emoji }
        list.insert(emoji, at: 0)
        Blitz.defaults?.set(Array(list.prefix(Self.recentLimit)), forKey: Self.recentKey)
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
            button.tintColor = .secondaryLabel
            button.tag = index
            button.accessibilityLabel = titles[index]
            button.addAction(UIAction { [weak self] _ in self?.jump(to: index, animated: false) }, for: .touchUpInside)
            categoryBar.addArrangedSubview(button)
        }

        collection.backgroundColor = .clear
        collection.showsVerticalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.id)
        collection.register(EmojiHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                            withReuseIdentifier: EmojiHeader.id)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        longPress.minimumPressDuration = 0.35
        collection.addGestureRecognizer(longPress)

        let abc = UIButton(type: .system)
        abc.setTitle("ABC", for: .normal)
        abc.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        abc.tintColor = .label
        abc.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        let delete = UIButton(type: .system)
        delete.setImage(UIImage(systemName: "delete.left"), for: .normal)
        delete.tintColor = .label
        delete.addAction(UIAction { [weak self] _ in self?.onBackspace?() }, for: .touchUpInside)
        let bottom = UIStackView(arrangedSubviews: [abc, UIView(), delete])
        bottom.axis = .horizontal

        for view in [collection, categoryBar, bottom] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            collection.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            collection.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            collection.bottomAnchor.constraint(equalTo: categoryBar.topAnchor, constant: -2),
            categoryBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            categoryBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            categoryBar.heightAnchor.constraint(equalToConstant: 30),
            categoryBar.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            bottom.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            bottom.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    /// Abschnitt 0 = zuletzt verwendet, 1 … = Kategorien.
    private func emojis(in section: Int) -> [String] {
        section == 0 ? recents : categories[section - 1].emojis
    }

    private func jump(to section: Int, animated: Bool) {
        hideTonePicker()
        guard section < collection.numberOfSections, collection.numberOfItems(inSection: section) > 0 else { return }
        let header = IndexPath(item: 0, section: section)
        if let attributes = collection.layoutAttributesForSupplementaryElement(
            ofKind: UICollectionView.elementKindSectionHeader, at: header) {
            let maxOffset = max(collection.contentSize.height - collection.bounds.height, 0)
            collection.setContentOffset(CGPoint(x: 0, y: min(attributes.frame.minY, maxOffset)), animated: animated)
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
        guard let tones = EmojiCatalog.skinTones[emoji] else { return }
        showTonePicker([emoji] + tones, above: cell.convert(cell.bounds, to: self))
    }

    private func showTonePicker(_ options: [String], above anchor: CGRect) {
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
                self?.insert(option)
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
        addSubview(overlay)
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
        (cell as? EmojiCell)?.label.text = emojis(in: indexPath.section)[indexPath.item]
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: EmojiHeader.id,
                                                                     for: indexPath)
        (header as? EmojiHeader)?.label.text = indexPath.section == 0
            ? "ZULETZT VERWENDET" : categories[indexPath.section - 1].title.uppercased()
        return header
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        emojis(in: section).isEmpty ? .zero : CGSize(width: collectionView.bounds.width, height: Self.headerHeight)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: floor(collectionView.bounds.width / Self.perRow), height: Self.rowHeight)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        insert(emojis(in: indexPath.section)[indexPath.item])
    }

    /// Die Kategorie oben im sichtbaren Bereich hervorheben.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        hideTonePicker()
        let probe = CGPoint(x: 10, y: scrollView.contentOffset.y + Self.headerHeight + 4)
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

private final class EmojiHeader: UICollectionReusableView {
    static let id = "header"
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        label.frame = bounds.insetBy(dx: 8, dy: 0)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}
