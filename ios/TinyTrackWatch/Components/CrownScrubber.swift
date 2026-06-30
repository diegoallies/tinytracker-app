import SwiftUI

/// Vertical segmented level indicator for the trailing edge. The top `progress`
/// fraction of segments fill with the accent gradient; the boundary segment is
/// widened and glows to mark the current position.
struct CrownScrubber: View {
    /// 0...1 fill fraction.
    var progress: Double
    var tint: Color
    var segments: Int = 16

    private var activeCount: Int {
        max(0, min(segments, Int((progress * Double(segments)).rounded())))
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<segments, id: \.self) { i in
                // i = 0 is the top segment → represents the highest value.
                let isOn   = i >= (segments - activeCount)
                let isEdge = i == (segments - activeCount) && activeCount < segments
                Capsule(style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Theme.gradient(tint))
                               : AnyShapeStyle(Color.white.opacity(0.13)))
                    .frame(width: isEdge ? 8 : 4, height: 5)
                    .shadow(color: isEdge ? tint.opacity(0.8) : .clear, radius: 4)
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.snappy(duration: 0.16), value: activeCount)
    }
}
