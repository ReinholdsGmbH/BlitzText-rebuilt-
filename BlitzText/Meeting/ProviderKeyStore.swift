import Foundation

/// API-Schlüssel für OpenRouter und Requesty.
///
/// Gleiches Muster wie der OpenAI-Schlüssel im `SettingsStore`: Gelesen wird nur aus dem
/// Speicher-Cache, geladen wird im Hintergrund. `SecItemCopyMatching` kann nach Sleep/Wake
/// oder bei einem Schlüsselbund-Prompt minutenlang blockieren und hat die App auf dem
/// Main-Thread schon einmal komplett eingefroren.
final class ProviderKeyStore: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [SummaryProvider: String] = [:]
    private let vault: SecretVault?

    /// `vault: nil` hält alles nur im Speicher (Tests).
    init(vault: SecretVault? = .shared, loadAsync: Bool = true) {
        self.vault = vault
        guard loadAsync, let vault else { return }
        Task.detached(priority: .utility) { [weak self] in
            for provider in SummaryProvider.allCases where !provider.isLocal {
                if let value = vault.value(for: provider.keychainAccount), !value.isEmpty {
                    self?.cache(value, for: provider)
                }
            }
        }
    }

    func key(for provider: SummaryProvider) -> String {
        lock.withLock { keys[provider] ?? "" }
    }

    /// Nutzerinitiiert aus den Einstellungen: darf dort einmalig den Schlüsselbund fragen.
    func setKey(_ value: String, for provider: SummaryProvider) {
        guard !provider.isLocal else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        cache(trimmed, for: provider)
        vault?.set(trimmed, for: provider.keychainAccount)
    }

    private func cache(_ value: String, for provider: SummaryProvider) {
        lock.withLock { keys[provider] = value }
    }
}
