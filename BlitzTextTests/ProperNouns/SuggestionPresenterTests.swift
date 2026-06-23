import Testing
import Foundation
@testable import BlitzText

@MainActor
struct SuggestionPresenterTests {

    private func makeStore() -> SettingsStore {
        let suite = "bt-presenter-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: d)
    }

    private func makeLedger() -> CandidateLedger {
        let suite = "bt-presenter-ledger-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return CandidateLedger(defaults: d, threshold: 2)
    }

    @Test("Einmaliger Kandidat wird nicht sofort vorgeschlagen (Ledger-Schwelle)")
    func singleSightingNotQueued() {
        let presenter = SuggestionPresenter(settings: makeStore(), ledger: makeLedger())
        presenter.enqueue(["Vardhaman"])
        #expect(presenter.current == nil)
    }

    @Test("Zweites Vorkommen löst den Vorschlag aus")
    func secondSightingQueues() {
        let presenter = SuggestionPresenter(settings: makeStore(), ledger: makeLedger())
        presenter.enqueue(["Vardhaman"])
        presenter.enqueue(["Vardhaman"])
        #expect(presenter.current?.word == "Vardhaman")
    }

    @Test("Variante eines bekannten Namens wird als Alias gemergt, nicht vorgeschlagen")
    func variantMergesAsAlias() {
        let store = makeStore()
        let term = ProperNoun(text: "Vardhaman")
        store.properNouns = [term]
        let presenter = SuggestionPresenter(settings: store, ledger: makeLedger())

        presenter.enqueue(["Wardhaman"]) // Fuzzy-Variante

        #expect(presenter.current == nil)
        #expect(store.properNouns.first?.aliases == ["Wardhaman"])
    }

    @Test("Duplikat innerhalb eines Batches wird dedupliziert")
    func duplicateWithinBatchDeduplicated() {
        let presenter = SuggestionPresenter(settings: makeStore(), ledger: makeLedger())
        // Pre-seed ledger so "Neuheit" has count=1 (one away from threshold=2)
        presenter.enqueue(["Neuheit"])
        #expect(presenter.current == nil) // nicht gezeigt, erst bei 2. Vorkommen

        // Jetzt enqueue mit Duplikat — beide sollten die Schwelle überschreiten,
        // aber dedupliziert sein → nur einmal in der Queue
        presenter.enqueue(["Neuheit", "Neuheit"])
        #expect(presenter.current?.word == "Neuheit")

        // Nach dismiss() sollte current nil sein, nicht "Neuheit" nochmal
        presenter.dismiss()
        #expect(presenter.current == nil)
    }
}
