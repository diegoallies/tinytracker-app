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
            TabView {
                TodayPage()
                NavigationStack { FeedPage() }
                DiaperPage()
                SleepPage()
                MedicinePage()
            }
            .tabViewStyle(.verticalPage)
            .environmentObject(connectivity)
        }
    }
}
