import SwiftUI

/// Draws the same scene marks used by the Android widget from its 24-point vector definitions.
struct AndroidSceneMark: View {
    let sceneID: String
    var color: Color = .white

    static func supports(_ sceneID: String) -> Bool {
        [
            "scene_all_off", "scene_close", "scene_off", "scene_focus",
            "scene_concentrate", "scene_true_colors", "scene_cozy",
            "scene_relax", "scene_sleep"
        ].contains(sceneID)
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            let offset = CGPoint(
                x: (size.width - 24 * scale) / 2,
                y: (size.height - 24 * scale) / 2
            )
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: offset.x + x * scale, y: offset.y + y * scale)
            }
            func ellipse(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
                CGRect(x: point(x, y).x, y: point(x, y).y, width: width * scale, height: height * scale)
            }
            func stroke(_ path: Path, width: Double = 1.6) {
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round)
                )
            }

            switch sceneID {
            case "scene_focus":
                var corners = Path()
                corners.move(to: point(4, 9)); corners.addLine(to: point(4, 5)); corners.addLine(to: point(9, 5))
                corners.move(to: point(15, 5)); corners.addLine(to: point(20, 5)); corners.addLine(to: point(20, 9))
                corners.move(to: point(20, 15)); corners.addLine(to: point(20, 19)); corners.addLine(to: point(15, 19))
                corners.move(to: point(9, 19)); corners.addLine(to: point(4, 19)); corners.addLine(to: point(4, 15))
                stroke(corners, width: 1.8)
                stroke(Path(ellipseIn: ellipse(7.5, 7.5, 9, 9)))
                context.fill(Path(ellipseIn: ellipse(10.2, 10.2, 3.6, 3.6)), with: .color(color))

            case "scene_concentrate":
                stroke(Path(ellipseIn: ellipse(4, 4, 16, 16)), width: 1.5)
                stroke(Path(ellipseIn: ellipse(7.5, 7.5, 9, 9)), width: 1.5)
                context.fill(Path(ellipseIn: ellipse(9.8, 9.8, 4.4, 4.4)), with: .color(color))
                var rays = Path()
                rays.move(to: point(12, 2)); rays.addLine(to: point(12, 4))
                rays.move(to: point(12, 20)); rays.addLine(to: point(12, 22))
                rays.move(to: point(2, 12)); rays.addLine(to: point(4, 12))
                rays.move(to: point(20, 12)); rays.addLine(to: point(22, 12))
                stroke(rays, width: 1.5)

            case "scene_cozy":
                var steam = Path()
                steam.move(to: point(8, 8)); steam.addCurve(to: point(8.2, 4.2), control1: point(6.8, 6.7), control2: point(8.5, 5.7))
                steam.move(to: point(12, 8)); steam.addCurve(to: point(12.2, 4.2), control1: point(10.8, 6.7), control2: point(12.5, 5.7))
                stroke(steam, width: 1.5)
                var cup = Path()
                cup.move(to: point(4, 9)); cup.addLine(to: point(17, 9)); cup.addLine(to: point(17, 15.2))
                cup.addCurve(to: point(11.2, 21), control1: point(17, 18.4), control2: point(14.4, 21))
                cup.addLine(to: point(9.8, 21)); cup.addCurve(to: point(4, 15.2), control1: point(6.6, 21), control2: point(4, 18.4)); cup.closeSubpath()
                context.fill(cup, with: .color(color))
                var handle = Path()
                handle.move(to: point(17, 11)); handle.addLine(to: point(19, 11))
                handle.addCurve(to: point(19, 16), control1: point(21.7, 11), control2: point(21.7, 16))
                handle.addLine(to: point(17, 16))
                handle.move(to: point(3, 22)); handle.addLine(to: point(19, 22))
                stroke(handle, width: 1.7)

            case "scene_relax":
                var leaves = Path()
                leaves.move(to: point(12, 3)); leaves.addCurve(to: point(12, 13), control1: point(9.3, 6), control2: point(9.2, 10.1)); leaves.addCurve(to: point(12, 3), control1: point(14.8, 10.1), control2: point(14.7, 6))
                leaves.move(to: point(4, 8)); leaves.addCurve(to: point(12, 18), control1: point(4.2, 13.5), control2: point(7.1, 17)); leaves.addCurve(to: point(4, 8), control1: point(11.3, 13.3), control2: point(8.5, 9.6))
                leaves.move(to: point(20, 8)); leaves.addCurve(to: point(12, 18), control1: point(19.8, 13.5), control2: point(16.9, 17)); leaves.addCurve(to: point(20, 8), control1: point(12.7, 13.3), control2: point(15.5, 9.6))
                leaves.move(to: point(5, 19)); leaves.addCurve(to: point(19, 19), control1: point(8.8, 21.4), control2: point(15.2, 21.4))
                stroke(leaves)

            case "scene_sleep":
                var moon = Path()
                moon.move(to: point(14.8, 3.2))
                moon.addCurve(to: point(8.4, 11.3), control1: point(11.1, 4.1), control2: point(8.4, 7.4))
                moon.addCurve(to: point(16.7, 19.6), control1: point(8.4, 15.9), control2: point(12.1, 19.6))
                moon.addCurve(to: point(20.5, 18.7), control1: point(18.1, 19.6), control2: point(19.4, 19.3))
                moon.addCurve(to: point(13.6, 22), control1: point(18.9, 20.7), control2: point(16.4, 22))
                moon.addCurve(to: point(5, 13.4), control1: point(8.8, 22), control2: point(5, 18.2))
                moon.addCurve(to: point(13.3, 4.8), control1: point(5, 8.7), control2: point(8.7, 4.9))
                moon.closeSubpath()
                context.fill(moon, with: .color(color))
                drawDiamond(context: &context, center: point(18, 5), radius: 2 * scale, color: color)
                drawDiamond(context: &context, center: point(21, 9), radius: scale, color: color)

            case "scene_true_colors":
                var palette = Path()
                palette.move(to: point(12, 3)); palette.addCurve(to: point(2, 11.5), control1: point(6.48, 3), control2: point(2, 6.81))
                palette.addCurve(to: point(10, 19), control1: point(2, 15.64), control2: point(5.58, 19))
                palette.addLine(to: point(11.6, 19)); palette.addCurve(to: point(12.44, 17.5), control1: point(12.37, 19), control2: point(12.84, 18.16))
                palette.addCurve(to: point(14.24, 14.3), control1: point(11.58, 16.09), control2: point(12.59, 14.3))
                palette.addLine(to: point(16, 14.3)); palette.addCurve(to: point(22, 8.65), control1: point(19.31, 14.3), control2: point(22, 11.77))
                palette.addCurve(to: point(12, 3), control1: point(22, 5.53), control2: point(17.52, 3)); palette.closeSubpath()
                context.fill(palette, with: .color(color))
                for (x, y) in [(6.5, 10.5), (9.0, 6.0), (14.0, 5.5), (18.0, 8.5)] {
                    context.fill(Path(ellipseIn: ellipse(x - 1.5, y - 1.5, 3, 3)), with: .color(.white.opacity(0.82)))
                }

            default:
                var power = Path()
                power.move(to: point(12, 2)); power.addLine(to: point(12, 12))
                stroke(power, width: 2)
                var arc = Path()
                arc.move(to: point(7.59, 6.58))
                arc.addCurve(to: point(3, 12), control1: point(4.23, 8.82), control2: point(3, 10.06))
                arc.addCurve(to: point(12, 21), control1: point(3, 16.97), control2: point(7.03, 21))
                arc.addCurve(to: point(21, 12), control1: point(16.97, 21), control2: point(21, 16.97))
                arc.addCurve(to: point(16.41, 6.58), control1: point(21, 10.06), control2: point(19.77, 8.82))
                stroke(arc, width: 2)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawDiamond(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }
}
