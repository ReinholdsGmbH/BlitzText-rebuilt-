import AppKit

/// Wegweiser zu den Einstellungen. Früher ein eigenes Fenster mit sieben Tabs; die
/// Einstellungen leben jetzt als Bereiche im App-Fenster (`AppWindowController`). Alle
/// Einstiege — Zahnrad im Popover, Menüleisten-Kontextmenü, Start mit `--settings`,
/// fehlender OpenAI-Schlüssel — rufen weiter `show()` auf und landen dort.
@MainActor
final class SettingsWindowController {
    /// Wird in `AppDelegate.bootstrap()` gesetzt, sobald das App-Fenster existiert.
    var openInApp: ((AppSection) -> Void)?

    func show(section: AppSection = .dictation) {
        guard let openInApp else {
            Log.write("SettingsWindowController: App-Fenster noch nicht bereit")
            return
        }
        openInApp(section)
    }
}
