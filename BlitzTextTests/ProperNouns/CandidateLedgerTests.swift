import Testing
import Foundation
@testable import BlitzText

struct CandidateLedgerTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "bt-ledger-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test("Erstes Vorkommen erreicht die Schwelle (2) noch nicht, zweites schon")
    func reachesThresholdOnSecondSighting() {
        let ledger = CandidateLedger(defaults: freshDefaults(), threshold: 2)
        #expect(ledger.record("Vardhaman") == false)
        #expect(ledger.record("vardhaman") == true) // case-insensitiv, zweites Vorkommen
    }

    @Test("reset setzt den Zähler zurück")
    func resetClearsCounter() {
        let ledger = CandidateLedger(defaults: freshDefaults(), threshold: 2)
        _ = ledger.record("Clara")
        ledger.reset("Clara")
        #expect(ledger.record("Clara") == false) // Zähler war zurückgesetzt → wieder 1
    }

    @Test("Zähler überlebt eine neue Ledger-Instanz (gleiche Defaults)")
    func persistsAcrossInstances() {
        let defaults = freshDefaults()
        #expect(CandidateLedger(defaults: defaults, threshold: 2).record("Ott") == false)
        #expect(CandidateLedger(defaults: defaults, threshold: 2).record("Ott") == true)
    }
}
