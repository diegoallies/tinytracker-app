import SwiftUI

/// Ultra-compact page label: a small tinted glyph + short title on a single tight
/// row, pinned top-left. Deliberately minimal height so it sits right under the
/// system clock without stealing space from the content/log list below.
struct PageHeader: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(tint)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
