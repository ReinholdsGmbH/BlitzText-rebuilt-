import Foundation
import FoundationModels

/// Formatierung mit Apple Intelligence auf dem Gerät, wie Wispr Flow sie macht: Listen,
/// Satzzeichen, Absätze. Strikt ohne Umformulieren; die Fassung wird nur übernommen, wenn der
/// Wortbestand erhalten bleibt und sie rechtzeitig kommt. Sonst bleibt das Regel-Ergebnis.
enum DictationAI {
    static let instructions = """
    Du formatierst diktierten deutschen Text. Ändere kein Wort, formuliere nichts um, lass nichts \
    weg und füge keine Wörter hinzu. Erlaubt ist nur: Satzzeichen und Groß- und Kleinschreibung \
    korrigieren; Aufzählungen als Liste setzen, eine Zeile je Punkt, mit „- “ davor oder mit \
    „1. “, „2. “, wenn der Sprecher nummeriert hat; Wörter wie „erstens“ oder „zweitens“ dürfen \
    dabei entfallen; einen Einleitungssatz vor einer Liste mit Doppelpunkt abschließen; Absätze \
    bei einem Themenwechsel. Emojis und Sonderzeichen bleiben unverändert. Antworte nur mit dem \
    formatierten Text, ohne Erklärung und ohne Anführungszeichen.
    """

    /// Kurze Diktate lohnen den Aufwand nicht.
    static let minimumWords = 8
    static let timeout: Duration = .seconds(4)

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
                return try? await session.respond(to: text).content
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let formatted = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"„“")),
              !formatted.isEmpty,
              DictationFormatter.preservesWords(original: text, formatted: formatted) else { return nil }
        return formatted
    }
}
