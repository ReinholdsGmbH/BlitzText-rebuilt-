import SwiftUI

@main
struct BlitzTextApp: App {
    @StateObject private var history: DictationHistory
    @StateObject private var meetings: MeetingStore
    @StateObject private var session: SessionController
    @StateObject private var sharedFolder: SharedFolder
    @StateObject private var oneDrive: OneDriveSync
    @StateObject private var lexicon = SwipeLexiconBuilder()
    @StateObject private var dictionary: DictionarySync
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.dictation

    init() {
        let history = DictationHistory()
        let meetings = MeetingStore()
        let oneDrive = OneDriveSync()
        let sharedFolder = SharedFolder(oneDrive: oneDrive)
        _oneDrive = StateObject(wrappedValue: oneDrive)
        _dictionary = StateObject(wrappedValue: DictionarySync(oneDrive: oneDrive))
        _history = StateObject(wrappedValue: history)
        _meetings = StateObject(wrappedValue: meetings)
        _sharedFolder = StateObject(wrappedValue: sharedFolder)
        _session = StateObject(wrappedValue: SessionController(history: history, meetings: meetings, sharedFolder: sharedFolder))
    }

    var body: some Scene {
        WindowGroup {
            RootView(tab: $tab)
                .environmentObject(session)
                .environmentObject(history)
                .environmentObject(meetings)
                .environmentObject(sharedFolder)
                .environmentObject(oneDrive)
                .environmentObject(lexicon)
                .environmentObject(dictionary)
                .task { lexicon.buildIfNeeded() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await dictionary.sync() } }
                }
                .onOpenURL { url in
                    if url.host == "settings" { tab = .settings } else { session.handle(url: url) }
                }
                .tint(Theme.accent)
        }
    }
}

enum AppTab: Hashable { case dictation, meetings, settings }

struct RootView: View {
    @Binding var tab: AppTab

    var body: some View {
        TabView(selection: $tab) {
            Tab("Diktat", systemImage: "bolt.fill", value: .dictation) { DictationView() }
            Tab("Meetings", systemImage: "person.2.wave.2", value: .meetings) { MeetingsView() }
            Tab("Einstellungen", systemImage: "gearshape", value: .settings) { SettingsView() }
        }
    }
}
