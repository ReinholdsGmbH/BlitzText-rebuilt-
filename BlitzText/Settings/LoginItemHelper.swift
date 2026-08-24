import AppKit
import ServiceManagement

/// Auto-Start beim Anmelden am Mac (Systemeinstellungen › Allgemein › Anmeldeobjekte).
///
/// Verantwortungsteilung wie bei den Bedienungshilfen: `register()` legt den EINTRAG an —
/// das ist alles, was die App darf. Sichtbar wird er unter „Beim Anmelden öffnen"; ob der
/// Schalter an ist, entscheidet der Nutzer (bzw. macOS, wenn er ihn nie deaktiviert hat).
/// Deshalb gibt es keinen eigenen persistierten Toggle-State: Quelle der Wahrheit ist
/// immer `SMAppService.mainApp.status`.
@MainActor
enum LoginItemHelper {

    enum Status {
        /// Eingetragen und aktiv — BlitzText startet beim Anmelden.
        case enabled
        /// Eingetragen, aber der Nutzer hat den Schalter aus (oder noch nicht bestätigt).
        case requiresApproval
        /// Kein Eintrag vorhanden.
        case notRegistered
        /// macOS findet das Bundle nicht (z. B. App läuft aus dem Build-Ordner statt
        /// aus /Applications) — Registrierung ist hier nicht sinnvoll möglich.
        case notFound
    }

    static func status() -> Status {
        switch SMAppService.mainApp.status {
        case .enabled:          return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered:    return .notRegistered
        case .notFound:         return .notFound
        @unknown default:       return .notRegistered
        }
    }

    /// Legt den Anmeldeobjekt-Eintrag an. No-Op, wenn schon eingetragen (`enabled` oder
    /// `requiresApproval`) — dann bleibt das Umlegen des Schalters Sache des Nutzers.
    @discardableResult
    static func register() -> Bool {
        switch status() {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            break
        }
        do {
            try SMAppService.mainApp.register()
            Log.write("LoginItem: registriert (Status danach: \(status()))")
            return true
        } catch {
            // Typische Ursachen: App nicht in /Applications, ad-hoc-signiertes Bundle
            // (self-signed Build), oder der Nutzer hat den Eintrag zuvor abgelehnt.
            Log.write("LoginItem: Registrierung fehlgeschlagen — \(error.localizedDescription)")
            return false
        }
    }

    /// Entfernt den Anmeldeobjekt-Eintrag wieder.
    @discardableResult
    static func unregister() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            Log.write("LoginItem: abgemeldet")
            return true
        } catch {
            Log.write("LoginItem: Abmelden fehlgeschlagen — \(error.localizedDescription)")
            return false
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
