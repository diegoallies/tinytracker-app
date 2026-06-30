import SwiftUI

/// Screen 1 — Home. "Next feed in Xm", last feed, and four large tap buttons.
struct HomeView: View {
    @EnvironmentObject private var connectivity: ConnectivityService

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                nextFeedCard

                NavigationLink { LogFeedView() } label: {
                    BigActionButton(title: "Feed", systemImage: "waterbottle.fill", tint: Theme.feed)
                }
                NavigationLink { LogDiaperView() } label: {
                    BigActionButton(title: "Diaper", systemImage: "drop.fill", tint: Theme.diaper)
                }
                NavigationLink { SleepView() } label: {
                    BigActionButton(title: "Sleep", systemImage: "moon.zzz.fill", tint: Theme.sleep)
                }
                NavigationLink { MedicineView() } label: {
                    BigActionButton(title: "Medicine", systemImage: "pills.fill", tint: Theme.medicine)
                }
            }
            .padding(.horizontal, 2)
            .buttonStyle(.plain)
        }
        .navigationTitle("TinyTrack")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var nextFeedCard: some View {
        VStack(spacing: 4) {
            Text("Next feed")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(connectivity.summary.nextFeedShort)
                .font(.system(.title, design: .rounded).weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("\(connectivity.summary.feedsToday) feeds · \(connectivity.summary.totalMlToday)ml today")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.feed.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environmentObject(ConnectivityService.shared)
}
