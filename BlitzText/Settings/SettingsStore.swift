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
    @Published var properNouns: [ProperNoun] = []
    /// Alle kanonischen Texte der Eigennamen (für Prompt-Builder und Duplikatprüfung).
    var properNounTexts: [String] { properNouns.map(\.text) }
    @Published var autoInsert: Bool = false
    /// Standard-Modus (`.blitztext`): ausgeschriebene Zahlen in Ziffern umwandeln (`fünf` → `5`).
    @Published var convertNumbersToDigits: Bool = true
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

    /// In-Memory-Cache des API-Keys — die EINZIGE Quelle für Lesezugriffe.
    ///
    /// KRITISCH: Lesen darf NIE synchron die Keychain treffen. `SecItemCopyMatching` blockiert
    /// per `mach_msg` auf `securityd` und kann nach Sleep/Wake/Unlock oder bei einem
    /// Keychain-Zugriffs-Prompt (geänderte Code-Signatur) minutenlang hängen. Auf dem
    /// Main-Thread friert das die GANZE App ein (kein Crash, RunLoop steht). Stack-Analyse
    /// 2026-06-25: bootstrap → needsOpenAIKey → apiKey → SecItemCopyMatching → mach_msg.
    /// Eigene `@unchecked Sendable`-Box (NSLock-geschützt): so reicht der Hintergrund-Lade-Task
    /// NUR diese Box über die Isolationsgrenze — nicht den nicht-`Sendable` SettingsStore (`self`).
    private let apiKeyCache = APIKeyCache()

    /// API-Key (OpenAI). Lesen = nur In-Memory-Cache (nicht-blockierend). Schreiben = Cache
    /// sofort aktualisieren + synchroner Keychain-Write (nutzerinitiiert im Settings-Fenster,
    /// darf dort einmalig prompten). Initiales Laden läuft asynchron im Hintergrund (s. `init`).
    var apiKey: String {
        get {
            #if DEBUG
            if let override = _testApiKeyOverride { return override }
            #endif
            return apiKeyCache.current
        }
        set {
            #if DEBUG
            if _testApiKeyOverride != nil {
                _testApiKeyOverride = newValue
                objectWillChange.send()
                return
            }
            #endif
            apiKeyCache.set(newValue)
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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        loadAPIKeyFromKeychainAsync()
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

    /// Lädt den API-Key EINMALIG aus der Keychain in den In-Memory-Cache — bewusst im
    /// Hintergrund (`Task.detached`), weil Keychain-Zugriff (`SecItemCopyMatching` / `securityd`)
    /// prompten oder nach Sleep/Wake blockieren kann; auf dem Main-Thread würde das die App
    /// einfrieren (siehe `apiKey`-Doku). Enthält zugleich die einmalige Legacy-Migration
    /// (UserDefaults → Keychain). Idempotent. Bei Keychain-Schreibfehler bleibt der
    /// Legacy-Eintrag erhalten, damit der User den Key nicht verliert.
    private func loadAPIKeyFromKeychainAsync() {
        // Nur Sendable-Werte einfangen (kein `self`, kein UserDefaults!), damit der Task nichts
        // Nicht-Sendables über die Isolationsgrenze reicht: account/legacy sind Strings, `cache`
        // ist @unchecked Sendable.
        let account = Self.apiKeyKeychainAccount
        let legacy = defaults.string(forKey: Self.apiKeyLegacyDefaultsKey)   // nicht-blockierend
        let cache = apiKeyCache
        Task.detached {
            var value = Keychain.shared.read(account: account)
            if value == nil, let legacy, !legacy.isEmpty {
                // Einmalige Legacy-Migration (UserDefaults → Keychain). Der verwaiste
                // UserDefaults-Eintrag bleibt liegen — harmlos, weil nach erfolgreicher
                // Migration jeder Folge-Load die Keychain zuerst trifft (value != nil) und
                // diesen Zweig nie wieder betritt.
                if Keychain.shared.write(value: legacy, account: account) {
                    value = legacy
                    Log.write("SettingsStore: API-Key von UserDefaults nach Keychain migriert")
                } else {
                    Log.write("SettingsStore: API-Key Migration fehlgeschlagen — UserDefaults-Eintrag bleibt erhalten")
                }
            }
            cache.set(value ?? "")
        }
    }

    private struct Snapshot: Codable {
        var styleForPlus: WritingStyle
        var customPromptPlus: String
        var customPromptRant: String
        var context: String
        var properNouns: [String]?          // Legacy (vor V2) — nur noch zum Migrieren gelesen
        var properNounsV2: [ProperNoun]?    // Aktuelles Modell
        var autoInsert: Bool
        var convertNumbersToDigits: Bool?   // additives Optional — alte Snapshots laden ohne Crash
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
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return }
        let snap: Snapshot
        do {
            snap = try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            Log.write("SettingsStore: load() fehlgeschlagen — \(error) — Defaults werden verwendet")
            return
        }
        styleForPlus = snap.styleForPlus
        // Migration: alter Default-Prompt → leer, damit backend-spezifischer Prompt greift
        customPromptPlus = snap.customPromptPlus.isEmpty ? Mode.blitztextPlus.defaultRewritePrompt : snap.customPromptPlus
        customPromptRant = snap.customPromptRant.isEmpty ? Mode.blitztextRant.defaultRewritePrompt : snap.customPromptRant
        context = snap.context
        if let v2 = snap.properNounsV2 {
            properNouns = v2
        } else {
            properNouns = (snap.properNouns ?? []).map { ProperNoun(text: $0) }
        }
        autoInsert = snap.autoInsert
        convertNumbersToDigits = snap.convertNumbersToDigits ?? true
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

    /// Erhöht den Vorkommens-Zähler eines Eintrags und stempelt „zuletzt gesehen".
    func bumpOccurrence(termID: UUID) {
        guard let idx = properNouns.firstIndex(where: { $0.id == termID }) else { return }
        properNouns[idx].occurrenceCount += 1
        properNouns[idx].lastSeenAt = Date()
    }

    /// Fügt einem Eintrag einen neu entdeckten Alias hinzu (case-insensitiv dedupliziert).
    func addAlias(_ alias: String, toTermID id: UUID) {
        guard let idx = properNouns.firstIndex(where: { $0.id == id }) else { return }
        let lower = alias.lowercased()
        let known = properNouns[idx].allForms.map { $0.lowercased() }
        guard !known.contains(lower) else { return }
        properNouns[idx].aliases.append(alias)
    }

    func save() {
        let snap = Snapshot(
            styleForPlus: styleForPlus,
            customPromptPlus: customPromptPlus,
            customPromptRant: customPromptRant,
            context: context,
            properNouns: nil,
            properNounsV2: properNouns,
            autoInsert: autoInsert,
            convertNumbersToDigits: convertNumbersToDigits,
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
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            Log.write("SettingsStore: save() fehlgeschlagen — \(error)")
        }
    }
}

/// Thread-sicherer In-Memory-Halter für den API-Key. Eigene Klasse, damit sie als
/// `@unchecked Sendable` über Isolationsgrenzen gereicht werden kann, ohne den ganzen
/// (nicht-Sendable) SettingsStore mitzuziehen.
private final class APIKeyCache: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    var current: String { lock.withLock { value } }
    func set(_ newValue: String) { lock.withLock { value = newValue } }
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
    // Unbekannte Werte aus älteren Builds → .openAI statt Decode-Fehler
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TranscriptionBackend(rawValue: raw) ?? .openAI
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
