import Testing
import Foundation
@testable import BlitzText

struct ProperNounMigrationTests {

    /// Eigene UserDefaults-Suite pro Test, damit die echte App-Konfig nicht berührt wird.
    private func freshDefaults() -> UserDefaults {
        let suite = "bt-propernoun-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Alter [String]-Snapshot migriert verlustfrei zu [ProperNoun]")
    func legacyStringArrayMigrates() throws {
        let defaults = freshDefaults()
        // Alten Snapshot mit dem Legacy-Feld "properNouns": [String] simulieren.
        let legacyJSON = """
        {"styleForPlus":"neutral","customPromptPlus":"","customPromptRant":"",
         "context":"","properNouns":["Vardhaman","Clara"],"autoInsert":false,
         "transcriptionLanguage":"de","rewriteModel":"gpt-4o-mini",
         "transcriptionModel":"whisper-1","backend":"parakeet"}
        """
        defaults.set(legacyJSON.data(using: .utf8)!, forKey: "de.reinholds.blitztext.settings")

        let store = SettingsStore(defaults: defaults)

        #expect(store.properNounTexts == ["Vardhaman", "Clara"])
        #expect(store.properNouns.allSatisfy { $0.aliases.isEmpty && $0.occurrenceCount == 0 })
    }

    @Test("bumpOccurrence erhöht Zähler und setzt lastSeenAt")
    func bumpOccurrenceUpdatesCounter() {
        let store = SettingsStore(defaults: freshDefaults())
        let noun = ProperNoun(text: "Vardhaman")
        store.properNouns = [noun]

        store.bumpOccurrence(termID: noun.id)

        #expect(store.properNouns.first?.occurrenceCount == 1)
        #expect(store.properNouns.first?.lastSeenAt != nil)
    }

    @Test("addAlias fügt neuen Alias case-insensitiv nur einmal hinzu")
    func addAliasDeduplicates() {
        let store = SettingsStore(defaults: freshDefaults())
        let noun = ProperNoun(text: "Vardhaman")
        store.properNouns = [noun]

        store.addAlias("Wardhaman", toTermID: noun.id)
        store.addAlias("wardhaman", toTermID: noun.id) // Duplikat (case)

        #expect(store.properNouns.first?.aliases == ["Wardhaman"])
    }
}
