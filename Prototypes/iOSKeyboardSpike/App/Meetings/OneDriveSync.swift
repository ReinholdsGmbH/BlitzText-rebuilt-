import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// Upload in das OneDrive-App-Verzeichnis über Microsoft Graph, ohne Dateien-App.
/// Anmeldung: persönliches Microsoft-Konto, OAuth 2.0 mit PKCE (kein Client-Geheimnis).
/// Berechtigung `Files.ReadWrite.AppFolder`: nur `OneDrive/Apps/BlitzText iPhone/`.
@MainActor
final class OneDriveSync: ObservableObject {
    /// Öffentliche Kennung der App-Registrierung (kein Geheimnis).
    static let clientID = "13450a13-c7bc-4ed4-bf47-3529049cafbb"
    static let redirectScheme = "msauth.de.reinholds.blitzspike"
    static let redirectURI = "\(redirectScheme)://auth"
    static let scopes = "Files.ReadWrite.AppFolder offline_access User.Read"
    private static let authority = "https://login.microsoftonline.com/consumers/oauth2/v2.0"

    @Published private(set) var accountName: String?
    @Published private(set) var lastMessage: String?
    @Published private(set) var busy = false

    var isConnected: Bool { Keychain.read(Self.refreshKey) != nil }

    private static let refreshKey = "onedrive.refresh"
    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var session: ASWebAuthenticationSession?
    private let anchor = PresentationAnchor()

    init() {
        accountName = UserDefaults.standard.string(forKey: "onedrive.account")
    }

    // MARK: - Anmeldung

    func connect() async {
        busy = true
        defer { busy = false }
        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)
        var components = URLComponents(string: "\(Self.authority)/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: Self.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "response_mode", value: "query"),
            .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "select_account"),
        ]
        do {
            let callback = try await authenticate(url: components.url!)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let error = items.first(where: { $0.name == "error_description" || $0.name == "error" })?.value {
                lastMessage = "Anmeldung abgelehnt: \(error)"
                return
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                lastMessage = "Anmeldung ohne Code zurückgekehrt."
                return
            }
            try await redeem([
                "grant_type": "authorization_code", "code": code,
                "redirect_uri": Self.redirectURI, "code_verifier": verifier,
            ])
            await loadAccountName()
            lastMessage = "Mit OneDrive verbunden\(accountName.map { " als \($0)" } ?? "")."
        } catch {
            lastMessage = "OneDrive-Anmeldung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        Keychain.delete(Self.refreshKey)
        accessToken = nil
        accountName = nil
        UserDefaults.standard.removeObject(forKey: "onedrive.account")
        lastMessage = "OneDrive getrennt."
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(Self.redirectScheme),
                                                     completionHandler: Self.completion(continuation))
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: OneDriveError.message("Anmeldefenster ließ sich nicht öffnen."))
            }
        }
    }

    /// Der Rückruf kommt nicht zwingend auf dem Main-Thread; deshalb außerhalb des MainActors gebaut.
    nonisolated private static func completion(_ continuation: CheckedContinuation<URL, Error>) -> ASWebAuthenticationSession.CompletionHandler {
        { url, error in
            if let url { continuation.resume(returning: url) }
            else { continuation.resume(throwing: error ?? OneDriveError.message("Anmeldung abgebrochen.")) }
        }
    }

    private func redeem(_ parameters: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "\(Self.authority)/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = parameters
        form["client_id"] = Self.clientID
        form["scope"] = Self.scopes
        request.httpBody = form.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let access = json["access_token"] as? String else {
            throw OneDriveError.message(json["error_description"] as? String ?? "Token nicht erhalten.")
        }
        accessToken = access
        accessExpiry = Date().addingTimeInterval((json["expires_in"] as? Double ?? 3600) - 120)
        if let refresh = json["refresh_token"] as? String { Keychain.write(Self.refreshKey, refresh) }
    }

    private func validToken() async throws -> String {
        if let accessToken, Date() < accessExpiry { return accessToken }
        guard let refresh = Keychain.read(Self.refreshKey) else { throw OneDriveError.message("Nicht mit OneDrive verbunden.") }
        try await redeem(["grant_type": "refresh_token", "refresh_token": refresh])
        guard let accessToken else { throw OneDriveError.message("Token nicht erhalten.") }
        return accessToken
    }

    private func loadAccountName() async {
        guard let token = try? await validToken() else { return }
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let name = (json["userPrincipalName"] as? String) ?? (json["displayName"] as? String)
        accountName = name
        UserDefaults.standard.set(name, forKey: "onedrive.account")
    }

    // MARK: - Upload

    /// Lädt eine Datei nach `Apps/BlitzText iPhone/<pfad>`. Ordner legt OneDrive dabei an.
    func upload(_ data: Data, to path: String) async throws {
        let token = try await validToken()
        let encoded = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/:"))) ?? String($0)
        }.joined(separator: "/")
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/drive/special/approot:/\(encoded):/content")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (body, response) = try await URLSession.shared.upload(for: request, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let text = String(data: body, encoding: .utf8) ?? ""
            throw OneDriveError.message("Upload \(status): \(text.prefix(200))")
        }
    }

    // MARK: - Hilfen

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? value
    }
}

enum OneDriveError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

/// Fenster, über dem das Anmeldeblatt erscheint.
@MainActor
final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

/// Refresh-Token im Schlüsselbund des Geräts, nur diese App.
enum Keychain {
    private static let service = "de.reinholds.blitzspike.onedrive"

    static func write(_ key: String, _ value: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
