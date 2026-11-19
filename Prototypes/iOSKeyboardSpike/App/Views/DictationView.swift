import SwiftUI

/// Startseite: Wortzähler groß, darunter die Session und die letzten Diktate.
struct DictationView: View {
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var history: DictationHistory
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    counter
                    sessionCard
                    recentCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("BlitzText")
            .toast($toast)
        }
    }

    private var counter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(history.totalWords.grouped)
                .font(Theme.heroNumber)
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .animation(.snappy, value: history.totalWords)
            Text("Wörter insgesamt")
                .font(.headline)
                .foregroundStyle(Theme.muted)
            Text("\(history.dictatedWords.grouped) diktiert · \(history.meetingWords.grouped) in Meetings")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var sessionCard: some View {
        Card("Session") {
            HStack(alignment: .center, spacing: 14) {
                StatusDot(state: session.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.state.headline).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(session.state.detail).font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            if session.state == .off {
                Button { session.startSession() } label: {
                    Label("Session starten", systemImage: "mic.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(role: .destructive) { session.endSession(reason: "manuell") } label: {
                    Label("Session beenden", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Text("Zurück in deine App: unten nach rechts wischen oder oben links „◀ …“ antippen. Dann diktierst du direkt aus der BlitzText-Tastatur.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            LabeledContent("Spracherkennung", value: session.modelStatus)
                .font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private var recentCard: some View {
        if !history.entries.isEmpty {
            Card("Zuletzt") {
                ForEach(history.entries.prefix(3)) { entry in
                    Button {
                        Clipboard.copy(entry.text)
                        toast = "Kopiert"
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.text).font(.body).foregroundStyle(Theme.ink).lineLimit(3)
                                .multilineTextAlignment(.leading)
                            Text("\(entry.date.formatted(date: .omitted, time: .shortened)) · \(entry.words) Wörter · tippen zum Kopieren")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    if entry.id != history.entries.prefix(3).last?.id { Divider() }
                }
            }
        }
    }
}

/// Farbiger Punkt für den Session-Zustand; pulsiert bei Aufnahme.
struct StatusDot: View {
    let state: Spike.State
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(color.opacity(0.35), lineWidth: pulse ? 10 : 0))
            .animation(isLive ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: pulse)
            .onAppear { pulse = isLive }
            .onChange(of: state) { pulse = isLive }
    }

    private var isLive: Bool { state == .recording || state == .meeting }

    private var color: Color {
        switch state {
        case .off: Theme.muted
        case .idle: Theme.success
        case .recording, .meeting: Theme.recording
        case .processing: Theme.accent
        }
    }
}

extension Spike.State {
    var headline: String {
        switch self {
        case .off: "Aus"
        case .idle: "Bereit"
        case .recording: "Hört zu"
        case .processing: "Schreibt …"
        case .meeting: "Meeting läuft"
        }
    }

    var detail: String {
        switch self {
        case .off: "Start hier oder über das Mikro in der Tastatur."
        case .idle: "Diktieren über die BlitzText-Tastatur, in jeder App."
        case .recording: "Diktat läuft."
        case .processing: "Parakeet transkribiert auf dem Gerät."
        case .meeting: "Diktat ist pausiert, bis das Meeting endet."
        }
    }
}
