import SwiftUI

// MARK: - Über / Updates

struct UeberTab: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var updateService: UpdateService

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            section("VERSION") {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill").font(.title2).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BlitzText \(version)").font(.headline)
                        Text("Build \(build)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            section("UPDATES") {
                Toggle("Automatisch nach Updates suchen", isOn: $settings.autoUpdateCheckEnabled)
                Text("Prüft beim Start und alle 2 Stunden, ob eine neuere Version auf GitHub liegt, und benachrichtigt dich. Der Download startet erst auf deinen Klick.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        Task { await updateService.checkForUpdates(userInitiated: true) }
                    } label: {
                        Label("Jetzt nach Updates suchen", systemImage: "arrow.clockwise")
                    }
                    .disabled(updateService.checkState == .checking)

                    checkStatus
                }
                .padding(.top, 2)
            }

            Divider()

            section("LINKS") {
                Button("Release-Notes auf GitHub öffnen …") {
                    NSWorkspace.shared.open(GitHubRepo.releasesPageURL)
                }
                .buttonStyle(.link)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var checkStatus: some View {
        switch updateService.checkState {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Suche …").font(.caption).foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("Aktuell", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .idle:
            if let plan = updateService.availableUpdate {
                Button("Version \(plan.latest.version) verfügbar – Details") {
                    updateService.presentWindow?()
                }
                .font(.caption)
                .foregroundStyle(.tint)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).bold()
            content()
        }
    }
}
