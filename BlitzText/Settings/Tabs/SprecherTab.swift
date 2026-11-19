import SwiftUI
import FluidAudio

// MARK: - Sprecher Tab (Phase 5)

struct SprecherTab: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var speakerVM: SpeakerProfileViewModel
    @EnvironmentObject var enrollmentVM: EnrollmentViewModel
    @EnvironmentObject var diarizerManager: DiarizerModelManager
    @State private var speakerToDelete: Speaker?
    @State private var showDeleteConfirm = false
    @State private var pendingNames: [String: String] = [:]
    @State private var mergeTargetID: String = ""
    @State private var speakerToMerge: String?
    @State private var showEnrollmentSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if settings.backend != .parakeet {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Sprecher-Profile sind nur mit dem Parakeet-Backend aktiv. Wechsle in den Einstellungen unter \"Backend\" zu \"Parakeet TDT v3 (Lokal)\".")
                        .font(.caption).foregroundStyle(.orange)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            unnamedSection
            allSpeakersSection
            enrollmentSection
            thresholdSection
        }
        .sheet(isPresented: $showEnrollmentSheet, onDismiss: {
            enrollmentVM.reset()
        }) {
            EnrollmentSheet(viewModel: enrollmentVM)
                .environmentObject(speakerVM)
        }
    }

    // MARK: - Letztes Transkript (SPK-06)

    @ViewBuilder
    private var unnamedSection: some View {
        let unnamed = speakerVM.unnamedFromLastTranscript
        if !unnamed.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("LETZTES TRANSKRIPT — UNBEKANNTE SPRECHER")
                    .font(.caption).foregroundStyle(.secondary).bold()
                Text("Weise diesen Sprechern einen Namen zu, damit sie bei zukünftigen Aufnahmen wiedererkannt werden.")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(unnamed) { speaker in
                    UnnamedSpeakerRow(speaker: speaker, onAssign: { name in
                        speakerVM.assignName(to: speaker.id, name: name)
                    })
                }
            }
            Divider()
        }
    }

    // MARK: - Alle Sprecher (SPK-04, SPK-05)

    private var allSpeakersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALLE SPRECHER").font(.caption).foregroundStyle(.secondary).bold()
            if speakerVM.speakers.isEmpty {
                Text("Noch keine Sprecher-Profile vorhanden. Nimm ein Meeting auf oder lege unten ein Profil an.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(speakerVM.speakers) { speaker in
                    SpeakerRow(
                        speaker: speaker,
                        allSpeakers: speakerVM.speakers,
                        onRename: { name in speakerVM.rename(id: speaker.id, name: name) },
                        onTogglePermanent: { speakerVM.togglePermanent(id: speaker.id) },
                        onMerge: { targetID in speakerVM.merge(sourceID: speaker.id, intoID: targetID) },
                        onDelete: {
                            if speaker.isPermanent {
                                speakerToDelete = speaker
                                showDeleteConfirm = true
                            } else {
                                speakerVM.delete(id: speaker.id)
                            }
                        }
                    )
                }
            }
        }
        .confirmationDialog(
            "Sprecher wirklich löschen?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let s = speakerToDelete { speakerVM.delete(id: s.id) }
                speakerToDelete = nil
            }
            Button("Abbrechen", role: .cancel) { speakerToDelete = nil }
        } message: {
            if let s = speakerToDelete {
                Text("\"\(s.name)\" ist als permanent markiert. Trotzdem löschen?")
            }
        }
    }

    // MARK: - Enrollment (SPK-08)

    @ViewBuilder
    private var enrollmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("ENROLLMENT").font(.caption).foregroundStyle(.secondary).bold()
            Button("Neues Profil aufnehmen") { showEnrollmentSheet = true }
                .buttonStyle(.borderedProminent)
                .disabled(!diarizerManager.isInstalled)
            if !diarizerManager.isInstalled {
                Text("Diarizer-Modell nicht installiert. Es lädt beim ersten Meeting oder unter Diktat mit „Sprecher im Diktat kennzeichnen“.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Threshold (SPK-07)

    private var thresholdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("MATCHING-SCHWELLENWERT").font(.caption).foregroundStyle(.secondary).bold()
            HStack {
                Text("Strenger").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $settings.speakerMatchThreshold, in: 0.5...0.9, step: 0.05)
                Text("Locker").font(.caption2).foregroundStyle(.secondary)
            }
            Text("Aktuell: \(String(format: "%.2f", settings.speakerMatchThreshold))  ·  Kleiner Wert = gleiche Stimmen werden öfter zusammengeführt. Größerer Wert = mehr separate Profile.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Unnamed Speaker Row (SPK-06)

private struct UnnamedSpeakerRow: View {
    let speaker: Speaker
    let onAssign: (String) -> Void
    @State private var name: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.fill.questionmark")
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sprecher \(speaker.id)").font(.subheadline)
                Text("\(Int(speaker.duration)) s · \(speaker.updateCount) Erkennungen")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Name eingeben", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                .onSubmit { commit() }
            Button("Zuweisen") { commit() }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAssign(trimmed)
        name = ""
    }
}

// MARK: - Speaker Row (SPK-04, SPK-05)

private struct SpeakerRow: View {
    let speaker: Speaker
    let allSpeakers: [Speaker]
    let onRename: (String) -> Void
    let onTogglePermanent: () -> Void
    let onMerge: (String) -> Void
    let onDelete: () -> Void

    @State private var editName: String = ""
    @State private var isEditing = false
    @State private var showMergePicker = false

    private var mergeOptions: [Speaker] {
        allSpeakers.filter { $0.id != speaker.id }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: speaker.isPermanent ? "person.fill.checkmark" : "person.fill")
                .foregroundStyle(speaker.isPermanent ? .green : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Name", text: $editName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .onSubmit { commitRename() }
                } else {
                    Text(speaker.name).bold()
                }
                HStack(spacing: 6) {
                    Text("\(speaker.updateCount) Erkennungen")
                    Text("·").foregroundStyle(.tertiary)
                    Text("Zuletzt: \(speaker.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    if speaker.isPermanent {
                        Text("PERMANENT")
                            .font(.caption2).bold()
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            if isEditing {
                Button("OK") { commitRename() }
                    .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Abbrechen") { isEditing = false }
                    .foregroundStyle(.secondary)
            } else {
                Button("Umbenennen") {
                    editName = speaker.name
                    isEditing = true
                }
                if !mergeOptions.isEmpty {
                    Menu("Zusammenführen") {
                        ForEach(mergeOptions) { target in
                            Button("\(speaker.name) → \(target.name)") {
                                onMerge(target.id)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 130)
                }
                Toggle("", isOn: Binding(
                    get: { speaker.isPermanent },
                    set: { _ in onTogglePermanent() }
                ))
                .toggleStyle(.checkbox)
                .help("Als permanent markieren (schützt vor automatischem Löschen)")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Sprecher-Profil löschen")
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func commitRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onRename(trimmed)
        isEditing = false
    }
}

// MARK: - Diarizer Status Block (Phase 3 Wave 1)

/// Vier-State-Block für den Diarizer-Modell-Lifecycle.
/// Spec: 03-UI-SPEC.md § State-by-State Visual Spec.
/// Strings sind LOCKED durch UI-SPEC § Copywriting Contract — NICHT paraphrasieren.
struct DiarizerStatusBlock: View {
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
            Text("Schreibt bei mehreren Stimmen „Sprecher 1: …“ in den Diktat-Text. Meetings trennen Sprecher immer, unabhängig von diesem Schalter. Lädt beim ersten Einschalten ein Diarizer-Modell (~80 MB).")
                .font(.caption2).foregroundStyle(.tertiary)
        case .installed:
            Toggle("Sprecher im Diktat kennzeichnen", isOn: $settings.parakeetDiarization)
            if settings.parakeetDiarization {
                if settings.backend == .parakeet {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Modell vorhanden — aktiv").font(.caption).foregroundStyle(.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Diarization erfordert das Parakeet-Backend — wähle oben \"Parakeet TDT v3 (Lokal)\".")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Text("Schreibt bei mehreren Stimmen „Sprecher 1: …“ in den Diktat-Text. Meetings trennen Sprecher immer, unabhängig von diesem Schalter. Lädt beim ersten Einschalten ein Diarizer-Modell (~80 MB).")
                .font(.caption2).foregroundStyle(.tertiary)
        case .failed(let message):
            errorView(message: message)
        }
    }

    @ViewBuilder
    private var toggleAndSubtitle: some View {
        Toggle("Sprecher im Diktat kennzeichnen", isOn: $settings.parakeetDiarization)
        Text("Schreibt bei mehreren Stimmen „Sprecher 1: …“ in den Diktat-Text. Meetings trennen Sprecher immer, unabhängig von diesem Schalter. Lädt beim ersten Einschalten ein Diarizer-Modell (~80 MB).")
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
