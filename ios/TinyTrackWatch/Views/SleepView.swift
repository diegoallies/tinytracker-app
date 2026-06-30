import SwiftUI

/// Screen 4 — Sleep. Start/Stop toggle with a live running timer while active.
/// The active start time is persisted (`@AppStorage`) so the timer survives
/// navigation and app relaunch.
struct SleepView: View {
    @EnvironmentObject private var connectivity: ConnectivityService
    @AppStorage("tinytrack.sleepStartedAt") private var sleepStartedAt: Double = 0

    private var isSleeping: Bool { sleepStartedAt > 0 }
    private var startDate: Date { Date(timeIntervalSince1970: sleepStartedAt) }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isSleeping ? "moon.zzz.fill" : "moon.stars.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.sleep)

            if isSleeping {
                Text(timerInterval: startDate...Date.distantFuture, countsDown: false)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.sleep)
                Text("Asleep since \(startDate.shortTime)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not sleeping")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Button(action: toggle) {
                Label(isSleeping ? "Stop" : "Start",
                      systemImage: isSleeping ? "stop.fill" : "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.sleep))
        }
        .padding(.horizontal, 4)
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle() {
        if isSleeping {
            connectivity.send(action: .sleepStop)     // ["action": "sleepStop"]
            sleepStartedAt = 0
        } else {
            connectivity.send(action: .sleepStart)    // ["action": "sleepStart"]
            sleepStartedAt = Date().timeIntervalSince1970
        }
    }
}

#Preview {
    NavigationStack { SleepView() }
        .environmentObject(ConnectivityService.shared)
}
