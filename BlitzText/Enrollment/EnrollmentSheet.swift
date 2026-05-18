import SwiftUI
import Combine

// MARK: - EnrollmentSheet

/// SwiftUI-Sheet für den Sprecher-Enrollment-Flow.
/// Spec: SPK-08, 06-UI-SPEC.md §"Surface 2: EnrollmentSheet".
struct EnrollmentSheet: View {
    @ObservedObject var viewModel: EnrollmentViewModel
    @EnvironmentObject var speakerVM: SpeakerProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // MARK: Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Sprecher-Profil aufnehmen")
                    .font(.title3)
                    .bold()
                Text("Sprich 15 Sekunden frei — lies vor, zähle, erzähle. Dann wird dein Profil gespeichert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Name-Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline)
                TextField("Dein Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled({
                        switch viewModel.state {
                        case .recording, .processing: return true
                        default: return false
                        }
                    }())
            }

            // MARK: Status-Section (State-Switch)
            statusSection

            Spacer()

            // MARK: Footer (Buttons)
            HStack {
                Button("Enrollment abbrechen") {
                    viewModel.reset()
                    dismiss()
                }
                .disabled({
                    if case .processing = viewModel.state { return true }
                    return false
                }())
                Spacer()
                primaryButton
            }
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 320)
        .onChange(of: viewModel.state) { _, newState in
            if case .done = newState {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Status-Section

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.state {
        case .recording(let remaining):
            VStack(alignment: .leading, spacing: 8) {
                LevelMeterBar(level: viewModel.currentLevel)
                Text("\(remaining) s verbleibend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .processing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Profil wird erstellt …")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        case .idle, .done:
            EmptyView()
        }
    }

    // MARK: - Primary Button

    @ViewBuilder
    private var primaryButton: some View {
        switch viewModel.state {
        case .recording:
            Button("Stopp") {
                viewModel.stopAndEnroll(name: name)
            }
            .buttonStyle(.bordered)
        case .processing:
            Button("Stopp") {}
                .disabled(true)
                .buttonStyle(.bordered)
        case .idle, .failed:
            Button("Aufnahme starten") {
                viewModel.startRecording(name: name)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .done:
            EmptyView()
        }
    }
}

// MARK: - LevelMeterBar

private struct LevelMeterBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * CGFloat(level), height: 8)
            }
        }
        .frame(height: 8)
        .animation(.linear(duration: 0.05), value: level)
    }
}
