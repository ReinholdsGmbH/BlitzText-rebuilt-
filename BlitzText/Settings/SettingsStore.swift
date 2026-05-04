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
    /// Pro-Modus Rewrite-Backend (Apple Foundation lokal vs. OpenAI Cloud).
    /// Default `.appleFoundation` — bei `.unavailable` mit vorhandenem API-Key
    /// schaltet `applyAutoFallbackIfNeeded()` einmalig auf `.openAI` (siehe AC-AVAIL-1).
    @Published var rewriteBackendForPlus: RewriteBackend = .appleFoundation
    @Published var rewriteBackendForRant: RewriteBackend = .appleFoundation
    /// Runtime-Only Availability-State. **NICHT** in Snapshot persistiert —
    /// AC-AVAIL-1 fordert frische Verfügbarkeitsprüfung bei jedem Bootstrap;
    /// persistierter veralteter State würde dem widersprechen (T-08-02-03).
    @Published var foundationAvailability: FoundationAvailability = .unavailable(.modelNotReady)
    /// Self-Idempotency-Marker: `applyAutoFallbackIfNeeded()` setzt diesen Flag
    /// auf `true` und verweigert danach jeden Re-Trigger (WARNING 7 / T-08-02-07).
    /// Runtime-Only.
    @Published var didAutoFallbackToOpenAI: Bool = false
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
    /// In-Memory-Test-Hook: überschreibt den Keychain-Getter, damit
    /// AppleFoundationAvailabilityTests keine echten Keychain-Einträge auf
    /// Dev-/CI-Maschinen schreiben (BLOCKER 2 / T-08-02-06).
    /// Ausschließlich `#if DEBUG` — wird vom Release-Compiler entfernt
    /// (T-08-02-05). Tests setzen `store._testApiKeyOverride = "sk-test-123"`.
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

    /// DI-Slot für Apple-Foundation-Availability. Default ist Live-Impl
    /// (`SystemLanguageModelAvailabilityProvider`); Tests injizieren
    /// `FakeFoundationAvailabilityProvider`. Pattern analog
    /// `DiarizerModelManager.init(loader:)`.
    private let availabilityProvider: FoundationAvailabilityProviding

    init(availabilityProvider: FoundationAvailabilityProviding = SystemLanguageModelAvailabilityProvider()) {
        self.availabilityProvider = availabilityProvider
        load()
        migrateAPIKeyFromUserDefaultsIfNeeded()
        // Auto-Persist bei jeder Änderung
        objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }

    // MARK: - Rewrite-Backend per Mode

    /// Liefert das aktuell konfigurierte Rewrite-Backend für den gegebenen Modus.
    /// `.blitztext` (plain) hat keinen Rewrite-Schritt — wir liefern `.appleFoundation`
    /// als unbenutzten Stub-Default zurück.
    func rewriteBackend(for mode: Mode) -> RewriteBackend {
        switch mode {
        case .blitztextPlus: return rewriteBackendForPlus
        case .blitztextRant: return rewriteBackendForRant
        case .blitztext:     return .appleFoundation
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

    // MARK: - Foundation-Availability + Auto-Fallback

    /// Live-Refresh des Apple-Foundation-Availability-States. Bei State-Wechsel
    /// werden UI-Observers (@Published) getriggert UND `applyAutoFallbackIfNeeded()`
    /// aufgerufen — Letzteres ist self-idempotent (WARNING 7).
    /// Aufrufer: AppDelegate.bootstrap() + NSApplication.didBecomeActiveNotification.
    func refreshFoundationAvailability() {
        let new = availabilityProvider.currentAvailability()
        if new != foundationAvailability {
            foundationAvailability = new
            applyAutoFallbackIfNeeded()
        }
    }

    /// Schaltet beide Rewrite-Backend-Slots (Plus + Rant) einmalig auf `.openAI`,
    /// wenn (a) Foundation `.unavailable` ist, (b) ein API-Key vorhanden ist und
    /// (c) mindestens ein Modus aktuell auf `.appleFoundation` steht.
    ///
    /// Self-Idempotency: der `didAutoFallbackToOpenAI`-Guard als allererste
    /// Anweisung schützt gegen Multi-Fire (T-08-02-07 / WARNING 7) — auch wenn
    /// `didBecomeActiveNotification` mehrfach feuert oder der State zwischen
    /// zwei `unavailable`-Reasons wandert.
    private func applyAutoFallbackIfNeeded() {
        guard !didAutoFallbackToOpenAI else { return }
        guard foundationAvailability != .available, !apiKey.isEmpty else { return }
        let switched = rewriteBackendForPlus == .appleFoundation || rewriteBackendForRant == .appleFoundation
        if switched {
            rewriteBackendForPlus = .openAI
            rewriteBackendForRant = .openAI
            didAutoFallbackToOpenAI = true
        }
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
        // Phase 8: additive Optionals — alte Snapshots laden ohne Crash.
        var rewriteBackendForPlus: RewriteBackend?
        var rewriteBackendForRant: RewriteBackend?
        // foundationAvailability + didAutoFallbackToOpenAI bewusst NICHT hier
        // (Runtime-Only — siehe Property-Doc-Comments + T-08-02-03).
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
        rewriteBackendForPlus = snap.rewriteBackendForPlus ?? .appleFoundation
        rewriteBackendForRant = snap.rewriteBackendForRant ?? .appleFoundation
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
            parakeetDiarization: parakeetDiarization,
            rewriteBackendForPlus: rewriteBackendForPlus,
            rewriteBackendForRant: rewriteBackendForRant
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

/// Pro-Modus Rewrite-Backend. Default `.appleFoundation` (lokal, on-device);
/// `.openAI` ist Cloud-Fallback (gpt-4o-mini).
enum RewriteBackend: String, CaseIterable, Codable, Identifiable {
    case appleFoundation
    case openAI
    var id: String { rawValue }
    var label: String {
        switch self {
        case .appleFoundation: return "Apple Foundation (lokal)"
        case .openAI:          return "OpenAI gpt-4o-mini (Cloud)"
        }
    }
}
