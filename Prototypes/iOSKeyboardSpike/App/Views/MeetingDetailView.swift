import SwiftUI

/// Ein Meeting: Notizen (eigene und automatische) oder Transkript, mit Kopieren, Teilen, Umbenennen, Löschen.
struct MeetingDetailView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    let meetingID: UUID

    private enum Pane: String, CaseIterable { case notes = "Notizen", transcript = "Transkript" }
    @State private var pane: Pane = .notes
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false
    @State private var toast: String?

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
                    Text(meeting.title).font(Theme.title).foregroundStyle(Theme.ink)
                    Text(meeting.timeRange).font(.subheadline).foregroundStyle(Theme.muted)
                    if meeting.status != .done { statusLine(meeting) }
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
        .alert("Umbenennen", isPresented: $renaming) {
            TextField("Titel", text: $newTitle)
            Button("Speichern") { store.update(meeting.id) { $0.title = newTitle } }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("Meeting löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                store.delete(meeting.id)
                dismiss()
            }
        } message: {
            Text("Audio, Transkript und Notizen werden entfernt.")
        }
        .toast($toast)
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
                ShareLink("Notizen teilen", item: meeting.notesForCopy)
                Divider()
                Button("Umbenennen …", systemImage: "pencil") { newTitle = meeting.title; renaming = true }
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
