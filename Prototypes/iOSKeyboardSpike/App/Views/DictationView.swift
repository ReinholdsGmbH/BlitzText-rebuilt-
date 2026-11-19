import SwiftUI

/// Diktat: Wortzähler oben, darunter alle Diktate nach Tagen. Tippen kopiert, Wischen löscht.
/// Die Session schaltet der Schalter oben rechts.
struct DictationView: View {
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var history: DictationHistory
    @State private var query = ""
    @State private var confirmDeleteAll = false
    @State private var toast: String?

    private var filtered: [DictationEntry] {
        query.isEmpty ? history.entries
            : history.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var days: [(day: Date, entries: [DictationEntry])] {
        let grouped = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { counter }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
                if history.entries.isEmpty {
                    Section {
                        Text("Was du mit der BlitzText-Tastatur diktierst, landet hier. Tippen kopiert, nach links wischen löscht.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
                ForEach(days, id: \.day) { day in
                    Section(day.day.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                        ForEach(day.entries) { entry in row(entry) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Diktat")
            .searchable(text: $query, prompt: "In Diktaten suchen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SessionToggle() }
                if !history.entries.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Alle löschen", systemImage: "trash", role: .destructive) { confirmDeleteAll = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .confirmationDialog("Alle Diktate löschen?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Alle löschen", role: .destructive) { history.deleteAll() }
            } message: {
                Text("Der Wortzähler bleibt erhalten.")
            }
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
            Text("Wörter insgesamt · \(history.dictatedWords.grouped) diktiert · \(history.meetingWords.grouped) in Meetings")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                StatusDot(state: session.state)
                Text(session.state.detail).font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(.top, 6)
        }
    }

    private func row(_ entry: DictationEntry) -> some View {
        Button { copy(entry) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.text).foregroundStyle(Theme.ink).lineLimit(5).multilineTextAlignment(.leading)
                Text("\(entry.date.formatted(date: .omitted, time: .shortened)) · \(entry.words) Wörter")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Löschen", systemImage: "trash", role: .destructive) { history.delete(entry) }
        }
        .swipeActions(edge: .leading) {
            Button("Kopieren", systemImage: "doc.on.doc") { copy(entry) }.tint(Theme.accent)
        }
        .contextMenu {
            Button("Kopieren", systemImage: "doc.on.doc") { copy(entry) }
            ShareLink(item: entry.text)
            Button("Löschen", systemImage: "trash", role: .destructive) { history.delete(entry) }
        }
    }

    private func copy(_ entry: DictationEntry) {
        Clipboard.copy(entry.text)
        toast = "Kopiert"
    }
}

/// Schalter oben rechts: Session an/aus. Während Diktat oder Meeting zeigt er den Zustand und bleibt an.
struct SessionToggle: View {
    @EnvironmentObject private var session: SessionController

    var body: some View {
        Toggle(isOn: Binding(
            get: { session.state != .off },
            set: { on in on ? session.startSession() : session.endSession(reason: "manuell") }
        )) {
            Text(session.state.headline).font(.footnote.weight(.semibold))
        }
        .toggleStyle(.switch)
        .tint(session.state == .meeting || session.state == .recording ? Theme.recording : Theme.success)
        .fixedSize()
        .accessibilityLabel("Session")
    }
}

/// Farbiger Punkt für den Session-Zustand; pulsiert bei Aufnahme.
struct StatusDot: View {
    let state: Spike.State
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(color.opacity(0.35), lineWidth: pulse ? 8 : 0))
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
        case .idle: "An"
        case .recording: "Hört zu"
        case .processing: "Schreibt"
        case .meeting: "Meeting"
        }
    }

    var detail: String {
        switch self {
        case .off: "Session aus. Schalter oben rechts oder Mikro in der Tastatur."
        case .idle: "Bereit. Diktiere über die BlitzText-Tastatur, in jeder App."
        case .recording: "Diktat läuft."
        case .processing: "Parakeet transkribiert auf dem Gerät."
        case .meeting: "Meeting läuft, Diktat pausiert."
        }
    }
}
