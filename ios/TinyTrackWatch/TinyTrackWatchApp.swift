import SwiftUI

/// TinyTrack — watchOS companion to the TinyTrack iPhone (Flutter) app.
/// Talks to the phone only via WatchConnectivity; no direct backend access.
///
/// Apple-native full-screen paging: each category is its own page, swipe (or turn
/// the crown) vertically to move between them.
@main
struct TinyTrackWatchApp: App {
    @StateObject private var connectivity = ConnectivityService.shared

    var body: some Scene {
        WindowGroup {
            RootTabs().environmentObject(connectivity)
        }
    }
}

private struct RootTabs: View {
    @State private var selection: Int = {
        #if DEBUG
        // Lets the Simulator land directly on a page for UI screenshots, e.g.
        // SIMCTL_CHILD_WATCH_TAB=4 → Medicine. No effect on device builds.
        if let raw = ProcessInfo.processInfo.environment["WATCH_TAB"],
           let i = Int(raw) { return i }
        #endif
        return 0
    }()

    var body: some View {
        TabView(selection: $selection) {
            TodayPage().tag(0)
            NavigationStack { FeedPage() }.tag(1)
            DiaperPage().tag(2)
            SleepPage().tag(3)
            MedicinePage().tag(4)
        }
        .tabViewStyle(.verticalPage)
    }
}
