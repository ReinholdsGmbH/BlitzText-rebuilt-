import SwiftUI

/// Release-Notes-Screen. Zwei Modi:
///  - **Update-Modus** (`availableUpdate != nil`): zeigt die Neuerungen seit der installierten
///    Version und bietet unten rechts den Download-/Install-Button.
///  - **Browse-Modus** (kein Update): zeigt die bisherigen Release-Notes zum Nachlesen, ohne
///    Download-Button. So auch über Rechtsklick → „Release-Notes…" erreichbar.
struct UpdateView: View {
    @EnvironmentObject var service: UpdateService
    let onDismiss: () -> Void

    private var isUpdate: Bool { service.availableUpdate != nil }
    private var releasesToShow: [ReleaseInfo] {
        if let plan = service.availableUpdate { return plan.newerReleases }
        return service.allReleases
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: isUpdate ? "arrow.down.circle.fill" : "sparkles")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(isUpdate ? "Update verfügbar" : "Release-Notes").font(.title2).bold()
                if let plan = service.availableUpdate {
                    HStack(spacing: 6) {
                        Text(service.currentVersion.description).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                        Text(plan.latest.version.description).bold().foregroundStyle(.tint)
                    }
                    .font(.subheadline)
                } else {
                    Text("Installierte Version \(service.currentVersion.description)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(20)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !releasesToShow.isEmpty {
            notesList
        } else {
            switch service.checkState {
            case .checking:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Lade Release-Notes …").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Release-Notes nicht ladbar", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Erneut versuchen") {
                        Task { await service.checkForUpdates(userInitiated: true) }
                    }
                }
                .frame(maxHeight: .infinity)
            default:
                ContentUnavailableView("Keine Release-Notes",
                                       systemImage: "doc.text",
                                       description: Text("Für BlitzText liegen noch keine Release-Notes vor."))
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var notesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(releasesToShow) { release in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(release.tag)
                                .font(.caption).bold().monospaced()
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(.tint.opacity(0.15), in: Capsule())
                                .foregroundStyle(.tint)
                            if release.version == service.currentVersion {
                                Text("installiert")
                                    .font(.caption2).bold()
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(.green.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                            if let date = release.publishedAt {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ReleaseNotesText(markdown: release.notes.isEmpty ? release.title : release.notes)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Notes-Fläche füllt bewusst den Platz zwischen Header und Footer — verhindert, dass
        // die ScrollView in einem VStack(spacing:0) auf Höhe 0 kollabiert.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isUpdate { phaseIndicator }

            HStack {
                Button(isUpdate ? "Später" : "Schließen") { onDismiss() }
                Spacer()
                if let plan = service.availableUpdate, plan.isDownloadable {
                    primaryButton
                } else {
                    Button("Auf GitHub öffnen") {
                        NSWorkspace.shared.open(GitHubRepo.releasesPageURL)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var phaseIndicator: some View {
        if let phase = service.installPhase {
            switch phase {
            case .downloading(let fraction):
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: fraction).progressViewStyle(.linear)
                    Text("Lädt … \(Int(fraction * 100)) %").font(.caption).foregroundStyle(.secondary)
                }
            case .preparing:
                Label("Wird vorbereitet …", systemImage: "shippingbox")
                    .font(.caption).foregroundStyle(.secondary)
            case .relaunching:
                Label("BlitzText startet neu …", systemImage: "arrow.clockwise")
                    .font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch service.installPhase {
        case .downloading?, .preparing?, .relaunching?:
            Button("Aktualisierung herunterladen und installieren") {}
                .buttonStyle(.borderedProminent)
                .disabled(true)
        case .failed?:
            Button("Erneut versuchen") {
                service.resetInstallError()
                service.beginInstall()
            }
            .buttonStyle(.borderedProminent)
        case nil:
            Button("Aktualisierung herunterladen und installieren") {
                service.beginInstall()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
}

/// Schlanker Markdown-Renderer für die Release-Notes (`#`/`##`/`###`-Überschriften,
/// `-`/`*`-Aufzählungen, `**fett**`, `` `code` ``). SwiftUI-`Text` rendert nur Inline-
/// Markdown, keine Blockstrukturen — daher zeilenweise aufbereiten.
private struct ReleaseNotesText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(for: line)
            }
        }
    }

    private var lines: [String] {
        markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    @ViewBuilder
    private func row(for raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            Spacer().frame(height: 2)
        } else if line.hasPrefix("### ") {
            Text(String(line.dropFirst(4))).font(.headline).padding(.top, 4)
        } else if line.hasPrefix("## ") {
            Text(String(line.dropFirst(3))).font(.title3).bold().padding(.top, 6)
        } else if line.hasPrefix("# ") {
            Text(String(line.dropFirst(2))).font(.title2).bold().padding(.top, 6)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                inline(String(line.dropFirst(2)))
            }
        } else {
            inline(line)
        }
    }

    /// Inline-Markdown (fett/code/Links) via AttributedString; Fallback auf Klartext.
    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}
