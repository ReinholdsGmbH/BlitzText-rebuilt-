import Foundation

/// Typisierte Fehler der Release-Abfrage — für differenzierte UI-Meldungen.
enum UpdateCheckError: Error, LocalizedError {
    case network(Error)
    case http(Int)
    case rateLimited
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .network:     return "Keine Verbindung zu GitHub. Bist du online?"
        case .http(let c): return "GitHub antwortete mit Fehler \(c)."
        case .rateLimited: return "GitHub-Limit erreicht. Bitte später erneut versuchen."
        case .decoding:    return "Die Antwort von GitHub war unerwartet."
        }
    }
}

/// Fragt die öffentliche GitHub-Releases-API ab. Unauthentifiziert (Repo ist public).
///
/// Concurrency: `@unchecked Sendable` wie die übrigen Netzwerk-Clients im Projekt.
/// `URLSession`-Aufrufe laufen von Natur aus off-main; diese Klasse hält keinen
/// veränderlichen Zustand außer der injizierten Session (selbst Sendable).
final class GitHubReleaseClient: @unchecked Sendable {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Lädt und dekodiert alle Releases (neueste zuerst, roh — Filterung macht der `UpdatePlanner`).
    /// Wirft ausschließlich `UpdateCheckError`.
    func fetchReleases() async throws -> [GitHubReleaseDTO] {
        var request = URLRequest(url: GitHubRepo.releasesAPIURL)
        // GitHub verlangt einen User-Agent; ohne ihn kommt 403 zurück.
        request.setValue("BlitzText-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // Kurzer Timeout — die Prüfung darf im Hintergrund nie lange hängen.
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdateCheckError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.http(-1)
        }
        // 403 mit erschöpftem Rate-Limit von echten 403ern unterscheiden.
        if http.statusCode == 403 || http.statusCode == 429 {
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw UpdateCheckError.rateLimited
            }
            throw UpdateCheckError.http(http.statusCode)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateCheckError.http(http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([GitHubReleaseDTO].self, from: data)
        } catch {
            throw UpdateCheckError.decoding(error)
        }
    }
}
