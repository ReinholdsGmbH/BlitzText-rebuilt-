import SwiftUI

/// Eingabeleiste unten im Meetings-Bereich, wie Wispr Flows „Ask anything about your
/// meetings“. Eine Frage öffnet die Chat-Seite mit Verlauf.
struct ChatDock: View {
    @ObservedObject var chat: MeetingChat
    @ObservedObject var library: MeetingLibrary
    let openChat: () -> Void
    @State private var input = ""
    @State private var allMeetings = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(MeetingTheme.dawn700)
            TextField(library.selected != nil && !allMeetings ? "Frag etwas zu diesem Meeting …" : "Frag etwas zu deinen Meetings …",
                      text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .onSubmit(send)
            if library.selected != nil {
                Picker("", selection: $allMeetings) {
                    Text("Alle").tag(true)
                    Text("Dieses").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Alle Meetings durchsuchen oder nur das gewählte")
            }
            Button("Bisherige Chats") { openChat() }
                .buttonStyle(SandButtonStyle())
            Button(action: send) { Image(systemName: "arrow.up") }
                .buttonStyle(LavenderButtonStyle(compact: true))
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || chat.busy)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 25).fill(MeetingTheme.card)
            .shadow(color: .black.opacity(0.14), radius: 14, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(MeetingTheme.border))
        .frame(maxWidth: 720)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        input = ""
        let scope: MeetingChat.Scope = (!allMeetings && library.selected != nil) ? .meeting(library.selected!.folder) : .all
        // Neue Frage aus den Meetings heraus beginnt einen neuen Chat.
        chat.newChat()
        openChat()
        let entries = library.entries
        Task { await chat.ask(question, scope: scope, entries: entries) }
    }
}

/// Chat-Seite wie bei Wispr Flow: links „Neuer Chat“ und bisherige Chats nach Tagen,
/// rechts das Gespräch, unten die Eingabe.
struct ChatPage: View {
    @ObservedObject var chat: MeetingChat
    @ObservedObject var library: MeetingLibrary
    let back: () -> Void
    let openMeeting: (URL) -> Void
    @State private var input = ""

    private var groups: [(day: Date, threads: [MeetingChat.Thread])] {
        let grouped = Dictionary(grouping: chat.threads) { Calendar.current.startOfDay(for: $0.updatedAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.updatedAt > $1.updatedAt }) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 260)
            Rectangle().fill(MeetingTheme.border).frame(width: 1)
            conversation.frame(maxWidth: .infinity)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: back) { Image(systemName: "chevron.left") }
                    .buttonStyle(SandButtonStyle()).help("Zurück zu den Meetings")
                Spacer()
                Button { chat.newChat() } label: { Label("Neuer Chat", systemImage: "plus") }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(groups, id: \.day) { group in
                        Text(dayLabel(group.day))
                            .font(.system(size: 11, weight: .semibold)).tracking(0.6)
                            .foregroundStyle(MeetingTheme.foregroundTertiary)
                            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
                        ForEach(group.threads) { thread in
                            Button { chat.select(thread.id) } label: {
                                Text(thread.title).font(.system(size: 13)).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10)
                                        .fill(thread.id == chat.currentID ? MeetingTheme.backgroundTertiary : .clear))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { chat.delete(thread.id) } label: { Label("Chat löschen", systemImage: "trash") }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            if let folder = chat.current?.meetingFolder,
               let entry = library.entries.first(where: { MeetingLibrary.key($0.folder) == MeetingLibrary.key(folder) }) {
                HStack {
                    Label("Zu: \(MeetingMarkdown.title(for: entry.document))", systemImage: "doc.text")
                        .font(.caption).foregroundStyle(MeetingTheme.foregroundTertiary).lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 32).padding(.top, 14)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if chat.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Frag etwas zu deinen Meetings").font(.system(size: 20, weight: .semibold))
                                Text("Etwa „Projekt Nord, wie sieht es aus?“ oder „Welche Aufgaben habe ich diese Woche bekommen?“. BlitzText sucht die passenden Transkripte und nennt die Quellen.")
                                    .font(.system(size: 13)).foregroundStyle(MeetingTheme.foregroundTertiary)
                            }
                            .padding(.top, 40)
                        }
                        ForEach(chat.messages) { message in
                            row(message).id(message.id)
                        }
                        if chat.busy {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Sucht in deinen Meetings …").font(.caption) }
                                .foregroundStyle(MeetingTheme.foregroundTertiary)
                        }
                    }
                    .padding(.horizontal, 32).padding(.vertical, 24)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            HStack(spacing: 8) {
                TextField("Frag etwas zu deinen Meetings …", text: $input)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "arrow.up") }
                    .buttonStyle(LavenderButtonStyle(compact: true))
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || chat.busy)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 26).fill(MeetingTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(MeetingTheme.foreground.opacity(0.6), lineWidth: 1.2))
            .frame(maxWidth: 820)
            .padding(.horizontal, 32).padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private func row(_ message: MeetingChat.Message) -> some View {
        switch message.role {
        case .user:
            HStack { Spacer(minLength: 80)
                Text(message.text).font(.system(size: 14)).textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18).fill(MeetingTheme.backgroundSecondary))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                SummaryText(markdown: message.text)
                if !message.sources.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(message.sources, id: \.self) { folder in
                            if let entry = library.entries.first(where: { MeetingLibrary.key($0.folder) == MeetingLibrary.key(folder) }) {
                                Button { openMeeting(folder) } label: {
                                    Label(MeetingMarkdown.title(for: entry.document), systemImage: "doc.text")
                                        .lineLimit(1)
                                }
                                .buttonStyle(.link).font(.system(size: 12.5))
                            }
                        }
                    }
                }
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain).foregroundStyle(MeetingTheme.foregroundTertiary).help("Antwort kopieren")
            }
        case .error:
            Label(message.text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5)).foregroundStyle(MeetingTheme.coral)
        }
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        input = ""
        let scope = chat.current?.scope ?? .all
        let entries = library.entries
        Task { await chat.ask(question, scope: scope, entries: entries) }
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "HEUTE" }
        if Calendar.current.isDateInYesterday(day) { return "GESTERN" }
        return day.formatted(.dateTime.day().month(.wide)).uppercased()
    }
}
