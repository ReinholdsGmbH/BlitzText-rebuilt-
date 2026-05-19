import Foundation
import Combine

/// In Keychain liegt nur der API-Key. Alles andere als JSON in UserDefaults.
final class SettingsStore: ObservableObject {

    // MARK: - Persisted Preferences (JSON in UserDefaults)

    @Published var hotkeyForBlitztext: HotkeyBinding = .defaultBlitztext
    @Published var hotkeyForBlitztextPlus: HotkeyBinding = .defaultBlitztextPlus
    @Published var hotkeyForBlitztextRant: HotkeyBinding = .defaultBlitztextRant

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
    @Published var rewriteBackendForPlus: RewriteBackend = .openAI
    @Published var rewriteBackendForRant: RewriteBackend = .openAI
    @Published var ollamaModel: String = "phi4-mini"
    @Published var ollamaBaseURL: String = "http://localhost:11434"
    /// Schwellenwert für Sprecher-Matching (0.5 = aggressiv zusammenführen, 0.9 = strikt trennen).
    /// Wird an SpeakerManager.speakerThreshold übergeben — kleiner Wert = mehr Treffer, größer = mehr neue Profile.
    @Published var speakerMatchThreshold: Double = 0.7
    /// Bei Parakeet-Backend: Sprecher-Diarization aktivieren.
    /// Side-Effect (D-01): `false → true` triggert sofortigen Manager-Download.
    /// Snapshot-Save läuft separat über das debounced `objectWillChange`-Sink.
    @Published var parakeetDiarization: Bool = false {
        didSet {
            guard parakeetDiarization, !oldValue else { return }
            // D-01: Toggle-On löst Manager-Start aus. Manager ist idempotent —
            // No-Op wenn bereits installed oder ein Download läuft.
            // `load()` läuft im init() vor AppDelegate-DI, daher diarizerManager == nil
            // und der Side-Effect feuert beim Initial-Load nicht.
            // MainActor-Hop weil DiarizerModelManager.start() @MainActor-isoliert ist.
            Task { @MainActor [weak diarizerManager] in
                diarizerManager?.start()
            }
        }
    }

    /// Wird in AppDelegate.bootstrap() gesetzt, sobald der DiarizerModelManager existiert.
    /// `weak` verhindert Retain-Cycle; AppDelegate ist alleiniger Owner.
    weak var diarizerManager: DiarizerModelManager?

    // MARK: - API-Key

    #if DEBUG
    internal var _testApiKeyOverride: String?
    #endif

    /// Liegt in der macOS-Keychain (Service `de.reinholds.blitztext`,
    /// Account `openai-api-key`). Synchroner Zugriff bleibt erhalten —
    /// Keychain.read/write sind blockierend und Sendable-safe.
    var apiKey: String {
        get {
            #if DEBUG
            if let override = _testApiKeyOverride { return override }
            #endif
            return Keychain.shared.read(account: Self.apiKeyKeychainAccount) ?? ""
        }
        set {
            #if DEBUG
            if _testApiKeyOverride != nil {
                _testApiKeyOverride = newValue
                objectWillChange.send()
                return
            }
            #endif
            if newValue.isEmpty {
                Keychain.shared.delete(account: Self.apiKeyKeychainAccount)
            } else {
                Keychain.shared.write(value: newValue, account: Self.apiKeyKeychainAccount)
            }
            objectWillChange.send()
        }
    }
    private static let apiKeyLegacyDefaultsKey = "de.reinholds.blitztext.apiKey"
    private static let apiKeyKeychainAccount = "openai-api-key"

    // MARK: - Lifecycle

    private static let defaultsKey = "de.reinholds.blitztext.settings"
    private var cancellables = Set<AnyCancellable>()

    init() {
        load()
        migrateAPIKeyFromUserDefaultsIfNeeded()
        objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }

    // MARK: - Rewrite-Backend per Mode

    func rewriteBackend(for mode: Mode) -> RewriteBackend {
        switch mode {
        case .blitztextPlus: return rewriteBackendForPlus
        case .blitztextRant: return rewriteBackendForRant
        case .blitztext:     return .openAI
        }
    }

    /// Setzt das Rewrite-Backend für den gegebenen Modus. `.blitztext` ist No-Op.
    func setRewriteBackend(_ backend: RewriteBackend, for mode: Mode) {
        switch mode {
        case .blitztextPlus: rewriteBackendForPlus = backend
        case .blitztextRant: rewriteBackendForRant = backend
        case .blitztext:     break
        }
    }

    // MARK: - Hotkey-Bindungen

    func hotkeyBinding(for mode: Mode) -> HotkeyBinding {
        switch mode {
        case .blitztext:     return hotkeyForBlitztext
        case .blitztextPlus: return hotkeyForBlitztextPlus
        case .blitztextRant: return hotkeyForBlitztextRant
        }
    }

    func setHotkeyBinding(_ binding: HotkeyBinding, for mode: Mode) {
        switch mode {
        case .blitztext:     hotkeyForBlitztext = binding
        case .blitztextPlus: hotkeyForBlitztextPlus = binding
        case .blitztextRant: hotkeyForBlitztextRant = binding
        }
        save()
    }

    /// Einmalige Migration: alter UserDefaults-Eintrag → Keychain.
    /// Idempotent (kein Eintrag = No-Op). Bei Keychain-Fehler bleibt der
    /// Legacy-Eintrag erhalten, damit der User den Key nicht verliert.
    private func migrateAPIKeyFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: Self.apiKeyLegacyDefaultsKey),
              !legacy.isEmpty else { return }

        if Keychain.shared.read(account: Self.apiKeyKeychainAccount) == nil {
            if Keychain.shared.write(value: legacy, account: Self.apiKeyKeychainAccount) {
                Log.write("SettingsStore: API-Key von UserDefaults nach Keychain migriert")
            } else {
                Log.write("SettingsStore: API-Key Migration fehlgeschlagen — UserDefaults-Eintrag bleibt erhalten")
                return
            }
        }
        defaults.removeObject(forKey: Self.apiKeyLegacyDefaultsKey)
    }

    private struct Snapshot: Codable {
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
        var rewriteBackendForPlus: RewriteBackend?
        var rewriteBackendForRant: RewriteBackend?
        // Hotkey-Konfiguration: additive Optionals — alte Snapshots laden ohne Crash.
        var hotkeyForBlitztext: HotkeyBinding?
        var hotkeyForBlitztextPlus: HotkeyBinding?
        var hotkeyForBlitztextRant: HotkeyBinding?
        // Ollama-Konfiguration: additive Optionals — alte Snapshots laden ohne Crash.
        var ollamaModel: String?
        var ollamaBaseURL: String?
        // Sprecher-Matching-Threshold: additives Optional — alte Snapshots laden ohne Crash.
        var speakerMatchThreshold: Double?
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        styleForPlus = snap.styleForPlus
        // Migration: alter Default-Prompt → leer, damit backend-spezifischer Prompt greift
        customPromptPlus = snap.customPromptPlus.isEmpty ? Mode.blitztextPlus.defaultRewritePrompt : snap.customPromptPlus
        customPromptRant = snap.customPromptRant.isEmpty ? Mode.blitztextRant.defaultRewritePrompt : snap.customPromptRant
        context = snap.context
        properNouns = snap.properNouns
        autoInsert = snap.autoInsert
        transcriptionLanguage = snap.transcriptionLanguage
        rewriteModel = snap.rewriteModel
        transcriptionModel = snap.transcriptionModel
        backend = snap.backend
        aiSuggestProperNouns = snap.aiSuggestProperNouns ?? true
        parakeetDiarization = snap.parakeetDiarization ?? false
        rewriteBackendForPlus = snap.rewriteBackendForPlus ?? .openAI
        rewriteBackendForRant = snap.rewriteBackendForRant ?? .openAI
        hotkeyForBlitztext = snap.hotkeyForBlitztext ?? .defaultBlitztext
        hotkeyForBlitztextPlus = snap.hotkeyForBlitztextPlus ?? .defaultBlitztextPlus
        hotkeyForBlitztextRant = snap.hotkeyForBlitztextRant ?? .defaultBlitztextRant
        ollamaModel = snap.ollamaModel ?? "phi4-mini"
        ollamaBaseURL = snap.ollamaBaseURL ?? "http://localhost:11434"
        speakerMatchThreshold = snap.speakerMatchThreshold ?? 0.7
    }

    func save() {
        let snap = Snapshot(
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
            parakeetDiarization: parakeetDiarization,
            rewriteBackendForPlus: rewriteBackendForPlus,
            rewriteBackendForRant: rewriteBackendForRant,
            hotkeyForBlitztext: hotkeyForBlitztext,
            hotkeyForBlitztextPlus: hotkeyForBlitztextPlus,
            hotkeyForBlitztextRant: hotkeyForBlitztextRant,
            ollamaModel: ollamaModel,
            ollamaBaseURL: ollamaBaseURL,
            speakerMatchThreshold: speakerMatchThreshold
        )
        do {
            let data = try JSONEncoder().encode(snap)
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        } catch {
            Log.write("SettingsStore: save() fehlgeschlagen — \(error)")
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

/// Pro-Modus Rewrite-Backend.
enum RewriteBackend: String, CaseIterable, Codable, Identifiable {
    case openAI
    case ollama
    var id: String { rawValue }
    var label: String {
        switch self {
        case .openAI:  return "OpenAI gpt-4o-mini (Cloud)"
        case .ollama:  return "Ollama (lokal)"
        }
    }
    // Migration: alte "appleFoundation"-Werte in UserDefaults → .openAI
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RewriteBackend(rawValue: raw) ?? .openAI
    }
}
