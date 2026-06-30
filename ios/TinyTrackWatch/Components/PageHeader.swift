import SwiftUI

/// Compact, definitive page header: a gradient icon badge + a short label.
/// Used at the top of every full-screen page so a glance tells you where you are.
struct PageHeader: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Theme.gradient(tint))
                    .frame(width: 26, height: 26)
                    .shadow(color: tint.opacity(0.55), radius: 4, y: 1)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .tracking(1.5)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}
