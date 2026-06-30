import SwiftUI

/// A compact stat card for the Today screen: glowing gradient icon badge, big
/// value, label, and an optional trailing caption — on a frosted card.
struct StatTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.gradient(tint))
                    .frame(width: 38, height: 38)
                    .shadow(color: tint.opacity(0.5), radius: 5, y: 2)
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(title)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 0)

            if let caption {
                Text(caption)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18, tint: tint, strokeOpacity: 0.22)
    }
}
