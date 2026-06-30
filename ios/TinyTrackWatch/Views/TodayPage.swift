import SwiftUI

/// Full-screen Today page. Page 0 is today's live summary (2×2 grid + avatar hub);
/// swipe LEFT to walk back through previous days (Feat 1), each rendered as the
/// same glanceable grid for that date. Previous days come from the phone's
/// `daySummaries` (newest first, today at index 0).
struct TodayPage: View {
    @EnvironmentObject private var connectivity: ConnectivityService
    private var s: WatchSummary { connectivity.summary }

    private let cols = [GridItem(.flexible(), spacing: 7),
                        GridItem(.flexible(), spacing: 7)]

    /// Everything after today (the phone sends today first).
    private var previousDays: [DaySummary] { Array(connectivity.daySummaries.dropFirst()) }

    var body: some View {
        TabView {
            todayView
            ForEach(previousDays) { day in
                pastDayView(day)
            }
        }
        .tabViewStyle(.page)
    }

    // MARK: Today (live, with avatar hub + next feed)

    private var todayView: some View {
        VStack(spacing: 10) {
            PageHeader(icon: "chart.bar.fill", title: "TODAY", tint: Theme.today)

            LazyVGrid(columns: cols, spacing: 7) {
                tile("Feeds", "\(s.feedsToday)", "\(s.totalMlToday) ml",
                     "waterbottle.fill", Theme.feed, .topLeading)
                tile("Sleep", s.sleepTodayShort, nil,
                     "moon.zzz.fill", Theme.sleep, .topTrailing)
                tile("Diapers", "\(s.diapersToday)", nil,
                     "drop.fill", Theme.diaper, .bottomLeading)
                tile("Next", s.nextFeedShort, nil,
                     "clock.fill", Theme.today, .bottomTrailing)
            }
            .overlay(alignment: .center) { avatarHub }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground(Theme.today)
    }

    // MARK: A previous day (pure totals, no live next-feed / avatar)

    private func pastDayView(_ day: DaySummary) -> some View {
        VStack(spacing: 10) {
            PageHeader(icon: "calendar", title: day.label.uppercased(), tint: Theme.today)

            LazyVGrid(columns: cols, spacing: 7) {
                tile("Feeds", "\(day.feeds)", nil,
                     "waterbottle.fill", Theme.feed, .topLeading)
                tile("Sleep", day.sleepShort, nil,
                     "moon.zzz.fill", Theme.sleep, .topTrailing)
                tile("Diapers", "\(day.diapers)", nil,
                     "drop.fill", Theme.diaper, .bottomLeading)
                tile("Milk", "\(day.totalMl)", "ml",
                     "cup.and.saucer.fill", Theme.today, .bottomTrailing)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground(Theme.today)
    }

    private var avatarHub: some View {
        BabyAvatar(photoUrl: s.babyPhotoUrl, initials: s.babyInitials, diameter: 58)
            .padding(5)
            .background(Circle().fill(Theme.surface))
    }

    private func tile(_ title: String, _ value: String, _ caption: String?,
                      _ icon: String, _ tint: Color, _ corner: Alignment) -> some View {
        let isLeading = corner == .topLeading || corner == .bottomLeading
        let hAlign: HorizontalAlignment = isLeading ? .leading : .trailing
        return VStack(alignment: hAlign, spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(caption ?? title)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: corner)
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .glassCard(20, tint: tint, strokeOpacity: 0.18)
    }
}

#Preview {
    TodayPage().environmentObject(ConnectivityService.shared)
}
