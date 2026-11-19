import Foundation
import FoundationModels

/// Formatierung mit Apple Intelligence auf dem Gerät, wie Wispr Flow sie macht: Listen,
/// Satzzeichen, Absätze. Strikt ohne Umformulieren; die Fassung wird nur übernommen, wenn der
/// Wortbestand erhalten bleibt und sie rechtzeitig kommt. Sonst bleibt das Regel-Ergebnis.
enum DictationAI {
    /// Am Mac mit Apple Intelligence erprobt (2026-11-19): Beispiele und feste Wortwahl
    /// verhindern erfundene Listen und Wiederholungen.
    static let instructions = """
    Du formatierst diktierten deutschen Text. Gib jeden Satz genau einmal zurück, nichts wiederholen, nichts erfinden.
    Eine nummerierte Liste setzt du nur, wenn der Sprecher ausdrücklich aufzählt, also mit erstens, zweitens, drittens, als Erstes, dann, danach, außerdem, als Nächstes, als Letztes oder zuletzt. Dann gilt: Der Satz vor der Aufzählung bleibt immer erhalten und endet mit einem Doppelpunkt, jeder Punkt steht in einer eigenen Zeile mit 1., 2., 3. In den Punkten entfallen nur die Aufzählungswörter und die Füllwörter "möchte ich", "ich möchte", "muss ich", "noch", "außerdem", "dann" und "und". Alle übrigen Wörter und jede Zahl bleiben unverändert in derselben Reihenfolge.
    Ohne solche Aufzählungswörter gibst du den Text unverändert zurück und korrigierst höchstens Satzzeichen.
    Antworte nur mit dem Text.

    Beispiel 1
    Eingabe: Für morgen habe ich drei Dinge. Erstens muss ich das Angebot 7 schicken, dann möchte ich noch mit Anna telefonieren und als Letztes die Rechnung prüfen.
    Ausgabe:
    Für morgen habe ich drei Dinge:
    1. Das Angebot 7 schicken
    2. Mit Anna telefonieren
    3. Die Rechnung prüfen

    Beispiel 2
    Eingabe: Hallo Jens, wir brauchen den Raum, den Beamer und die Unterlagen.
    Ausgabe: Hallo Jens, wir brauchen den Raum, den Beamer und die Unterlagen.
    """

    /// Kurze Diktate lohnen den Aufwand nicht.
    static let minimumWords = 8
    static let timeout: Duration = .seconds(6)

    /// Lädt das Modell vorab (beim Session-Start), damit das erste Diktat nicht ins Zeitlimit läuft.
    static func prewarm() {
        guard isAvailable else { return }
        LanguageModelSession(instructions: instructions).prewarm()
    }

    /// Für die Einstellungen: ob und warum Apple Intelligence nicht erreichbar ist.
    static var statusText: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "verfügbar"
        case .unavailable(.deviceNotEligible): return "Gerät nicht geeignet"
        case .unavailable(.appleIntelligenceNotEnabled): return "in den iPhone-Einstellungen aus"
        case .unavailable(.modelNotReady): return "Modell wird noch geladen"
        case .unavailable: return "nicht verfügbar"
        }
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Liefert die formatierte Fassung oder nil (zu kurz, nicht verfügbar, zu langsam, Wörter verändert).
    static func format(_ text: String) async -> String? {
        guard text.split(whereSeparator: \.isWhitespace).count >= minimumWords, isAvailable else { return nil }
        let candidate: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: instructions)
                return try? await session.respond(to: text, options: GenerationOptions(sampling: .greedy)).content
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard var formatted = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"„“")),
              !formatted.isEmpty else { return nil }
        formatted = DictationFormatter.restoreIntro(original: text, formatted: formatted)
        guard
              DictationFormatter.preservesWords(original: text, formatted: formatted) else { return nil }
        return formatted
    }
}
