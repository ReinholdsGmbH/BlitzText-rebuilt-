import UIKit

/// Minimal-Tastatur: ein Mikro-Knopf, eine Statuszeile, der Globus zum Wechseln.
/// Ohne laufende Session öffnet der Knopf die Haupt-App; mit Session schickt er Start/Stopp.
final class KeyboardViewController: UIInputViewController {
    private let micButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let globeButton = UIButton(type: .system)
    private var observers: [DarwinObserver] = []
    private var refreshTimer: Timer?
    private var lastInsertedID: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        lastInsertedID = Spike.defaults?.string(forKey: Spike.Key.resultID)
        observers = [DarwinObserver(Spike.Note.resultReady) { [weak self] in self?.insertResult() }]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func buildUI() {
        micButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .center

        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globeButton.isHidden = !needsInputModeSwitchKey

        let stack = UIStackView(arrangedSubviews: [statusLabel, micButton, globeButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            view.heightAnchor.constraint(equalToConstant: 200),
        ])
    }

    private func refresh() {
        guard hasFullAccess else {
            statusLabel.text = "Voller Zugriff fehlt (Einstellungen > Tastaturen)"
            micButton.setTitle("—", for: .normal)
            micButton.isEnabled = false
            return
        }
        guard Spike.defaults != nil else {
            statusLabel.text = "App Group nicht verfügbar"
            micButton.isEnabled = false
            return
        }
        micButton.isEnabled = true
        switch Spike.state {
        case .off:
            statusLabel.text = "Keine Session. Tippen öffnet BlitzSpike."
            micButton.setTitle("Session starten", for: .normal)
        case .idle:
            statusLabel.text = "Session läuft"
            micButton.setTitle("Diktat starten", for: .normal)
        case .recording:
            statusLabel.text = "Aufnahme läuft …"
            micButton.setTitle("Fertig", for: .normal)
        case .processing:
            statusLabel.text = "Wird transkribiert …"
            micButton.setTitle("…", for: .normal)
            micButton.isEnabled = false
        }
    }

    @objc private func micTapped() {
        switch Spike.state {
        case .off:
            if !openContainingApp(Spike.sessionURL) {
                statusLabel.text = "App konnte nicht geöffnet werden"
            }
        case .idle:
            Spike.post(Spike.Note.start)
        case .recording:
            Spike.post(Spike.Note.stop)
        case .processing:
            break
        }
    }

    private func insertResult() {
        guard let id = Spike.defaults?.string(forKey: Spike.Key.resultID), id != lastInsertedID,
              let text = Spike.defaults?.string(forKey: Spike.Key.result) else { return }
        lastInsertedID = id
        textDocumentProxy.insertText(text)
        refresh()
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
