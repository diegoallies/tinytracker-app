import SwiftUI

/// TinyTrack — watchOS companion to the TinyTrack iPhone (Flutter) app.
/// Talks to the phone only via WatchConnectivity; no direct backend access.
@main
struct TinyTrackWatchApp: App {
    @StateObject private var connectivity = ConnectivityService.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { HomeView() }
                NavigationStack { TodayView() }
            }
            .tabViewStyle(.verticalPage)
            .environmentObject(connectivity)
        }
    }
}
