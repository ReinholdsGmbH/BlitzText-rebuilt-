import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var modelManager: LocalModelManager
    @State private var selectedTab: Tab = .anpassen

    enum Tab: String, CaseIterable, Identifiable {
        case anpassen, zugang, lokal
        var id: String { rawValue }
        var label: String {
            switch self {
            case .anpassen: return "Anpassen"
            case .zugang:   return "Zugang"
            case .lokal:    return "Lokales Modell"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            ScrollView {
                Group {
                    switch selectedTab {
                    case .anpassen: AnpassenTab()
                    case .zugang:   ZugangTab()
                    case .lokal:    LokalTab()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, idealWidth: 560, minHeight: 640, idealHeight: 640)
    }
}

// MARK: - Anpassen

private struct AnpassenTab: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var newProperNoun: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("TASTENKÜRZEL") {
                hotkeyRow("fn + Shift",   "Blitztext")
                hotkeyRow("fn + Control", "Blitztext+")
                hotkeyRow("fn + Option",  "Blitztext $%&!")
            }

            section("MODUS") {
                Picker("", selection: $settings.triggerMode) {
                    ForEach(TriggerMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
            }

            section("BLITZTEXT $%&!") {
                Text("Eigene Anweisung").font(.subheadline)
                TextEditor(text: $settings.customPromptRant)
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
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
                Text("Begriffe, die korrekt geschrieben werden müssen.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Toggle("KI-Vorschläge nach jeder Aufnahme (gpt-4o-mini)", isOn: $settings.aiSuggestProperNouns)
                Text("Heuristik (großgeschriebene Wörter, Diff Roh ↔ Poliert) ist immer aktiv. KI-Vorschläge sind zusätzlich.")
                    .font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(settings.properNouns, id: \.self) { noun in
                        TagView(text: noun) {
                            settings.properNouns.removeAll { $0 == noun }
                        }
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
        guard !trimmed.isEmpty, !settings.properNouns.contains(trimmed) else { return }
        settings.properNouns.append(trimmed)
        newProperNoun = ""
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).bold()
            content()
        }
    }

    private func hotkeyRow(_ keys: String, _ name: String) -> some View {
        HStack {
            Text(keys).font(.system(.body, design: .monospaced))
            Spacer()
            Text(name).bold()
        }
    }
}

// MARK: - Zugang

private struct ZugangTab: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var draftKey: String = ""
    @State private var showKey: Bool = false
    @State private var saved: Bool = false
    @State private var permissionRefresh: Int = 0

    private var accessibilityGranted: Bool {
        _ = permissionRefresh
        return PermissionsHelper.accessibilityStatus() == .granted
    }
    private var microphoneStatus: PermissionsHelper.Status {
        _ = permissionRefresh
        return PermissionsHelper.microphoneStatus()
    }
    private var micSubtitle: String {
        switch microphoneStatus {
        case .granted: return "freigegeben"
        case .denied: return "abgelehnt — in Systemeinstellungen aktivieren"
        case .undetermined: return "noch nicht angefragt"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            VStack(alignment: .leading, spacing: 8) {
                Text("BERECHTIGUNGEN").font(.caption).foregroundStyle(.secondary).bold()
                permissionRow(
                    title: "Bedienungshilfen",
                    subtitle: "nötig für globale Hotkeys (fn + …) und direktes Einfügen",
                    granted: accessibilityGranted,
                    actionLabel: accessibilityGranted ? "Öffnen" : "Aktivieren"
                ) {
                    PermissionsHelper.requestAccessibilityPrompt()
                    PermissionsHelper.openAccessibilitySettings()
                }
                permissionRow(
                    title: "Mikrofon",
                    subtitle: micSubtitle,
                    granted: microphoneStatus == .granted,
                    actionLabel: microphoneStatus == .undetermined ? "Anfragen" : "Öffnen"
                ) {
                    if microphoneStatus == .undetermined {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in
                            DispatchQueue.main.async { permissionRefresh += 1 }
                        }
                    } else {
                        PermissionsHelper.openMicrophoneSettings()
                    }
                }
                Text("Nach dem Erteilen der Bedienungshilfen-Berechtigung BlitzText einmal beenden und neu starten — sonst greift sie nicht für den Hotkey-Tap.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Status aktualisieren") { permissionRefresh += 1 }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("API-KEY").font(.caption).foregroundStyle(.secondary).bold()
                HStack {
                    if showKey {
                        TextField("sk-…", text: $draftKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-…", text: $draftKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showKey ? "Verbergen" : "Anzeigen") { showKey.toggle() }
                }
                HStack {
                    Button("Speichern") {
                        settings.apiKey = draftKey
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftKey.isEmpty)
                    if saved { Text("Gespeichert ✓").foregroundStyle(.green) }
                    Spacer()
                    if !settings.apiKey.isEmpty {
                        Button("Löschen", role: .destructive) {
                            settings.apiKey = ""
                            draftKey = ""
                        }
                    }
                }
                Text("Der Schlüssel liegt in deinem macOS-Schlüsselbund (Service `de.reinholds.blitztext`, Account `openai-api-key`). Beim ersten Speichern und Lesen fragt der Schlüsselbund einmal nach Bestätigung — auf „Immer erlauben\" klicken.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("OPENAI-MODELLE").font(.caption).foregroundStyle(.secondary).bold()
                Text("Backend-Auswahl im Tab 'Lokales Modell'. Sprache kann direkt im Popover umgeschaltet werden.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Whisper-Modell (Cloud)", text: $settings.transcriptionModel)
                TextField("Rewrite-Modell (Cloud)", text: $settings.rewriteModel)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("AUSGABE").font(.caption).foregroundStyle(.secondary).bold()
                Toggle("Direkt einfügen (statt nur Zwischenablage)", isOn: $settings.autoInsert)
            }

            Spacer(minLength: 0)
        }
        .onAppear { draftKey = settings.apiKey }
    }

    @ViewBuilder
    private func permissionRow(title: String, subtitle: String, granted: Bool, actionLabel: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionLabel, action: action)
        }
    }
}

// MARK: - Tag-View

private struct TagView: View {
    let text: String
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.caption2)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

// MARK: - Lokal Tab

private struct LokalTab: View {
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
                if settings.backend == .local && modelManager.activeID == nil {
                    Text("Lokales Backend gewählt, aber kein Modell aktiviert. Wähle unten ein Modell zum Aktivieren oder lade eines herunter.")
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
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("MODELLE").font(.caption).foregroundStyle(.secondary).bold()
                    Spacer()
                    Picker("", selection: $langFilter) {
                        ForEach(LangFilter.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }

                Text("Lokale Whisper-Modelle laufen on-device via WhisperKit (CoreML, Apple-Silicon-optimiert). Keine Cloud, keine API-Kosten. Für Deutsch nur die multilingualen Modelle wählen — `.en`-Varianten verstehen ausschließlich Englisch.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(filteredModels) { model in
                    LocalModelRow(model: model)
                }

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("PARAKEET TDT v3 (NVIDIA, via FluidAudio)").font(.caption).foregroundStyle(.secondary).bold()
                    Text("Alternatives lokales STT-Backend. NVIDIA Parakeet TDT v3 läuft via CoreML auf Apple Silicon. Modell wird beim ersten Start automatisch heruntergeladen (~600 MB).")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Wähle oben Backend: 'Parakeet TDT v3 (Lokal)' aus, um Parakeet aktiv zu nutzen.")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Toggle("Sprechererkennung (Diarization)", isOn: $settings.parakeetDiarization)
                    Text("Aktiviert Sprecher-Annotationen (\"Sprecher 1: …\"). Lädt zusätzlich ein Diarizer-Modell (~80 MB). Beim ersten Aktivieren dauert es etwas länger.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                Text("Speicherort: \(LocalModelManager.modelsRoot.path)")
                    .font(.caption2).foregroundStyle(.tertiary)

                if let err = modelManager.lastError {
                    Text(err).foregroundStyle(.red).font(.caption)
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

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, totalHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = y + rowHeight
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
