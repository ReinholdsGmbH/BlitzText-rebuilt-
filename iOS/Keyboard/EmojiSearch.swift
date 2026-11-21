import UIKit

/// Emoji-Suche über die deutschen CLDR-Namen und Stichwörter, wie bei Apple.
enum EmojiSearch {
    private struct Entry {
        let emoji: String
        let name: String
        let keywords: [String]
    }

    private static let maximumResults = 80

    private static let entries: [Entry] = EmojiSearchIndex.raw.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "\t", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let terms = parts[1].split(separator: "|", omittingEmptySubsequences: false).map { fold(String($0)) }
        return Entry(emoji: String(parts[0]), name: terms.first ?? "", keywords: Array(terms.dropFirst()))
    }

    /// Klein und ohne Akzente, damit „kase“ auch „Käse“ findet.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    private static func startsWord(_ text: String, _ query: String) -> Bool {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(query) }
    }

    /// Treffer nach Güte: ein Wort im Namen beginnt mit der Eingabe, dann Stichwörter, dann irgendwo enthalten.
    static func results(for query: String) -> [String] {
        let needle = fold(query.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return [] }
        // Innerhalb einer Stufe zuerst kurze Namen: „rotes Herz“ vor „Herz mit Schleife“.
        var scored: [(score: Int, length: Int, index: Int, emoji: String)] = []
        for (index, entry) in entries.enumerated() {
            let score: Int
            if startsWord(entry.name, needle) {
                score = 1
            } else if entry.keywords.contains(where: { $0.hasPrefix(needle) }) {
                score = 2
            } else if entry.keywords.contains(where: { startsWord($0, needle) }) {
                score = 3
            } else if entry.name.contains(needle) || entry.keywords.contains(where: { $0.contains(needle) }) {
                score = 4
            } else {
                continue
            }
            scored.append((score, entry.name.count, index, entry.emoji))
        }
        return scored.sorted { ($0.score, $0.length, $0.index) < ($1.score, $1.length, $1.index) }
            .prefix(maximumResults).map(\.emoji)
    }
}

/// Leiste über den Buchstaben während der Suche: oben das Suchfeld, darunter die Treffer.
final class EmojiSearchStrip: UIView {
    var onPick: ((String) -> Void)?
    var onClose: (() -> Void)?

    private let field = UIView()
    private let queryLabel = UILabel()
    private let results = UIScrollView()
    private let resultStack = UIStackView()
    private let emptyLabel = UILabel()
    static let height: CGFloat = 90

    override init(frame: CGRect) {
        super.init(frame: frame)
        field.backgroundColor = .tertiarySystemFill
        field.layer.cornerRadius = 10
        let glass = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        glass.tintColor = .secondaryLabel
        glass.setContentHuggingPriority(.required, for: .horizontal)
        queryLabel.font = .systemFont(ofSize: 17)
        queryLabel.lineBreakMode = .byTruncatingHead
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = .secondaryLabel
        close.accessibilityLabel = "Suche beenden"
        close.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        close.setContentHuggingPriority(.required, for: .horizontal)
        let fieldRow = UIStackView(arrangedSubviews: [glass, queryLabel, close])
        fieldRow.spacing = 8
        fieldRow.alignment = .center

        resultStack.axis = .horizontal
        resultStack.spacing = 2
        results.showsHorizontalScrollIndicator = false
        results.alwaysBounceHorizontal = true
        results.addSubview(resultStack)
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabel

        for view in [field, fieldRow, results, resultStack, emptyLabel] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        field.addSubview(fieldRow)
        addSubview(field)
        addSubview(results)
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            field.heightAnchor.constraint(equalToConstant: 36),
            fieldRow.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 10),
            fieldRow.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -6),
            fieldRow.topAnchor.constraint(equalTo: field.topAnchor),
            fieldRow.bottomAnchor.constraint(equalTo: field.bottomAnchor),
            results.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 2),
            results.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            results.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            results.bottomAnchor.constraint(equalTo: bottomAnchor),
            resultStack.topAnchor.constraint(equalTo: results.contentLayoutGuide.topAnchor),
            resultStack.bottomAnchor.constraint(equalTo: results.contentLayoutGuide.bottomAnchor),
            resultStack.leadingAnchor.constraint(equalTo: results.contentLayoutGuide.leadingAnchor),
            resultStack.trailingAnchor.constraint(equalTo: results.contentLayoutGuide.trailingAnchor),
            resultStack.heightAnchor.constraint(equalTo: results.frameLayoutGuide.heightAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: results.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: results.leadingAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Suchtext und Treffer zeigen; ohne Eingabe die zuletzt verwendeten.
    func show(query: String, emojis: [String]) {
        queryLabel.text = query.isEmpty ? "Emoji suchen" : query
        queryLabel.textColor = query.isEmpty ? .secondaryLabel : .label
        resultStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for emoji in emojis {
            let button = UIButton(type: .system)
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 30)
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onPick?(emoji) }, for: .touchUpInside)
            resultStack.addArrangedSubview(button)
        }
        results.setContentOffset(.zero, animated: false)
        emptyLabel.text = query.isEmpty ? nil : "Keine Emojis gefunden"
        emptyLabel.isHidden = !emojis.isEmpty
    }
}
