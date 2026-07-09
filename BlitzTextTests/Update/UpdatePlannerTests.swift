import Testing
import Foundation
@testable import BlitzText

struct UpdatePlannerTests {

    /// Dekodiert eine Releases-JSON-Fixture genau wie der echte Client (ISO-8601-Datum).
    private func decode(_ json: String) throws -> [GitHubReleaseDTO] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GitHubReleaseDTO].self, from: Data(json.utf8))
    }

    /// Fixture, die die realen Eigenheiten der GitHub-Antwort abbildet:
    /// stabile Releases mit DMG, ein Draft, ein Pre-Release, ein Release ohne DMG,
    /// ein Eintrag mit ungültigem Tag.
    private let fixture = """
    [
      { "tag_name": "v0.7.0", "name": "v0.7.0 — Neu", "body": "### Neu\\n- A", "draft": false, "prerelease": false, "published_at": "2026-08-01T10:00:00Z",
        "assets": [ { "name": "BlitzText-0.7.0.dmg", "browser_download_url": "https://example.com/BlitzText-0.7.0.dmg" } ] },
      { "tag_name": "v0.6.5-rc1", "name": "RC", "body": "rc", "draft": false, "prerelease": true, "published_at": "2026-07-20T10:00:00Z", "assets": [] },
      { "tag_name": "v0.6.1", "name": "v0.6.1 — Updater", "body": "### Behoben\\n- B", "draft": false, "prerelease": false, "published_at": "2026-07-15T10:00:00Z",
        "assets": [ { "name": "BlitzText-0.6.1.dmg", "browser_download_url": "https://example.com/BlitzText-0.6.1.dmg" } ] },
      { "tag_name": "v0.6.0", "name": "v0.6.0", "body": "notes", "draft": false, "prerelease": false, "published_at": "2026-07-09T09:24:19Z",
        "assets": [ { "name": "BlitzText-0.6.0.dmg", "browser_download_url": "https://example.com/BlitzText-0.6.0.dmg" } ] },
      { "tag_name": "v0.9.9-draft", "name": "geheim", "body": "wip", "draft": true, "prerelease": false, "published_at": "2026-09-01T10:00:00Z", "assets": [] },
      { "tag_name": "v0.4.0", "name": "v0.4.0 — alt, kein DMG", "body": "alt", "draft": false, "prerelease": false, "published_at": "2026-05-15T13:18:36Z", "assets": [] },
      { "tag_name": "kaputt", "name": "ungültig", "body": "x", "draft": false, "prerelease": false, "published_at": "2026-01-01T10:00:00Z", "assets": [] }
    ]
    """

    @Test("Filtert Drafts, Pre-Releases und ungültige Tags; sortiert absteigend")
    func filtersAndSorts() throws {
        let releases = UpdatePlanner.usableReleases(from: try decode(fixture))
        #expect(releases.map(\.tag) == ["v0.7.0", "v0.6.1", "v0.6.0", "v0.4.0"])
    }

    @Test("Erkennt Update und aggregiert alle neueren Releases (neueste zuerst)")
    func plansUpdateFromOldVersion() throws {
        let plan = UpdatePlanner.plan(current: SemanticVersion("0.6.0")!, from: try decode(fixture))
        let unwrapped = try #require(plan)
        #expect(unwrapped.latest.tag == "v0.7.0")
        #expect(unwrapped.newerReleases.map(\.tag) == ["v0.7.0", "v0.6.1"])  // 0.6.0 selbst NICHT enthalten
        #expect(unwrapped.isDownloadable)
    }

    @Test("Kein Update, wenn laufende Version >= neuestem stabilem Release")
    func noUpdateWhenCurrent() throws {
        #expect(UpdatePlanner.plan(current: SemanticVersion("0.7.0")!, from: try decode(fixture)) == nil)
        #expect(UpdatePlanner.plan(current: SemanticVersion("1.0.0")!, from: try decode(fixture)) == nil)
    }

    @Test("Pre-Release wird nie als Update angeboten, auch wenn es die höchste Nummer trägt")
    func ignoresPrerelease() throws {
        // Laufend 0.6.4: das einzige „neuere" ist v0.6.5-rc1 (prerelease) → aber v0.7.0 ist stabil.
        let plan = UpdatePlanner.plan(current: SemanticVersion("0.6.4")!, from: try decode(fixture))
        #expect(plan?.latest.tag == "v0.7.0")
        #expect(plan?.newerReleases.contains { $0.tag == "v0.6.5-rc1" } == false)
    }

    @Test("Release ohne DMG-Asset wird erkannt, ist aber nicht herunterladbar")
    func handlesReleaseWithoutAsset() throws {
        let onlyOld = """
        [ { "tag_name": "v0.4.0", "name": "alt", "body": "x", "draft": false, "prerelease": false, "published_at": "2026-05-15T13:18:36Z", "assets": [] } ]
        """
        let plan = UpdatePlanner.plan(current: SemanticVersion("0.3.0")!, from: try decode(onlyOld))
        #expect(plan?.latest.tag == "v0.4.0")
        #expect(plan?.isDownloadable == false)
        #expect(plan?.latest.dmgURL == nil)
    }

    @Test("Leere Release-Liste → kein Update")
    func emptyList() throws {
        #expect(UpdatePlanner.plan(current: SemanticVersion("0.6.0")!, from: try decode("[]")) == nil)
    }
}
