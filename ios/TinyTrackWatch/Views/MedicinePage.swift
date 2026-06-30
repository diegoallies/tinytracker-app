import SwiftUI

/// Full-screen Medicine page. One glass card per scheduled med (sent from the
/// phone); tapping marks it given. Empty state when none are scheduled.
struct MedicinePage: View {
    @EnvironmentObject private var connectivity: ConnectivityService
    @State private var givenNames: Set<String> = []

    var body: some View {
        // Header sits at the top of the stack; content flows beneath it. Same
        // clean pattern as the other pages (no overlapping/floating header).
        VStack(spacing: 8) {
            header

            if connectivity.scheduledMeds.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Image(systemName: "pills")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.medicine.opacity(0.8))
                    Text("No meds scheduled")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Schedule medicine in the\nTinyTrack iPhone app.")
                        .font(.system(size: 12, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 9) {
                        ForEach(connectivity.scheduledMeds, id: \.self) { name in
                            medCard(name)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .screenBackground(Theme.medicine)
    }

    private var header: some View {
        PageHeader(icon: "pills.fill", title: "MEDICINE", tint: Theme.medicine)
    }

    private func medCard(_ name: String) -> some View {
        let isGiven = givenNames.contains(name)
        return Button {
            give(name)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.gradient(isGiven ? .green : Theme.medicine))
                        .frame(width: 34, height: 34)
                        .shadow(color: (isGiven ? Color.green : Theme.medicine).opacity(0.5), radius: 5, y: 2)
                    Image(systemName: isGiven ? "checkmark" : "pills.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(name)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(isGiven ? "Given" : "Tap")
                    .font(.system(size: 12, design: .rounded).weight(.medium))
                    .foregroundStyle((isGiven ? Color.green : Theme.medicine))
            }
            .padding(11)
            .glassCard(20, tint: isGiven ? .green : Theme.medicine)
        }
        .buttonStyle(.plain)
        .disabled(isGiven)
    }

    private func give(_ name: String) {
        connectivity.send(action: .logMed, extra: ["name": name])
        Haptics.success()
        givenNames.insert(name)
    }
}

#Preview {
    MedicinePage().environmentObject(ConnectivityService.shared)
}
