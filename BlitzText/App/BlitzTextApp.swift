import SwiftUI
import AppKit

@main
struct BlitzTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Bewusst leere Scene — Settings-Window steuert SettingsWindowController,
        // weil .accessory-Apps (LSUIElement) keinen Settings-Selector aus App-Menu haben.
        Settings { EmptyView() }
    }
}
