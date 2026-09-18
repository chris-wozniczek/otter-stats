import SwiftUI
import AppKit

/// SwiftUI recreation of otter-swarm-website/assets/logo.svg (64x64 viewBox).
struct OtterLogo: View {
    var size: CGFloat = 64

    private var s: CGFloat { size / 64 }

    var body: some View {
        Canvas { ctx, _ in
            let grad = Gradient(colors: [Theme.cyan, Theme.teal])
            let shading = GraphicsContext.Shading.linearGradient(grad, startPoint: p(9.5, 6), endPoint: p(54.5, 58))

            var spokes = Path()
            for (a, b) in [((32, 9.4), (32, 16.6)), ((51.5, 20.8), (45.2, 24.4)), ((51.5, 43.2), (45.2, 39.6)),
                           ((32, 54.6), (32, 47.4)), ((12.5, 43.2), (18.8, 39.6)), ((12.5, 20.8), (18.8, 24.4))] {
                spokes.move(to: p(a.0, a.1)); spokes.addLine(to: p(b.0, b.1))
            }
            ctx.stroke(spokes, with: .color(Theme.cyan.opacity(0.35)), lineWidth: 1 * s)

            var ring = Path()
            ring.move(to: p(32, 6))
            let corners: [(Double, Double)] = [(54.5, 19), (54.5, 45), (32, 58), (9.5, 45), (9.5, 19)]
            for pt in corners { ring.addLine(to: p(pt.0, pt.1)) }
            ring.closeSubpath()
            ctx.stroke(ring, with: shading, style: StrokeStyle(lineWidth: 2.5 * s, lineJoin: .round))

            ctx.fill(circle(20.6, 25.2, 3.4), with: .color(Color(hex: 0xD5DEEA)))
            ctx.fill(circle(43.4, 25.2, 3.4), with: .color(Color(hex: 0xD5DEEA)))
            ctx.fill(ellipse(32, 33, 14.2, 12.2), with: .color(Color(hex: 0xE8EEF8)))
            ctx.fill(ellipse(32, 38.6, 8.4, 5.8), with: .color(Color(hex: 0xC9D4E3)))
            ctx.fill(ellipse(32, 36.2, 2.7, 1.9), with: .color(Theme.amber))

            var mouth = Path()
            mouth.move(to: p(29.6, 39.4))
            mouth.addQuadCurve(to: p(34.4, 39.4), control: p(32, 41.4))
            ctx.stroke(mouth, with: .color(Color(hex: 0x33405C)), style: StrokeStyle(lineWidth: 1.1 * s, lineCap: .round))

            ctx.fill(ellipse(26.6, 30.8, 1.5, 1.9), with: .color(Theme.surface))
            ctx.fill(ellipse(37.4, 30.8, 1.5, 1.9), with: .color(Theme.surface))
            ctx.fill(circle(27.1, 30.2, 0.5), with: .color(.white))
            ctx.fill(circle(37.9, 30.2, 0.5), with: .color(.white))

            var whiskers = Path()
            for (a, b) in [((23.5, 37.2), (15.5, 35.6)), ((23.5, 38.8), (15, 38.8)), ((23.5, 40.4), (15.5, 42.2)),
                           ((40.5, 37.2), (48.5, 35.6)), ((40.5, 38.8), (49, 38.8)), ((40.5, 40.4), (48.5, 42.2))] {
                whiskers.move(to: p(a.0, a.1)); whiskers.addLine(to: p(b.0, b.1))
            }
            ctx.stroke(whiskers, with: .color(Color(hex: 0x9FB0C8).opacity(0.85)), style: StrokeStyle(lineWidth: 1 * s, lineCap: .round))

            for pt in [(32, 6)] + corners {
                ctx.fill(circle(CGFloat(pt.0), CGFloat(pt.1), 3), with: shading)
            }
        }
        .frame(width: size, height: size)
    }

    private func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    private func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: (cx - r) * s, y: (cy - r) * s, width: 2 * r * s, height: 2 * r * s))
    }
    private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: (cx - rx) * s, y: (cy - ry) * s, width: 2 * rx * s, height: 2 * ry * s))
    }
}

/// Monochrome template glyph for the status bar: hex ring + otter silhouette.
enum MenuBarGlyph {
    static func image(pointSize: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
            let s = rect.width / 64
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let ring = NSBezierPath()
            ring.move(to: pt(32, 6))
            for p in [(54.5, 19), (54.5, 45), (32, 58), (9.5, 45), (9.5, 19)] as [(CGFloat, CGFloat)] { ring.line(to: pt(p.0, p.1)) }
            ring.close()
            ring.lineWidth = 5 * s
            ring.lineJoinStyle = .round
            ring.stroke()

            for p in [(32, 6), (54.5, 19), (54.5, 45), (32, 58), (9.5, 45), (9.5, 19)] as [(CGFloat, CGFloat)] {
                NSBezierPath(ovalIn: NSRect(x: (p.0 - 4.5) * s, y: (p.1 - 4.5) * s, width: 9 * s, height: 9 * s)).fill()
            }

            NSBezierPath(ovalIn: NSRect(x: (20.6 - 4) * s, y: (25.2 - 4) * s, width: 8 * s, height: 8 * s)).fill()
            NSBezierPath(ovalIn: NSRect(x: (43.4 - 4) * s, y: (25.2 - 4) * s, width: 8 * s, height: 8 * s)).fill()
            NSBezierPath(ovalIn: NSRect(x: (32 - 14.2) * s, y: (33 - 12.2) * s, width: 28.4 * s, height: 24.4 * s)).fill()

            NSColor.clear.setFill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: (26.6 - 2.4) * s, y: (30.8 - 3) * s, width: 4.8 * s, height: 6 * s)).fill()
            NSBezierPath(ovalIn: NSRect(x: (37.4 - 2.4) * s, y: (30.8 - 3) * s, width: 4.8 * s, height: 6 * s)).fill()
            NSBezierPath(ovalIn: NSRect(x: (32 - 3.4) * s, y: (36.4 - 2.6) * s, width: 6.8 * s, height: 5.2 * s)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
