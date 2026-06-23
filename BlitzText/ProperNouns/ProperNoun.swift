import Foundation

/// Ein gelernter Eigenname samt bekannten Fehlhörungen (Aliase) und Statistik.
/// Ersetzt das frühere `[String]`-Modell — die Aliase treiben die Fuzzy-Korrektur,
/// occurrenceCount/lastSeenAt die Übersicht im Anpassen-Tab.
struct ProperNoun: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var aliases: [String]
    var occurrenceCount: Int
    var lastSeenAt: Date?

    init(
        id: UUID = UUID(),
        text: String,
        aliases: [String] = [],
        occurrenceCount: Int = 0,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.aliases = aliases
        self.occurrenceCount = occurrenceCount
        self.lastSeenAt = lastSeenAt
    }

    /// Alle Schreibweisen, gegen die gematcht wird (kanonisch + Aliase).
    var allForms: [String] { [text] + aliases }
}
