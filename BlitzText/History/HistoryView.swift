import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Verlauf").font(.title2).bold()
                Spacer()
                Text("\(history.entries.count) Einträge").font(.caption).foregroundStyle(.secondary)
                Button(role: .destructive) { confirmClear = true } label: {
                    Label("Alle löschen", systemImage: "trash")
                }
                .disabled(history.entries.isEmpty)
                .confirmationDialog("Alle Einträge wirklich löschen?", isPresented: $confirmClear) {
                    Button("Alle löschen", role: .destructive) { history.clearAll() }
                    Button("Abbrechen", role: .cancel) {}
                }
            }
            .padding()
            Divider()

            if history.entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Noch keine Transkripte.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(history.entries) { entry in
                            HistoryRow(entry: entry)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @EnvironmentObject var history: HistoryStore
    @State private var copiedKind: CopiedKind = .none

    enum CopiedKind { case none, raw, polished }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy, HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: entry.mode.systemImage)
                    .foregroundStyle(.secondary)
                Text(entry.mode.title).bold()
                Text(Self.formatter.string(from: entry.date))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    history.delete(entry)
                } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.plain)
                .help("Eintrag löschen")
            }

            if let polished = entry.polished {
                section(
                    title: "Polierte Version",
                    text: polished,
                    isCopied: copiedKind == .polished,
                    onCopy: {
                        copy(polished); copiedKind = .polished
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedKind = .none }
                    }
                )
                section(
                    title: "Original-Transkript",
                    text: entry.rawTranscript,
                    isCopied: copiedKind == .raw,
                    onCopy: {
                        copy(entry.rawTranscript); copiedKind = .raw
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedKind = .none }
                    }
                )
            } else {
                section(
                    title: "Transkript",
                    text: entry.rawTranscript,
                    isCopied: copiedKind == .raw,
                    onCopy: {
                        copy(entry.rawTranscript); copiedKind = .raw
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedKind = .none }
                    }
                )
            }
        }
        .padding()
    }

    @ViewBuilder
    private func section(title: String, text: String, isCopied: Bool, onCopy: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary).bold()
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onCopy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(isCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(isCopied ? "Kopiert" : "In Zwischenablage")
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
