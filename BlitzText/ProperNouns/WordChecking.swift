import AppKit

/// Abstrahiert „ist dieses Wort dem Wörterbuch bekannt?" — injizierbar, damit
/// Korrektur und Erkennung deterministisch ohne echtes Wörterbuch testbar sind.
protocol WordChecking: Sendable {
    func isKnownWord(_ word: String) -> Bool
}

/// Produktiv-Implementierung über `NSSpellChecker`. Ein Wort gilt als „bekannt",
/// wenn der Checker es NICHT als Tippfehler markiert. On-device, keine Cloud.
struct SystemSpellChecker: WordChecking {
    let language: String

    init(language: String = "de") {
        self.language = language
    }

    func isKnownWord(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(
            of: trimmed,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        // location == NSNotFound → kein Fehler gefunden → Wort ist bekannt.
        return range.location == NSNotFound
    }
}
