import SwiftUI

/// Optimistic "Saved ✓" confirmation. Show it for ~0.9s after a log is sent,
/// regardless of whether the phone is reachable (logs queue offline).
struct SavedOverlay: View {
    var text: String = "Saved"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.green)
            Text(text)
                .font(.headline)
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

/// View modifier that flashes `SavedOverlay` while `isPresented` is true.
struct SavedFlash: ViewModifier {
    @Binding var isPresented: Bool
    var text: String = "Saved"

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                SavedOverlay(text: text)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPresented)
    }
}

extension View {
    func savedFlash(_ isPresented: Binding<Bool>, text: String = "Saved") -> some View {
        modifier(SavedFlash(isPresented: isPresented, text: text))
    }
}
