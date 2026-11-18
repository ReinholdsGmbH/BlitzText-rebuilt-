import SwiftUI

// Bausteine der Bereiche Diktat, Stil, Wörterbuch und Modelle. Früher steckte all das im Tab
// „Anpassen“, das Ollama-Modell sogar doppelt; die Backend-Wahl lag getrennt vom Schlüssel.

// MARK: - Ausgabe (Diktat)

struct OutputSection: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Sprache") {
                Picker("", selection: $settings.transcriptionLanguage) {
                    Text("Automatisch").tag("")
                    Text("Deutsch").tag("de")
                    Text("Englisch").tag("en")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
            }
            Toggle("Direkt einfügen statt nur in die Zwischenablage", isOn: $settings.autoInsert)
            Toggle("Zahlen als Ziffern schreiben", isOn: $settings.convertNumbersToDigits)
            Text("Wandelt im Modus Blitztext ausgesprochene Zahlen in Ziffern um (fünf → 5, dritte → 3., acht Uhr dreißig → 8:30). Blitztext+ und $%&! formulieren ohnehin selbst.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Stil

struct StyleSection: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Blitztext+").font(.system(size: 14, weight: .semibold))
                Picker("Schreibstil", selection: $settings.styleForPlus) {
                    ForEach(WritingStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                promptEditor(text: $settings.customPromptPlus, defaultPrompt: Mode.blitztextPlus.defaultRewritePrompt)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Blitztext $%&!").font(.system(size: 14, weight: .semibold))
                Text("Macht aus Frust eine sachliche Nachricht.").font(.caption).foregroundStyle(.secondary)
                promptEditor(text: $settings.customPromptRant, defaultPrompt: Mode.blitztextRant.defaultRewritePrompt)
            }
        }
    }

    private func promptEditor(text: Binding<String>, defaultPrompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Anweisung").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if text.wrappedValue != defaultPrompt {
                    Button("Auf Standard zurücksetzen") { text.wrappedValue = defaultPrompt }
                        .buttonStyle(.link).font(.caption)
                }
            }
            TextEditor(text: text)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(MeetingTheme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MeetingTheme.border))
        }
    }
}

// MARK: - Umformulieren (Modelle)

struct RewriteBackendSection: View {
    @EnvironmentObject var settings: SettingsStore

    private var usesOllama: Bool { settings.rewriteBackendForPlus == .ollama || settings.rewriteBackendForRant == .ollama }
    private var usesOpenAI: Bool { settings.rewriteBackendForPlus == .openAI || settings.rewriteBackendForRant == .openAI }
    private var cloudProviders: [SummaryProvider] {
        var seen = Set<SummaryProvider>()
        return [settings.rewriteBackendForPlus, settings.rewriteBackendForRant]
            .compactMap(\.provider)
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Blitztext+") {
                Picker("", selection: $settings.rewriteBackendForPlus) {
                    ForEach(RewriteBackend.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 260)
            }
            LabeledContent("Blitztext $%&!") {
                Picker("", selection: $settings.rewriteBackendForRant) {
                    ForEach(RewriteBackend.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 260)
            }
            if usesOllama {
                LabeledContent("Ollama-Modell") {
                    TextField("gemma4:e4b", text: $settings.ollamaModel)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                }
                LabeledContent("Ollama-Adresse") {
                    TextField("http://localhost:11434", text: $settings.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                }
                Text("Ollama muss laufen (ollama serve) und das Modell geladen sein (ollama pull …). Dasselbe Modell nutzt auch die lokale Meeting-Zusammenfassung.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(cloudProviders, id: \.self) { provider in
                Text("\(provider.label): Modell \(settings.meetingSummaryModel(for: provider)), einstellbar unter „Zugang \(provider.label)“.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if usesOpenAI {
                Text("OpenAI: Modell \(settings.rewriteModel), einstellbar unter „Transkription“, wenn dort OpenAI gewählt ist.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Wörterbuch

struct DictionarySection: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var newProperNoun = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Eingabe oben: Neue Begriffe sollen schnell gehen, auch bei langer Liste.
            HStack {
                TextField("Neuer Begriff", text: $newProperNoun)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNoun)
                Button("Hinzufügen", action: addNoun)
                    .buttonStyle(LavenderButtonStyle(compact: true))
                    .disabled(newProperNoun.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.bottom, 4)
            ForEach(settings.properNouns.sorted { $0.occurrenceCount > $1.occurrenceCount }) { noun in
                ProperNounRow(noun: noun) { settings.properNouns.removeAll { $0.id == noun.id } }
                Divider()
            }
            Toggle("KI-Vorschläge nach jeder Aufnahme (gpt-4o-mini)", isOn: $settings.aiSuggestProperNouns)
            Text("Unbekannte, großgeschriebene Wörter werden auf dem Gerät erkannt und nach dem zweiten Vorkommen vorgeschlagen. Die KI-Vorschläge laufen über die OpenAI-Cloud.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addNoun() {
        let trimmed = newProperNoun.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.properNounTexts.contains(trimmed) else { return }
        settings.properNouns.append(ProperNoun(text: trimmed))
        newProperNoun = ""
    }
}

struct ContextSection: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $settings.context)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 70)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(MeetingTheme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MeetingTheme.border))
            Text("Wird jeder Transkription und jedem Umformulieren mitgegeben, etwa Rolle, Projekt, Fachbegriffe.")
                .font(.caption).foregroundStyle(.secondary)
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
