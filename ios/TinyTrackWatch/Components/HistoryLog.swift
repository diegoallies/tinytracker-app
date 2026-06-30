import SwiftUI

/// One record row inside a page's history log.
struct LogRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?
    let time: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.gradient(tint))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
            Text(time)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(10)
        .glassCard(16, tint: tint)
    }
}

/// Standard chrome for a page's left-scroll history log (Feat 2): header + a
/// scrolling list of `LogRow`s, or a centred empty state.
struct HistoryLog<Rows: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let isEmpty: Bool
    let emptyText: String
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(spacing: 8) {
            PageHeader(icon: icon, title: title, tint: tint)

            if isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.8))
                    Text(emptyText)
                        .font(.system(size: 12, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 8) { rows() }
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground(tint)
    }
}

extension Date {
    /// Compact history stamp: "14:32" today, "Yest 14:32", else "Mon 14:32".
    var logStamp: String {
        let cal = Calendar.current
        let t = DateFormatter(); t.dateFormat = "HH:mm"
        if cal.isDateInToday(self) { return t.string(from: self) }
        if cal.isDateInYesterday(self) { return "Yest " + t.string(from: self) }
        let d = DateFormatter(); d.dateFormat = "EEE HH:mm"
        return d.string(from: self)
    }
}
