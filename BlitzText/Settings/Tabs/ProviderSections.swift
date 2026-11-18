import SwiftUI

// MARK: - Zugang je Cloud-Anbieter

/// Schlüssel, Modell und Verbindungstest für einen Anbieter. Einmal eingerichtet, nutzen ihn
/// Umformulieren (Blitztext+, $%&!) und Meeting-Zusammenfassung gemeinsam.
struct ProviderAccountSection: View {
    @EnvironmentObject var settings: SettingsStore
    let provider: SummaryProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AccountKeyField(
                hasKey: !settings.providerKeys.key(for: provider).isEmpty,
                save: { settings.providerKeys.setKey($0, for: provider) },
                remove: { settings.providerKeys.setKey("", for: provider) }
            )
            AccountModelPicker(
                model: Binding(
                    get: { settings.meetingSummaryModel(for: provider) },
                    set: { settings.setMeetingSummaryModel($0, for: provider) }
                ),
                defaultModel: provider.isLocal ? nil : provider.defaultModel,
                note: provider.isLocal ? "Dasselbe Ollama-Modell wie beim Diktat-Rewrite." : nil,
                load: { try await ModelCatalog.fetch(provider, ollamaBaseURL: settings.ollamaBaseURL) },
                loadErrorPrefix: provider.isLocal ? "Ollama nicht erreichbar" : "Liste nicht geladen"
            )
            AccountConnectionTest(model: settings.meetingSummaryModel(for: provider)) {
                let chat = OpenAICompatibleChat(provider: provider, apiKey: settings.providerKeys.key(for: provider),
                                                model: settings.meetingSummaryModel(for: provider))
                return try await chat.complete(system: AccountConnectionTest.systemPrompt, user: "Verbindungstest")
            }
        }
    }
}

/// Zugang OpenAI im selben Aufbau wie OpenRouter und Requesty. Der Schlüssel dient außerdem
/// Cloud-Whisper und den KI-Eigennamen-Vorschlägen; das Modell ist das Umformulier-Modell.
struct OpenAIAccountSection: View {
    @EnvironmentObject var settings: SettingsStore

    static let defaultModel = "gpt-4o-mini"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AccountKeyField(
                hasKey: !settings.apiKey.isEmpty,
                save: { settings.apiKey = $0 },
                remove: { settings.apiKey = "" },
                usage: "Gebraucht für Cloud-Whisper, Umformulieren über OpenAI und KI-Eigennamen-Vorschläge."
            )
            AccountModelPicker(
                model: $settings.rewriteModel,
                defaultModel: Self.defaultModel,
                note: "Gilt für Blitztext+ und $%&!, wenn dort OpenAI gewählt ist.",
                load: { try await OpenAIModelCatalog.fetch(apiKey: settings.apiKey) },
                loadErrorPrefix: "Liste nicht geladen"
            )
            AccountConnectionTest(model: settings.rewriteModel) {
                try await OpenAIChatClient(settings: settings).rewrite(
                    input: "Verbindungstest", systemPrompt: AccountConnectionTest.systemPrompt, model: settings.rewriteModel)
            }
        }
    }
}

/// Modellliste von OpenAI, ohne Audio-, Bild- und Embedding-Modelle.
enum OpenAIModelCatalog {
    static let url = URL(string: "https://api.openai.com/v1/models")!

    static func fetch(apiKey: String) async throws -> [ModelOption] {
        guard !apiKey.isEmpty else { throw TranscriptionError.missingAPIKey }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranscriptionError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> [ModelOption] {
        struct Model: Decodable { let id: String }
        struct List: Decodable { let data: [Model] }
        let excluded = ["whisper", "tts", "dall-e", "embedding", "audio", "realtime", "transcribe", "image", "moderation", "search"]
        return try JSONDecoder().decode(List.self, from: data).data
            .map(\.id)
            .filter { id in (id.hasPrefix("gpt") || id.hasPrefix("o") || id.hasPrefix("chatgpt")) && !excluded.contains { id.contains($0) } }
            .sorted()
            .map { ModelOption(id: $0, name: $0) }
    }
}

// MARK: - Bausteine der Zugangs-Karten

struct AccountKeyField: View {
    let hasKey: Bool
    let save: (String) -> Void
    let remove: () -> Void
    var usage: String?

    @State private var draftKey = ""
    @State private var keySaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API-SCHLÜSSEL").font(.caption).foregroundStyle(.secondary).bold()
            if let usage {
                Text(usage).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                SecureField(hasKey ? "gespeichert, zum Ersetzen neu einfügen" : "Schlüssel einfügen", text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                Button("Speichern") {
                    save(draftKey.trimmingCharacters(in: .whitespacesAndNewlines))
                    draftKey = ""
                    keySaved = true
                }
                .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if hasKey {
                    Button("Entfernen", role: .destructive) {
                        remove()
                        keySaved = false
                    }
                }
            }
            Text(keySaved ? "Im Schlüsselbund gespeichert." : "Liegt im macOS-Schlüsselbund, nicht in den Einstellungsdateien.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AccountModelPicker: View {
    @Binding var model: String
    let defaultModel: String?
    let note: String?
    let load: () async throws -> [ModelOption]
    let loadErrorPrefix: String

    @State private var models: [ModelOption] = []
    @State private var loadingModels = false
    @State private var loadError: String?
    @State private var filter = ""

    private var filteredModels: [ModelOption] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let hits = needle.isEmpty ? models : models.filter {
            $0.id.lowercased().contains(needle) || $0.name.lowercased().contains(needle)
        }
        return Array(hits.prefix(60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODELL").font(.caption).foregroundStyle(.secondary).bold()
            HStack {
                TextField("Modell-ID", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                if let defaultModel {
                    Button("Standard") { model = defaultModel }
                        .help(defaultModel)
                }
                Button {
                    Task { await loadModels() }
                } label: {
                    if loadingModels { ProgressView().controlSize(.small) } else { Text("Liste laden") }
                }
                .disabled(loadingModels)
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if let loadError {
                Text(loadError).font(.caption).foregroundStyle(.red)
            }
            if !models.isEmpty {
                TextField("Suchen, z. B. haiku, gemini, eu-central", text: $filter)
                    .textFieldStyle(.roundedBorder)
                List(filteredModels) { option in
                    Button {
                        model = option.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.id).font(.system(.callout, design: .monospaced))
                                if option.name != option.id {
                                    Text(option.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if option.id == model {
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

    private func loadModels() async {
        loadingModels = true
        loadError = nil
        defer { loadingModels = false }
        do {
            models = try await load()
            if models.isEmpty { loadError = "Keine Modelle gefunden." }
        } catch {
            loadError = "\(loadErrorPrefix): \(error.localizedDescription)"
        }
    }
}

struct AccountConnectionTest: View {
    static let systemPrompt = "Antworte ausschließlich mit dem Wort OK."

    let model: String
    let run: () async throws -> String

    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    var body: some View {
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
            Text("Schickt eine Mini-Anfrage ohne Inhalte an das gewählte Modell.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func runTest() async {
        testing = true
        testResult = nil
        defer { testing = false }
        let started = Date()
        do {
            let reply = try await run()
            let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
            testResult = (true, "\(model) antwortet (\(seconds) s): \(reply.prefix(40))")
        } catch {
            testResult = (false, error.localizedDescription)
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
