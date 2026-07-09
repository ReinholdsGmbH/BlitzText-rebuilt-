import Foundation

/// Zentrale Definition des GitHub-Repos, aus dem BlitzText verteilt wird.
///
/// EINZIGE Quelle für Owner/Repo — sowohl der In-App-Updater als auch der
/// „Release-Notes öffnen…"-Menüpunkt lesen von hier. Früher stand die URL
/// hartkodiert (und veraltet) im `MenuBarController`.
///
/// Das Repo ist PUBLIC → die REST-API und die Asset-Downloads funktionieren
/// unauthentifiziert (kein Token nötig). Das unauth. Rate-Limit von 60 Anfragen/h
/// ist bei einem 2-Stunden-Prüftakt unkritisch.
enum GitHubRepo {
    /// Organisation/Owner auf GitHub.
    static let owner = "ReinholdsGmbH"
    /// Repository-Name. Achtung: endet bewusst auf „-" (so heißt das Repo).
    static let name = "BlitzText-rebuilt-"

    /// REST-Endpunkt, der ALLE Releases (neueste zuerst) liefert.
    /// Doku: https://docs.github.com/rest/releases/releases#list-releases
    static var releasesAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(name)/releases")!
    }

    /// Menschlich lesbare Releases-Übersichtsseite (für „Release-Notes öffnen…").
    /// Robust auch für noch nicht veröffentlichte Versionen — die aktuellste steht oben.
    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(owner)/\(name)/releases")!
    }

    /// Direktlink auf die Release-Seite eines konkreten Tags (z. B. `v0.6.1`).
    static func releasePageURL(tag: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(name)/releases/tag/\(tag)")!
    }
}
