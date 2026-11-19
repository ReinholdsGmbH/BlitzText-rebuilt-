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
    @Published var backend: TranscriptionBackend = .parakeet
    @Published var aiSuggestProperNouns: Bool = true
    /// Wer die KI-Wortvorschläge macht. Ollama ist ausgenommen: zu langsam für jede Aufnahme.
    @Published var properNounSuggestBackend: RewriteBackend = .requesty
    @Published var rewriteBackendForPlus: RewriteBackend = .requesty
    @Published var rewriteBackendForRant: RewriteBackend = .requesty
    @Published var ollamaModel: String = "gemma4:e4b"
    @Published var ollamaBaseURL: String = "http://localhost:11434"
    /// Schwellenwert für Sprecher-Matching (0.5 = aggressiv zusammenführen, 0.9 = strikt trennen).
    /// Wird an SpeakerManager.speakerThreshold übergeben — kleiner Wert = mehr Treffer, größer = mehr neue Profile.
    @Published var speakerMatchThreshold: Double = 0.7
    /// Automatisch bei Start + im 2-Stunden-Takt nach neuen BlitzText-Versionen suchen (Opt-out).
    /// Der Download/Install ist immer nutzerinitiiert (Button) — hier geht es nur um die Prüfung
    /// und die Benachrichtigung.
    @Published var autoUpdateCheckEnabled: Bool = true
    /// Wer die Meeting-Zusammenfassung schreibt. Standard lokal; Cloud nur bewusst gewählt.
    @Published var meetingSummaryProvider: SummaryProvider = .requesty
    @Published var openRouterModel: String = SummaryProvider.openRouter.defaultModel
    @Published var requestyModel: String = SummaryProvider.requesty.defaultModel
    /// Meetings sofort in den Wissensordner (Baalda-Vault) spiegeln, nach mw-route-Regeln.
    @Published var vaultExportEnabled: Bool = true
    @Published var vaultRootPath: String = VaultExporter.defaultRoot.path
    /// Gemeinsame Ablage mit der iPhone-App (iCloud Drive, OneDrive …); leer = aus.
    @Published var phoneInboxPath: String = ""
    /// Wann BlitzText im Dock erscheint. Standard: solange das App-Fenster offen ist.
    @Published var dockIconMode: DockIconMode = .whileWindowOpen
    /// Welches Stimmprofil man selbst ist; erscheint in Meetings als „Ich“.
    @Published var selfSpeakerName: String = "" {
        didSet { SpeakerNaming.selfName = selfSpeakerName.isEmpty ? nil : selfSpeakerName }
    }
    /// Schlüssel für OpenRouter/Requesty — Keychain, nie UserDefaults.
    let providerKeys = ProviderKeyStore(vault: RuntimeEnvironment.isRunningTests ? nil : .shared)
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
            SecretVault.shared.set(newValue, for: Self.apiKeyKeychainAccount)
            objectWillChange.send()
        }
    }
    private static let apiKeyLegacyDefaultsKey = "de.reinholds.blitztext.apiKey"
    private static let apiKeyKeychainAccount = "openai-api-key"

    // MARK: - Lifecycle

    private static let defaultsKey = "de.reinholds.blitztext.settings"
    private var cancellables = Set<AnyCancellable>()

    private let defaults: UserDefaults

    /// Im Test-Host nie die echten Einstellungen: Tests, die `SettingsStore()` ohne eigenen
    /// Speicher anlegen, schrieben sonst in die BlitzText-Einstellungen des Nutzers.
    static var defaultStorage: UserDefaults {
        RuntimeEnvironment.isRunningTests ? (UserDefaults(suiteName: "de.reinholds.blitztext.tests") ?? .standard) : .standard
    }

    init(defaults: UserDefaults = SettingsStore.defaultStorage) {
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
        guard !RuntimeEnvironment.isRunningTests else { return }
        // Nur Sendable-Werte einfangen (kein `self`, kein UserDefaults!), damit der Task nichts
        // Nicht-Sendables über die Isolationsgrenze reicht: account/legacy sind Strings, `cache`
        // ist @unchecked Sendable.
        let account = Self.apiKeyKeychainAccount
        let legacy = defaults.string(forKey: Self.apiKeyLegacyDefaultsKey)   // nicht-blockierend
        let cache = apiKeyCache
        Task.detached {
            var value = SecretVault.shared.value(for: account)
            if value == nil, let legacy, !legacy.isEmpty {
                // Einmalige Legacy-Migration (UserDefaults → Keychain). Der verwaiste
                // UserDefaults-Eintrag bleibt liegen — harmlos, weil nach erfolgreicher
                // Migration jeder Folge-Load die Keychain zuerst trifft (value != nil) und
                // diesen Zweig nie wieder betritt.
                if SecretVault.shared.set(legacy, for: account) {
                    value = legacy
                    Log.write("SettingsStore: API-Key von UserDefaults nach Keychain migriert")
                } else {
                    Log.write("SettingsStore: API-Key Migration fehlgeschlagen — UserDefaults-Eintrag bleibt erhalten")
                }
            }
            cache.finishLoading(value ?? "")
        }
    }

    /// `true`, sobald der OpenAI-Schlüssel aus dem Schlüsselbund geladen ist. Nach einem neuen
    /// Build kann das dauern, bis der Nutzer die Passwortabfrage bestätigt.
    var isAPIKeyLoaded: Bool { apiKeyCache.isLoaded }

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
        var properNounSuggestBackend: RewriteBackend?
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
        // Auto-Update-Prüfung: additives Optional — alte Snapshots laden ohne Crash.
        var autoUpdateCheckEnabled: Bool?
        // Meeting-Zusammenfassung: additive Optionals — alte Snapshots laden ohne Crash.
        var meetingSummaryProvider: SummaryProvider?
        var openRouterModel: String?
        var requestyModel: String?
        var vaultExportEnabled: Bool?
        var vaultRootPath: String?
        var phoneInboxPath: String?
        var dockIconMode: DockIconMode?
        var selfSpeakerName: String?
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
        properNounSuggestBackend = snap.properNounSuggestBackend ?? .requesty
        parakeetDiarization = snap.parakeetDiarization ?? false
        rewriteBackendForPlus = snap.rewriteBackendForPlus ?? .requesty
        rewriteBackendForRant = snap.rewriteBackendForRant ?? .requesty
        hotkeyForBlitztext = snap.hotkeyForBlitztext ?? .defaultBlitztext
        hotkeyForBlitztextPlus = snap.hotkeyForBlitztextPlus ?? .defaultBlitztextPlus
        hotkeyForBlitztextRant = snap.hotkeyForBlitztextRant ?? .defaultBlitztextRant
        ollamaModel = snap.ollamaModel ?? "gemma4:e4b"
        ollamaBaseURL = snap.ollamaBaseURL ?? "http://localhost:11434"
        speakerMatchThreshold = snap.speakerMatchThreshold ?? 0.7
        autoUpdateCheckEnabled = snap.autoUpdateCheckEnabled ?? true
        meetingSummaryProvider = snap.meetingSummaryProvider ?? .requesty
        openRouterModel = snap.openRouterModel ?? SummaryProvider.openRouter.defaultModel
        requestyModel = snap.requestyModel ?? SummaryProvider.requesty.defaultModel
        vaultExportEnabled = snap.vaultExportEnabled ?? true
        vaultRootPath = snap.vaultRootPath ?? VaultExporter.defaultRoot.path
        phoneInboxPath = snap.phoneInboxPath ?? ""
        dockIconMode = snap.dockIconMode ?? .whileWindowOpen
        selfSpeakerName = snap.selfSpeakerName ?? ""
    }

    /// Exporter für den Wissensordner, oder `nil`, wenn ausgeschaltet.
    func makeVaultExporter() -> VaultExporter? {
        guard vaultExportEnabled, !vaultRootPath.isEmpty else { return nil }
        return VaultExporter(root: URL(fileURLWithPath: (vaultRootPath as NSString).expandingTildeInPath, isDirectory: true))
    }

    /// Modell des aktuell gewählten Zusammenfassungs-Anbieters.
    func meetingSummaryModel(for provider: SummaryProvider) -> String {
        switch provider {
        case .ollama:     return ollamaModel
        case .openRouter: return openRouterModel
        case .requesty:   return requestyModel
        }
    }

    func setMeetingSummaryModel(_ model: String, for provider: SummaryProvider) {
        switch provider {
        case .ollama:     ollamaModel = model
        case .openRouter: openRouterModel = model
        case .requesty:   requestyModel = model
        }
    }

    /// Baut den Zusammenfasser für den aktuell gewählten Anbieter. Wird pro Meeting neu
    /// gerufen, damit eine Umstellung in den Einstellungen sofort greift.
    func makeMeetingSummarizer() -> MeetingSummarizing {
        let provider = meetingSummaryProvider
        let model = meetingSummaryModel(for: provider)
        if provider.isLocal {
            return MeetingSummarizer(chat: OllamaNativeChat(baseURL: ollamaBaseURL, model: model))
        }
        return MeetingSummarizer(chat: OpenAICompatibleChat(
            provider: provider,
            apiKey: providerKeys.key(for: provider),
            model: model
        ))
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
            properNounSuggestBackend: properNounSuggestBackend,
            parakeetDiarization: parakeetDiarization,
            rewriteBackendForPlus: rewriteBackendForPlus,
            rewriteBackendForRant: rewriteBackendForRant,
            hotkeyForBlitztext: hotkeyForBlitztext,
            hotkeyForBlitztextPlus: hotkeyForBlitztextPlus,
            hotkeyForBlitztextRant: hotkeyForBlitztextRant,
            ollamaModel: ollamaModel,
            ollamaBaseURL: ollamaBaseURL,
            speakerMatchThreshold: speakerMatchThreshold,
            autoUpdateCheckEnabled: autoUpdateCheckEnabled,
            meetingSummaryProvider: meetingSummaryProvider,
            openRouterModel: openRouterModel,
            requestyModel: requestyModel,
            vaultExportEnabled: vaultExportEnabled,
            vaultRootPath: vaultRootPath,
            phoneInboxPath: phoneInboxPath,
            dockIconMode: dockIconMode,
            selfSpeakerName: selfSpeakerName
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
    private var loaded = false
    var current: String { lock.withLock { value } }
    /// Erst nach dem Laden aus dem Schlüsselbund ist „leer“ auch wirklich „kein Schlüssel“.
    var isLoaded: Bool { lock.withLock { loaded } }
    func set(_ newValue: String) { lock.withLock { value = newValue } }
    func finishLoading(_ newValue: String) { lock.withLock { value = newValue; loaded = true } }
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
    case openRouter
    case requesty
    var id: String { rawValue }
    var label: String {
        switch self {
        case .openAI:     return "OpenAI (Cloud)"
        case .ollama:     return "Ollama (lokal)"
        case .openRouter: return "OpenRouter (Cloud)"
        case .requesty:   return "Requesty (Cloud)"
        }
    }
    /// Cloud-Anbieter im OpenAI-Format; Schlüssel und Modell teilen sie mit der
    /// Meeting-Zusammenfassung.
    var provider: SummaryProvider? {
        switch self {
        case .openRouter: return .openRouter
        case .requesty:   return .requesty
        case .openAI, .ollama: return nil
        }
    }
    // Migration: alte "appleFoundation"-Werte in UserDefaults → .openAI
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RewriteBackend(rawValue: raw) ?? .openAI
    }
}

/// Sichtbarkeit im Dock. BlitzText ist eine Menüleisten-App; mit offenem Fenster soll es sich
/// aber wie eine normale App verhalten (Dock-Symbol, ⌘-Tab, App-Menü).
enum DockIconMode: String, CaseIterable, Codable, Identifiable {
    case whileWindowOpen
    case always
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .whileWindowOpen: return "Wenn das Fenster offen ist"
        case .always:          return "Immer"
        case .never:           return "Nie"
        }
    }

    /// Ob das Dock-Symbol bei diesem Fensterzustand zu sehen sein soll.
    func showsIcon(windowOpen: Bool) -> Bool {
        switch self {
        case .whileWindowOpen: return windowOpen
        case .always:          return true
        case .never:           return false
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DockIconMode(rawValue: raw) ?? .whileWindowOpen
    }
}
