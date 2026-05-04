import SwiftUI

/// Vier-State-Banner für Apple-Foundation-Verfügbarkeit (UI-SPEC Surface 2).
///
/// Render-Logik:
/// - `.available` → EmptyView (Banner verschwindet komplett, kein Übergangs-State).
/// - `.unavailable(.appleIntelligenceNotEnabled)` → Variante A (orange, Link in Systemeinstellungen).
/// - `.unavailable(.modelNotReady)` → Variante B (secondary-tint, ProgressView, "Erneut prüfen").
/// - `.unavailable(.deviceNotEligible)` → Variante C (orange, kein Action — Final-State).
///
/// Optional ergänzend: Variante D (Auto-Fallback-Zeile) bei `didAutoFallbackToOpenAI == true`,
/// unterdrückt bei Variante C (Detail-Text deckt OpenAI-Fall dort bereits ab — UI-SPEC Zeile 216).
struct FoundationAvailabilityBanner: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if shouldShowAutoFallbackHint {
                autoFallbackRow
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch settings.foundationAvailability {
        case .available:                              EmptyView()
        case .unavailable(.appleIntelligenceNotEnabled): variantA
        case .unavailable(.modelNotReady):               variantB
        case .unavailable(.deviceNotEligible):           variantC
        }
    }

    // MARK: - Variante A: Apple Intelligence ist nicht aktiviert

    @ViewBuilder
    private var variantA: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Intelligence ist nicht aktiviert")
                    .font(.subheadline)
                Text("Aktiviere Apple Intelligence in den Systemeinstellungen, um BlitzText+ und BlitzText $%&! lokal zu rewriten — ohne Cloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(
                    "Systemeinstellungen öffnen …",
                    destination: URL(string: "x-apple.systempreferences:com.apple.preference.appleintelligence")!
                )
            }
            Spacer()
        }
    }

    // MARK: - Variante B: Modell wird geladen

    @ViewBuilder
    private var variantB: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Apple-Foundation-Modell wird geladen …")
                        .font(.subheadline)
                    ProgressView().controlSize(.small)
                }
                Text("Das passiert einmalig nach Aktivierung von Apple Intelligence. BlitzText prüft regelmäßig, ob das Modell bereit ist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Erneut prüfen") {
                    settings.refreshFoundationAvailability()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
    }

    // MARK: - Variante C: Gerät unterstützt Apple Intelligence nicht

    @ViewBuilder
    private var variantC: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Dieses Gerät unterstützt Apple Intelligence nicht")
                    .font(.subheadline)
                Text("BlitzText+ und BlitzText $%&! laufen über die OpenAI-Cloud, sofern ein API-Key hinterlegt ist. Ohne API-Key bleibt nur der einfache Blitztext-Mode (kein Rewrite).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Variante D: Auto-Fallback-Hinweis (overlay zu A/B, unterdrückt bei C)

    @ViewBuilder
    private var autoFallbackRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "cloud")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("OpenAI als Fallback aktiv. Aktiviere Apple Intelligence, um lokal zu rewriten.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var shouldShowAutoFallbackHint: Bool {
        guard settings.didAutoFallbackToOpenAI else { return false }
        // UI-SPEC Zeile 216: Bei deviceNotEligible deckt Variante-C-Detail OpenAI bereits ab —
        // Doppelung unterdrücken.
        if case .unavailable(.deviceNotEligible) = settings.foundationAvailability {
            return false
        }
        return true
    }
}
