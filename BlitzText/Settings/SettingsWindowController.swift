import AppKit
import SwiftUI

/// Eigenständiges Einstellungsfenster — funktioniert in Accessory-Apps (LSUIElement),
/// wo der Selector `showSettingsWindow:` nicht greift, weil es kein App-Menu gibt.
@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let modelManager: LocalModelManager
    private let diarizerManager: DiarizerModelManager
    private let speakerViewModel: SpeakerProfileViewModel
    private let enrollmentViewModel: EnrollmentViewModel
    private var window: NSWindow?

    init(settings: SettingsStore, modelManager: LocalModelManager, diarizerManager: DiarizerModelManager, speakerViewModel: SpeakerProfileViewModel, enrollmentViewModel: EnrollmentViewModel) {
        self.settings = settings
        self.modelManager = modelManager
        self.diarizerManager = diarizerManager
        self.speakerViewModel = speakerViewModel
        self.enrollmentViewModel = enrollmentViewModel
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        let host = NSHostingController(
            rootView: SettingsView()
                .environmentObject(settings)
                .environmentObject(modelManager)
                .environmentObject(diarizerManager)
                .environmentObject(speakerViewModel)
                .environmentObject(enrollmentViewModel)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Einstellungen"
        window.contentViewController = host
        window.setContentSize(NSSize(width: 600, height: 700))
        window.minSize = NSSize(width: 520, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        window.collectionBehavior = [.fullScreenAuxiliary]
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
