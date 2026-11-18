import Foundation

/// Lesen, Schreiben und Löschen einzelner Geheimnisse; der Schlüsselbund im Betrieb,
/// ein Wörterbuch in Tests.
protocol SecretStorage: AnyObject, Sendable {
    func read(account: String) -> String?
    @discardableResult func write(value: String, account: String) -> Bool
    @discardableResult func delete(account: String) -> Bool
}

extension Keychain: SecretStorage {}

/// Alle API-Schlüssel in EINEM Schlüsselbund-Eintrag.
///
/// Warum: BlitzText ist selbst signiert. Nach jedem neuen Build fragt macOS je Eintrag erneut
/// nach dem Passwort. Mit OpenAI und Requesty in getrennten Einträgen waren das zwei Abfragen
/// pro Build, mit einem gemeinsamen Eintrag ist es eine.
///
/// Geladen wird genau einmal, im Hintergrund (`SecItemCopyMatching` kann blockieren, siehe
/// `SettingsStore.apiKey`). Beim ersten Laden werden die alten Einzeleinträge übernommen und
/// danach gelöscht; scheitert das Schreiben, bleiben sie liegen.
final class SecretVault: @unchecked Sendable {
    static let shared = SecretVault(storage: Keychain.shared)

    static let combinedAccount = "blitztext-api-keys"
    /// Frühere Einzeleinträge: OpenAI, OpenRouter, Requesty.
    static let legacyAccounts = ["openai-api-key", "openrouter-api-key", "requesty-api-key"]

    private let storage: SecretStorage
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var loaded = false

    init(storage: SecretStorage) {
        self.storage = storage
    }

    /// Wert zu einem Konto, lädt beim ersten Aufruf. Nur aus Hintergrund-Tasks rufen.
    func value(for account: String) -> String? {
        loadIfNeeded()
        return lock.withLock { values[account] }
    }

    /// Nutzerinitiiert aus den Einstellungen: darf dort den Schlüsselbund fragen.
    @discardableResult
    func set(_ value: String, for account: String) -> Bool {
        loadIfNeeded()
        let snapshot: [String: String] = lock.withLock {
            if value.isEmpty { values[account] = nil } else { values[account] = value }
            return values
        }
        return persist(snapshot)
    }

    private func loadIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        if let json = storage.read(account: Self.combinedAccount),
           let decoded = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8)) {
            values = decoded
            return
        }
        var migrated: [String: String] = [:]
        for account in Self.legacyAccounts {
            if let value = storage.read(account: account), !value.isEmpty { migrated[account] = value }
        }
        values = migrated
        guard !migrated.isEmpty, write(migrated) else { return }
        Self.legacyAccounts.forEach { storage.delete(account: $0) }
        Log.write("SecretVault: \(migrated.count) Schlüssel in einen Schlüsselbund-Eintrag übernommen")
    }

    private func persist(_ snapshot: [String: String]) -> Bool {
        guard !snapshot.isEmpty else {
            storage.delete(account: Self.combinedAccount)
            return true
        }
        return write(snapshot)
    }

    private func write(_ snapshot: [String: String]) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot), let json = String(data: data, encoding: .utf8) else { return false }
        return storage.write(value: json, account: Self.combinedAccount)
    }
}
