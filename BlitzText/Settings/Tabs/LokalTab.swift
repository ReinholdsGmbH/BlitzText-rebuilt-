import SwiftUI

// MARK: - Lokal Tab

struct LokalTab: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var modelManager: LocalModelManager

    enum LangFilter: String, CaseIterable, Identifiable {
        case all, multi, english
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:     return "Alle"
            case .multi:   return "Multilingual"
            case .english: return "Nur Englisch"
            }
        }
    }
    @State private var langFilter: LangFilter = .multi

    private var filteredModels: [LocalModelManager.ModelInfo] {
        switch langFilter {
        case .all:     return LocalModelManager.available
        case .multi:   return LocalModelManager.available.filter { $0.isMultilingual }
        case .english: return LocalModelManager.available.filter { !$0.isMultilingual }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            VStack(alignment: .leading, spacing: 8) {
                Text("BACKEND-WAHL").font(.caption).foregroundStyle(.secondary).bold()
                Picker("Backend", selection: $settings.backend) {
                    ForEach(TranscriptionBackend.allCases) { Text($0.label).tag($0) }
                }
            }

            Divider()

            switch settings.backend {
            case .openAI:
                VStack(alignment: .leading, spacing: 8) {
                    Text("OPENAI-MODELLE").font(.caption).foregroundStyle(.secondary).bold()
                    Text("Modellnamen wie von der OpenAI-API definiert. API-Schlüssel weiter unten auf dieser Seite.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Transkription") {
                        TextField("whisper-1", text: $settings.transcriptionModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Rewrite") {
                        TextField("gpt-4o-mini", text: $settings.rewriteModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            case .local:
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("WHISPER-MODELLE (LOKAL)").font(.caption).foregroundStyle(.secondary).bold()
                        Spacer()
                        Picker("", selection: $langFilter) {
                            ForEach(LangFilter.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280)
                    }
                    Text("Laufen on-device via WhisperKit (CoreML, Apple-Silicon-optimiert). Keine Cloud, keine API-Kosten. Für Deutsch nur die multilingualen Modelle wählen — `.en`-Varianten verstehen ausschließlich Englisch.")
                        .font(.caption).foregroundStyle(.secondary)
                    if modelManager.activeID == nil {
                        Text("Kein Modell aktiviert. Wähle unten ein Modell oder lade eines herunter.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if modelManager.isPreloading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Modell wird geladen … (CoreML-Compile, beim ersten Mal 1–3 min)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let id = modelManager.preloadedID, let dur = modelManager.preloadDurationSeconds {
                        Text("Modell '\(id)' einsatzbereit (\(String(format: "%.1f", dur)) s).")
                            .font(.caption).foregroundStyle(.green)
                    }
                    ForEach(filteredModels) { LocalModelRow(model: $0) }
                    if let err = modelManager.lastError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                    Text("Speicherort: \(LocalModelManager.modelsRoot.path)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            case .parakeet:
                VStack(alignment: .leading, spacing: 8) {
                    Text("PARAKEET TDT v3 (NVIDIA, via FluidAudio)").font(.caption).foregroundStyle(.secondary).bold()
                    Text("NVIDIA Parakeet TDT v3 läuft via CoreML auf Apple Silicon. Modell wird beim ersten Start automatisch heruntergeladen (~600 MB).")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Sprechererkennung und Profil-Verwaltung findest du im Tab \"Sprecher\".")
                        .font(.caption2).foregroundStyle(.tertiary)
                    if let err = modelManager.lastError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
        }
    }
}

private struct LocalModelRow: View {
    let model: LocalModelManager.ModelInfo
    @EnvironmentObject var modelManager: LocalModelManager

    private var isDownloaded: Bool { modelManager.downloadedIDs.contains(model.id) }
    private var isActive: Bool { modelManager.activeID == model.id }
    private var progress: Double? { modelManager.downloadProgress[model.id] }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "cube.box")
                .foregroundStyle(isActive ? .green : .secondary)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName).bold()
                    Text(model.displaySize).font(.caption).foregroundStyle(.secondary)
                    Text(model.languageBadge)
                        .font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(model.isMultilingual ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2),
                                    in: Capsule())
                        .foregroundStyle(model.isMultilingual ? .blue : .secondary)
                    if isActive { Text("AKTIV").font(.caption2).bold().foregroundStyle(.green) }
                }
                if let note = model.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 200)
                    Text("Lädt … \(Int(progress * 100)) %").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let _ = progress {
                Button("Abbrechen") { modelManager.cancelDownload(model.id) }
            } else if isDownloaded {
                if isActive {
                    Button("Deaktivieren") { modelManager.deactivate() }
                } else {
                    Button("Aktivieren") { modelManager.activate(model.id) }
                        .buttonStyle(.borderedProminent)
                }
                Button(role: .destructive) { modelManager.delete(model.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Modell löschen")
            } else {
                Button("Laden") { modelManager.download(model.id) }
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
