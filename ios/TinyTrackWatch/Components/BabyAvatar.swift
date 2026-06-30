import SwiftUI

/// Circular baby avatar. Loads the public photo URL sent by the phone; falls back
/// to a clean monogram on the brand gradient when there's no photo yet.
struct BabyAvatar: View {
    var photoUrl: String?
    var initials: String
    var diameter: CGFloat = 58

    var body: some View {
        avatar
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .overlay(Circle().strokeBorder(Theme.brand.opacity(0.55), lineWidth: 2).blur(radius: 0.5))
            .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = photoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    monogram
                case .empty:
                    ZStack { monogram; ProgressView().tint(.white.opacity(0.7)) }
                @unknown default:
                    monogram
                }
            }
        } else {
            monogram
        }
    }

    private var monogram: some View {
        ZStack {
            Theme.gradient(Theme.brand)
            Text(initials.isEmpty ? "•" : initials)
                .font(.system(size: diameter * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
