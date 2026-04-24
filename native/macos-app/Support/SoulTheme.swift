import SwiftUI

enum SoulTheme {
    static let background = Color(hex: 0x131313)
    static let surface = Color(hex: 0x201F1F)
    static let surfaceHigh = Color(hex: 0x2A2A2A)
    static let text = Color(hex: 0xE5E2E1)
    static let muted = Color(hex: 0xCBC3D7).opacity(0.72)
    static let primary = Color(hex: 0xD0BCFF)
    static let primaryContainer = Color(hex: 0xA078FF)
    static let secondary = Color(hex: 0x4CD7F6)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 16
    var opacity: Double = 0.58

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(opacity), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: SoulTheme.primary.opacity(0.08), radius: 28, x: 0, y: 18)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 16, opacity: Double = 0.58) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, opacity: opacity))
    }
}
