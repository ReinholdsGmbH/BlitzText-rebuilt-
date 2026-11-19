import SwiftUI

/// Ein Meeting: Notizen (eigene und automatische) oder Transkript, mit Kopieren, Teilen, Umbenennen, Löschen.
struct MeetingDetailView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    let meetingID: UUID

    private enum Pane: String, CaseIterable { case notes = "Notizen", transcript = "Transkript" }
    @State private var pane: Pane = .notes
    @State private var title = ""
    @FocusState private var titleFocused: Bool
    @State private var confirmDelete = false
    @State private var toast: String?
    @State private var sharedFile: SharedFile?

    var body: some View {
        if let meeting = store.meeting(meetingID) {
            content(meeting)
        } else {
            ContentUnavailableView("Meeting gelöscht", systemImage: "trash")
        }
    }

    private func content(_ meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Titel", text: $title)
                        .font(Theme.title)
                        .foregroundStyle(Theme.ink)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onAppear { title = meeting.title }
                        .onChange(of: meeting.title) { _, new in if !titleFocused { title = new } }
                        .onChange(of: titleFocused) { _, focused in if !focused { saveTitle(meeting) } }
                        .onSubmit { titleFocused = false }
                    Text(meeting.timeRange).font(.subheadline).foregroundStyle(Theme.muted)
                    if meeting.status != .done { statusLine(meeting) }
                }
                if session.activeMeetingID == meeting.id {
                    ActiveMeetingCard(meetingID: meeting.id)
                } else if !meeting.status.isBusy {
                    Button { session.resumeMeeting(meeting.id) } label: {
                        CenteredLabel("Fortsetzen", systemImage: "record.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(session.state == .recording || session.state == .processing || session.state == .meeting)
                }
                Picker("Ansicht", selection: $pane) {
                    ForEach(Pane.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                switch pane {
                case .notes:
                    Card("Eigene Notizen") { OwnNotesEditor(meetingID: meeting.id) }
                    Card("Automatische Notizen") {
                        if meeting.summary.isEmpty {
                            Text(meeting.status.isBusy ? "Entsteht nach der Transkription." : "Noch keine.")
                                .foregroundStyle(Theme.muted)
                        } else {
                            NotesMarkdown(markdown: meeting.summary)
                        }
                    }
                case .transcript:
                    Card {
                        if meeting.transcript.isEmpty {
                            Text(meeting.status.isBusy ? "Wird erstellt …" : "Kein Transkript.").foregroundStyle(Theme.muted)
                        } else {
                            Text(meeting.transcript).textSelection(.enabled).foregroundStyle(Theme.ink)
                            Text("\(meeting.words.grouped) Wörter").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(meeting) }
        .confirmationDialog("Meeting löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                store.delete(meeting.id)
                dismiss()
            }
        } message: {
            Text("Audio, Transkript und Notizen werden entfernt.")
        }
        .toast($toast)
        .sheet(item: $sharedFile) { ShareSheet(url: $0.url).presentationDetents([.medium, .large]) }
    }

    /// Eine M4A mit allen Teilen, Datum und Titel im Namen, eigenen Notizen in den Metadaten.
    /// Am Mac: per AirDrop empfangen und auf die Meeting-Liste ziehen (Aufnahme importieren).
    private func sendToMac(_ meeting: Meeting) {
        toast = "Audio wird vorbereitet …"
        Task {
            do {
                let url = try await MeetingExport.audioFile(for: meeting, parts: store.audioURLs(for: meeting.id))
                sharedFile = SharedFile(url: url)
            } catch {
                toast = error.localizedDescription
            }
        }
    }

    private func saveTitle(_ meeting: Meeting) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { title = meeting.title; return }
        if trimmed != meeting.title { store.update(meeting.id) { $0.title = trimmed } }
    }

    private func statusLine(_ meeting: Meeting) -> some View {
        HStack(spacing: 8) {
            if meeting.status.isBusy { ProgressView().controlSize(.small) }
            Text(meeting.status.label).font(.subheadline.weight(.semibold))
                .foregroundStyle(meeting.status.isBusy ? Theme.accent : Theme.recording)
            if case .failed = meeting.status {
                Button("Erneut verarbeiten") { session.reprocess(meeting.id) }.font(.subheadline)
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ meeting: Meeting) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Notizen kopieren", systemImage: "doc.on.doc") {
                    Clipboard.copy(meeting.notesForCopy); toast = "Notizen kopiert"
                }
                Button("Transkript kopieren", systemImage: "text.quote") {
                    Clipboard.copy(meeting.transcript); toast = "Transkript kopiert"
                }
                .disabled(meeting.transcript.isEmpty)
                Button("An Mac senden (Audio)", systemImage: "laptopcomputer.and.arrow.down") { sendToMac(meeting) }
                    .disabled(meeting.status == .recording)
                ShareLink("Notizen teilen", item: meeting.notesForCopy)
                Divider()
                Button("Umbenennen", systemImage: "pencil") { titleFocused = true }
                Button("Erneut verarbeiten", systemImage: "arrow.clockwise") { session.reprocess(meeting.id) }
                    .disabled(meeting.status.isBusy || meeting.status == .recording)
                Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }
}

/// Zeigt die Notizen-Struktur des Protokolls: Überschriften, Stichpunkte, Aufgaben mit Kästchen.
struct NotesMarkdown: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(line.trimmingCharacters(in: .whitespaces))
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.isEmpty {
            Color.clear.frame(height: 2)
        } else if line.hasPrefix("#") {
            Text(line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))
                .font(.headline).foregroundStyle(Theme.ink).padding(.top, 6)
        } else if line.hasPrefix("- [ ]") || line.hasPrefix("- [x]") {
            bullet(symbol: line.hasPrefix("- [x]") ? "checkmark.square" : "square", text: String(line.dropFirst(5)))
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            bullet(symbol: "circle.fill", text: String(line.dropFirst(2)), small: true)
        } else {
            Text(inline(line)).foregroundStyle(Theme.ink)
        }
    }

    private func bullet(symbol: String, text: String, small: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(small ? .system(size: 5) : .body).foregroundStyle(Theme.accent)
            Text(inline(text.trimmingCharacters(in: .whitespaces))).foregroundStyle(Theme.ink)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
