import SwiftUI

/// Screen 5 — Medicine. One "Given" button per scheduled med name (sent from the phone as
/// `"scheduledMeds": ["Panado", "Vitamin D"]`). Tapping sends
/// `["action": "logMed", "name": "<med name>"]`.
struct MedicineView: View {
    @EnvironmentObject private var connectivity: ConnectivityService
    @State private var givenNames: Set<String> = []

    var body: some View {
        Group {
            if connectivity.scheduledMeds.isEmpty {
                ContentUnavailableView("No meds scheduled",
                                       systemImage: "pills",
                                       description: Text("Schedule medicine in the TinyTrack iPhone app."))
            } else {
                List(connectivity.scheduledMeds, id: \.self) { name in
                    medRow(name)
                }
            }
        }
        .navigationTitle("Medicine")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func medRow(_ name: String) -> some View {
        let isGiven = givenNames.contains(name)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "pills.fill").foregroundStyle(Theme.medicine)
                Text(name).font(.headline)
                Spacer()
            }
            Button {
                give(name)
            } label: {
                Label(isGiven ? "Given" : "Mark given",
                      systemImage: isGiven ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(PrimaryButtonStyle(tint: isGiven ? .green : Theme.medicine))
            .disabled(isGiven)
        }
        .padding(.vertical, 4)
    }

    private func give(_ name: String) {
        connectivity.send(action: .logMed, extra: ["name": name])
        givenNames.insert(name)
    }
}

#Preview {
    NavigationStack { MedicineView() }
        .environmentObject(ConnectivityService.shared)
}
