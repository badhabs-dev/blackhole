import SwiftUI

/// Farb- und Stil-Definitionen im „blackhole"-Look (vgl. index.html der Website).
enum Theme {
    static let void = Color(hex: 0x000000)
    static let eventHorizon = Color(hex: 0x0a0a0f)
    static let accretion = Color(hex: 0x1a0a2e)
    static let corona = Color(hex: 0x2d1b69)
    static let accent = Color(hex: 0x8c50ff)     // glow-active
    static let accentDim = Color(hex: 0x6432dc)
    static let success = Color(hex: 0x28c878)
    static let danger = Color(hex: 0xdc1e1e)
    static let warning = Color(hex: 0xe0a020)

    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textFaint = Color.white.opacity(0.30)

    /// Vertikaler Verlauf für Bildschirmhintergründe.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [void, eventHorizon, accretion],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Karten-Container im App-Stil.
struct GlowCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.eventHorizon)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.corona.opacity(0.5), lineWidth: 1)
                    )
            )
            .shadow(color: Theme.accent.opacity(0.15), radius: 12, y: 4)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}
