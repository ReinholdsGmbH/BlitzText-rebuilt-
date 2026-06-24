import Testing
@testable import BlitzText

struct FillerWordFilterTests {

    @Test("Führender Zögerlaut wird entfernt und Folgewort re-kapitalisiert")
    func leadingFillerRemovedAndRecapitalized() {
        #expect(FillerWordFilter.strip("Ähm, das ist wichtig.") == "Das ist wichtig.")
    }

    @Test("Zögerlaut mitten im Satz wird entfernt, Casing bleibt")
    func midSentenceFillerRemoved() {
        #expect(FillerWordFilter.strip("Das ist äh wichtig.") == "Das ist wichtig.")
    }

    @Test("Dehnvarianten und mehrere Füller werden entfernt")
    func elongatedAndMultipleFillers() {
        #expect(FillerWordFilter.strip("Äääh, ich denke öhm das passt.") == "Ich denke das passt.")
    }

    @Test("Eingeklammerter Füller mit Kommata kollabiert sauber")
    func commaWrappedFiller() {
        #expect(FillerWordFilter.strip("Das, ähm, ist gut.") == "Das, ist gut.")
    }

    @Test("Echtes Wort 'eh' wird NICHT entfernt (e-Variante braucht m)")
    func realWordEhPreserved() {
        #expect(FillerWordFilter.strip("Ich gehe eh nach Hause.") == "Ich gehe eh nach Hause.")
    }

    @Test("Wörter mit innerem 'äh' bleiben unangetastet (Wortgrenzen)")
    func wordsContainingAehPreserved() {
        #expect(FillerWordFilter.strip("Das ist ähnlich und zäh.") == "Das ist ähnlich und zäh.")
    }

    @Test("Text ohne Füller bleibt unverändert (auch Casing)")
    func noFillerUnchanged() {
        #expect(FillerWordFilter.strip("das ist gut") == "das ist gut")
        #expect(FillerWordFilter.strip("") == "")
    }
}
