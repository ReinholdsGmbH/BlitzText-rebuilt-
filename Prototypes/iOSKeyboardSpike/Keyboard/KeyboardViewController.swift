import UIKit

/// Vollwertige QWERTZ-Tastatur mit Diktat-Knopf, Wortvorschlägen und Swipe.
/// Diktat: Ohne laufende Session öffnet der Knopf die Haupt-App, mit Session schickt er Start/Stopp.
final class KeyboardViewController: UIInputViewController {
    private let keyboard = KeyboardView()
    private let micButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private let suggestionStack = UIStackView()
    private let bar = UIStackView()
    private let words = WordSuggestions()

    private var layer: KeyboardLayer = .letters
    private var shift: ShiftState = .on
    private var lastShiftTap = Date.distantPast
    private var spaceAfterWordAt: Date?
    /// Letztes eigenes Zeichen war Buchstabe/Ziffer (unabhängig vom Textkontext der App).
    private var lastCharWasWord = false
    /// Zuletzt per Swipe eingefügter Text (inkl. Leerzeichen davor); Löschen nimmt ihn ganz weg.
    private var lastSwipeInsert: String?
    private var swipeAlternatives: [String] = []
    private var observers: [DarwinObserver] = []
    private var refreshTimer: Timer?
    private var lastInsertedID: String?
    private var lastState: Spike.State?

    private static let barHeight: CGFloat = 46
    private static let keysHeight: CGFloat = 216
    /// Zusätzliche Höhe der Ziffernleiste (flacher als eine Buchstabenreihe).
    private static let digitRowHeight: CGFloat = 40
    private var heightConstraint: NSLayoutConstraint?
    private var digits: Spike.DigitsMode = .row

    override func viewDidLoad() {
        super.viewDidLoad()
        buildBar()
        buildKeyboard()
        lastInsertedID = Spike.defaults?.string(forKey: Spike.Key.resultID)
        // Kontaktnamen, die iOS der Tastatur bereitstellt (Einträge, bei denen Kürzel und Text gleich sind).
        // Die Antwort kommt auf einem XPC-Thread; der Closure darf deshalb nicht MainActor-isoliert sein.
        requestSupplementaryLexicon(completion: Self.lexiconHandler { [weak self] lexicon in
            self?.words.lexiconWords = lexicon.entries
                .filter { $0.userInput == $0.documentText }
                .map { $0.documentText }
        })
        observers = [DarwinObserver(Spike.Note.resultReady) { [weak self] in self?.insertDictation() }]
        let height = view.heightAnchor.constraint(equalToConstant: Self.barHeight + Self.keysHeight)
        height.priority = .init(999)
        height.isActive = true
        heightConstraint = height
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboard.swipeEnabled = Spike.isSwipeEnabled
        words.userWords = Spike.userWords
        digits = Spike.digitsMode
        placeMic(onRight: Spike.isMicOnRight)
        updateAutoShift()
        reloadKeys()
        refreshMic()
        updateSuggestions()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMic() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        reloadKeys()
        updateSuggestions()
    }

    /// Baut den Lexikon-Callback außerhalb des MainActors und reicht das Lexikon auf die Main-Queue
    /// weiter; die Einträge dürfen nur dort gelesen werden.
    nonisolated private static func lexiconHandler(_ deliver: @escaping @MainActor (UILexicon) -> Void) -> (UILexicon) -> Void {
        { lexicon in
            let box = LexiconBox(lexicon: lexicon)
            DispatchQueue.main.async { MainActor.assumeIsolated { deliver(box.lexicon) } }
        }
    }

    // MARK: - Aufbau

    private func buildBar() {
        micButton.layer.cornerRadius = 17
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        micButton.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center

        suggestionStack.axis = .horizontal
        suggestionStack.distribution = .fillEqually
        suggestionStack.spacing = 1

        bar.addArrangedSubview(micButton)
        bar.addArrangedSubview(suggestionStack)
        bar.axis = .horizontal
        bar.spacing = 8
        bar.alignment = .center
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
            micButton.widthAnchor.constraint(equalToConstant: 34),
            micButton.heightAnchor.constraint(equalToConstant: 34),
            suggestionStack.heightAnchor.constraint(equalToConstant: 36),
            spinner.centerXAnchor.constraint(equalTo: micButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
        ])
    }

    /// Mikro links oder rechts von der Vorschlagsleiste.
    private func placeMic(onRight: Bool) {
        bar.removeArrangedSubview(micButton)
        bar.insertArrangedSubview(micButton, at: onRight ? bar.arrangedSubviews.count : 0)
    }

    private func buildKeyboard() {
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)
        NSLayoutConstraint.activate([
            keyboard.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.barHeight),
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        keyboard.onAction = { [weak self] in self?.handle($0) }
        keyboard.onInsertAlternate = { [weak self] in self?.insert($0) }
        keyboard.onSwipe = { [weak self] path, corners in self?.handleSwipe(path: path, corners: corners) }
    }

    private var layoutSignature = ""

    /// Baut die Tasten nur neu, wenn sich Ebene, Umschalt-Zustand oder Return-Beschriftung ändern.
    private func reloadKeys() {
        let signature = "\(layer)|\(shift)|\(returnLabel)|\(needsInputModeSwitchKey)|\(digits)"
        guard signature != layoutSignature else { return }
        layoutSignature = signature
        keyboard.layer_ = layer
        let digitRow = layer == .letters && digits == .row
        keyboard.compactFirstRow = digitRow
        heightConstraint?.constant = Self.barHeight + Self.keysHeight + (digitRow ? Self.digitRowHeight : 0)
        keyboard.rows = KeyLayout.rows(layer: layer, shift: shift, returnLabel: returnLabel,
                                       showGlobe: needsInputModeSwitchKey, digits: digits)
    }

    private var returnLabel: String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .search, .google, .yahoo: "Suchen"
        case .go: "Öffnen"
        case .send: "Senden"
        case .done: "Fertig"
        case .next: "Weiter"
        case .join: "Beitreten"
        default: "Zeilenschalter"
        }
    }

    // MARK: - Tasten

    private func handle(_ action: KeyAction) {
        switch action {
        case .character(let text):
            insert(text)
        case .shift:
            let now = Date()
            switch shift {
            case .off: shift = .on
            case .on: shift = now.timeIntervalSince(lastShiftTap) < 0.35 ? .locked : .off
            case .locked: shift = .off
            }
            lastShiftTap = now
            reloadKeys()
        case .backspace:
            if let swiped = lastSwipeInsert {
                swiped.forEach { _ in textDocumentProxy.deleteBackward() }
                lastSwipeInsert = nil
            } else {
                textDocumentProxy.deleteBackward()
            }
            afterEdit()
        case .deleteWord:
            deleteWordBackward()
        case .space:
            insertSpace()
        case .returnKey:
            textDocumentProxy.insertText("\n")
            afterEdit()
        case .globe:
            advanceToNextInputMode()
        case .layer(let target):
            layer = target
            reloadKeys()
        }
    }

    private func insert(_ text: String) {
        textDocumentProxy.insertText(text)
        if shift == .on { shift = .off }
        afterEdit()
        lastCharWasWord = text.last.map { $0.isLetter || $0.isNumber } ?? false
    }

    /// Löscht das Wort vor dem Cursor samt folgender Leerzeichen; vor Satzzeichen nur ein Zeichen.
    private func deleteWordBackward() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        var count = 0
        var rest = Substring(before)
        while let last = rest.last, last == " " { count += 1; rest = rest.dropLast() }
        let wordLength = rest.reversed().prefix { $0.isLetter || $0.isNumber }.count
        count += max(wordLength, rest.isEmpty ? 0 : (wordLength == 0 ? 1 : 0))
        if count == 0 { count = 1 }
        for _ in 0..<count { textDocumentProxy.deleteBackward() }
        lastSwipeInsert = nil
        afterEdit()
    }

    /// Doppeltes Leerzeichen setzt einen Punkt. Merkt sich selbst, ob das letzte Zeichen ein
    /// Leerzeichen nach einem Wort war: Der Textkontext der Ziel-App ist direkt nach dem
    /// Einfügen nicht in jeder App aktuell.
    private func insertSpace() {
        if let previous = spaceAfterWordAt, Date().timeIntervalSince(previous) < 0.8 {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            if layer != .letters { layer = .letters }
            afterEdit()
            return
        }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let followsWord = lastCharWasWord || (before.last.map { $0.isLetter || $0.isNumber } ?? false)
        textDocumentProxy.insertText(" ")
        if layer != .letters { layer = .letters }
        afterEdit()
        if followsWord { spaceAfterWordAt = Date() }
    }

    private func afterEdit() {
        // Nach normaler Eingabe löscht die Rücktaste wieder Zeichen für Zeichen.
        spaceAfterWordAt = nil
        lastCharWasWord = false
        lastSwipeInsert = nil
        swipeAlternatives = []
        updateAutoShift()
        reloadKeys()
        updateSuggestions()
    }

    /// Großbuchstabe am Textanfang und nach Satzende, sofern das Feld das will.
    private func updateAutoShift() {
        guard shift != .locked else { return }
        guard textDocumentProxy.autocapitalizationType != UITextAutocapitalizationType.none else {
            if shift == .on { shift = .off }
            return
        }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let sentenceStart = before.isEmpty || before.hasSuffix("\n")
            || (before.hasSuffix(" ") && [".", "!", "?"].contains(trimmed.last.map(String.init) ?? ""))
        shift = sentenceStart ? .on : .off
    }

    // MARK: - Swipe

    private func handleSwipe(path: [String], corners: [String]) {
        let candidates = words.swipeCandidates(path: path, corners: corners)
        guard let best = candidates.first else {
            statusLabel.text = "Kein Wort: \(words.lastDiagnosis)"
            statusLabel.adjustsFontSizeToFitWidth = true
            statusLabel.minimumScaleFactor = 0.6
            showStatusOnly()
            return
        }
        insertSwiped(best)
        swipeAlternatives = Array(candidates.dropFirst())
        updateSuggestions()
    }

    private func insertSwiped(_ word: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsSpace = !(before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n"))
        var text = word
        if shift != .off, let first = text.first { text = first.uppercased() + text.dropFirst() }
        if shift == .locked { text = text.uppercased() }
        let insertion = (needsSpace ? " " : "") + text
        textDocumentProxy.insertText(insertion)
        if shift == .on { shift = .off }
        lastSwipeInsert = insertion
        lastCharWasWord = true
        spaceAfterWordAt = nil
        updateAutoShift()
        reloadKeys()
    }

    // MARK: - Vorschläge

    /// Angefangenes Wort direkt vor dem Cursor.
    private var partialWord: String {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        return String(before.reversed().prefix { $0.isLetter }.reversed())
    }

    private func updateSuggestions() {
        var typed: String?
        let items: [String]
        if lastSwipeInsert != nil, !swipeAlternatives.isEmpty {
            items = swipeAlternatives
        } else {
            swipeAlternatives = []
            let result = words.suggestions(for: partialWord)
            typed = result.typed
            items = result.words
        }
        suggestionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard typed != nil || !items.isEmpty else { showStatusOnly(); return }
        if let typed {
            // Wie bei Apple: das Getippte in Anführungszeichen; antippen behält und merkt es.
            addSuggestionButton(title: "„\(typed)“") { [weak self] in self?.keepAndLearn(typed) }
        }
        for word in items.prefix(3) {
            addSuggestionButton(title: word) { [weak self] in self?.applySuggestion(word) }
        }
    }

    private func addSuggestionButton(title: String, action: @escaping () -> Void) {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.tintColor = .label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        suggestionStack.addArrangedSubview(button)
    }

    private func keepAndLearn(_ word: String) {
        words.learn(word)
        textDocumentProxy.insertText(" ")
        afterEdit()
        statusLabel.text = "„\(word)“ gemerkt"
        showStatusOnly()
    }

    private func showStatusOnly() {
        suggestionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        suggestionStack.addArrangedSubview(statusLabel)
    }

    private func applySuggestion(_ word: String) {
        if let swiped = lastSwipeInsert {
            swiped.forEach { _ in textDocumentProxy.deleteBackward() }
            lastSwipeInsert = nil
            swipeAlternatives = []
            insertSwiped(word)
        } else {
            partialWord.forEach { _ in textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(word + " ")
            afterEdit()
        }
        updateSuggestions()
    }

    // MARK: - Diktat

    private func refreshMic() {
        let state: Spike.State = hasFullAccess ? Spike.state : .off
        guard state != lastState || micButton.currentImage == nil else { return }
        lastState = state
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        var symbol = "mic"
        var tint = UIColor.label
        var background = UIColor.secondarySystemFill
        micButton.isEnabled = true
        spinner.stopAnimating()
        switch state {
        case .off:
            statusLabel.text = hasFullAccess ? "Mikro tippen startet die Session" : "Für Diktat „Vollen Zugriff“ erlauben"
            if !hasFullAccess { symbol = "mic.slash" }
        case .idle:
            symbol = "mic.fill"; tint = .white; background = .systemOrange
            statusLabel.text = "Bereit zum Diktieren"
        case .recording:
            symbol = "stop.fill"; tint = .white; background = .systemRed
            statusLabel.text = "Hört zu … tippen zum Beenden"
        case .processing:
            symbol = ""; spinner.startAnimating(); micButton.isEnabled = false
            statusLabel.text = "Schreibt …"
        case .meeting:
            symbol = "person.2.wave.2"; micButton.isEnabled = false
            statusLabel.text = "Meeting läuft"
        }
        micButton.setImage(symbol.isEmpty ? nil : UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        micButton.tintColor = tint
        micButton.backgroundColor = background
    }

    @objc private func micTapped() {
        guard hasFullAccess else { return }
        switch Spike.state {
        case .off:
            if !openContainingApp(Spike.sessionURL) { statusLabel.text = "App konnte nicht geöffnet werden" }
        case .idle:
            Spike.post(Spike.Note.start)
        case .recording:
            Spike.post(Spike.Note.stop)
        case .processing, .meeting:
            break
        }
        lastState = nil
        refreshMic()
    }

    private func insertDictation() {
        guard let id = Spike.defaults?.string(forKey: Spike.Key.resultID), id != lastInsertedID,
              let text = Spike.defaults?.string(forKey: Spike.Key.result) else { return }
        lastInsertedID = id
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsSpace = !(before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n"))
        textDocumentProxy.insertText((needsSpace ? " " : "") + text)
        lastSwipeInsert = nil
        afterEdit()
        lastState = nil
        refreshMic()
    }

    /// Erweiterungen dürfen UIApplication.open nicht direkt aufrufen. Üblicher Weg:
    /// UIApplication über die Responder-Kette finden und die Methode zur Laufzeit aufrufen.
    private func openContainingApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.isKind(of: UIApplication.self), current.responds(to: selector) {
                typealias OpenFn = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(current.method(for: selector), to: OpenFn.self)
                open(current, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }
}

/// Trägt das Lexikon vom XPC-Thread zur Main-Queue; gelesen wird es erst dort.
private struct LexiconBox: @unchecked Sendable {
    let lexicon: UILexicon
}
