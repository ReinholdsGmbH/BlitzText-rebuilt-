import AppKit
import Combine
import SwiftUI

/// Bereiche des BlitzText-Fensters. Aufbau wie Wispr Flows Hauptfenster: links eine schmale
/// Navigation auf Sand, rechts eine weiße Karte. Die früheren Einstellungs-Tabs sind hier
/// aufgegangen und neu geordnet.
enum AppSection: String, CaseIterable, Identifiable {
    case meetings, history, dictation, style, dictionary, speakers, models, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meetings:   return "Meetings"
        case .history:    return "Verlauf"
        case .dictation:  return "Diktat"
        case .style:      return "Stil"
        case .dictionary: return "Wörterbuch"
        case .speakers:   return "Sprecher"
        case .models:     return "Modelle"
        case .system:     return "System"
        }
    }

    var icon: String {
        switch self {
        case .meetings:   return "record.circle"
        case .history:    return "clock.arrow.circlepath"
        case .dictation:  return "mic"
        case .style:      return "textformat"
        case .dictionary: return "character.book.closed"
        case .speakers:   return "person.2.wave.2"
        case .models:     return "cpu"
        case .system:     return "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .meetings, .history: return ""
        case .dictation:  return "Tastenkürzel und was mit dem Text passiert."
        case .style:      return "Wie Blitztext+ und $%&! deine Diktate umformulieren."
        case .dictionary: return "Begriffe und Kontext, damit Namen und Fachwörter stimmen."
        case .speakers:   return "Stimmprofile für Diktat und Meetings. Alles bleibt auf diesem Mac."
        case .models:     return "Wer transkribiert, umformuliert und zusammenfasst, lokal oder in der Cloud."
        case .system:     return "Darstellung, Ablage im Wissensordner, Berechtigungen, Autostart und Updates."
        }
    }
}

/// Das Hauptfenster von BlitzText: Meetings und alle Einstellungen.
@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var dockObserver: AnyCancellable?
    private let model: AppWindowModel
    private let library: MeetingLibrary
    private let controller: MeetingController
    private let environment: AppEnvironment

    /// Alles, was die Einstellungsseiten als EnvironmentObject brauchen.
    struct AppEnvironment {
        let settings: SettingsStore
        let modelManager: LocalModelManager
        let diarizerManager: DiarizerModelManager
        let speakerViewModel: SpeakerProfileViewModel
        let enrollmentViewModel: EnrollmentViewModel
        let updateService: UpdateService
        let history: HistoryStore
    }

    init(library: MeetingLibrary, controller: MeetingController, environment: AppEnvironment) {
        self.library = library
        self.controller = controller
        self.environment = environment
        self.model = AppWindowModel()
        super.init()
        // Einstellung live übernehmen, ohne Neustart.
        dockObserver = environment.settings.$dockIconMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyDockPolicy() } }
        applyDockPolicy()
    }

    private var isWindowOpen: Bool { window?.isVisible == true }

    /// Dock-Symbol nach Einstellung und Fensterzustand. `.regular` bringt Dock-Symbol, ⌘-Tab
    /// und App-Menü; `.accessory` macht BlitzText wieder zur reinen Menüleisten-App.
    func applyDockPolicy() {
        let wanted: NSApplication.ActivationPolicy =
            environment.settings.dockIconMode.showsIcon(windowOpen: isWindowOpen) ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        if wanted == .regular, isWindowOpen {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Erst nach dem Schließen auswerten, sonst gilt das Fenster noch als sichtbar.
        DispatchQueue.main.async { [weak self] in self?.applyDockPolicy() }
    }

    func show(section: AppSection? = nil, selecting folder: URL? = nil) {
        library.reload()
        if let folder {
            library.select(folder)
            model.section = .meetings
        } else if let section {
            model.section = section
        }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "BlitzText"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor(MeetingTheme.backgroundTertiary)
            window.minSize = NSSize(width: 860, height: 560)
            let env = environment
            window.contentViewController = NSHostingController(
                rootView: AppRootView(model: model, library: library, controller: controller)
                    .environmentObject(env.settings)
                    .environmentObject(env.modelManager)
                    .environmentObject(env.diarizerManager)
                    .environmentObject(env.speakerViewModel)
                    .environmentObject(env.enrollmentViewModel)
                    .environmentObject(env.updateService)
                    .environmentObject(env.history)
            )
            window.setFrameAutosaveName("BlitzTextAppWindow")
            window.center()
            window.delegate = self
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        applyDockPolicy()
    }
}

@MainActor
final class AppWindowModel: ObservableObject {
    @Published var section: AppSection = .meetings
}

struct AppRootView: View {
    @ObservedObject var model: AppWindowModel
    @ObservedObject var library: MeetingLibrary
    @ObservedObject var controller: MeetingController
    @State private var search = ""

    var body: some View {
        HStack(spacing: 0) {
            AppSidebar(model: model, controller: controller)
                .frame(width: 180)
            Group {
                if model.section == .meetings {
                    HStack(spacing: 0) {
                        // Schmal genug für ein Fenster am Bildschirmrand: Liste 260–340 pt,
                        // Detail ab 340 pt, Navigation 180 pt.
                        MeetingListColumn(library: library, controller: controller, search: $search)
                            .frame(minWidth: 260, idealWidth: 340, maxWidth: 340)
                            .clipped()
                        Rectangle().fill(MeetingTheme.border).frame(width: 1)
                        Group {
                            if controller.isRecording {
                                LiveMeetingView(controller: controller)
                            } else if let entry = library.selected {
                                MeetingDetailView(entry: entry, library: library).id(entry.folder)
                            } else {
                                EmptyDetail()
                            }
                        }
                        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                } else if model.section == .history {
                    HistoryView()
                } else {
                    SettingsPage(section: model.section)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(MeetingTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MeetingTheme.border))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.vertical, 10)
            .padding(.trailing, 10)
        }
        .background(MeetingTheme.backgroundTertiary)
        .foregroundStyle(MeetingTheme.foreground)
        .tint(MeetingTheme.dawn700)
        .overlay(alignment: .bottom) { Toast(library: library) }
    }
}

// MARK: - Navigation

private struct AppSidebar: View {
    @ObservedObject var model: AppWindowModel
    @ObservedObject var controller: MeetingController

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Image(systemName: "bolt.fill").font(.system(size: 15, weight: .bold))
                Text("BlitzText").font(.system(size: 19, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.top, 40)
            .padding(.bottom, 22)

            ForEach(AppSection.allCases.filter { $0 != .system }) { section in
                NavItem(icon: section.icon, title: section.title, active: model.section == section) {
                    model.section = section
                }
            }

            Spacer()
            LiveCard(controller: controller)
                .padding(.bottom, 8)
            NavItem(icon: AppSection.system.icon, title: AppSection.system.title, active: model.section == .system) {
                model.section = .system
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }
}

private struct NavItem: View {
    let icon: String
    let title: String
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 18)
                Text(title).font(.system(size: 13.5, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(active ? MeetingTheme.backgroundSecondary : (hovering ? MeetingTheme.backgroundSecondary.opacity(0.5) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Karte unten in der Navigation, wie Wispr Flows „Untitled note · 0:39“ während der Aufnahme.
private struct LiveCard: View {
    @ObservedObject var controller: MeetingController

    var body: some View {
        switch controller.phase {
        case .recording(let startedAt):
            card(title: "Laufendes Meeting") {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    HStack(spacing: 6) {
                        GreenWave()
                        Text(MeetingMarkdown.clock(context.date.timeIntervalSince(startedAt), alwaysHours: false))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(MeetingTheme.success)
                        Spacer()
                        Button("Stopp") { controller.stop() }.buttonStyle(SandButtonStyle())
                    }
                }
            }
        case .importing, .diarizing, .transcribing, .summarizing:
            card(title: "Wird verarbeitet") {
                Text(statusText).font(.system(size: 12)).foregroundStyle(MeetingTheme.foregroundTertiary)
            }
        default:
            EmptyView()
        }
    }

    private var statusText: String {
        switch controller.phase {
        case .importing: return "Importiere Aufnahme …"
        case .diarizing: return "Erkenne Sprecher …"
        case .transcribing(let done, let total): return total == 0 ? "Transkribiere …" : "Transkribiere \(done) von \(total)"
        case .summarizing: return "Schreibe Notizen …"
        default: return ""
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .medium))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(MeetingTheme.backgroundSecondary))
    }
}



// MARK: - Einstellungsseiten

/// Rahmen einer Einstellungsseite: Titel, Unterzeile und Karten mit Abschnitten.
private struct SettingsPage: View {
    let section: AppSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title).font(.system(size: 22, weight: .semibold))
                    Text(section.subtitle).font(.system(size: 13)).foregroundStyle(MeetingTheme.foregroundTertiary)
                }
                .padding(.bottom, 4)
                content
            }
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 32)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(section)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .meetings, .history:
            EmptyView()
        case .dictation:
            SettingsCard("Tastenkürzel") { HotkeysTab() }
            SettingsCard("Ausgabe") { OutputSection() }
        case .style:
            SettingsCard(nil) { StyleSection() }
        case .dictionary:
            SettingsCard("Eigennamen", footnote: "Die Liste korrigiert jede Transkription automatisch, auch in Meetings.") { DictionarySection() }
            SettingsCard("Kontext") { ContextSection() }
        case .speakers:
            SettingsCard("Ich") { SelfSpeakerSection() }
            SettingsCard(nil) { SprecherTab() }
        case .models:
            SettingsCard("Transkription") { LokalTab() }
            SettingsCard("Umformulieren", footnote: "Blitztext+ und $%&! einzeln: lokal über Ollama oder über einen Cloud-Anbieter.") { RewriteBackendSection() }
            SettingsCard("Meeting-Zusammenfassung") { MeetingSummarySection() }
            SettingsCard("Zugang OpenAI") { OpenAIKeySection() }
            SettingsCard("Zugang OpenRouter") { ProviderAccountSection(provider: .openRouter) }
            SettingsCard("Zugang Requesty") { ProviderAccountSection(provider: .requesty) }
        case .system:
            SettingsCard("Darstellung") { AppearanceSection() }
            SettingsCard("Ablage im Wissensordner") { VaultSection() }
            SettingsCard("Berechtigungen und Autostart") { PermissionsSection() }
            SettingsCard("Updates und Version") { UeberTab() }
        }
    }
}

/// Karte wie Wispr Flows graue Abschnitte: Sand-Fläche, kleine Großbuchstaben-Überschrift.
struct SettingsCard<Content: View>: View {
    let title: String?
    var footnote: String?
    let content: Content

    init(_ title: String?, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(MeetingTheme.foregroundTertiary)
            }
            if let footnote {
                Text(footnote).font(.caption).foregroundStyle(MeetingTheme.foregroundTertiary)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(MeetingTheme.backgroundTertiary))
    }
}
