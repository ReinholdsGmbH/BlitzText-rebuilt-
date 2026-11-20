import Foundation

/// Titelregeln für Meetings mit Besprechungsnamen aus Teams.
///
/// Einmalige Termine heißen wie in der Einladung. Serien wie Daily oder Weekly hießen dann
/// jedes Mal gleich; dort hängt die KI das Thema an: „Team Daily: Releaseplanung“.
extension MeetingDocument {

    /// Begriffe, an denen ein Serientermin schon beim ersten Mal erkennbar ist.
    static let seriesKeywords = ["daily", "weekly", "monthly", "jour fixe", "jourfixe", "standup", "stand-up",
                                 "sync", "regeltermin", "teamabstimmung", "retro"]

    /// Serie, wenn der Name nach einem Regeltermin klingt oder im Archiv mehrfach vorkommt.
    /// `archiveTitles` enthält die Besprechungsnamen aller Meetings, dieses eingeschlossen.
    static func isSeries(_ callTitle: String, archiveTitles: [String]) -> Bool {
        let key = callTitle.lowercased()
        if seriesKeywords.contains(where: { key.contains($0) }) { return true }
        return archiveTitles.filter { $0.lowercased() == key }.count >= 2
    }

    /// „Name: Thema“. Wiederholt die KI den Namen am Anfang, wird er nicht verdoppelt.
    static func seriesTitle(call: String, topic: String) -> String {
        var rest = topic.trimmingCharacters(in: .whitespaces)
        if rest.lowercased().hasPrefix(call.lowercased()) {
            rest = String(rest.dropFirst(call.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " :-–—|,"))
        }
        return rest.isEmpty ? call : String("\(call): \(rest)".prefix(80))
    }

    /// Übernimmt einen KI-Titel nach der Zusammenfassung. Eigene Titel bleiben, einmalige
    /// Termine behalten ihren Besprechungsnamen, Serien bekommen das Thema angehängt.
    mutating func applySummaryTitle(_ suggested: String?, isSeries: Bool) {
        guard titleChosenByUser != true, let suggested, !suggested.isEmpty else { return }
        guard let call = callTitle, !call.isEmpty else { aiTitle = suggested; return }
        if isSeries { aiTitle = Self.seriesTitle(call: call, topic: suggested) }
    }
}
