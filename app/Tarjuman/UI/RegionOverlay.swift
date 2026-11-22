// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI

/// Dashed box over the preview showing where text is read.
/// In editing mode, dragging draws a new box.
struct RegionOverlay: View {
    @Binding var region: CGRect // normalized, origin top-left
    var editing: Bool
    @State private var dragStart: CGPoint?
    @State private var draft: CGRect?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let shown = draft ?? region
            ZStack(alignment: .topLeading) {
                if editing {
                    Color.black.opacity(0.35)
                    Text("اسحب بإصبعك على مكان الحوار")
                        .font(.caption.weight(.semibold))
                        .padding(6)
                        .background(.black.opacity(0.6), in: Capsule())
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(editing ? 0.15 : 0.04)))
                    .frame(width: shown.width * size.width, height: shown.height * size.height)
                    .offset(x: shown.minX * size.width, y: shown.minY * size.height)
            }
            .contentShape(Rectangle())
            .gesture(drag(in: size), including: editing ? .all : .none)
        }
        .allowsHitTesting(editing)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let start = dragStart ?? v.startLocation
                dragStart = start
                draft = normalized(from: start, to: v.location, in: size)
            }
            .onEnded { v in
                if let d = draft, d.width > 0.05, d.height > 0.04 { region = d }
                draft = nil
                dragStart = nil
            }
    }

    private func normalized(from a: CGPoint, to b: CGPoint, in size: CGSize) -> CGRect {
        func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
        let x0 = clamp(min(a.x, b.x) / size.width), x1 = clamp(max(a.x, b.x) / size.width)
        let y0 = clamp(min(a.y, b.y) / size.height), y1 = clamp(max(a.y, b.y) / size.height)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
