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

    /// Liegt in der macOS-Keychain (Service `de.reinholds.blitztext`,
    /// Account `openai-api-key`). Synchroner Zugriff bleibt erhalten —
    /// Keychain.read/write sind blockierend und Sendable-safe.
    var apiKey: String {
        get { Keychain.shared.read(account: Self.apiKeyKeychainAccount) ?? "" }
        set {
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
        // Auto-Persist bei jeder Änderung
        objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
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
