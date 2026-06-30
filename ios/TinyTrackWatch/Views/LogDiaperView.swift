import SwiftUI

/// Screen 3 — Log Diaper. Three big buttons: Wet / Dirty / Both.
struct LogDiaperView: View {
    @EnvironmentObject private var connectivity: ConnectivityService
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(DiaperKind.allCases) { kind in
                    Button {
                        log(kind)
                    } label: {
                        BigActionButton(title: kind.label, systemImage: kind.symbol, tint: Theme.diaper)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Diaper")
        .navigationBarTitleDisplayMode(.inline)
        .savedFlash($saved)
    }

    private func log(_ kind: DiaperKind) {
        // ["action": "logDiaper", "type": "wet" | "dirty" | "both"]
        connectivity.send(action: .logDiaper, extra: ["type": kind.rawValue])
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
    }
}

#Preview {
    NavigationStack { LogDiaperView() }
        .environmentObject(ConnectivityService.shared)
}
