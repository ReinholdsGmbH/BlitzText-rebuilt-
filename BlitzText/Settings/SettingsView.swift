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
                HotkeyRecorderRow(mode: .blitztext)
                HotkeyRecorderRow(mode: .blitztextPlus)
                HotkeyRecorderRow(mode: .blitztextRant)
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
                Text("Nach dem Erteilen der Bedienungshilfen-Berechtigung sind die Hotkeys sofort aktiv — kein App-Neustart nötig.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Status aktualisieren") { permissionRefresh += 1 }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("OPENAI-API-KEY").font(.caption).foregroundStyle(.secondary).bold()
                Text("Wird gebraucht für: Cloud-Whisper-Backend, Blitztext+ / $%&! (Rewrite via gpt-4o-mini), KI-Eigennamen-Vorschläge. Bei rein lokalem Setup (Parakeet/Whisper-Local + Roh-Modus + KI-Vorschläge aus) ist er optional.")
                    .font(.caption).foregroundStyle(.secondary)
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
                    DiarizerStatusBlock()
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

// MARK: - Diarizer Status Block (Phase 3 Wave 1)

/// Vier-State-Block für den Diarizer-Modell-Lifecycle.
/// Spec: 03-UI-SPEC.md § State-by-State Visual Spec.
/// Strings sind LOCKED durch UI-SPEC § Copywriting Contract — NICHT paraphrasieren.
private struct DiarizerStatusBlock: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var diarizerManager: DiarizerModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch diarizerManager.state {
        case .notInstalled:
            toggleAndSubtitle
        case .downloading(let progress, let eta):
            downloadingView(progress: progress, eta: eta)
            // Subtitle bleibt sichtbar (UI-SPEC: "darf während Download sichtbar bleiben")
            Text("Aktiviert Sprecher-Annotationen (\"Sprecher 1: …\"). Lädt zusätzlich ein Diarizer-Modell (~80 MB).")
                .font(.caption2).foregroundStyle(.tertiary)
        case .installed:
            Toggle("Sprechererkennung (Diarization)", isOn: $settings.parakeetDiarization)
            if settings.parakeetDiarization {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Modell vorhanden").font(.caption).foregroundStyle(.green)
                }
            }
            Text("Aktiviert Sprecher-Annotationen (\"Sprecher 1: …\"). Lädt zusätzlich ein Diarizer-Modell (~80 MB).")
                .font(.caption2).foregroundStyle(.tertiary)
        case .failed(let message):
            errorView(message: message)
        }
    }

    @ViewBuilder
    private var toggleAndSubtitle: some View {
        Toggle("Sprechererkennung (Diarization)", isOn: $settings.parakeetDiarization)
        Text("Aktiviert Sprecher-Annotationen (\"Sprecher 1: …\"). Lädt zusätzlich ein Diarizer-Modell (~80 MB).")
            .font(.caption2).foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func downloadingView(progress: Double, eta: Double?) -> some View {
        // D-03: Toggle ist NICHT gerendert (auch nicht disabled) — komplett ersetzt.
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Lädt Diarizer-Modell …").font(.subheadline)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 280)
                Text(progressDetailText(progress: progress, eta: eta))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func errorView(message: String) -> some View {
        // D-12: Toggle visuell weg, logisch bleibt parakeetDiarization == true.
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Diarizer-Modell konnte nicht geladen werden").font(.subheadline)
                Text(message).font(.caption).foregroundStyle(.red)
                Button("Erneut versuchen") { diarizerManager.retry() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - ETA formatting (UI-SPEC § ETA-Algorithmus)

    private func progressDetailText(progress: Double, eta: Double?) -> String {
        let percent = Int((progress * 100).rounded())
        let etaText = formatETA(eta)
        return "\(percent) % · \(etaText)"
    }

    /// Mapping per UI-SPEC § ETA-Algorithmus:
    ///   nil               → "Geschwindigkeit wird ermittelt …"
    ///   0..<60            → "noch ~N s"
    ///   60..<3600         → "noch ~N min"
    ///   >= 3600           → "noch ~N h"
    private func formatETA(_ eta: Double?) -> String {
        guard let eta else { return "Geschwindigkeit wird ermittelt …" }
        if eta < 60 {
            return "noch ~\(Int(eta.rounded())) s"
        } else if eta < 3600 {
            return "noch ~\(Int((eta / 60).rounded())) min"
        } else {
            return "noch ~\(Int((eta / 3600).rounded())) h"
        }
    }
}

// MARK: - Hotkey-Recorder

/// Verwaltet den NSEvent-Monitor während des Aufnahme-Modus.
/// Läuft auf dem Main-Thread (NSEvent.addLocalMonitorForEvents liefert auf Main).
@MainActor
final class KeyRecorderViewModel: ObservableObject {
    @Published var liveModifiers: Set<HotkeyModifier> = []
    @Published var peakModifiers: Set<HotkeyModifier> = []
    private var monitor: Any?

    var liveDisplay: String {
        let mods = liveModifiers.isEmpty ? peakModifiers : liveModifiers
        if mods.isEmpty { return "Drücke Tastenkombination …" }
        return HotkeyModifier.allCases.filter { mods.contains($0) }.map { $0.symbol }.joined()
    }

    func start(onCommit: @escaping (HotkeyBinding?) -> Void) {
        liveModifiers = []
        peakModifiers = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                self.handleFlagsChanged(event, onCommit: onCommit)
            } else if event.type == .keyDown {
                self.handleKeyDown(event, onCommit: onCommit)
            }
            return nil
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        liveModifiers = []
        peakModifiers = []
    }

    private func handleFlagsChanged(_ event: NSEvent, onCommit: @escaping (HotkeyBinding?) -> Void) {
        var mods: Set<HotkeyModifier> = []
        let flags = event.modifierFlags
        if flags.contains(.function) { mods.insert(.fn) }
        if flags.contains(.shift)    { mods.insert(.shift) }
        if flags.contains(.control)  { mods.insert(.control) }
        if flags.contains(.option)   { mods.insert(.option) }
        if flags.contains(.command)  { mods.insert(.command) }
        liveModifiers = mods
        if mods.count > peakModifiers.count { peakModifiers = mods }
        if mods.isEmpty && !peakModifiers.isEmpty {
            let binding = HotkeyBinding(modifiers: peakModifiers)
            stop()
            onCommit(binding)
        }
    }

    private func handleKeyDown(_ event: NSEvent, onCommit: @escaping (HotkeyBinding?) -> Void) {
        if event.keyCode == 53 { // Escape → Abbrechen
            stop()
            onCommit(nil)
        } else {
            let label = keyLabel(for: event)
            let binding = HotkeyBinding(modifiers: liveModifiers, keyCode: event.keyCode, keyLabel: label)
            stop()
            onCommit(binding)
        }
    }

    private func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case 0x7A: return "F1";  case 0x78: return "F2";  case 0x63: return "F3"
        case 0x76: return "F4";  case 0x60: return "F5";  case 0x61: return "F6"
        case 0x62: return "F7";  case 0x64: return "F8";  case 0x65: return "F9"
        case 0x6D: return "F10"; case 0x67: return "F11"; case 0x6F: return "F12"
        case 0x31: return "Space"
        case 0x24: return "↩"
        case 0x7B: return "←"; case 0x7C: return "→"; case 0x7D: return "↓"; case 0x7E: return "↑"
        default:   return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }
}

/// Interaktive Zeile für eine Hotkey-Bindung in den Settings.
/// Zeigt die aktuelle Bindung und erlaubt dem User, eine neue aufzuzeichnen.
struct HotkeyRecorderRow: View {
    let mode: Mode
    @EnvironmentObject var settings: SettingsStore
    @State private var isRecording = false
    @StateObject private var recorder = KeyRecorderViewModel()

    var body: some View {
        HStack(spacing: 8) {
            Text(mode.title)
                .frame(minWidth: 110, alignment: .leading)
            Spacer()
            if isRecording {
                recordingField
            } else {
                displayField
            }
        }
        .onDisappear {
            recorder.stop()
            isRecording = false
        }
    }

    @ViewBuilder
    private var displayField: some View {
        Text(settings.hotkeyBinding(for: mode).displayString)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

        Button("Ändern") { startRecording() }

        Button {
            settings.setHotkeyBinding(.defaultBinding(for: mode), for: mode)
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Standard wiederherstellen")
    }

    @ViewBuilder
    private var recordingField: some View {
        Text(recorder.liveDisplay)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(minWidth: 160, alignment: .leading)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1))

        Button {
            recorder.stop()
            isRecording = false
        } label: {
            Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Abbrechen")
    }

    private func startRecording() {
        isRecording = true
        recorder.start { binding in
            if let b = binding, !b.isEmpty {
                settings.setHotkeyBinding(b, for: mode)
            }
            isRecording = false
        }
    }
}
