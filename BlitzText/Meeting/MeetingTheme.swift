import AppKit
import SwiftUI

/// Gestaltung der Meeting-Oberfläche, abgeleitet aus Wispr Flows Designsystem
/// (Tokens aus `app.asar`, Stand v1.6.1483): warme Sand-Töne statt Systemgrau, Serifen für
/// Überschriften, Lavendel als Primärfarbe, schwarze Kapsel für die Aufnahme.
/// Hell und dunkel wie dort: `background` sand-50 ↔ vast-950 usw.
enum MeetingTheme {

    // MARK: Paletten (Hex aus Wispr Flows CSS)

    static let sand50 = Color(hex: 0xFCFCFB), sand500 = Color(hex: 0xF5F4F0), sand600 = Color(hex: 0xEEEBE3)
    static let sand700 = Color(hex: 0xC5C0B3), sand950 = Color(hex: 0x4D4A42)
    static let vast50 = Color(hex: 0xE9E8E1), vast600 = Color(hex: 0x71716E)
    static let vast900 = Color(hex: 0x30302F), vast925 = Color(hex: 0x202020), vast950 = Color(hex: 0x1A1A1A)
    static let dawn100 = Color(hex: 0xFCF7FF), dawn500 = Color(hex: 0xF0D7FF), dawn700 = Color(hex: 0xA26EC1)
    static let glow300 = Color(hex: 0xFFA946)
    static let evergreen = Color(hex: 0x034F46)
    static let coral = Color(hex: 0xFF6C4C)
    static let success = Color(hex: 0x4FBF78)

    // MARK: Semantik (hell / dunkel)

    static let background = Color(light: 0xFCFCFB, dark: 0x1A1A1A)
    static let backgroundSecondary = Color(light: 0xEEEBE3, dark: 0x30302F)
    static let backgroundTertiary = Color(light: 0xF5F4F0, dark: 0x202020)
    /// Fläche hinter dem Transkript (Website: warm-graues Panel).
    static let panel = Color(light: 0xE9E8E1, dark: 0x2A2A29)
    static let card = Color(light: 0xFFFFFF, dark: 0x202020)
    static let foreground = Color(light: 0x1A1A1A, dark: 0xE9E8E1)
    static let foregroundTertiary = Color(light: 0x71716E, dark: 0x9D9C98)
    static let border = Color(light: 0xEEEBE3, dark: 0x30302F)

    /// Karte „Wer spricht hier?“: hell Lavendel, dunkel tiefes Violett (dawn-950).
    static let assignCard = Color(light: 0xFCF7FF, dark: 0x2A2131)
    static let assignBorder = Color(light: 0xF0D7FF, dark: 0x6C358C)

    /// Sprecherfarben wie die Namens-Kapseln auf wisprflow.ai: (Grund, Schrift).
    static let speakerColors: [(fill: Color, text: Color)] = [
        (Color(hex: 0x034F46), .white),
        (Color(hex: 0xFFA946), Color(hex: 0x1A1A1A)),
        (Color(hex: 0xF0D7FF), Color(hex: 0x3C2947)),
        (Color(hex: 0xD1F2EE), Color(hex: 0x034F46)),
        (Color(hex: 0xFFBCF2), Color(hex: 0x502B66)),
        (Color(hex: 0xA550A7), .white),
        (Color(hex: 0xFACDA1), Color(hex: 0x5C370B))
    ]
    /// „Ich“ in Dunkel, wie die eigene Kachel.
    static let meColors: (fill: Color, text: Color) = (Color(light: 0x1A1A1A, dark: 0xE9E8E1), Color(light: 0xFCFCFB, dark: 0x1A1A1A))

    static func speaker(_ index: Int) -> (fill: Color, text: Color) {
        speakerColors[index % speakerColors.count]
    }

    // MARK: Schrift

    /// Wispr setzt Überschriften in EB Garamond. Ohne gebündelte Schrift die systemeigene
    /// Serifenschrift (New York), die dem Charakter am nächsten kommt.
    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        let font = Font.system(size: size, weight: .regular, design: .serif)
        return italic ? font.italic() : font
    }
}

// MARK: - Bausteine

/// Primärknopf wie „Get started“: Lavendel, dunkler Rand, dunkle Schrift.
struct LavenderButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(MeetingTheme.vast950)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(height: compact ? 26 : 32)
            .background(
                RoundedRectangle(cornerRadius: compact ? 8 : 10)
                    .fill(configuration.isPressed ? MeetingTheme.dawn500.opacity(0.75) : MeetingTheme.dawn500)
            )
            .overlay(RoundedRectangle(cornerRadius: compact ? 8 : 10).strokeBorder(MeetingTheme.vast950, lineWidth: 1.2))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Sekundärknopf: ruhige Sand-Fläche ohne Rand.
struct SandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(MeetingTheme.foreground)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(MeetingTheme.backgroundSecondary.opacity(configuration.isPressed ? 0.6 : 1))
            )
    }
}

/// Umschalter wie „Dictation | Notetaker“: Kapsel-Spur, aktiver Teil weiß.
struct CapsuleToggle<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let active = option.0 == selection
                Button { selection = option.0 } label: {
                    Text(option.1)
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize()
                        .foregroundStyle(MeetingTheme.foreground)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(active ? MeetingTheme.card : .clear)
                            .shadow(color: .black.opacity(active ? 0.08 : 0), radius: 2, y: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(MeetingTheme.backgroundSecondary))
    }
}

/// Namens-Kapsel mit Wellenform-Symbol, wie die Sprecher-Tags auf wisprflow.ai.
struct SpeakerTag: View {
    let name: String
    let colors: (fill: Color, text: Color)
    var small = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform").font(.system(size: small ? 8 : 9, weight: .bold))
            Text(name).font(.system(size: small ? 10 : 11, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(colors.text)
        .padding(.horizontal, small ? 6 : 8)
        .frame(height: small ? 18 : 22)
        .background(Capsule().fill(colors.fill))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Farbe, die dem hellen oder dunklen Erscheinungsbild folgt.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}
