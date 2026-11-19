import UIKit

/// Emoji-Auswahl der Tastatur: Kategorien oben, Raster zum Scrollen, unten „ABC“ und Löschen.
/// Apples eigene Emoji-Tastatur lässt sich aus einer fremden Tastatur nicht einblenden.
final class EmojiPanel: UIView {
    var onInsert: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onClose: (() -> Void)?

    struct Category {
        let symbol: String
        let title: String
        let emojis: [String]
    }

    static let categories: [Category] = [
        Category(symbol: "face.smiling", title: "Smileys", emojis: Array("😀😃😄😁😆😅😂🤣🥲☺️😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🥸🤩🥳😏😒😞😔😟😕🙁☹️😣😖😫😩🥺😢😭😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🤗🤔🫣🤭🫢🤫🤥😶😐😑😬🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👻💀🤖👽🙈🙉🙊").map(String.init).filter { !$0.unicodeScalars.allSatisfy { $0.properties.isVariationSelector } }),
        Category(symbol: "hand.raised", title: "Gesten", emojis: ["👍", "👎", "👌", "🤌", "✌️", "🤞", "🫰", "🤟", "🤘", "🤙", "👈", "👉", "👆", "👇", "☝️", "✋", "🤚", "🖐️", "🖖", "👋", "🤝", "🙏", "👏", "🙌", "👐", "🤲", "💪", "🫶", "✍️", "🫡", "🤷", "🤦", "🙋", "🙆", "🙅", "💁"]),
        Category(symbol: "heart", title: "Herzen", emojis: ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❤️‍🔥", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💯", "💢", "💥", "💫", "💦", "💤"]),
        Category(symbol: "leaf", title: "Natur & Essen", emojis: ["☀️", "🌤️", "⛅️", "🌧️", "⛈️", "❄️", "🌈", "🌙", "⭐️", "✨", "🔥", "🌊", "🌸", "🌻", "🌲", "🍀", "🐶", "🐱", "🦊", "🐻", "🐼", "🐸", "🦄", "🐝", "☕️", "🍺", "🍷", "🥂", "🍕", "🍔", "🍝", "🥗", "🍰", "🍫", "🍎", "🍓", "🥨", "🍿"]),
        Category(symbol: "lightbulb", title: "Dinge", emojis: ["🎉", "🎊", "🎁", "🎂", "🏆", "🥇", "⚽️", "🚴", "🏃", "🚗", "🚆", "✈️", "🚀", "🏠", "🏢", "💻", "📱", "⌚️", "📷", "💡", "📅", "📌", "📎", "✏️", "📝", "📚", "📞", "✉️", "📦", "🔑", "🔒", "🛠️", "⏰", "💰", "💶", "🧾"]),
        Category(symbol: "checkmark.circle", title: "Symbole", emojis: ["✅", "☑️", "✔️", "❌", "❎", "⚠️", "❗️", "❓", "‼️", "⁉️", "➡️", "⬅️", "⬆️", "⬇️", "↩️", "🔁", "🔜", "🆗", "🆕", "🆓", "ℹ️", "🔴", "🟠", "🟡", "🟢", "🔵", "🟣", "⚫️", "⚪️", "🟥", "🟩", "🟦", "▶️", "⏸️", "⏹️", "🔇"]),
    ]

    private static let recentKey = "recentEmojis"
    private let categoryBar = UIStackView()
    private let scroll = UIScrollView()
    private let grid = UIStackView()
    private var selected = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
        show(category: recents.isEmpty ? 1 : 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private var recents: [String] {
        Blitz.defaults?.stringArray(forKey: Self.recentKey) ?? []
    }

    private func remember(_ emoji: String) {
        var list = recents.filter { $0 != emoji }
        list.insert(emoji, at: 0)
        Blitz.defaults?.set(Array(list.prefix(32)), forKey: Self.recentKey)
    }

    private func build() {
        categoryBar.axis = .horizontal
        categoryBar.distribution = .fillEqually
        let symbols = ["clock"] + Self.categories.map(\.symbol)
        for (index, symbol) in symbols.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.tintColor = .secondaryLabel
            button.tag = index
            button.addAction(UIAction { [weak self] _ in self?.show(category: index) }, for: .touchUpInside)
            categoryBar.addArrangedSubview(button)
        }

        grid.axis = .vertical
        grid.spacing = 2
        scroll.addSubview(grid)
        scroll.showsVerticalScrollIndicator = false

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

        for view in [categoryBar, scroll, bottom] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        grid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            categoryBar.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            categoryBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            categoryBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            categoryBar.heightAnchor.constraint(equalToConstant: 30),
            scroll.topAnchor.constraint(equalTo: categoryBar.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -2),
            grid.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            grid.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            grid.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            bottom.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            bottom.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    /// 0 = zuletzt verwendet, 1 … = Kategorien.
    private func show(category index: Int) {
        selected = index
        for case let button as UIButton in categoryBar.arrangedSubviews {
            button.tintColor = button.tag == index ? .label : .secondaryLabel
        }
        let emojis = index == 0 ? recents : Self.categories[index - 1].emojis
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let perRow = 8
        for start in stride(from: 0, to: emojis.count, by: perRow) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            for emoji in emojis[start..<min(start + perRow, emojis.count)] {
                let button = UIButton(type: .system)
                button.setTitle(emoji, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 30)
                button.addAction(UIAction { [weak self] _ in
                    self?.remember(emoji)
                    self?.onInsert?(emoji)
                }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            for _ in 0..<(perRow - row.arrangedSubviews.count) { row.addArrangedSubview(UIView()) }
            row.heightAnchor.constraint(equalToConstant: 42).isActive = true
            grid.addArrangedSubview(row)
        }
        if emojis.isEmpty {
            let label = UILabel()
            label.text = "Noch keine zuletzt verwendeten Emojis."
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.heightAnchor.constraint(equalToConstant: 42).isActive = true
            grid.addArrangedSubview(label)
        }
        scroll.setContentOffset(.zero, animated: false)
    }
}
