import SwiftUI

/// Full-screen Feed page. Page 0 is the glanceable next-feed summary + log action;
/// swipe LEFT (Feat 2) to see the recent feed log. The primary action drills into
/// the crown dial (`LogFeedView`).
struct FeedPage: View {
    @EnvironmentObject private var connectivity: ConnectivityService
    private var s: WatchSummary { connectivity.summary }

    @State private var sub: Int = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["WATCH_FEED_SUB"],
           let i = Int(raw) { return i }
        #endif
        return 0
    }()

    var body: some View {
        TabView(selection: $sub) {
            main.tag(0)
            logView.tag(1)
        }
        .tabViewStyle(.page)
    }

    private var main: some View {
        VStack(spacing: 8) {
            PageHeader(icon: "waterbottle.fill", title: "FEED", tint: Theme.feed)

            Spacer(minLength: 0)
            Text("Next feed")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Text(s.nextFeedShort)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("\(s.feedsToday) feeds · \(s.totalMlToday) ml today")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)

            NavigationLink {
                LogFeedView()
            } label: {
                Label("Log Feed", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.feed))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground(Theme.feed)
    }

    private var logView: some View {
        HistoryLog(title: "FEED LOG", icon: "list.bullet", tint: Theme.feed,
                   isEmpty: connectivity.feedLog.isEmpty,
                   emptyText: "No feeds logged yet.") {
            ForEach(connectivity.feedLog) { f in
                let kind = FeedKind(rawValue: f.type)
                LogRow(icon: kind?.symbol ?? "waterbottle.fill",
                       tint: Theme.feed,
                       title: kind?.label ?? f.type.capitalized,
                       subtitle: f.amountMl != nil ? "\(f.amountMl!) ml" : nil,
                       time: f.loggedAt.logStamp)
            }
        }
    }
}

#Preview {
    NavigationStack { FeedPage() }
        .environmentObject(ConnectivityService.shared)
}
