import SwiftUI

/// Full-screen Sleep page. Pulsing moon, live running timer while asleep, and a
/// single Start/Stop action.
///
/// The PHONE is the source of truth for sleep state (`summary.sleepStartedAt`),
/// so a session started on the phone carries straight over to the watch with the
/// running timer, and the watch can only Stop it — never start a second one.
/// `optimisticStart` only bridges the brief gap between tapping Start here and
/// the phone echoing the new session back.
struct SleepPage: View {
    @EnvironmentObject private var connectivity: ConnectivityService
    @State private var optimisticStart: Date? = nil
    @State private var pulse = false

    /// Phone state wins; fall back to the optimistic local stamp until it arrives.
    private var startDate: Date? {
        connectivity.summary.sleepStartedAt ?? optimisticStart
    }
    private var isSleeping: Bool { startDate != nil }

    var body: some View {
        TabView {
            main
            logView
        }
        .tabViewStyle(.page)
    }

    private var main: some View {
        VStack(spacing: 6) {
            PageHeader(icon: "moon.zzz.fill", title: "SLEEP", tint: Theme.sleep)
            Spacer(minLength: 2)
            moon

            if let start = startDate {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("Asleep since \(start.shortTime)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                Text("Not sleeping")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 2)

            Button(action: toggle) {
                Label(isSleeping ? "Stop" : "Start",
                      systemImage: isSleeping ? "stop.fill" : "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.sleep))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground(Theme.sleep)
        .onAppear { if isSleeping { startPulse() } }
        // Once the phone confirms (or clears) the session, drop the optimistic stamp.
        .onChange(of: connectivity.summary.sleepStartedAt) { _, phoneStart in
            optimisticStart = nil
            if phoneStart != nil { startPulse() }
        }
    }

    private var logView: some View {
        HistoryLog(title: "SLEEP LOG", icon: "list.bullet", tint: Theme.sleep,
                   isEmpty: connectivity.sleepLog.isEmpty,
                   emptyText: "No sleep logged yet.") {
            ForEach(connectivity.sleepLog) { sl in
                LogRow(icon: "moon.zzz.fill",
                       tint: Theme.sleep,
                       title: sl.durationShort,
                       subtitle: sl.endedAt != nil ? "until \(sl.endedAt!.logStamp)" : nil,
                       time: sl.startedAt.logStamp)
            }
        }
    }

    private var moon: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.sleep.opacity(0.45), .clear],
                                     center: .center, startRadius: 2, endRadius: 36))
                .frame(width: 72, height: 72)
                .scaleEffect(pulse ? 1.12 : 0.92)
                .opacity(isSleeping ? 1 : 0.5)
            Image(systemName: isSleeping ? "moon.zzz.fill" : "moon.stars.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.gradient(Theme.sleep))
                .shadow(color: Theme.sleep.opacity(0.6), radius: 8)
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    private func toggle() {
        if isSleeping {
            connectivity.send(action: .sleepStop)
            optimisticStart = nil
            Haptics.stop()
        } else {
            connectivity.send(action: .sleepStart)
            optimisticStart = Date()
            Haptics.start()
            startPulse()
        }
    }
}

#Preview {
    SleepPage().environmentObject(ConnectivityService.shared)
}
