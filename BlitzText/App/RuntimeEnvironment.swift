import Foundation

enum RuntimeEnvironment {
    /// Läuft die App gerade als Test-Host unter XCTest/Swift Testing?
    ///
    /// Der Test-Host ist unsigniert gebaut. macOS behandelt ihn deshalb als fremde App: Jeder
    /// Schlüsselbund-Zugriff und jede Berechtigungsabfrage (Bedienungshilfen, Mikrofon) löst
    /// bei jedem Testlauf einen neuen Systemdialog aus. Unter Tests bleibt beides deshalb aus.
    static let isRunningTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCInjectBundleInto"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()
}
