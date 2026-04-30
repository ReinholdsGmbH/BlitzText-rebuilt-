import Foundation
import Combine

/// In Keychain liegt nur der API-Key. Alles andere als JSON in UserDefaults.
final class SettingsStore: ObservableObject {

    // MARK: - Persisted Preferences (JSON in UserDefaults)

    @Published var triggerMode: TriggerMode = .hold
    @Published var styleForPlus: WritingStyle = .neutral
    @Published var customPromptPlus: String = Mode.blitztextPlus.defaultRewritePrompt
    @Published var customPromptRant: String = Mode.blitztextRant.defaultRewritePrompt
    @Published var context: String = ""
    @Published var properNouns: [String] = []
    @Published var autoInsert: Bool = false
    @Published var transcriptionLanguage: String = "de"
    @Published var rewriteModel: String = "gpt-4o-mini"
    @Published var transcriptionModel: String = "whisper-1"
    @Published var backend: TranscriptionBackend = .openAI
    @Published var aiSuggestProperNouns: Bool = true
    /// Bei Parakeet-Backend: Sprecher-Diarization aktivieren
    @Published var parakeetDiarization: Bool = false

    // MARK: - API-Key

    /// Liegt in UserDefaults, nicht im Keychain.
    /// Grund: Bei Self-Signed-Dev-Builds ist die Keychain-ACL Code-Hash-gebunden →
    /// jedes Rebuild triggert einen Schlüsselbund-Prompt, „Immer erlauben" hält
    /// nicht. UserDefaults ist genauso File-system-protected (User-Login), kein
    /// meaningful Security-Verlust für Personal-Use.
    var apiKey: String {
        get { UserDefaults.standard.string(forKey: Self.apiKeyDefaultsKey) ?? "" }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: Self.apiKeyDefaultsKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: Self.apiKeyDefaultsKey)
            }
            objectWillChange.send()
        }
    }
    private static let apiKeyDefaultsKey = "de.reinholds.blitztext.apiKey"

    // MARK: - Lifecycle

    private static let defaultsKey = "de.reinholds.blitztext.settings"
    private var cancellables = Set<AnyCancellable>()

    init() {
        load()
        // Auto-Persist bei jeder Änderung
        objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }

    private struct Snapshot: Codable {
        var triggerMode: TriggerMode
        var styleForPlus: WritingStyle
        var customPromptPlus: String
        var customPromptRant: String
        var context: String
        var properNouns: [String]
        var autoInsert: Bool
        var transcriptionLanguage: String
        var rewriteModel: String
        var transcriptionModel: String
        var backend: TranscriptionBackend
        var aiSuggestProperNouns: Bool?
        var parakeetDiarization: Bool?
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        triggerMode = snap.triggerMode
        styleForPlus = snap.styleForPlus
        customPromptPlus = snap.customPromptPlus
        customPromptRant = snap.customPromptRant
        context = snap.context
        properNouns = snap.properNouns
        autoInsert = snap.autoInsert
        transcriptionLanguage = snap.transcriptionLanguage
        rewriteModel = snap.rewriteModel
        transcriptionModel = snap.transcriptionModel
        backend = snap.backend
        aiSuggestProperNouns = snap.aiSuggestProperNouns ?? true
        parakeetDiarization = snap.parakeetDiarization ?? false
    }

    private func save() {
        let snap = Snapshot(
            triggerMode: triggerMode,
            styleForPlus: styleForPlus,
            customPromptPlus: customPromptPlus,
            customPromptRant: customPromptRant,
            context: context,
            properNouns: properNouns,
            autoInsert: autoInsert,
            transcriptionLanguage: transcriptionLanguage,
            rewriteModel: rewriteModel,
            transcriptionModel: transcriptionModel,
            backend: backend,
            aiSuggestProperNouns: aiSuggestProperNouns,
            parakeetDiarization: parakeetDiarization
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

enum TranscriptionBackend: String, CaseIterable, Codable, Identifiable {
    case openAI
    case local            // Lokal Whisper (WhisperKit)
    case parakeet         // Lokal Parakeet TDT v3 (FluidAudio, optional Diarization)
    var id: String { rawValue }
    var label: String {
        switch self {
        case .openAI:   return "OpenAI Whisper (Cloud)"
        case .local:    return "Whisper (Lokal)"
        case .parakeet: return "Parakeet TDT v3 (Lokal)"
        }
    }
}
