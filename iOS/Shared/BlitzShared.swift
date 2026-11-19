import Foundation

/// Gemeinsamer Kanal zwischen Haupt-App und Tastatur: App-Group-UserDefaults für Zustand,
/// Darwin Notifications als Weckruf. Darwin Notifications tragen keine Nutzdaten.
enum Blitz {
    static let appGroup = "group.de.reinholds.blitztext"
    static let sessionURL = URL(string: "blitztext://session?record=1")!

    /// Heartbeat älter als das gilt als "Session aus".
    static let heartbeatTimeout: TimeInterval = 3

    enum Key {
        static let heartbeat = "heartbeat"
        static let state = "state"
        static let result = "result"
        static let resultID = "resultID"
        /// Swipe-Eingabe in der Tastatur an/aus (Standard an).
        static let swipeEnabled = "swipeEnabled"
        /// Eigene Wörter (Namen, Fachbegriffe), von Tastatur und App gemeinsam gepflegt.
        static let userWords = "userWords"
        static let digitsMode = "digitsMode"
        static let micOnRight = "micOnRight"
        static let clipboardPreview = "clipboardPreview"
    }

    enum State: String {
        case off, idle, recording, processing, meeting
    }

    enum Note {
        static let start = "de.reinholds.blitztext.start"
        static let stop = "de.reinholds.blitztext.stop"
        static let resultReady = "de.reinholds.blitztext.resultReady"
    }

    /// Gemeinsamer Ordner von App und Tastatur (App Group), z. B. für das Swipe-Wörterbuch.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var swipeLexiconURL: URL? { containerURL?.appendingPathComponent("swipe-lexicon.tsv") }

    /// nil, wenn die App Group nicht verfügbar ist (z. B. Signatur ohne Entitlement).
    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static var isSessionAlive: Bool {
        guard let beat = defaults?.double(forKey: Key.heartbeat), beat > 0 else { return false }
        return Date().timeIntervalSince1970 - beat < heartbeatTimeout
    }

    static var state: State {
        guard isSessionAlive,
              let raw = defaults?.string(forKey: Key.state),
              let state = State(rawValue: raw) else { return .off }
        return state
    }

    static var isSwipeEnabled: Bool {
        defaults?.object(forKey: Key.swipeEnabled) as? Bool ?? true
    }

    /// Wie die Tastatur Ziffern auf der Buchstabenebene anbietet.
    enum DigitsMode: String, CaseIterable {
        case off, row, longPress

        var label: String {
            switch self {
            case .off: "Aus"
            case .row: "Leiste"
            case .longPress: "Langer Druck"
            }
        }
    }

    static var digitsMode: DigitsMode {
        get { defaults?.string(forKey: Key.digitsMode).flatMap(DigitsMode.init) ?? .longPress }
        set { defaults?.set(newValue.rawValue, forKey: Key.digitsMode) }
    }

    /// Vorschau der Zwischenablage in der Leiste (liest jede neue Kopie einmal).
    static var isClipboardPreviewEnabled: Bool {
        get { defaults?.object(forKey: Key.clipboardPreview) as? Bool ?? true }
        set { defaults?.set(newValue, forKey: Key.clipboardPreview) }
    }

    /// Mikro-Knopf rechts (Standard) oder links neben den Vorschlägen.
    static var isMicOnRight: Bool {
        get { defaults?.object(forKey: Key.micOnRight) as? Bool ?? true }
        set { defaults?.set(newValue, forKey: Key.micOnRight) }
    }

    static var userWords: [String] {
        get { defaults?.stringArray(forKey: Key.userWords) ?? [] }
        set {
            var seen = Set<String>()
            let cleaned = newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            defaults?.set(cleaned.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, forKey: Key.userWords)
        }
    }

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true
        )
    }
}

/// Hält eine Darwin-Notification-Registrierung, solange das Objekt lebt.
/// Handler läuft immer auf der Main-Queue; deshalb @unchecked Sendable.
final class DarwinObserver: @unchecked Sendable {
    private let handler: () -> Void

    init(_ name: String, handler: @escaping () -> Void) {
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let me = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { me.handler() }
        }, name as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
}
