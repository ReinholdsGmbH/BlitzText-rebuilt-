import SwiftUI
import UIKit

/// Warme Sand-Töne wie die Mac-App, Bernstein als Blitz-Akzent, Rot nur für „nimmt auf“.
enum Theme {
    static let background = dynamic(light: 0xF4F1EA, dark: 0x171512)
    static let card = dynamic(light: 0xFFFDF8, dark: 0x24211C)
    static let sand = dynamic(light: 0xE9E3D6, dark: 0x2F2B25)
    static let ink = dynamic(light: 0x1F1C17, dark: 0xF3EFE6)
    static let muted = dynamic(light: 0x6F685B, dark: 0xA9A193)
    static let accent = dynamic(light: 0xC98A0B, dark: 0xF2B230)
    static let recording = dynamic(light: 0xC8402F, dark: 0xF06A55)
    static let success = dynamic(light: 0x2F7A57, dark: 0x5FC495)

    static let heroNumber = Font.system(size: 64, weight: .bold, design: .rounded)
    static let title = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let sectionLabel = Font.system(size: 12, weight: .semibold).width(.expanded)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Karte mit Sand-Fläche und kleiner Großbuchstaben-Überschrift.
struct Card<Content: View>: View {
    let label: String?
    @ViewBuilder let content: Content

    init(_ label: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let label {
                Text(label.uppercased())
                    .font(Theme.sectionLabel)
                    .foregroundStyle(Theme.muted)
                    .tracking(0.8)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.sand, lineWidth: 1))
    }
}

/// Kurzer Hinweis „Kopiert“ am unteren Rand.
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.ink, in: Capsule())
                    .foregroundStyle(Theme.background)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View { modifier(ToastModifier(message: message)) }
}

enum Clipboard {
    static func copy(_ text: String) { UIPasteboard.general.string = text }
}

extension Int {
    /// 67109 → „67.109“
    var grouped: String { formatted(.number.grouping(.automatic).locale(Locale(identifier: "de_DE"))) }
}

/// Symbol und Text als eine Einheit mittig im Knopf (Label richtet sich in breiten Knöpfen nicht sauber mittig aus).
struct CenteredLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }
}
