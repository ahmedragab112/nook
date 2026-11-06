import SwiftUI

/// The notch silhouette: flush with the top of the screen, rounded bottom corners.
/// A positive `topRadius` rounds all four corners so the pill can detach and
/// float below the menu bar.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var flare: CGFloat = 0
    var topRadius: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, flare) }
        set { bottomRadius = newValue.first; flare = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2)
        let tr = min(max(topRadius, 0), min(rect.width / 4, rect.height / 2))
        let f = min(max(flare, 0), rect.width / 4)

        if f <= 0.5 {
            // Detached or standard pill: square (tr = 0) or fully rounded top.
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + tr, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
            if tr > 0.5 {
                p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr),
                               control: CGPoint(x: rect.maxX, y: rect.minY))
            }
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                           control: CGPoint(x: rect.maxX - r * 0.18, y: rect.maxY - r * 0.18))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                           control: CGPoint(x: rect.minX + r * 0.18, y: rect.maxY - r * 0.18))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tr))
            if tr > 0.5 {
                p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY),
                               control: CGPoint(x: rect.minX, y: rect.minY))
            }
            p.closeSubpath()
            return p
        }

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // concave "armpit" so the panel grows out of the screen edge smoothly
        p.addLine(to: CGPoint(x: rect.minX + f, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + f),
                       control: CGPoint(x: rect.minX + f * 0.45, y: rect.minY + f * 0.45))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                       control: CGPoint(x: rect.minX + r * 0.18, y: rect.maxY - r * 0.18))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                       control: CGPoint(x: rect.maxX - r * 0.18, y: rect.maxY - r * 0.18))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - f, y: rect.minY),
                       control: CGPoint(x: rect.maxX - f * 0.45, y: rect.minY + f * 0.45))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
