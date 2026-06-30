import SwiftUI

/// Large action row: gradient icon badge, title, optional subtitle, chevron,
/// on a frosted card. Wrap in a `NavigationLink` or `Button`.
struct BigActionButton: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(Theme.gradient(tint))
                    .frame(width: 44, height: 44)
                    .shadow(color: tint.opacity(0.55), radius: 7, y: 3)
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint.opacity(0.85))
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22, tint: tint)
        .contentShape(Rectangle())
    }
}

/// A filled "primary" confirm button (e.g. Save) — gradient fill, soft glow,
/// press-scale feedback.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(.white)
            .background(Theme.gradient(tint),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: tint.opacity(0.45), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
