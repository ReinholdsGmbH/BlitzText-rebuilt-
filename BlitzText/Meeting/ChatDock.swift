import SwiftUI

/// Aufklappbarer Chat unten im Meetings-Bereich, wie Wispr Flows „Ask anything“.
/// Zugeklappt nur eine Eingabezeile; beim Fragen klappt er mit dem Verlauf auf.
struct ChatDock: View {
    @ObservedObject var chat: MeetingChat
    @ObservedObject var library: MeetingLibrary
    @State private var expanded = false
    @State private var input = ""
    @State private var allMeetings = true
    @FocusState private var focused: Bool

    private var scope: MeetingChat.Scope {
        if !allMeetings, let folder = library.selected?.folder { return .meeting(folder) }
        return .all
    }

    var body: some View {
        VStack(spacing: 0) {
            if expanded { header; Divider(); conversation }
            inputBar
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(MeetingTheme.card)
            .shadow(color: .black.opacity(0.14), radius: 14, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MeetingTheme.border))
        .frame(maxWidth: 680)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .animation(.easeOut(duration: 0.2), value: expanded)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(MeetingTheme.dawn700)
            if library.selected != nil {
                CapsuleToggle(options: [(true, "Alle Meetings"), (false, "Dieses Meeting")], selection: $allMeetings)
            } else {
                Text("Alle Meetings").font(.system(size: 13, weight: .medium))
            }
            Spacer()
            Button("Neuer Chat") { chat.reset() }.buttonStyle(SandButtonStyle()).disabled(chat.messages.isEmpty)
            Button { expanded = false } label: { Image(systemName: "chevron.down") }
                .buttonStyle(SandButtonStyle()).help("Zuklappen")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chat.messages.isEmpty {
                        Text(allMeetings || library.selected == nil
                             ? "Frag etwa: „Was hat Anna zum Cutover gesagt?“ oder „Welche Aufgaben habe ich diese Woche bekommen?“"
                             : "Frag etwas zu diesem Meeting.")
                            .font(.system(size: 12.5)).foregroundStyle(MeetingTheme.foregroundTertiary)
                    }
                    ForEach(chat.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if chat.busy {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Denkt nach …").font(.caption) }
                            .foregroundStyle(MeetingTheme.foregroundTertiary)
                    }
                }
                .padding(14)
            }
            .frame(height: 300)
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: MeetingChat.Message) -> some View {
        switch message.role {
        case .user:
            HStack { Spacer(minLength: 60)
                Text(message.text).font(.system(size: 13)).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(MeetingTheme.dawn500))
                    .foregroundStyle(MeetingTheme.vast950)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                Text((try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text))
                    .font(.system(size: 13)).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(MeetingTheme.backgroundTertiary))
                if !message.sources.isEmpty {
                    HStack(spacing: 6) {
                        Text("Quellen:").font(.caption).foregroundStyle(MeetingTheme.foregroundTertiary)
                        ForEach(message.sources, id: \.self) { folder in
                            if let entry = library.entries.first(where: { MeetingLibrary.key($0.folder) == MeetingLibrary.key(folder) }) {
                                Button(MeetingMarkdown.title(for: entry.document)) { library.select(folder) }
                                    .buttonStyle(.link).font(.caption).lineLimit(1)
                            }
                        }
                    }
                }
            }
        case .error:
            Label(message.text, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(MeetingTheme.coral)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(library.selected != nil && !allMeetings ? "Frag etwas zu diesem Meeting …" : "Frag etwas zu deinen Meetings …",
                      text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($focused)
                .onSubmit(send)
            if !expanded && !chat.messages.isEmpty {
                Button { expanded = true } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(SandButtonStyle()).help("Verlauf aufklappen")
            }
            Button(action: send) { Image(systemName: "arrow.up") }
                .buttonStyle(LavenderButtonStyle(compact: true))
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || chat.busy)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func send() {
        let question = input
        input = ""
        expanded = true
        let scope = self.scope
        let entries = library.entries
        Task { await chat.ask(question, scope: scope, entries: entries) }
    }
}
