import SwiftUI

/// Palette mirrored from the TinyTrack iPhone app (`lib/config/theme.dart`) so the
/// watch reads as the same product: purple brand, dark purple-tinted surfaces, and
/// the dashboard's per-category accent colours (Feed = pink, Diaper = yellow,
/// Sleep = blue).
enum Theme {
    // Brand — AppColors.primary / primaryLight / primaryDark
    static let brand      = Color(hex: 0x9B72CF)
    static let brandLight = Color(hex: 0xB794E0)
    static let brandDark  = Color(hex: 0x7B52AF)

    // Dark surfaces — AppPalette.dark
    static let surface  = Color(hex: 0x120F1A)
    static let card     = Color(hex: 0x262038)
    static let hairline = Color(hex: 0x3F3558)
    static let muted    = Color(hex: 0xABA3C2)

    // Category accents — same hue families as the app's dashboard quick actions,
    // saturated so they read on the dark watch face.
    static let feed     = Color(hex: 0xEC8AB8)   // pink   (pastelPink family)
    static let diaper   = Color(hex: 0xE6C36A)   // gold   (pastelYellow family)
    static let sleep    = Color(hex: 0x86B6E6)   // blue   (pastelBlue family)
    static let medicine = brand                  // purple (care / brand)
    static let today    = Color(hex: 0x7FD3AC)   // mint   (pastelGreen family)

    /// Rich diagonal gradient derived from an accent — icon badges, rings, fills.
    static func gradient(_ base: Color) -> LinearGradient {
        LinearGradient(colors: [base, base.opacity(0.55)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: 1)
    }
}

extension View {
    /// App-matched screen background: the dark purple surface with a soft accent
    /// glow at the top, instead of flat black.
    func screenBackground(_ tint: Color = Theme.brand) -> some View {
        self.background(
            ZStack {
                Theme.surface
                RadialGradient(colors: [tint.opacity(0.22), .clear],
                               center: .top, startRadius: 0, endRadius: 230)
            }
            .ignoresSafeArea()
        )
    }

    /// Liquid Glass (watchOS 26+) with a frosted-material fallback. Tinted and
    /// hair-lined to match the app's card treatment.
    @ViewBuilder
    func glassCard(_ cornerRadius: CGFloat, tint: Color, strokeOpacity: Double = 0.28) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(watchOS 26.0, *) {
            self.glassEffect(.regular.tint(tint.opacity(0.20)), in: shape)
                .overlay(shape.strokeBorder(tint.opacity(strokeOpacity), lineWidth: 0.8))
        } else {
            self.background(shape.fill(.ultraThinMaterial))
                .overlay(shape.fill(tint.opacity(0.13)))
                .overlay(shape.strokeBorder(tint.opacity(strokeOpacity), lineWidth: 1))
        }
    }
}

extension Date {
    /// "14:32" style short time, used across the glanceable screens.
    var shortTime: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: self)
    }
}
