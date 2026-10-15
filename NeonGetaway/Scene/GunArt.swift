import UIKit
import GameCore

/// Side-profile weapon art drawn in code: shaded metal, polymer grips, sights, magazines and
/// stocks, so guns read as real objects instead of pixel blocks. All designs are generic and
/// original. `finish` (the Workbench paint) tints the frame/furniture.
@MainActor
enum GunArt {
    private static var cache: [String: UIImage] = [:]

    /// Width:height of each drawing.
    static func aspect(_ w: WeaponID) -> CGFloat {
        switch w {
        case .bat: 4.6
        case .pistol: 1.55
        case .smg: 2.1
        case .shotgun: 4.4
        case .rifle: 3.6
        }
    }

    static func image(_ w: WeaponID, finish: Int = 0, height: CGFloat) -> UIImage {
        let key = "\(w.rawValue)|\(finish)|\(Int(height))"
        if let hit = cache[key] { return hit }
        let size = CGSize(width: (height * aspect(w)).rounded(), height: height.rounded())
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let g = ctx.cgContext
            // Draw in a 100-unit-tall space.
            let s = size.height / 100
            g.scaleBy(x: s, y: s)
            draw(w, finish: finish, g, width: size.width / s)
        }
        cache[key] = image
        return image
    }

    // MARK: Palette

    private static let gunmetal = UIColor(hex: 0x2A2E35)
    private static let steel = UIColor(hex: 0x4A505A)
    private static let edge = UIColor(hex: 0x0E1014)
    private static let polymer = UIColor(hex: 0x1B1D21)
    private static let shine = UIColor(white: 1, alpha: 0.22)

    private static func accent(_ finish: Int) -> UIColor {
        finish == 0 ? polymer : PixelArt.finishColors[max(0, min(finish, PixelArt.finishColors.count - 1))]
    }

    // MARK: Helpers

    private static func fill(_ g: CGContext, _ path: CGPath, _ color: UIColor, metal: Bool = false, line: CGFloat = 2.2) {
        g.saveGState()
        g.addPath(path)
        g.clip()
        let box = path.boundingBox
        if metal {
            // Top-lit metal: lighter above, darker below.
            let colors = [color.lighter(0.18).cgColor, color.cgColor, color.darker(0.25).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            g.drawLinearGradient(grad, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
        } else {
            g.setFillColor(color.cgColor)
            g.fill(box)
        }
        g.restoreGState()
        g.addPath(path)
        g.setStrokeColor(edge.cgColor)
        g.setLineWidth(line)
        g.setLineJoin(.round)
        g.strokePath()
    }

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 2) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
    }

    private static func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    private static func highlight(_ g: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
        g.setStrokeColor(shine.cgColor)
        g.setLineWidth(1.6)
        g.move(to: CGPoint(x: x, y: y))
        g.addLine(to: CGPoint(x: x + w, y: y))
        g.strokePath()
    }

    private static func lines(_ g: CGContext, from x: CGFloat, to x2: CGFloat, y: CGFloat, h: CGFloat, step: CGFloat) {
        g.setStrokeColor(UIColor(white: 0, alpha: 0.45).cgColor)
        g.setLineWidth(1.2)
        var cx = x
        while cx < x2 {
            g.move(to: CGPoint(x: cx, y: y))
            g.addLine(to: CGPoint(x: cx, y: y + h))
            cx += step
        }
        g.strokePath()
    }

    private static func trigger(_ g: CGContext, x: CGFloat, y: CGFloat, size: CGFloat) {
        // Guard loop and the trigger blade.
        let guardPath = CGMutablePath()
        guardPath.addArc(center: CGPoint(x: x, y: y), radius: size, startAngle: 0, endAngle: .pi, clockwise: false)
        g.addPath(guardPath)
        g.setStrokeColor(edge.cgColor)
        g.setLineWidth(3)
        g.strokePath()
        g.move(to: CGPoint(x: x + size * 0.15, y: y - size * 0.1))
        g.addQuadCurve(to: CGPoint(x: x - size * 0.2, y: y + size * 0.75), control: CGPoint(x: x + size * 0.25, y: y + size * 0.5))
        g.setLineWidth(2.6)
        g.strokePath()
    }

    // MARK: Drawings

    private static func draw(_ w: WeaponID, finish: Int, _ g: CGContext, width W: CGFloat) {
        let furniture = accent(finish)
        switch w {
        case .pistol:
            // Slide over a frame, angled grip with texture, front and rear sights.
            fill(g, poly([(18, 54), (60, 54), (66, 60), (58, 96), (34, 96), (36, 64), (20, 64)]), furniture)
            lines(g, from: 42, to: 58, y: 70, h: 20, step: 3.2)
            fill(g, rect(10, 28, 138, 27, r: 3), gunmetal, metal: true)       // slide
            fill(g, rect(140, 40, 12, 10, r: 1.5), steel, metal: true)         // muzzle/barrel tip
            lines(g, from: 18, to: 40, y: 32, h: 18, step: 4)                  // rear serrations
            fill(g, rect(70, 33, 26, 9, r: 1.5), edge)                         // ejection port
            fill(g, rect(16, 21, 9, 8, r: 1), edge)                            // rear sight
            fill(g, rect(132, 22, 6, 7, r: 1), edge)                           // front sight
            fill(g, rect(60, 54, 80, 9, r: 2), furniture)                      // dust cover / rail
            highlight(g, 14, 31, 128)
            trigger(g, x: 72, y: 62, size: 13)
        case .smg:
            fill(g, poly([(6, 42), (40, 40), (44, 58), (8, 72)]), furniture)                 // folding stock
            fill(g, rect(38, 30, 120, 32, r: 3), gunmetal, metal: true)                      // receiver
            fill(g, rect(156, 40, 44, 12, r: 2), steel, metal: true)                         // barrel shroud
            fill(g, rect(196, 43, 10, 6, r: 1), edge)
            fill(g, poly([(98, 60), (114, 60), (120, 99), (104, 100)]), polymer)              // magazine
            fill(g, poly([(62, 60), (84, 60), (80, 92), (60, 92)]), furniture)                // grip
            lines(g, from: 64, to: 80, y: 68, h: 18, step: 3)
            fill(g, rect(56, 23, 70, 8, r: 1.5), edge)                                       // top rail
            lines(g, from: 60, to: 124, y: 23, h: 8, step: 6)
            fill(g, rect(130, 52, 26, 18, r: 3), furniture)                                  // foregrip
            highlight(g, 42, 33, 112)
            trigger(g, x: 92, y: 66, size: 9)
        case .shotgun:
            fill(g, poly([(4, 40), (104, 36), (110, 62), (96, 66), (60, 62), (8, 80), (2, 72)]), furniture)  // stock
            fill(g, rect(100, 34, 100, 30, r: 3), gunmetal, metal: true)                     // receiver
            fill(g, rect(196, 36, 236, 12, r: 2), steel, metal: true)                        // barrel
            fill(g, rect(196, 50, 200, 10, r: 2), gunmetal, metal: true)                     // tube magazine
            fill(g, rect(250, 46, 84, 20, r: 4), furniture)                                  // pump
            lines(g, from: 256, to: 330, y: 49, h: 14, step: 5)
            fill(g, rect(424, 31, 6, 6, r: 1), Palette.UI.sunset)                            // bead sight
            fill(g, rect(130, 40, 30, 8, r: 1.5), edge)                                      // loading port
            highlight(g, 104, 38, 92)
            highlight(g, 200, 39, 228)
            trigger(g, x: 144, y: 66, size: 10)
        case .rifle:
            fill(g, poly([(4, 34), (62, 36), (64, 60), (8, 74), (2, 66)]), furniture)        // stock
            fill(g, rect(58, 30, 116, 30, r: 3), gunmetal, metal: true)                      // receiver
            fill(g, rect(170, 32, 120, 24, r: 3), furniture)                                 // handguard
            lines(g, from: 178, to: 284, y: 36, h: 16, step: 7)
            fill(g, rect(286, 40, 60, 9, r: 2), steel, metal: true)                          // barrel
            fill(g, rect(342, 37, 12, 15, r: 2), edge)                                       // muzzle brake
            fill(g, rect(70, 20, 210, 9, r: 1.5), edge)                                      // top rail
            lines(g, from: 74, to: 276, y: 20, h: 9, step: 7)
            fill(g, rect(100, 6, 54, 15, r: 7), polymer)                                     // optic
            fill(g, CGPath(ellipseIn: CGRect(x: 102, y: 8, width: 11, height: 11), transform: nil), UIColor(hex: 0x4FB3FF).withAlphaComponent(0.8))
            fill(g, poly([(126, 58), (146, 58), (156, 98), (136, 100)]), polymer)            // curved magazine
            fill(g, poly([(84, 58), (104, 58), (98, 92), (80, 90)]), furniture)              // grip
            highlight(g, 62, 33, 108)
            trigger(g, x: 116, y: 64, size: 9)
        case .bat:
            let bat = CGMutablePath()
            bat.move(to: CGPoint(x: 8, y: 44))
            bat.addLine(to: CGPoint(x: 150, y: 40))
            bat.addQuadCurve(to: CGPoint(x: W - 10, y: 30), control: CGPoint(x: 300, y: 26))
            bat.addQuadCurve(to: CGPoint(x: W - 10, y: 70), control: CGPoint(x: W + 4, y: 50))
            bat.addQuadCurve(to: CGPoint(x: 150, y: 60), control: CGPoint(x: 300, y: 74))
            bat.addLine(to: CGPoint(x: 8, y: 56))
            bat.closeSubpath()
            fill(g, bat, finish == 0 ? UIColor(hex: 0xB9834A) : furniture, metal: true)
            fill(g, rect(4, 40, 12, 20, r: 4), edge)                                          // knob
            fill(g, rect(16, 42, 90, 16, r: 3), UIColor(hex: 0x1B1D21))                      // grip tape
            lines(g, from: 22, to: 104, y: 43, h: 14, step: 6)
            highlight(g, 160, 40, W - 190)
        }
    }
}

extension UIColor {
    func lighter(_ amount: CGFloat) -> UIColor { mix(with: .white, amount) }
    func darker(_ amount: CGFloat) -> UIColor { mix(with: .black, amount) }
    private func mix(with other: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1)
    }
}
