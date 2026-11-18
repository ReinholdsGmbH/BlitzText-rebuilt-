import Foundation
import Testing
@testable import BlitzText

final class MemorySecretStorage: SecretStorage, @unchecked Sendable {
    var items: [String: String] = [:]
    var reads: [String] = []
    var failWrites = false

    func read(account: String) -> String? { reads.append(account); return items[account] }
    func write(value: String, account: String) -> Bool {
        guard !failWrites else { return false }
        items[account] = value
        return true
    }
    func delete(account: String) -> Bool { items.removeValue(forKey: account) != nil }
}

struct SecretVaultTests {

    @Test("Alte Einzeleinträge werden in einen Eintrag übernommen und danach gelöscht")
    func migratesLegacyItems() {
        let storage = MemorySecretStorage()
        storage.items = ["openai-api-key": "sk-openai", "requesty-api-key": "rq-key"]
        let vault = SecretVault(storage: storage)

        #expect(vault.value(for: "openai-api-key") == "sk-openai")
        #expect(vault.value(for: "requesty-api-key") == "rq-key")
        #expect(Set(storage.items.keys) == [SecretVault.combinedAccount])
    }

    @Test("Nach der Übernahme liest ein neuer Start nur noch den gemeinsamen Eintrag")
    func secondStartReadsOnce() {
        let storage = MemorySecretStorage()
        storage.items = ["openai-api-key": "sk-openai", "requesty-api-key": "rq-key"]
        _ = SecretVault(storage: storage).value(for: "openai-api-key")
        storage.reads = []

        let restarted = SecretVault(storage: storage)
        #expect(restarted.value(for: "requesty-api-key") == "rq-key")
        #expect(restarted.value(for: "openai-api-key") == "sk-openai")
        #expect(storage.reads == [SecretVault.combinedAccount])
    }

    @Test("Scheitert das Schreiben, bleiben die alten Einträge liegen")
    func keepsLegacyOnWriteFailure() {
        let storage = MemorySecretStorage()
        storage.items = ["openai-api-key": "sk-openai"]
        storage.failWrites = true
        let vault = SecretVault(storage: storage)

        #expect(vault.value(for: "openai-api-key") == "sk-openai")
        #expect(storage.items["openai-api-key"] == "sk-openai")
    }

    @Test("Setzen und Entfernen ändern nur das eigene Konto")
    func setAndRemove() {
        let storage = MemorySecretStorage()
        let vault = SecretVault(storage: storage)
        vault.set("sk-openai", for: "openai-api-key")
        vault.set("rq-key", for: "requesty-api-key")
        vault.set("", for: "openai-api-key")

        let restarted = SecretVault(storage: storage)
        #expect(restarted.value(for: "openai-api-key") == nil)
        #expect(restarted.value(for: "requesty-api-key") == "rq-key")
    }
}
