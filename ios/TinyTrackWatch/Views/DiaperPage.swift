import SwiftUI

/// Full-screen Diaper page. Three definitive icon buttons — Wet / Dirty / Both —
/// logged inline with a haptic + "Saved" flash. No drill-down.
struct DiaperPage: View {
    @EnvironmentObject private var connectivity: ConnectivityService
    @State private var saved = false

    var body: some View {
        TabView {
            main
            logView
        }
        .tabViewStyle(.page)
    }

    private var main: some View {
        VStack(spacing: 10) {
            PageHeader(icon: "drop.fill", title: "DIAPER", tint: Theme.diaper)

            Spacer(minLength: 0)
            HStack(spacing: 10) {
                ForEach(DiaperKind.allCases) { kind in
                    Button { log(kind) } label: {
                        choice(kind)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Tap to log a change")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground(Theme.diaper)
        .savedFlash($saved)
    }

    private var logView: some View {
        HistoryLog(title: "DIAPER LOG", icon: "list.bullet", tint: Theme.diaper,
                   isEmpty: connectivity.diaperLog.isEmpty,
                   emptyText: "No diapers logged yet.") {
            ForEach(connectivity.diaperLog) { d in
                let kind = DiaperKind(rawValue: d.type)
                LogRow(icon: kind?.symbol ?? "drop.fill",
                       tint: Theme.diaper,
                       title: kind?.label ?? d.type.capitalized,
                       subtitle: nil,
                       time: d.loggedAt.logStamp)
            }
        }
    }

    private func choice(_ kind: DiaperKind) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Theme.gradient(Theme.diaper))
                    .frame(width: 52, height: 52)
                    .shadow(color: Theme.diaper.opacity(0.5), radius: 6, y: 2)
                Image(systemName: kind.symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(kind.label)
                .font(.system(size: 13, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private func log(_ kind: DiaperKind) {
        connectivity.send(action: .logDiaper, extra: ["type": kind.rawValue])
        Haptics.success()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { saved = false }
    }
}

#Preview {
    DiaperPage().environmentObject(ConnectivityService.shared)
}
