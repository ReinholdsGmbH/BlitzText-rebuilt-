import Foundation

/// Roh-DTO für einen Eintrag aus `GET /repos/:owner/:repo/releases`.
/// Nur die Felder, die wir wirklich brauchen — der Rest der JSON wird ignoriert.
struct GitHubReleaseDTO: Decodable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date?
    let assets: [Asset]

    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case draft
        case prerelease
        case publishedAt = "published_at"
        case assets
    }
}

/// Bereinigtes Domänenmodell eines veröffentlichten Releases — das, womit UI und
/// Installer arbeiten. Aus einem `GitHubReleaseDTO` mit gültigem SemVer-Tag gebaut.
struct ReleaseInfo: Identifiable, Sendable, Equatable {
    let version: SemanticVersion
    /// Menschlicher Titel (GitHub-`name`), Fallback auf den Tag.
    let title: String
    /// Roh-Markdown der Release-Notes (deutsch, mit `###`-Sektionen). Kann leer sein.
    let notes: String
    /// Original-Tag (z. B. `v0.6.1`) — für den Direktlink auf GitHub.
    let tag: String
    /// Download-URL des DMG-Assets, sofern vorhanden. `nil`, wenn das Release kein
    /// `BlitzText-*.dmg` mitliefert (kommt bei alten Releases vor) → dann ist nur
    /// „Notes anzeigen" möglich, kein In-App-Download.
    let dmgURL: URL?
    let publishedAt: Date?

    var id: String { tag }

    /// Baut das Domänenmodell aus dem DTO. Gibt `nil` zurück, wenn der Tag kein
    /// gültiger SemVer ist (dann können wir nicht vergleichen → Eintrag ignorieren).
    init?(dto: GitHubReleaseDTO) {
        guard let version = SemanticVersion(dto.tagName) else { return nil }
        self.version = version
        self.tag = dto.tagName
        self.title = dto.name?.isEmpty == false ? dto.name! : dto.tagName
        self.notes = dto.body ?? ""
        self.publishedAt = dto.publishedAt
        // Erstes DMG-Asset wählen (Namensschema `BlitzText-X.Y.Z.dmg`, aber wir sind
        // tolerant: irgendein `.dmg` genügt).
        self.dmgURL = dto.assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL
    }

    /// Direkter Testkonstruktor (umgeht das DTO) — für Unit-Tests und Previews.
    init(version: SemanticVersion, title: String, notes: String, tag: String, dmgURL: URL?, publishedAt: Date? = nil) {
        self.version = version
        self.title = title
        self.notes = notes
        self.tag = tag
        self.dmgURL = dmgURL
        self.publishedAt = publishedAt
    }
}
