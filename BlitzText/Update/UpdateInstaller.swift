import Foundation
import Security

/// Fortschritts-Phasen der Installation — vom Service in `@Published`-State gespiegelt.
enum InstallPhase: Sendable, Equatable {
    case downloading(Double)   // 0…1
    case preparing             // Mount + Kopie aus dem DMG
    case relaunching           // Übergabe an den Helfer, App startet gleich neu
    case failed(String)        // Klartext-Fehler für die UI
}

/// Lädt das DMG des neuesten Releases, mountet es, ersetzt das LAUFENDE App-Bundle und
/// startet neu. Bewusst analog zu `Scripts/install.sh` + dem Relaunch-Helfer im
/// `LifecycleWatchdog` (sh-Helfer: warten → ersetzen → neu öffnen).
///
/// Wichtige Entscheidung: Ziel ist `Bundle.main.bundleURL` — das aktuell laufende Bundle,
/// NICHT hart `/Applications`. So funktioniert das Update auch, wenn die App mal woanders
/// liegt, und es kann nie ein fremdes Bundle überschreiben.
///
/// Concurrency: `@unchecked Sendable`, kein veränderlicher Instanz-Zustand. Alle Schritte
/// laufen off-main (der Service ruft `install` aus einem `Task.detached` auf). Die
/// blockierenden `hdiutil`-Aufrufe sind damit vom Main-Thread entkoppelt.
final class UpdateInstaller: @unchecked Sendable {

    private let downloader = DMGDownloader()

    /// Führt den kompletten Ablauf aus. Non-throwing: jeder Fehler wird als `.failed`
    /// gemeldet. Bei Erfolg kehrt die Funktion NICHT zurück (der Prozess beendet sich via
    /// `exit(0)`, der Helfer startet die neue Version).
    func install(plan: UpdatePlan, phase: @escaping @Sendable (InstallPhase) -> Void) async {
        guard let dmgURL = plan.latest.dmgURL else {
            phase(.failed("Für diese Version gibt es keinen automatischen Download. Bitte manuell von GitHub laden."))
            return
        }

        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            phase(.failed("Keine Schreibrechte für \(parent.path). Bitte BlitzText manuell aus dem DMG ersetzen."))
            return
        }

        // Eigenes Arbeitsverzeichnis mit „blitztext-"-Präfix (wird von der Temp-Bereinigung
        // beim App-Start ohnehin mit erfasst, falls hier mal etwas liegen bleibt).
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-update-\(UUID().uuidString)", isDirectory: true)
        let dmgFile = workDir.appendingPathComponent("BlitzText.dmg")

        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

            // 1) Download mit Fortschritt.
            phase(.downloading(0))
            try await downloader.download(from: dmgURL, to: dmgFile) { fraction in
                phase(.downloading(fraction))
            }
            Log.write("Update: DMG geladen (\(plan.latest.tag)) → \(dmgFile.lastPathComponent)")

            // 2) Mounten, App herauskopieren, wieder aushängen.
            phase(.preparing)
            let mountPoint = try mountDMG(dmgFile)
            defer { detachDMG(mountPoint) }

            let sourceApp = try locateApp(in: mountPoint)
            let stagedApp = workDir.appendingPathComponent("BlitzText.app")
            try? FileManager.default.removeItem(at: stagedApp)
            try FileManager.default.copyItem(at: sourceApp, to: stagedApp)
            Log.write("Update: App aus DMG kopiert → \(stagedApp.path)")

            // 3) Code-Signatur prüfen, BEVOR wir das laufende Bundle ersetzen. Der Download
            //    muss dieselbe Designated Requirement erfüllen wie die laufende App (pinnt den
            //    Leaf-Cert-Hash). Schützt gegen einen kompromittierten Verteilungskanal —
            //    HTTPS deckt nur den Transport ab, nicht die Echtheit des Signierers.
            try verifySignature(of: stagedApp)
            Log.write("Update: Signatur des Downloads verifiziert (gleicher Signierer).")

            // 4) Quarantäne von der Staging-Kopie entfernen (Gatekeeper-freundlicher Start).
            stripQuarantine(stagedApp)

            // 5) Übergabe an den Helfer + Selbstbeendigung.
            phase(.relaunching)
            Log.write("Update: übergebe an Relaunch-Helfer, ersetze \(target.path)")
            launchReplaceHelper(staged: stagedApp, target: target, dmg: dmgFile, workDir: workDir)
            // Kurze Gnadenfrist, damit die UI „wird neu gestartet…" zeigen kann.
            try? await Task.sleep(nanoseconds: 400_000_000)
            exit(0)
        } catch let error as UpdateCheckError {
            try? FileManager.default.removeItem(at: workDir)
            phase(.failed(error.errorDescription ?? "Update fehlgeschlagen."))
            Log.write("Update fehlgeschlagen: \(error)")
        } catch {
            try? FileManager.default.removeItem(at: workDir)
            phase(.failed("Update fehlgeschlagen: \(error.localizedDescription)"))
            Log.write("Update fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // MARK: - DMG-Handling

    /// `hdiutil attach … -plist` → Mount-Point aus dem Ergebnis-Plist.
    private func mountDMG(_ dmg: URL) throws -> String {
        let result = runProcess(
            "/usr/bin/hdiutil",
            ["attach", "-nobrowse", "-noverify", "-noautoopen", "-plist", dmg.path]
        )
        guard result.exitCode == 0 else {
            throw InstallProcessError.mountFailed(String(data: result.stderr, encoding: .utf8) ?? "hdiutil-Fehler")
        }
        guard
            let plist = try? PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil) as? [String: Any],
            let entities = plist["system-entities"] as? [[String: Any]],
            let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw InstallProcessError.mountFailed("Mount-Point nicht gefunden")
        }
        return mountPoint
    }

    private func detachDMG(_ mountPoint: String) {
        _ = runProcess("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
    }

    /// Findet `BlitzText.app` (oder ersatzweise das erste `.app`) im gemounteten Volume.
    private func locateApp(in mountPoint: String) throws -> URL {
        let root = URL(fileURLWithPath: mountPoint)
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let apps = entries.filter { $0.pathExtension == "app" }
        if let named = apps.first(where: { $0.lastPathComponent == "BlitzText.app" }) {
            return named
        }
        guard let first = apps.first else {
            throw InstallProcessError.appNotFound
        }
        return first
    }

    private func stripQuarantine(_ app: URL) {
        _ = runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
    }

    // MARK: - Signaturprüfung

    /// Verifiziert, dass `stagedApp` (a) eine intakte Code-Signatur hat und (b) dieselbe
    /// Designated Requirement erfüllt wie die LAUFENDE App. Die Requirement einer self-signed
    /// App pinnt den Leaf-Cert-Hash („certificate leaf = H\"…\""), den ein Angreifer ohne den
    /// privaten Schlüssel nicht reproduzieren kann. So wird nur ein Update akzeptiert, das vom
    /// selben Signierer stammt wie die aktuelle Installation — auch wenn das GitHub-Release
    /// kompromittiert wäre. Wirft bei Fehlschlag (der Aufrufer bietet dann den manuellen
    /// GitHub-Download als Fallback an).
    private func verifySignature(of stagedApp: URL) throws {
        var runningCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &runningCode) == errSecSuccess,
              let runningCode else {
            throw InstallProcessError.signatureInvalid("Signatur der laufenden App ist nicht lesbar.")
        }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(runningCode, [], &requirement) == errSecSuccess,
              let requirement else {
            throw InstallProcessError.signatureInvalid("Signatur-Anforderung der laufenden App ist nicht ableitbar.")
        }

        var stagedCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(stagedApp as CFURL, [], &stagedCode) == errSecSuccess,
              let stagedCode else {
            throw InstallProcessError.signatureInvalid("Der Download hat keine lesbare Code-Signatur.")
        }

        // (a) Signatur intakt? (kein Requirement → reine Integritätsprüfung)
        let integrity = SecStaticCodeCheckValidity(stagedCode, [], nil)
        guard integrity == errSecSuccess else {
            throw InstallProcessError.signatureInvalid("Die Signatur des Downloads ist ungültig oder beschädigt (Status \(integrity)).")
        }

        // (b) Gleicher Signierer wie die laufende App?
        let match = SecStaticCodeCheckValidity(stagedCode, [], requirement)
        guard match == errSecSuccess else {
            throw InstallProcessError.signatureInvalid("Der Download ist nicht vom selben Entwickler signiert wie die installierte Version (Status \(match)). Bitte manuell von GitHub laden.")
        }
    }

    // MARK: - Relaunch-Helfer

    /// Detachter sh-Helfer: wartet, bis DIESER Prozess weg ist, ersetzt das Bundle und öffnet neu.
    /// Muss außerhalb unseres Prozesses laufen — wir ersetzen ja unser eigenes, laufendes Bundle.
    private func launchReplaceHelper(staged: URL, target: URL, dmg: URL, workDir: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        // Paths in doppelten Anführungszeichen → Leerzeichen sicher. Diese Pfade sind
        // app-kontrolliert (Temp-UUID / Bundle-Pfad), kein User-Input.
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        sleep 0.5
        rm -rf "\(target.path)"
        cp -R "\(staged.path)" "\(target.path)"
        xattr -dr com.apple.quarantine "\(target.path)" 2>/dev/null || true
        rm -rf "\(workDir.path)"
        open "\(target.path)"
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
    }

    // MARK: - Process-Helfer

    private struct ProcessResult { let exitCode: Int32; let stdout: Data; let stderr: Data }

    private func runProcess(_ launchPath: String, _ arguments: [String]) -> ProcessResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        let out = Pipe(); let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do {
            try task.run()
        } catch {
            return ProcessResult(exitCode: -1, stdout: Data(), stderr: Data(error.localizedDescription.utf8))
        }
        // Erst die Pipes leeren, DANN warten — sonst blockiert ein volles Pipe-Buffer den Prozess.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return ProcessResult(exitCode: task.terminationStatus, stdout: outData, stderr: errData)
    }
}

private enum InstallProcessError: Error, LocalizedError {
    case mountFailed(String)
    case appNotFound
    case signatureInvalid(String)

    var errorDescription: String? {
        switch self {
        case .mountFailed(let detail): return "DMG konnte nicht geöffnet werden: \(detail)"
        case .appNotFound:             return "Im DMG wurde keine BlitzText.app gefunden."
        case .signatureInvalid(let detail): return detail
        }
    }
}
