import SwiftUI

/// Accent colours of the Focus timer's phases.
enum DockAccent {
    static let blue = Color(red: 0.31, green: 0.66, blue: 1.00)
    static let green = Color(red: 0.30, green: 0.85, blue: 0.53)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.24)
}

/// Smooth line through a series of values, used by the chart tiles.
struct Sparkline: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let range = max(high - low, 0.0001)
        let step = rect.width / CGFloat(values.count - 1)

        var points: [CGPoint] = []
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * step
            let normalized = CGFloat((value - low) / range)
            points.append(CGPoint(x: x, y: rect.maxY - normalized * rect.height))
        }

        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: midpoint, control: previous)
            path.addQuadCurve(to: current, control: midpoint)
        }
        return path
    }
}
