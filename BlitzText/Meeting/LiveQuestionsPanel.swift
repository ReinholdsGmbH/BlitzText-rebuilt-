import AppKit
import SwiftUI

/// Aufklappbarer Chat unten im laufenden Meeting: Fragen zum bisherigen Live-Transkript, etwa
/// „Was hat sie zum Termin gesagt?“ oder „Welche Rückfragen sollte ich stellen?“.
/// Jede Frage schickt den aktuellen Stand mit; Antworten lassen sich in die Notizen übernehmen.
/// Der Verlauf wird gespeichert und hängt sich nach dem Stopp an das fertige Meeting.
struct LiveQuestionsPanel: View {
    @ObservedObject var chat: MeetingChat
    @ObservedObject var controller: MeetingController
    let startedAt: Date
    @State private var input = ""
    @State private var expanded = false

    private var messages: [MeetingChat.Message] { chat.liveThread(for: startedAt)?.messages ?? [] }

    static let suggestions = [
        "Welche Rückfragen sollte ich jetzt stellen?",
        "Was wurde in den letzten Minuten besprochen?",
        "Was ist noch offen oder unklar?"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.up")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                    Text("Fragen zum Meeting")
                    if !messages.isEmpty {
                        Text("\(messages.filter { $0.role == .user }.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(MeetingTheme.accentSoft))
                            .foregroundStyle(MeetingTheme.accent)
                    }
                    Spacer()
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(MeetingTheme.foregroundTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded { conversation }
            inputBar
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(MeetingTheme.backgroundTertiary))
    }

    private var conversation: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty { emptyState }
                        ForEach(messages) { message in row(message).id(message.id) }
                        if chat.liveBusy {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Liest das Live-Transkript …")
                            }
                            .font(.system(size: 12.5)).foregroundStyle(MeetingTheme.foregroundTertiary)
                            .id("busy")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                .onChange(of: chat.liveBusy) { _, busy in
                    if busy { withAnimation { proxy.scrollTo("busy", anchor: .bottom) } }
                }
            }
            .frame(height: 240)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(MeetingTheme.dawn700)
                TextField("Frag etwas zum bisherigen Gespräch …", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .onSubmit { send(input) }
                Button { send(input) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(LavenderButtonStyle(compact: true))
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || chat.liveBusy)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 22).fill(MeetingTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(MeetingTheme.border))
            if expanded {
                Text("Antwortet mit dem Modell der Zusammenfassung; jede Frage schickt den bisherigen Live-Stand mit. Der Verlauf hängt sich nach dem Stopp an das Meeting.")
                    .font(.caption).foregroundStyle(MeetingTheme.foregroundTertiary)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frag nach, ohne das Gespräch zu unterbrechen.")
                .font(.system(size: 13)).foregroundStyle(MeetingTheme.foregroundTertiary)
            ForEach(Self.suggestions, id: \.self) { suggestion in
                Button { send(suggestion) } label: {
                    Label(suggestion, systemImage: "text.bubble")
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(MeetingTheme.accentSoft))
                        .foregroundStyle(MeetingTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(chat.liveBusy)
            }
        }
    }

    @ViewBuilder
    private func row(_ message: MeetingChat.Message) -> some View {
        switch message.role {
        case .user:
            HStack { Spacer(minLength: 60)
                Text(message.text).font(.system(size: 13.5)).textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 16).fill(MeetingTheme.backgroundSecondary))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                SummaryText(markdown: message.text)
                HStack(spacing: 14) {
                    Button { appendToNotes(message.text) } label: {
                        Label("In Notizen übernehmen", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.link)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).foregroundStyle(MeetingTheme.foregroundTertiary).help("Antwort kopieren")
                }
                .font(.system(size: 12.5))
            }
        case .error:
            Label(message.text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5)).foregroundStyle(MeetingTheme.coral)
        }
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !chat.liveBusy else { return }
        input = ""
        withAnimation(.easeOut(duration: 0.2)) { expanded = true }
        let lines = controller.live.lines
        let notes = controller.liveNotes
        Task { await chat.askLive(question, startedAt: startedAt, lines: lines, notes: notes) }
    }

    private func appendToNotes(_ text: String) {
        let current = controller.liveNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        controller.liveNotes = current.isEmpty ? text : current + "\n\n" + text
    }
}
