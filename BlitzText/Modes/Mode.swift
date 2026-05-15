import Foundation

enum Mode: String, CaseIterable, Codable, Identifiable {
    case blitztext       // fn+Shift   — Sprache rein, Text raus
    case blitztextPlus   // fn+Control — Geschrieben sprechen
    case blitztextRant   // fn+Option  — Frust rein, entspannt raus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blitztext: return "Blitztext"
        case .blitztextPlus: return "Blitztext+"
        case .blitztextRant: return "Blitztext $%&!"
        }
    }

    var subtitle: String {
        switch self {
        case .blitztext: return "Sprache rein. Text raus."
        case .blitztextPlus: return "Geschrieben sprechen."
        case .blitztextRant: return "Frust rein. Entspannt raus."
        }
    }

    var systemImage: String {
        switch self {
        case .blitztext: return "mic.fill"
        case .blitztextPlus: return "checklist"
        case .blitztextRant: return "flame.fill"
        }
    }

    /// Default-System-Prompt für den Rewrite-Schritt. `.blitztext` rewritet nicht.
    var defaultRewritePrompt: String {
        switch self {
        case .blitztext:
            return ""
        case .blitztextPlus:
            return """
            Du bist ein professioneller Assistent für Textaufbereitung.
            Du erhältst ein Transkript einer Sprachaufnahme, in der eine Person informell oder spontan eine Nachricht an eine oder mehrere Personen aufgenommen hat.

            Deine Aufgabe ist es, das Transkript so umzuschreiben, dass es sich so liest als wäre es geschrieben und nicht gesprochen. Ändere nichts am Inhalt. Es soll sich nur gut wie eine geschriebene Nachricht lesen.

            Also es muss nicht Wort für Wort stimmen. Mach es halt so wie man eine Nachricht schreiben würde.
            """
        case .blitztextRant:
            return """
            Der folgende Text wurde emotional und aufgeregt eingesprochen. Wandle ihn in eine sachliche, freundliche und professionelle Nachricht um.
            Entferne Schimpfwörter, Übertreibungen und aggressive Formulierungen. Behalte den inhaltlichen Kern bei. Kein Sarkasmus. Der Ton soll warmherzig und konstruktiv sein.
            """
        }
    }

}

enum WritingStyle: String, CaseIterable, Codable, Identifiable {
    case formal, neutral, casual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .formal: return "Formell"
        case .neutral: return "Neutral"
        case .casual: return "Locker"
        }
    }
    var promptHint: String {
        switch self {
        case .formal: return "Schreibstil: formell, professionell, Sie-Form."
        case .neutral: return "Schreibstil: neutral, klar, sachlich."
        case .casual: return "Schreibstil: locker, du-Form, freundlich."
        }
    }
}

enum TriggerMode: String, CaseIterable, Codable, Identifiable {
    case hold        // Halten
    case toggle      // Drücken
    var id: String { rawValue }
    var label: String { self == .hold ? "Halten" : "Drücken" }
}
