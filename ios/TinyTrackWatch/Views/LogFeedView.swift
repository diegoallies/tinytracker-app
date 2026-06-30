import SwiftUI

/// Screen 2 — Log Feed. Amount is dialled with the Digital Crown (0–300ml, step 10).
/// Sends `["action": "logFeed", "type": "bottle", "amountMl": <Int>]`.
struct LogFeedView: View {
    @EnvironmentObject private var connectivity: ConnectivityService
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double = 150
    @State private var saved = false
    @FocusState private var crownFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                amountDial

                Button(action: confirm) {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.feed))
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
        .savedFlash($saved)
        .onAppear { crownFocused = true }
    }

    private var amountDial: some View {
        VStack(spacing: 2) {
            Text("\(Int(amount))")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .foregroundStyle(Theme.feed)
            Text("ml · turn the crown")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Theme.feed.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .focusable(true)
        .focused($crownFocused)
        .digitalCrownRotation(
            $amount,
            from: 0, through: 300, by: 10,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .animation(.snappy, value: amount)
    }

    private func confirm() {
        connectivity.send(action: .logFeed, extra: ["type": "bottle", "amountMl": Int(amount)])
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
    }
}

#Preview {
    NavigationStack { LogFeedView() }
        .environmentObject(ConnectivityService.shared)
}
