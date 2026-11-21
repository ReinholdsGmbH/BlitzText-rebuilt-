import UIKit

/// Vollwertige QWERTZ-Tastatur mit Diktat-Knopf, Wortvorschlägen und Swipe.
/// Diktat: Ohne laufende Session öffnet der Knopf die Haupt-App, mit Session schickt er Start/Stopp.
final class KeyboardViewController: UIInputViewController {
    private let keyboard = KeyboardView()
    private let emojiPanel = EmojiPanel()
    private let usage = WordUsage()
    private let micButton = UIButton(type: .system)
    /// Gegenüber dem Mikro: öffnet die BlitzText-App auf den Einstellungen.
    private let settingsButton = UIButton(type: .system)
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
    private var lastState: Blitz.State?
    /// Diktat direkt in der Tastatur, wenn keine Session läuft.
    private lazy var dictation: KeyboardDictation = {
        let dictation = KeyboardDictation(host: view)
        dictation.onState = { [weak self] _ in
            self?.lastState = nil
            self?.refreshMic()
        }
        dictation.onText = { [weak self] text in self?.insertTranscript(DictationFormatter.apply(text)) }
        dictation.onFailure = { [weak self] message in
            self?.lastState = nil
            self?.refreshMic()
            self?.statusLabel.text = message
            self?.showStatusOnly()
        }
        return dictation
    }()
    /// Formvergleich-Decoder; lädt das von der App gebaute Wörterbuch im Hintergrund.
    private var swipeDecoder: SwipeDecoder?

    private static let barHeight: CGFloat = 46
    private static let keysHeight: CGFloat = 216
    /// Zusätzliche Höhe der Ziffernleiste (flacher als eine Buchstabenreihe).
    private static let digitRowHeight: CGFloat = 40
    private var heightConstraint: NSLayoutConstraint?
    private var digits: Blitz.DigitsMode = .longPress
    /// Reines Ziffernfeld (Zahl, Dezimalzahl, Einmalcode) erkannt: Ziffernblock statt Buchstaben.
    private var numericField: KeyboardLayer?
    /// URL- oder Adressfeld: „/“ und „.“ neben der Leertaste.
    private var urlField = false
    /// Mit „ABC“ verlassen; gilt bis zum nächsten anderen Feld.
    private var numberPadDismissed = false
    private var fieldSignature = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        buildBar()
        buildKeyboard()
        lastInsertedID = Blitz.defaults?.string(forKey: Blitz.Key.resultID)
        // Kontaktnamen, die iOS der Tastatur bereitstellt (Einträge, bei denen Kürzel und Text gleich sind).
        // Die Antwort kommt auf einem XPC-Thread; der Closure darf deshalb nicht MainActor-isoliert sein.
        requestSupplementaryLexicon(completion: Self.lexiconHandler { [weak self] lexicon in
            let names = lexicon.entries
                .filter { $0.userInput == $0.documentText }
                .map { $0.documentText }
            self?.words.lexiconWords = names
            // Kontaktnamen auch beim Swipe, falls der Decoder schon geladen ist.
            self?.swipeDecoder?.add(words: names)
        })
        observers = [DarwinObserver(Blitz.Note.resultReady) { [weak self] in self?.insertDictation() }]
        let height = view.heightAnchor.constraint(equalToConstant: Self.barHeight + Self.keysHeight)
        height.priority = .init(999)
        height.isActive = true
        heightConstraint = height
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboard.swipeEnabled = Blitz.isSwipeEnabled
        words.userWords = Blitz.userWords
        swipeDecoder?.add(words: Blitz.userWords)
        usage.load()
        words.usage = usage
        loadSwipeDecoderIfNeeded()
        digits = Blitz.digitsMode
        fieldSignature = ""
        detectNumericField()
        placeMic(onRight: Blitz.isMicOnRight)
        updateAutoShift()
        reloadKeys()
        refreshMic()
        updateSuggestions()
        if hasFullAccess { dictation.prepare() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMic() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        usage.save()
        dictation.cancel()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Die System-Gesten am Fenster halten Berührungen am Bildschirmrand zurück; Tasten der
        // obersten und untersten Reihe reagieren sonst verzögert oder gar nicht.
        releaseEdgeTouches()
    }

    /// Schaltet das Zurückhalten an allen Ebenen über der Tastatur ab, nicht nur am Fenster: Schnelle
    /// Tipps in der untersten Reihe wurden sonst verzögert und von der Home-Geste verworfen.
    private func releaseEdgeTouches() {
        var current: UIView? = view
        while let layer = current {
            layer.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
            current = layer.superview
        }
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Während der Cursorfahrt meldet die Ziel-App jede Verschiebung; das wird am Ende nachgeholt.
        guard cursorNavigator == nil else { return }
        detectNumericField()
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

    private var decoderLoading = false

    private func loadSwipeDecoderIfNeeded() {
        guard swipeDecoder == nil, !decoderLoading, let url = Blitz.swipeLexiconURL else { return }
        decoderLoading = true
        let extra = Blitz.userWords + words.lexiconWords
        Task.detached(priority: .utility) { [weak self] in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let decoder = text.isEmpty ? nil : SwipeDecoder(lexicon: text, extraWords: extra)
            await MainActor.run {
                // Was seit dem Start dazukam (Kontaktnamen, gemerkte Wörter), gleich mit aufnehmen.
                decoder?.add(words: Blitz.userWords + (self?.words.lexiconWords ?? []))
                self?.swipeDecoder = decoder
                self?.decoderLoading = false
            }
        }
    }

    // MARK: - Aufbau

    private func buildBar() {
        micButton.layer.cornerRadius = 17
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        micButton.translatesAutoresizingMaskIntoConstraints = false
        let gear = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        settingsButton.setImage(UIImage(systemName: "gearshape.fill", withConfiguration: gear), for: .normal)
        settingsButton.tintColor = .secondaryLabel
        settingsButton.backgroundColor = .secondarySystemFill
        settingsButton.layer.cornerRadius = 17
        settingsButton.accessibilityLabel = "BlitzText-Einstellungen öffnen"
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center

        suggestionStack.axis = .horizontal
        suggestionStack.distribution = .fillEqually
        suggestionStack.spacing = 1

        bar.addArrangedSubview(settingsButton)
        bar.addArrangedSubview(suggestionStack)
        bar.addArrangedSubview(micButton)
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
            settingsButton.widthAnchor.constraint(equalToConstant: 34),
            settingsButton.heightAnchor.constraint(equalToConstant: 34),
            suggestionStack.heightAnchor.constraint(equalToConstant: 36),
            spinner.centerXAnchor.constraint(equalTo: micButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
        ])
    }

    /// Mikro links oder rechts von der Vorschlagsleiste, das Zahnrad auf der Gegenseite.
    private func placeMic(onRight: Bool) {
        let (left, right) = onRight ? (settingsButton, micButton) : (micButton, settingsButton)
        for button in [left, right] { bar.removeArrangedSubview(button) }
        bar.insertArrangedSubview(left, at: 0)
        bar.addArrangedSubview(right)
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
        emojiPanel.translatesAutoresizingMaskIntoConstraints = false
        emojiPanel.isHidden = true
        view.addSubview(emojiPanel)
        NSLayoutConstraint.activate([
            emojiPanel.topAnchor.constraint(equalTo: keyboard.topAnchor),
            emojiPanel.leadingAnchor.constraint(equalTo: keyboard.leadingAnchor),
            emojiPanel.trailingAnchor.constraint(equalTo: keyboard.trailingAnchor),
            emojiPanel.bottomAnchor.constraint(equalTo: keyboard.bottomAnchor),
        ])
        emojiPanel.onInsert = { [weak self] emoji in
            self?.textDocumentProxy.insertText(emoji)
            self?.afterEdit()
        }
        emojiPanel.onBackspace = { [weak self] in self?.handle(.backspace) }
        emojiPanel.onClose = { [weak self] in self?.setEmojiPanel(visible: false) }
        keyboard.onAction = { [weak self] in self?.handle($0) }
        keyboard.onInsertAlternate = { [weak self] in self?.insert($0) }
        keyboard.onSwipe = { [weak self] path, corners, points in self?.handleSwipe(path: path, corners: corners, points: points) }
    }

    private var layoutSignature = ""

    /// Erkennt Zahlenfelder am Tastaturtyp der App. Wechselt das Feld, gilt ein „ABC“ nicht mehr.
    private func detectNumericField() {
        let type = textDocumentProxy.keyboardType ?? .default
        let content = textDocumentProxy.textContentType ?? nil
        let signature = "\(type.rawValue)|\(content?.rawValue ?? "")"
        guard signature != fieldSignature else { return }
        fieldSignature = signature
        numberPadDismissed = false
        urlField = type == .URL || type == .webSearch || content == .URL
        switch type {
        case .numberPad, .asciiCapableNumberPad: numericField = .numberPad(decimal: false)
        case .decimalPad: numericField = .numberPad(decimal: true)
        default: numericField = content == .oneTimeCode ? .numberPad(decimal: false) : nil
        }
    }

    /// Ebene, die gerade zu sehen ist: im Zahlenfeld der Ziffernblock, solange nicht verlassen.
    private var visibleLayer: KeyboardLayer {
        if let numericField, !numberPadDismissed { return numericField }
        return layer
    }

    /// Baut die Tasten nur neu, wenn sich Ebene, Umschalt-Zustand oder Return-Beschriftung ändern.
    private func reloadKeys() {
        let layer = visibleLayer
        let signature = "\(layer)|\(shift)|\(returnLabel)|\(needsInputModeSwitchKey)|\(digits)|\(urlField)"
        guard signature != layoutSignature else { return }
        layoutSignature = signature
        keyboard.layer_ = layer
        let digitRow = layer == .letters && digits == .row
        keyboard.compactFirstRow = digitRow
        heightConstraint?.constant = Self.barHeight + Self.keysHeight + (digitRow ? Self.digitRowHeight : 0)
        keyboard.rows = KeyLayout.rows(layer: layer, shift: shift, returnLabel: returnLabel,
                                       showGlobe: needsInputModeSwitchKey, digits: digits, urlField: urlField)
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
                // Nur das Wort löschen, das Leerzeichen davor bleibt stehen: So kann direkt das
                // nächste Wort folgen, wie bei Apple.
                let word = swiped.hasPrefix(" ") ? swiped.dropFirst() : Substring(swiped)
                word.forEach { _ in textDocumentProxy.deleteBackward() }
                lastSwipeInsert = nil
            } else {
                textDocumentProxy.deleteBackward()
            }
            afterEdit()
        case .deleteWords(let words):
            deleteWordsBackward(words)
        case .cursorTo(let target):
            guard var navigator = cursorNavigator else { break }
            let delta = target - navigator.position
            navigator.position = target
            cursorNavigator = navigator
            if delta != 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: delta) }
        case .cursorReload:
            let navigator = makeCursorNavigator()
            cursorNavigator = navigator
            keyboard.showCursorPreview(navigator, keepingX: true)
        case .cursorBegan:
            let navigator = makeCursorNavigator()
            cursorNavigator = navigator
            keyboard.showCursorPreview(navigator)
            lastSwipeInsert = nil
            spaceAfterWordAt = nil
        case .cursorEnded:
            // Vorschläge erst nach der Fahrt: Neuaufbau bei jedem Schritt bremst spürbar.
            cursorNavigator = nil
            updateAutoShift()
            reloadKeys()
            updateSuggestions()
        case .space:
            insertSpace()
        case .returnKey:
            textDocumentProxy.insertText("\n")
            afterEdit()
        case .globe:
            advanceToNextInputMode()
        case .emoji:
            setEmojiPanel(visible: true)
        case .layer(let target):
            if numericField != nil, !numberPadDismissed { numberPadDismissed = true }
            layer = target
            reloadKeys()
        }
    }

    private func insert(_ text: String) {
        if lastSwipeInsert == nil, text.count == 1, ".,!?;:".contains(text) { usage.record(partialWord) }
        textDocumentProxy.insertText(text)
        if shift == .on { shift = .off }
        afterEdit()
        lastCharWasWord = text.last.map { $0.isLetter || $0.isNumber } ?? false
    }

    /// Cursorfahrt über die Leertaste; lebt vom Halten bis zum Loslassen.
    private var cursorNavigator: CursorNavigator?

    /// Geschätzte Textbreite einer Zeile in der Ziel-App, in Punkt. Die Tastatur sieht das Textfeld
    /// nicht; ausgelegt ist sie auf Nachrichtenfelder (WhatsApp, Teams), die neben den Knöpfen rund
    /// 142 pt schmaler sind als der Bildschirm. Gemessen an einem WhatsApp-Screenshot auf 440 pt
    /// Bildschirmbreite: Zeilen bis 292 pt passten, ab 306 pt wurde umbrochen.
    private var estimatedLineWidth: CGFloat { max(160, view.bounds.width - 142) }

    /// Zeichenbreiten der Systemschrift in 17 pt, wie sie Nachrichten-Apps verwenden.
    private static let cursorFont = UIFont.systemFont(ofSize: 17)
    private var advanceCache: [Character: CGFloat] = [:]

    /// Textmodell aus dem Ausschnitt, den die Ziel-App gerade rund um den Cursor liefert. In
    /// WhatsApp beginnt er am Satzanfang (bis etwa 300 Zeichen), nicht am Zeilenanfang; bei langen
    /// Absätzen weichen die nachgebildeten Zeilen deshalb seitlich vom Textfeld ab. Den ganzen
    /// Absatz durch Hin- und Herschieben des Cursors einzusammeln scheiterte daran, dass iOS den
    /// Ausschnitt nach einer Verschiebung erst verzögert und ohne erkennbares Signal aktualisiert.
    private func makeCursorNavigator() -> CursorNavigator {
        CursorNavigator(before: textDocumentProxy.documentContextBeforeInput ?? "",
                        after: textDocumentProxy.documentContextAfterInput ?? "",
                        lineWidth: estimatedLineWidth,
                        advance: { [weak self] in self?.advance(of: $0) ?? 8.4 })
    }

    private func advance(of character: Character) -> CGFloat {
        if let cached = advanceCache[character] { return cached }
        let width = (String(character) as NSString).size(withAttributes: [.font: Self.cursorFont]).width
        advanceCache[character] = width
        return width
    }

    private func setEmojiPanel(visible: Bool) {
        emojiPanel.isHidden = !visible
        keyboard.isHidden = visible
        if visible {
            emojiPanel.refresh()
            releaseEdgeTouches()
        }
        if !visible {
            layer = .letters
            reloadKeys()
        }
    }

    /// Löscht `words` Wörter vor dem Cursor samt folgender Leerzeichen; ein Satzzeichen zählt
    /// als Wort. Alles wird auf demselben Textstand gezählt, weil der Kontext der Ziel-App nach
    /// dem Löschen verzögert nachzieht.
    private func deleteWordsBackward(_ words: Int) {
        var rest = Substring(textDocumentProxy.documentContextBeforeInput ?? "")
        var count = 0
        for _ in 0..<max(words, 1) {
            guard !rest.isEmpty else { break }
            while let last = rest.last, last == " " { count += 1; rest = rest.dropLast() }
            let wordLength = rest.reversed().prefix { $0.isLetter || $0.isNumber }.count
            let step = wordLength > 0 ? wordLength : (rest.isEmpty ? 0 : 1)
            count += step
            rest = rest.dropLast(step)
        }
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
        if lastSwipeInsert == nil { usage.record(partialWord) }
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

    private func handleSwipe(path: [String], corners: [String], points: [CGPoint]) {
        var candidates: [String] = []
        if let decoder = swipeDecoder {
            let geometry = keyboard.letterGeometry
            candidates = decoder.decode(points: points, centers: geometry.centers, keyWidth: geometry.keyWidth,
                                        usage: usage.counts)
        }
        if candidates.isEmpty { candidates = words.swipeCandidates(path: path, corners: corners) }
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
        usage.record(word)
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
        guard typed != nil || !items.isEmpty else { showIdleBar(); return }
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
        swipeDecoder?.add(words: [word])
        usage.record(word)
        textDocumentProxy.insertText(" ")
        afterEdit()
        statusLabel.text = "„\(word)“ gemerkt"
        showStatusOnly()
    }

    // MARK: - Zwischenablage

    /// Wie lange neu Kopiertes als „Einfügen“ angeboten wird.
    private static let clipboardOfferDuration: TimeInterval = 180
    private static let clipboardSeenKey = "clipboardSeen"
    private static let clipboardUsedKey = "clipboardUsed"

    /// Neu kopierter Text, der noch nicht eingefügt wurde. Gelesen wird erst beim Antippen,
    /// weil Lesen bei iOS die Rückfrage „Einfügen erlauben?“ auslösen kann.
    private var clipboardOffer: Bool {
        guard hasFullAccess else { return false }
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else { return false }
        let count = pasteboard.changeCount
        let defaults = Blitz.defaults
        guard defaults?.integer(forKey: Self.clipboardUsedKey) != count else { return false }
        var seen = defaults?.dictionary(forKey: Self.clipboardSeenKey) as? [String: Double] ?? [:]
        let firstSeen = seen[String(count)] ?? Date().timeIntervalSince1970
        if seen[String(count)] == nil {
            seen = [String(count): firstSeen]
            defaults?.set(seen, forKey: Self.clipboardSeenKey)
        }
        return Date().timeIntervalSince1970 - firstSeen < Self.clipboardOfferDuration
    }

    /// Gelesener Text der aktuellen Kopie (je Kopie nur einmal lesen, damit iOS nicht erneut fragt).
    private var clipboardCache: (count: Int, text: String?)?

    /// Liest die Zwischenablage einmal je Kopie. Kann bei iOS die Rückfrage „Einfügen erlauben?“
    /// auslösen; mit „Erlauben“ in den iPhone-Einstellungen bleibt es still.
    /// Auch ein „Nein“ wird je Kopie gemerkt; neu gefragt wird nur beim Antippen (`retry`).
    private func clipboardText(retry: Bool = false) -> String? {
        let pasteboard = UIPasteboard.general
        if let cache = clipboardCache, cache.count == pasteboard.changeCount, cache.text != nil || !retry {
            return cache.text
        }
        let text = pasteboard.string.flatMap { $0.isEmpty ? nil : $0 }
        clipboardCache = (pasteboard.changeCount, text)
        return text
    }

    /// Leere Leiste: neu Kopiertes mit Vorschau zum Einfügen, sonst der Status.
    private func showIdleBar() {
        let state: Blitz.State = hasFullAccess ? Blitz.state : .off
        guard state != .recording, state != .processing, clipboardOffer else { showStatusOnly(); return }
        suggestionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var title = "Einfügen"
        if Blitz.isClipboardPreviewEnabled, let text = clipboardText() {
            let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            title = flat.count > 28 ? String(flat.prefix(26)) + "…" : flat
        }
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "doc.on.clipboard")
        config.imagePadding = 6
        config.title = title
        config.titleLineBreakMode = .byTruncatingTail
        config.baseForegroundColor = .label
        button.configuration = config
        button.addAction(UIAction { [weak self] _ in self?.pasteClipboard() }, for: .touchUpInside)
        suggestionStack.addArrangedSubview(button)
    }

    private func pasteClipboard() {
        guard let text = clipboardText(retry: true) else {
            statusLabel.text = "Einfügen nicht erlaubt oder leer"
            showStatusOnly()
            return
        }
        let count = UIPasteboard.general.changeCount
        // Nach der Rückfrage von iOS ist das Textfeld kurz nicht erreichbar; deshalb leicht verzögert.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.textDocumentProxy.insertText(text)
            Blitz.defaults?.set(count, forKey: Self.clipboardUsedKey)
            self.afterEdit()
        }
    }

    private func showStatusOnly() {
        suggestionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        suggestionStack.addArrangedSubview(statusLabel)
    }

    private func applySuggestion(_ word: String) {
        if let swiped = lastSwipeInsert {
            usage.record(swiped, delta: -1)
            swiped.forEach { _ in textDocumentProxy.deleteBackward() }
            lastSwipeInsert = nil
            swipeAlternatives = []
            insertSwiped(word)
        } else {
            usage.record(word)
            partialWord.forEach { _ in textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(word + " ")
            afterEdit()
        }
        updateSuggestions()
    }

    // MARK: - Diktat

    private func refreshMic() {
        if dictation.state != .idle {
            showDirectDictation()
            return
        }
        let state: Blitz.State = hasFullAccess ? Blitz.state : .off
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
            statusLabel.text = hasFullAccess ? "Mikro tippen zum Diktieren" : "Für Diktat „Vollen Zugriff“ erlauben"
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

    /// Knopf während des Diktats direkt in der Tastatur.
    private func showDirectDictation() {
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        spinner.stopAnimating()
        micButton.isEnabled = true
        switch dictation.state {
        case .starting, .recording:
            micButton.setImage(UIImage(systemName: "stop.fill", withConfiguration: config), for: .normal)
            micButton.tintColor = .white
            micButton.backgroundColor = .systemRed
            statusLabel.text = dictation.state == .starting ? "Mikrofon startet …" : "Hört zu … tippen zum Beenden"
        case .transcribing:
            micButton.setImage(nil, for: .normal)
            micButton.backgroundColor = .secondarySystemFill
            spinner.startAnimating()
            statusLabel.text = "Schreibt …"
        case .idle:
            break
        }
        showStatusOnly()
    }

    @objc private func micTapped() {
        guard hasFullAccess else { return }
        switch dictation.state {
        case .starting, .recording:
            dictation.stop()
            return
        case .transcribing:
            return
        case .idle:
            break
        }
        switch Blitz.state {
        case .off:
            // Ohne Session diktiert die Tastatur selbst; die App braucht es nur noch für Meetings.
            dictation.start()
        case .idle:
            Blitz.post(Blitz.Note.start)
        case .recording:
            Blitz.post(Blitz.Note.stop)
        case .processing, .meeting:
            break
        }
        lastState = nil
        refreshMic()
    }

    @objc private func settingsTapped() {
        if !openContainingApp(Blitz.settingsURL) { statusLabel.text = "App konnte nicht geöffnet werden" }
    }

    private func insertDictation() {
        guard let id = Blitz.defaults?.string(forKey: Blitz.Key.resultID), id != lastInsertedID,
              let text = Blitz.defaults?.string(forKey: Blitz.Key.result) else { return }
        lastInsertedID = id
        insertTranscript(text)
    }

    private func insertTranscript(_ text: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsSpace = !(before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n"))
        textDocumentProxy.insertText((needsSpace ? " " : "") + text)
        usage.recordText(text)
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
