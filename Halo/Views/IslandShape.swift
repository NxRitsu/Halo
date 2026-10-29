import SwiftUI

/// Island outline: rounded bottom corners and concave "ears" that blend into the top edge of the screen.
struct IslandShape: Shape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, bottomRadius) }
        set {
            earRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let ear = min(earRadius, rect.width / 4, rect.height / 2)
        let left = rect.minX + ear
        let right = rect.maxX - ear
        let bottom = min(bottomRadius, (right - left) / 2, rect.height - ear)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + ear), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: left + bottom, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - bottom), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
