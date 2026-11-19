import SwiftUI

@main
struct SpikeApp: App {
    @StateObject private var history: DictationHistory
    @StateObject private var meetings: MeetingStore
    @StateObject private var session: SessionController

    init() {
        let history = DictationHistory()
        let meetings = MeetingStore()
        _history = StateObject(wrappedValue: history)
        _meetings = StateObject(wrappedValue: meetings)
        _session = StateObject(wrappedValue: SessionController(history: history, meetings: meetings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(history)
                .environmentObject(meetings)
                .onOpenURL { session.handle(url: $0) }
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Diktat", systemImage: "bolt.fill") { DictationView() }
            Tab("Meetings", systemImage: "person.2.wave.2") { MeetingsView() }
            Tab("Einstellungen", systemImage: "gearshape") { SettingsView() }
        }
    }
}
