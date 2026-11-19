import SwiftUI

@main
struct SpikeApp: App {
    @StateObject private var session = SessionController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onOpenURL { session.handle(url: $0) }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var session: SessionController

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Session", value: session.state.rawValue)
                    LabeledContent("App Group", value: session.appGroupOK ? "ok" : "FEHLT")
                    LabeledContent("Parakeet", value: session.modelStatus)
                    if let start = session.sessionStart, session.state != .off {
                        LabeledContent("Seit", value: start.formatted(date: .omitted, time: .shortened))
                    }
                    if let start = session.batteryAtStart {
                        LabeledContent("Akku Start/jetzt",
                                       value: "\(Int(start * 100)) % / \(Int(session.batteryNow * 100)) %")
                    }
                }
                Section("Auto-Stop bei Leerlauf") {
                    Picker("Auto-Stop", selection: $session.idleLimitMinutes) {
                        Text("5 min").tag(5)
                        Text("30 min").tag(30)
                        Text("aus").tag(0)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    if session.state == .off {
                        Button("Session starten") { session.startSession() }
                    } else {
                        Button("Session beenden", role: .destructive) { session.endSession(reason: "manuell") }
                    }
                } footer: {
                    Text("Nach dem Start mit der Wischgeste unten oder „◀ Zurück“ oben links in die vorige App wechseln.")
                }
                Section("Protokoll") {
                    ForEach(session.log, id: \.self) { Text($0).font(.caption.monospaced()) }
                }
            }
            .navigationTitle("BlitzSpike")
        }
    }
}
