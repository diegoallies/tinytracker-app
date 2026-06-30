import SwiftUI

/// A large, rounded, high-contrast action row used on Home and elsewhere.
/// Purely visual — drop it inside a `NavigationLink` or `Button`.
struct BigActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 28)
            Text(title)
                .font(.headline)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(tint)
        .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

/// A filled "primary" confirm button (e.g. Save).
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(tint.opacity(configuration.isPressed ? 0.7 : 1.0),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
