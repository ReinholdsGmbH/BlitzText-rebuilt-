import Foundation

/// Gemeinsamer Kanal zwischen Haupt-App und Tastatur: App-Group-UserDefaults für Zustand,
/// Darwin Notifications als Weckruf. Darwin Notifications tragen keine Nutzdaten.
enum Spike {
    static let appGroup = "group.de.reinholds.blitzspike"
    static let sessionURL = URL(string: "blitzspike://session?record=1")!

    /// Heartbeat älter als das gilt als "Session aus".
    static let heartbeatTimeout: TimeInterval = 3

    enum Key {
        static let heartbeat = "heartbeat"
        static let state = "state"
        static let result = "result"
        static let resultID = "resultID"
    }

    enum State: String {
        case off, idle, recording
    }

    enum Note {
        static let start = "de.reinholds.blitzspike.start"
        static let stop = "de.reinholds.blitzspike.stop"
        static let resultReady = "de.reinholds.blitzspike.resultReady"
    }

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
