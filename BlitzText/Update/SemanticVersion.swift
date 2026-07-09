import Foundation

/// Minimaler SemVer-Vergleich (nur `MAJOR.MINOR.PATCH`), zugeschnitten auf die
/// BlitzText-Versionierung (`CFBundleShortVersionString` bzw. Release-Tag ohne „v").
///
/// Bewusst KEIN vollständiger SemVer-Parser: keine Pre-Release-/Build-Metadaten-
/// Semantik (`1.0.0-beta+exp`). Pre-Releases werden im `UpdatePlanner` ohnehin
/// über das GitHub-`prerelease`-Flag ausgesiebt, nicht über den Versionsstring.
/// Fehlende Komponenten zählen als 0 (`"1"` == `1.0.0`, `"1.2"` == `1.2.0`).
struct SemanticVersion: Comparable, Equatable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parst einen Versionsstring. Ein optionales führendes „v"/„V" wird entfernt
    /// (GitHub-Tags heißen `v0.6.1`, die Info.plist trägt `0.6.1`). Alles nach dem
    /// dritten Segment (z. B. `-beta`, `+build`) wird ignoriert. `nil` bei Müll.
    init?(_ raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first == "v" || first == "V" {
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else { return nil }

        // Nur den numerischen `X.Y.Z`-Kopf betrachten — Suffixe wie „-beta.1" abschneiden.
        let core = trimmed.prefix { $0.isNumber || $0 == "." }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        func component(_ index: Int) -> Int? {
            guard index < parts.count else { return 0 }   // fehlend → 0
            let piece = parts[index]
            guard !piece.isEmpty else { return nil }       // "1..2" ist Müll
            return Int(piece)
        }
        guard let ma = component(0), let mi = component(1), let pa = component(2) else { return nil }
        self.init(major: ma, minor: mi, patch: pa)
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}
