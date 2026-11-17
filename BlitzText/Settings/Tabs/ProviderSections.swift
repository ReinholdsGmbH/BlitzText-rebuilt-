import SwiftUI

// MARK: - Zugang je Cloud-Anbieter

/// Schlüssel, Modell und Verbindungstest für einen Anbieter. Einmal eingerichtet, nutzen ihn
/// Umformulieren (Blitztext+, $%&!) und Meeting-Zusammenfassung gemeinsam.
struct ProviderAccountSection: View {
    @EnvironmentObject var settings: SettingsStore

    @State private var draftKey = ""
    @State private var keySaved = false
    @State private var models: [ModelOption] = []
    @State private var loadingModels = false
    @State private var loadError: String?
    @State private var filter = ""
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    let provider: SummaryProvider

    private var modelBinding: Binding<String> {
        Binding(
            get: { settings.meetingSummaryModel(for: provider) },
            set: { settings.setMeetingSummaryModel($0, for: provider) }
        )
    }

    private var filteredModels: [ModelOption] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let hits = needle.isEmpty ? models : models.filter {
            $0.id.lowercased().contains(needle) || $0.name.lowercased().contains(needle)
        }
        return Array(hits.prefix(60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            keySection
            modelSection
            testSection
        }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API-SCHLÜSSEL").font(.caption).foregroundStyle(.secondary).bold()
            HStack {
                SecureField(settings.providerKeys.key(for: provider).isEmpty ? "Schlüssel einfügen" : "gespeichert, zum Ersetzen neu einfügen",
                            text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                Button("Speichern") {
                    settings.providerKeys.setKey(draftKey, for: provider)
                    draftKey = ""
                    keySaved = true
                }
                .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if !settings.providerKeys.key(for: provider).isEmpty {
                    Button("Entfernen", role: .destructive) {
                        settings.providerKeys.setKey("", for: provider)
                        keySaved = false
                    }
                }
            }
            Text(keySaved ? "Im Schlüsselbund gespeichert." : "Liegt im macOS-Schlüsselbund, nicht in den Einstellungsdateien.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODELL").font(.caption).foregroundStyle(.secondary).bold()
            HStack {
                TextField("Modell-ID", text: modelBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                if !provider.isLocal {
                    Button("Standard") { modelBinding.wrappedValue = provider.defaultModel }
                        .help(provider.defaultModel)
                }
                Button {
                    Task { await loadModels() }
                } label: {
                    if loadingModels { ProgressView().controlSize(.small) } else { Text("Liste laden") }
                }
                .disabled(loadingModels)
            }
            if provider.isLocal {
                Text("Dasselbe Ollama-Modell wie beim Diktat-Rewrite.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let loadError {
                Text(loadError).font(.caption).foregroundStyle(.red)
            }
            if !models.isEmpty {
                TextField("Suchen, z. B. haiku, gemini, eu-central", text: $filter)
                    .textFieldStyle(.roundedBorder)
                List(filteredModels) { model in
                    Button {
                        modelBinding.wrappedValue = model.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.id).font(.system(.callout, design: .monospaced))
                                if model.name != model.id {
                                    Text(model.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if model.id == modelBinding.wrappedValue {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 240)
                Text("\(models.count) Modelle, angezeigt \(filteredModels.count).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VERBINDUNG").font(.caption).foregroundStyle(.secondary).bold()
            HStack(spacing: 10) {
                Button {
                    Task { await runTest() }
                } label: {
                    if testing { ProgressView().controlSize(.small) } else { Text("Verbindung testen") }
                }
                .disabled(testing)
                if let testResult {
                    Label(testResult.text, systemImage: testResult.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(testResult.ok ? .green : .red)
                        .lineLimit(3)
                }
            }
            Text("Schickt eine Mini-Anfrage ohne Meeting-Inhalte an das gewählte Modell.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func runTest() async {
        testing = true
        testResult = nil
        defer { testing = false }
        let model = settings.meetingSummaryModel(for: provider)
        let chat = OpenAICompatibleChat(provider: provider, apiKey: settings.providerKeys.key(for: provider), model: model)
        let started = Date()
        do {
            let reply = try await chat.complete(system: "Antworte ausschließlich mit dem Wort OK.", user: "Verbindungstest")
            let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
            testResult = (true, "\(model) antwortet (\(seconds) s): \(reply.prefix(40))")
        } catch {
            testResult = (false, error.localizedDescription)
        }
    }


    private func loadModels() async {
        loadingModels = true
        loadError = nil
        defer { loadingModels = false }
        do {
            models = try await ModelCatalog.fetch(provider, ollamaBaseURL: settings.ollamaBaseURL)
            if models.isEmpty { loadError = "Keine Modelle gefunden." }
        } catch {
            loadError = provider.isLocal
                ? "Ollama nicht erreichbar: \(error.localizedDescription)"
                : "Liste nicht geladen: \(error.localizedDescription)"
        }
    }
}

// MARK: - Meeting-Zusammenfassung

/// Wer die Meeting-Zusammenfassung schreibt. Die Transkription bleibt immer lokal (Parakeet).
struct MeetingSummarySection: View {
    @EnvironmentObject var settings: SettingsStore
    private var provider: SummaryProvider { settings.meetingSummaryProvider }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Anbieter", selection: $settings.meetingSummaryProvider) {
                ForEach(SummaryProvider.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            privacyNote
            Text(provider.isLocal
                 ? "Nutzt das Ollama-Modell aus „Umformulieren“."
                 : "Modell: \(settings.meetingSummaryModel(for: provider)). Schlüssel und Modell unter „Zugänge“.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var privacyNote: some View {
        if provider.isLocal {
            Label("Transkript und Zusammenfassung bleiben auf diesem Mac.", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Label("Das komplette Meeting-Transkript geht an \(provider.label), einschließlich allem, was die anderen Teilnehmenden gesagt haben. Die Transkription selbst bleibt lokal.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}
