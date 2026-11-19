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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SessionToggle() } }
            .navigationDestination(for: UUID.self) { MeetingDetailView(meetingID: $0) }
        }
    }

    @ViewBuilder
    private var recorder: some View {
        if let id = session.activeMeetingID {
            ActiveMeetingCard(meetingID: id)
        } else {
            Card {
                Text("Neues Meeting").font(Theme.title).foregroundStyle(Theme.ink)
                Text("Nimmt über das Mikrofon auf, auch wenn du die App verlässt. Transkript, Sprecher und Notizen entstehen danach auf dem Gerät.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Button { session.startMeeting() } label: {
                    CenteredLabel("Meeting aufnehmen", systemImage: "record.circle")
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

/// Laufende Aufnahme: Uhr, eigene Notizen, Beenden. Auch im Detail eines fortgesetzten Meetings.
struct ActiveMeetingCard: View {
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: MeetingStore
    let meetingID: UUID

    var body: some View {
        Card(title) {
            HStack {
                StatusDot(state: .meeting)
                let since = session.meetingRecordingSince ?? Date()
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Duration.seconds(max(0, context.date.timeIntervalSince(since))),
                         format: .time(pattern: .hourMinuteSecond))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
            }
            OwnNotesEditor(meetingID: meetingID)
            Button(role: .destructive) { session.stopMeeting() } label: {
                CenteredLabel("Meeting beenden", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.recording)
            .controlSize(.large)
        }
    }

    private var title: String {
        let parts = store.meeting(meetingID)?.partCount ?? 1
        return parts > 1 ? "Aufnahme läuft · Teil \(parts)" : "Aufnahme läuft"
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
