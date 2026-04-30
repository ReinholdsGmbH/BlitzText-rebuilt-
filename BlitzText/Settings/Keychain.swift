import Foundation
import Security

/// Klassischer macOS-Keychain (file-based login keychain).
/// Beim ersten Schreiben/Lesen prompted der Schlüsselbund einmal — auf
/// "Immer erlauben" klicken, dann fragt er nicht mehr, solange das
/// "BlitzText Local Dev"-Cert (Scripts/create-signing-cert.sh) verwendet
/// wird. Bei ad-hoc-Signing wechselt der Code-Hash bei jedem Build und der
/// Prompt erscheint erneut.
///
/// Hinweis: kSecUseDataProtectionKeychain wäre prompt-frei, braucht aber
/// eine echte Apple-Team-ID — funktioniert mit Self-signed-Cert nicht.
final class Keychain: @unchecked Sendable {
    static let shared = Keychain(service: "de.reinholds.blitztext")
    let service: String

    init(service: String) { self.service = service }

    @discardableResult
    func write(value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess {
            Log.write("Keychain write failed for \(account): OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                Log.write("Keychain read returned OSStatus \(status) for \(account)")
            }
            return nil
        }
        return s
    }

    @discardableResult
    func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
