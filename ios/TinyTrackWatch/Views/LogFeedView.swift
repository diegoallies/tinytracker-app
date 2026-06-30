import SwiftUI

/// Screen 2 — Log Feed. Amount is dialled with the Digital Crown (0–300ml, step 5),
/// shown as a circular progress ring with a segmented scrubber on the trailing edge.
/// Sends `["action": "logFeed", "type": "bottle", "amountMl": <Int>]`.
struct LogFeedView: View {
    @EnvironmentObject private var connectivity: ConnectivityService
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double = 150
    @State private var lastTick: Int = 15           // last 10ml step we buzzed on
    @State private var saved = false
    @FocusState private var crownFocused: Bool

    private let maxMl: Double = 300

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView {
                VStack(spacing: 16) {
                    ring
                    Button(action: confirm) {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.feed))
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }

            CrownScrubber(progress: amount / maxMl, tint: Theme.feed)
                .frame(width: 9)
                .padding(.trailing, 1)
        }
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground(Theme.feed)
        .savedFlash($saved)
        .focusable(true)
        .focused($crownFocused)
        .digitalCrownRotation(
            $amount,
            from: 0, through: maxMl, by: 5,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: amount) { _, newValue in
            let tick = Int(newValue / 10)
            if tick != lastTick {
                lastTick = tick
                Haptics.click()
            }
        }
        .onAppear { crownFocused = true }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 13)

            Circle()
                .trim(from: 0, to: max(0.001, amount / maxMl))
                .stroke(Theme.gradient(Theme.feed),
                        style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.feed.opacity(0.5), radius: 6)

            VStack(spacing: -2) {
                Text("\(Int(amount))")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(.white)
                Text("ml · turn crown")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 138, height: 138)
        .padding(.top, 6)
        .animation(.snappy(duration: 0.25), value: amount)
    }

    private func confirm() {
        connectivity.send(action: .logFeed, extra: ["type": "bottle", "amountMl": Int(amount)])
        Haptics.success()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
    }
}

#Preview {
    NavigationStack { LogFeedView() }
        .environmentObject(ConnectivityService.shared)
}
