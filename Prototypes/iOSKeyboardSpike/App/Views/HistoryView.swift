import SwiftUI

/// Alle Diktate, nach Tagen gruppiert. Tippen kopiert, Wischen löscht.
struct HistoryView: View {
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
            Group {
                if history.entries.isEmpty {
                    ContentUnavailableView("Noch keine Diktate", systemImage: "text.bubble",
                                           description: Text("Was du mit der BlitzText-Tastatur diktierst, landet hier."))
                } else {
                    list
                }
            }
            .background(Theme.background)
            .navigationTitle("Verlauf")
            .toolbar {
                if !history.entries.isEmpty {
                    Menu {
                        Button("Alle löschen", systemImage: "trash", role: .destructive) { confirmDeleteAll = true }
                    } label: { Image(systemName: "ellipsis.circle") }
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

    private var list: some View {
        List {
            ForEach(days, id: \.day) { day in
                Section(day.day.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                    ForEach(day.entries) { entry in
                        row(entry)
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
                }
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: "Im Verlauf suchen")
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
    }

    private func copy(_ entry: DictationEntry) {
        Clipboard.copy(entry.text)
        toast = "Kopiert"
    }
}
