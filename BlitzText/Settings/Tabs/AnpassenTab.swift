import SwiftUI

// MARK: - Anpassen

struct AnpassenTab: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var newProperNoun: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TASTENKÜRZEL").font(.caption).foregroundStyle(.secondary).bold()
                Text("Hotkeys werden im Tab \"Hotkeys\" konfiguriert.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            section("BLITZTEXT+") {
                Text("Schreibstil").font(.subheadline)
                Picker("", selection: $settings.styleForPlus) {
                    ForEach(WritingStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("Eigene Anweisung").font(.subheadline).padding(.top, 6)
                TextEditor(text: $settings.customPromptPlus)
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Text("Backend").font(.subheadline).padding(.top, 6)
                Picker("Backend", selection: $settings.rewriteBackendForPlus) {
                    ForEach(RewriteBackend.allCases) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 280)
                if settings.rewriteBackendForPlus == .openAI {
                    // WARNING 6 (Privacy-Marker-Konsistenz): Hint wird IMMER gezeigt, wenn .openAI
                    // gewählt ist — unabhängig vom availability-State. Privacy-Marker bleibt
                    // gerade dann sichtbar, wenn Foundation unavailable ist und der User
                    // unfreiwillig auf Cloud landet (Auto-Fallback).
                    Text("Rewrite für diesen Mode läuft über die OpenAI-Cloud.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if settings.rewriteBackendForPlus == .ollama {
                    TextField("Modell", text: $settings.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                    Text("Ollama muss installiert und gestartet sein (ollama serve). Modell vorher laden: ollama pull phi4-mini")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            section("BLITZTEXT $%&!") {
                Text("Eigene Anweisung").font(.subheadline)
                TextEditor(text: $settings.customPromptRant)
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Text("Backend").font(.subheadline).padding(.top, 6)
                Picker("Backend", selection: $settings.rewriteBackendForRant) {
                    ForEach(RewriteBackend.allCases) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 280)
                if settings.rewriteBackendForRant == .openAI {
                    // WARNING 6: siehe Plus-Block — Hint immer bei .openAI, ohne availability-Suppression.
                    Text("Rewrite für diesen Mode läuft über die OpenAI-Cloud.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if settings.rewriteBackendForRant == .ollama {
                    TextField("Modell", text: $settings.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                    Text("Ollama muss installiert und gestartet sein (ollama serve). Modell vorher laden: ollama pull phi4-mini")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            section("KONTEXT") {
                Text("Wer spricht? (wird in jeden Prompt mitgegeben)")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $settings.context)
                    .font(.body)
                    .frame(minHeight: 60)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }

            section("EIGENNAMEN") {
                Text("Begriffe, die korrekt geschrieben werden müssen. Die Liste korrigiert jede Transkription automatisch.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Toggle("KI-Vorschläge nach jeder Aufnahme (gpt-4o-mini)", isOn: $settings.aiSuggestProperNouns)
                Text("Erkennung läuft on-device (großgeschriebene, dem Wörterbuch unbekannte Wörter). Neue Begriffe werden erst nach dem 2. Vorkommen übernommen.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(settings.properNouns.sorted { $0.occurrenceCount > $1.occurrenceCount }) { noun in
                    ProperNounRow(noun: noun) {
                        settings.properNouns.removeAll { $0.id == noun.id }
                    }
                }

                HStack {
                    TextField("Neuer Begriff", text: $newProperNoun)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addNoun)
                    Button(action: addNoun) {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(newProperNoun.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addNoun() {
        let trimmed = newProperNoun.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.properNounTexts.contains(trimmed) else { return }
        settings.properNouns.append(ProperNoun(text: trimmed))
        newProperNoun = ""
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).bold()
            content()
        }
    }

}

// MARK: - Eigennamen-Zeile (Übersicht)

private struct ProperNounRow: View {
    let noun: ProperNoun
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(noun.text).font(.body)
                if !noun.aliases.isEmpty {
                    Text("Varianten: " + noun.aliases.joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text("\(noun.occurrenceCount)×")
                .font(.caption).foregroundStyle(.secondary)
                .help(noun.lastSeenAt.map { "Zuletzt: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Noch nicht vorgekommen")
            Button(action: onRemove) {
                Image(systemName: "trash").font(.caption)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
