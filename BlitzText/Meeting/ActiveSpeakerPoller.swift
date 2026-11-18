import AppKit
import ApplicationServices
import Foundation

/// Liest während der Aufnahme, wen die Meeting-App gerade als Sprecher markiert.
///
/// Vorbild ist Wispr Flows `MeetingSpeakerPoller` (Strategien für Zoom, Teams, Meet, Slack):
/// Die Apps beschriften die Kachel der sprechenden Person für Screenreader, etwa
/// „Anna Müller, spricht" oder „Anna Müller is speaking". Diese Beschriftung wird über die
/// Accessibility-API gelesen, die BlitzText für den Auto-Insert ohnehin hat.
///
/// Teams und der Browser bauen ihren Baum auf Chromium und legen ihn erst offen, wenn ein
/// Hilfsprogramm `AXManualAccessibility` setzt. Das tut Wispr Flow ebenso.
///
/// Grenzen: Die genauen Beschriftungen ändern sich mit App-Versionen und Sprache. Die
/// Marker unten sind belegt für das Muster „Name, Status", nicht für jede App-Version.
/// Findet der Poller nichts, bleibt es bei „Sprecher N" und der Zuordnung von Hand.
@MainActor
final class ActiveSpeakerPoller {

    private(set) var hints: [SpeakerHint] = []
    private var timer: Timer?
    private var pids: [pid_t] = []
    private var startedAt = Date()
    private var polls = 0
    /// Beschriftungen, die nach Teilnehmerkachel aussehen. Bleibt der Poller ohne Treffer,
    /// landen sie in `diagnosticsURL`, damit sich der Parser an die echte App anpassen lässt.
    private var labelSamples = Set<String>()
    private var budgetExhausted = 0
    private var scanning = false
    /// Angemeldeter Beobachter: Chromium hält seinen Accessibility-Baum nur dann laufend
    /// aktuell. Ohne ihn blieb im Test sogar die Anrufdauer auf 00:02 stehen.
    private var observers: [AXObserver] = []

    static let diagnosticsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/BlitzText-Sprecheranzeige.txt")
    static let sampleLimit = 400
    nonisolated static let sampleKeywords = ["speak", "sprech", "spricht", "mute", "stumm", "mikro", "micro", "video",
                                 "kamera", "camera", "teilnehm", "particip", "hand", "audio", "ton "]

    static let interval: TimeInterval = 1
    /// Obergrenze je Durchlauf, damit ein großer Teams-Baum den Main-Thread nicht blockiert.
    nonisolated static let nodeBudget = 6_000

    func start(pids: [pid_t], startedAt: Date) {
        stop()
        self.pids = pids
        self.startedAt = startedAt
        hints = []
        polls = 0
        labelSamples = []
        budgetExhausted = 0
        guard !pids.isEmpty else { return }
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            var observer: AXObserver?
            guard AXObserverCreate(pid, { _, _, _, _ in }, &observer) == .success, let observer else { continue }
            for notification in [kAXValueChangedNotification, kAXCreatedNotification, kAXUIElementDestroyedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(observer, app, notification as CFString, nil)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers.append(observer)
        }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Wer laut Meeting-App in den letzten Sekunden am meisten gesprochen hat. Für die
    /// Namen im Live-Transkript.
    func recentName(window: TimeInterval = 6) -> String? {
        let now = Date().timeIntervalSince(startedAt)
        let recent = hints.filter { $0.time >= now - window }
        let counts = Dictionary(grouping: recent, by: \.name).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
    }

    @discardableResult
    func stop() -> [SpeakerHint] {
        timer?.invalidate()
        timer = nil
        for observer in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers = []
        if polls > 0 {
            Log.write("ActiveSpeakerPoller: \(polls) Abfragen, \(hints.count) Treffer, \(Set(hints.map(\.name)).count) Namen, Budget \(budgetExhausted)× ausgeschöpft")
            if hints.isEmpty { writeDiagnostics() }
        }
        return hints
    }

    /// Nur lokal, nie im Wissensordner: enthält Teilnehmernamen.
    private func writeDiagnostics() {
        guard !labelSamples.isEmpty else { return }
        let header = "BlitzText: Beschriftungen der Meeting-App ohne erkannten Sprecher, \(Date())\n"
            + "Abfragen: \(polls), Knotenbudget ausgeschöpft: \(budgetExhausted)×\n\n"
        let body = labelSamples.sorted().joined(separator: "\n")
        try? (header + body).write(to: Self.diagnosticsURL, atomically: true, encoding: .utf8)
        Log.write("ActiveSpeakerPoller: \(labelSamples.count) Beschriftungen in \(Self.diagnosticsURL.lastPathComponent)")
    }

    /// Durchlauf im Hintergrund: Ein Teams-Baum mit vielen Kacheln braucht einige tausend
    /// Accessibility-Abfragen, das soll den Main-Thread nicht bremsen.
    private func poll() {
        guard !scanning else { return }
        polls += 1
        scanning = true
        let now = Date().timeIntervalSince(startedAt)
        let sample = hints.isEmpty && polls % 10 == 1 && labelSamples.count < Self.sampleLimit
        let pids = self.pids
        Task.detached(priority: .utility) { [weak self] in
            let result = AXSpeakerScan.scan(pids: pids, budget: ActiveSpeakerPoller.nodeBudget, sampling: sample)
            await MainActor.run {
                guard let self else { return }
                self.scanning = false
                guard self.timer != nil else { return }
                if result.exhausted { self.budgetExhausted += 1 }
                if sample {
                    self.labelSamples.formUnion(result.samples.prefix(max(0, Self.sampleLimit - self.labelSamples.count)))
                }
                for name in result.names { self.hints.append(SpeakerHint(time: now, name: name)) }
            }
        }
    }

    nonisolated static func isCandidate(_ text: String) -> Bool {
        guard (3...160).contains(text.count) else { return false }
        let lower = text.lowercased()
        return sampleKeywords.contains(where: lower.contains)
    }
}

/// Holt aus einer Screenreader-Beschriftung den Namen der sprechenden Person.
enum SpeakerLabelParser {
    /// Statusmarker nach dem Namen. Englisch und Deutsch, mit und ohne Komma.
    static let markers = [", is speaking", " is speaking", ", speaking", " speaking", ", spricht", " spricht", ", talking", " talking"]
    /// Die eigene Kachel. Die eigene Stimme kommt ohnehin über das Mikrofon.
    static let selfMarkers = ["you are speaking", "du sprichst", "sie sprechen", "(you)", "(du)", "(sie)", "(ich)", "(me)"]
    /// Verneinungen, die sonst als Treffer durchgingen.
    static let negations = ["not speaking", "spricht nicht", "is not talking"]

    static func speakingName(in label: String) -> String? {
        let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 120 else { return nil }
        let lower = text.lowercased()
        guard !selfMarkers.contains(where: lower.contains), !negations.contains(where: lower.contains) else { return nil }
        guard let marker = markers.first(where: { lower.contains($0) }),
              let range = text.range(of: marker, options: .caseInsensitive) else { return nil }
        let prefix = text[text.startIndex..<range.lowerBound]
        // Bei „Name, stummgeschaltet, spricht" zählt nur der erste Teil.
        let name = prefix.split(separator: ",").first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard name.count >= 2, name.count <= 60, name.rangeOfCharacter(from: .letters) != nil else { return nil }
        return name
    }
}

/// Ein Durchlauf durch die Fenster der Meeting-Apps.
///
/// Zwei Wege zum Namen:
/// 1. Beschriftung mit Statuswort („Anna, spricht“), wie Zoom oder ältere Apps es machen.
/// 2. Neues Teams: Die Kachel der sprechenden Person bekommt einen Rahmen mit der CSS-Klasse
///    `vdi-frame-occlusion`; der Name steht in der Beschriftung der Kachel darüber, etwa
///    „Max Muster, Kontextmenü ist verfügbar“. Belegt mit dem Echo-Testanruf und einem
///    echten Call am 18.11.2026 (Teams 2, deutsche Oberfläche).
enum AXSpeakerScan {
    static let speakingFrameClass = "vdi-frame-occlusion"

    struct Result {
        var names = Set<String>()
        var samples = Set<String>()
        var exhausted = false
    }

    static func scan(pids: [pid_t], budget: Int, sampling: Bool) -> Result {
        var result = Result()
        var remaining = budget
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            for window in children(of: app, attribute: kAXWindowsAttribute) {
                collect(in: window, tile: nil, budget: &remaining, sampling: sampling, into: &result)
            }
        }
        result.exhausted = remaining <= 0
        return result
    }

    private static func collect(in element: AXUIElement, tile: String?, budget: inout Int, sampling: Bool, into result: inout Result) {
        guard budget > 0 else { return }
        budget -= 1
        var tile = tile
        for attribute in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute, kAXHelpAttribute] {
            guard let text = string(element, attribute) else { continue }
            if let name = SpeakerLabelParser.speakingName(in: text) { result.names.insert(name) }
            if attribute == kAXDescriptionAttribute, let name = TeamsTileLabel.name(in: text) { tile = name }
            if sampling, ActiveSpeakerPoller.isCandidate(text) { result.samples.insert("[\(attribute)] \(text)") }
        }
        if let tile, classes(of: element).contains(speakingFrameClass) {
            result.names.insert(tile)
        }
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            collect(in: child, tile: tile, budget: &budget, sampling: sampling, into: &result)
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func classes(of element: AXUIElement) -> [String] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &value) == .success else { return [] }
        return value as? [String] ?? []
    }

    private static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}

/// Name aus der Beschriftung einer Teams-Kachel.
enum TeamsTileLabel {
    /// Hinweise, an denen eine Kachel-Beschriftung zu erkennen ist.
    static let tileMarkers = ["kontextmenü ist verfügbar", "hat kontextmenü", "context menu", "has context menu"]

    static func name(in label: String) -> String? {
        let lower = label.lowercased()
        guard label.count <= 250, tileMarkers.contains(where: lower.contains) else { return nil }
        // Die eigene Kachel: „Video von mir selbst, …“. Die eigene Stimme kommt übers Mikrofon.
        guard !lower.contains("mir selbst"), !lower.contains("myself"),
              !SpeakerLabelParser.selfMarkers.contains(where: lower.contains) else { return nil }
        var parts = label.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if lower.hasPrefix("video von ") || lower.hasPrefix("video of ") { parts.removeFirst() }
        guard let first = parts.first, !first.isEmpty else { return nil }
        // Firmenformat „Nachname, Vorname (Abteilung)“ → „Vorname Nachname“.
        if parts.count > 1, !first.contains(" "), let paren = parts[1].firstIndex(of: "("),
           case let given = parts[1][..<paren].trimmingCharacters(in: .whitespaces), !given.isEmpty {
            return "\(given) \(first)"
        }
        guard first.count >= 2, first.count <= 60, first.rangeOfCharacter(from: .letters) != nil else { return nil }
        return first
    }
}

/// Läuft in Teams noch ein Anruf? Erkennbar am Auflegen-Knopf, den Teams nur während eines
/// Calls zeigt (DOM-ID `hangup-button`, belegt am 18.11.2026). Teilen, Stummschalten und
/// Gerätewechsel lassen ihn stehen, deshalb taugt er als Gegenprobe zum Mikrofon-Signal.
enum TeamsCallControls {
    static let bundleIDs: Set<String> = ["com.microsoft.teams2", "com.microsoft.teams"]
    static let hangupIdentifier = "hangup-button"
    static let nodeBudget = 8_000

    static func isInCall(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var budget = nodeBudget
        for window in children(of: app, attribute: kAXWindowsAttribute) where find(in: window, budget: &budget) {
            return true
        }
        return false
    }

    private static func find(in element: AXUIElement, budget: inout Int) -> Bool {
        guard budget > 0 else { return false }
        budget -= 1
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXDOMIdentifier" as CFString, &value) == .success,
           (value as? String) == hangupIdentifier {
            return true
        }
        for child in children(of: element, attribute: kAXChildrenAttribute) where find(in: child, budget: &budget) {
            return true
        }
        return false
    }

    private static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
