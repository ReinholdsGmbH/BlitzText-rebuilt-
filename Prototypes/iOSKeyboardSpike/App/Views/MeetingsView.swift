import SwiftUI

/// Meeting-Liste mit großem Aufnahmeknopf. Während der Aufnahme: Laufzeit und eigene Notizen.
struct MeetingsView: View {
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: MeetingStore

    var body: some View {
        NavigationStack {
            List {
                Section { recorder }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                if store.meetings.contains(where: { $0.id != session.activeMeetingID }) {
                    Section("Meetings") {
                        ForEach(store.meetings.filter { $0.id != session.activeMeetingID }) { meeting in
                            NavigationLink(value: meeting.id) { MeetingRow(meeting: meeting) }
                                .swipeActions {
                                    Button("Löschen", systemImage: "trash", role: .destructive) { store.delete(meeting.id) }
                                }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Meetings")
            .navigationDestination(for: UUID.self) { MeetingDetailView(meetingID: $0) }
        }
    }

    @ViewBuilder
    private var recorder: some View {
        if let id = session.activeMeetingID, let meeting = store.meeting(id) {
            Card("Aufnahme läuft") {
                HStack {
                    StatusDot(state: .meeting)
                    TimelineView(.periodic(from: meeting.start, by: 1)) { context in
                        Text(Duration.seconds(context.date.timeIntervalSince(meeting.start)),
                             format: .time(pattern: .hourMinuteSecond))
                            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                }
                OwnNotesEditor(meetingID: id)
                Button(role: .destructive) { session.stopMeeting() } label: {
                    Label("Meeting beenden", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.recording)
                .controlSize(.large)
            }
        } else {
            Card {
                Text("Neues Meeting").font(Theme.title).foregroundStyle(Theme.ink)
                Text("Nimmt über das Mikrofon auf, auch wenn du die App verlässt. Transkript, Sprecher und Notizen entstehen danach auf dem Gerät.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Button { session.startMeeting() } label: {
                    Label("Meeting aufnehmen", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.state == .recording || session.state == .processing)
                Text("Nur aufnehmen, wenn alle Beteiligten einverstanden sind.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title).font(.headline).foregroundStyle(Theme.ink).lineLimit(2)
            HStack(spacing: 6) {
                Text(meeting.start.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text(Duration.seconds(meeting.duration), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                if meeting.status != .done {
                    Text("·")
                    Text(meeting.status.label).foregroundStyle(meeting.status.isBusy ? Theme.accent : Theme.recording)
                }
            }
            .font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
    }
}

/// Eigene Notizen, speichert beim Tippen.
struct OwnNotesEditor: View {
    @EnvironmentObject private var store: MeetingStore
    let meetingID: UUID
    @State private var text = ""

    var body: some View {
        TextField("Eigene Notizen, Stichpunkte, Aufgaben …", text: $text, axis: .vertical)
            .lineLimit(3...12)
            .padding(12)
            .background(Theme.sand.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onAppear { text = store.meeting(meetingID)?.ownNotes ?? "" }
            .onChange(of: text) { _, newValue in store.update(meetingID) { $0.ownNotes = newValue } }
    }
}
