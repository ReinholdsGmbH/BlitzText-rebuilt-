import Foundation

/// Entfernt deutsche Zögerlaute (ähm, äh, öhm, öh, ehm + Dehnvarianten) aus Diktat-Text.
/// Wird nur im Standard-Modus (`.blitztext`) angewandt — Plus/$%&! glätten das ohnehin
/// im Rewrite-Schritt. On-device, rein, ohne Abhängigkeiten.
enum FillerWordFilter {

    /// Zögerlaut-Token an Wortgrenzen, mit optionaler Dehnung (ä+/h+/m*).
    /// Die e-Variante verlangt ein abschließendes „m", damit das echte Wort „eh"
    /// nicht getroffen wird. `\b` ist Unicode-bewusst — „ähnlich", „während" oder
    /// „zäh" enthalten zwar „äh", werden aber nicht getroffen (keine Wortgrenze um
    /// das innere „äh").
    private static let fillerCore = "(?:ä+h+m*|ö+h+m*|e+h+m+)"
    private static let fillerPattern = "(?i)\\b" + fillerCore + "\\b"
    private static let leadingFillerPattern = "(?i)^\\s*" + fillerCore + "\\b"

    /// Entfernt alle Zögerlaute und räumt die Folgen auf (verwaiste Kommata,
    /// Doppel-Leerzeichen, Leerraum vor Satzzeichen). Stand am Satzanfang ein
    /// Füller, wird der neue Erstbuchstabe re-kapitalisiert.
    static func strip(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: fillerPattern) else { return text }

        let startedWithFiller = text.range(of: leadingFillerPattern, options: .regularExpression) != nil

        let ns = text as NSString
        let stripped = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: ""
        )

        let cleaned = cleanUp(stripped)
        return startedWithFiller ? capitalizeFirst(cleaned) : cleaned
    }

    // MARK: - Aufräumen

    private static func cleanUp(_ text: String) -> String {
        var result = text
        let steps: [(pattern: String, template: String)] = [
            ("\\s+([,.;:!?])", "$1"),   // Leerraum vor Satzzeichen entfernen
            ("(?:,\\s*){2,}", ", "),    // verwaiste Komma-Folgen → ein Komma
            ("[ \\t]{2,}", " "),         // Mehrfach-Leerraum → ein Leerzeichen
            ("^[\\s,;:]+", "")           // führende Satzzeichen/Whitespace
        ]
        for step in steps {
            result = result.replacingOccurrences(
                of: step.pattern, with: step.template, options: .regularExpression
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
