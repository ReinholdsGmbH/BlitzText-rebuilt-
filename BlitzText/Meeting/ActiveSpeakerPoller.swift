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

    static let diagnosticsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/BlitzText-Sprecheranzeige.txt")
    static let sampleLimit = 400
    nonisolated static let sampleKeywords = ["speak", "sprech", "spricht", "mute", "stumm", "mikro", "micro", "video",
                                 "kamera", "camera", "teilnehm", "particip", "hand", "audio", "ton "]

    static let interval: TimeInterval = 1
    /// Obergrenze je Durchlauf, damit ein großer Teams-Baum den Main-Thread nicht blockiert.
    static let nodeBudget = 2_500

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
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
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

    private func poll() {
        polls += 1
        let now = Date().timeIntervalSince(startedAt)
        var budget = Self.nodeBudget
        var names = Set<String>()
        // Proben nur alle 10 Abfragen und nur solange noch kein Name erkannt wurde.
        let sample = hints.isEmpty && polls % 10 == 1 && labelSamples.count < Self.sampleLimit
        var samples = Set<String>()
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            for window in Self.children(of: app, attribute: kAXWindowsAttribute) {
                Self.collect(in: window, budget: &budget, into: &names, sampling: sample, samples: &samples)
            }
        }
        if budget <= 0 { budgetExhausted += 1 }
        if sample { labelSamples.formUnion(samples.prefix(Self.sampleLimit - labelSamples.count)) }
        for name in names { hints.append(SpeakerHint(time: now, name: name)) }
    }

    private static func collect(in element: AXUIElement, budget: inout Int, into names: inout Set<String>,
                                sampling: Bool, samples: inout Set<String>) {
        guard budget > 0 else { return }
        budget -= 1
        for attribute in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute, kAXHelpAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let text = value as? String else { continue }
            if let name = SpeakerLabelParser.speakingName(in: text) { names.insert(name) }
            if sampling, isCandidate(text) { samples.insert("[\(attribute)] \(text)") }
        }
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            collect(in: child, budget: &budget, into: &names, sampling: sampling, samples: &samples)
        }
    }

    nonisolated static func isCandidate(_ text: String) -> Bool {
        guard (3...160).contains(text.count) else { return false }
        let lower = text.lowercased()
        return sampleKeywords.contains(where: lower.contains)
    }

    private static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
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
