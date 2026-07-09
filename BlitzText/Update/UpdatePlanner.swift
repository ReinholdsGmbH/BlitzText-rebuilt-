import Foundation

/// Ergebnis der Update-Prüfung: es gibt ein neueres Release als die laufende Version.
struct UpdatePlan: Sendable, Equatable {
    /// Das neueste stabile Release (Ziel des Downloads).
    let latest: ReleaseInfo
    /// ALLE stabilen Releases, die neuer sind als die laufende Version — neueste zuerst.
    /// Enthält `latest` als erstes Element. Der Notes-Screen zeigt sie aggregiert, damit
    /// ein Kollege, der zwei Versionen übersprungen hat, alle Änderungen sieht.
    let newerReleases: [ReleaseInfo]

    /// True, wenn das neueste Release ein DMG mitliefert (In-App-Download möglich).
    var isDownloadable: Bool { latest.dmgURL != nil }

    /// Aggregierte Notes als Klartext (für Notification-Body und Logging).
    /// Die eigentliche UI rendert `newerReleases` einzeln (Markdown pro Release).
    var aggregatedNotesPlain: String {
        newerReleases
            .map { "\($0.title)\n\($0.notes)" }
            .joined(separator: "\n\n———\n\n")
    }
}

/// Reine (seiteneffektfreie, testbare) Update-Entscheidungslogik. Kein Netzwerk, keine UI.
enum UpdatePlanner {

    /// Wandelt Roh-DTOs in verwendbare Releases: Drafts und Pre-Releases fliegen raus,
    /// Einträge mit ungültigem Tag ebenfalls. Sortiert absteigend nach Version.
    static func usableReleases(from dtos: [GitHubReleaseDTO]) -> [ReleaseInfo] {
        dtos
            .filter { !$0.draft && !$0.prerelease }
            .compactMap(ReleaseInfo.init(dto:))
            .sorted { $0.version > $1.version }
    }

    /// Ermittelt, ob ein Update ansteht. `nil` = alles aktuell (oder keine gültigen Releases).
    ///
    /// - Parameters:
    ///   - current: laufende Version (aus `CFBundleShortVersionString`).
    ///   - dtos: Roh-Releases von der GitHub-API.
    static func plan(current: SemanticVersion, from dtos: [GitHubReleaseDTO]) -> UpdatePlan? {
        let releases = usableReleases(from: dtos)
        let newer = releases.filter { $0.version > current }
        guard let latest = newer.first else { return nil }
        return UpdatePlan(latest: latest, newerReleases: newer)
    }
}
