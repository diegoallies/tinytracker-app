import SwiftUI

/// Screen 6 — Today. Glanceable summary counts pushed from the phone.
struct TodayView: View {
    @EnvironmentObject private var connectivity: ConnectivityService

    private var s: WatchSummary { connectivity.summary }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                StatTile(title: "Feeds",
                         value: "\(s.feedsToday)",
                         caption: "\(s.totalMlToday)ml",
                         systemImage: "waterbottle.fill",
                         tint: Theme.feed)
                StatTile(title: "Sleep",
                         value: s.sleepTodayShort,
                         systemImage: "moon.zzz.fill",
                         tint: Theme.sleep)
                StatTile(title: "Diapers",
                         value: "\(s.diapersToday)",
                         systemImage: "drop.fill",
                         tint: Theme.diaper)
                StatTile(title: "Next feed",
                         value: s.nextFeedShort,
                         systemImage: "clock.fill",
                         tint: Theme.today)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { TodayView() }
        .environmentObject(ConnectivityService.shared)
}
