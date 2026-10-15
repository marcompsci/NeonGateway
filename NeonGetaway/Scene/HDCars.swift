import UIKit
import GameCore

/// Top-down art for the dealership, exclusive and legendary cars, one drawer per body style,
/// plus rims. Every design is original; brands are fictional.
extension HDArt {
    static func lineupSize(_ model: VehicleID) -> CGSize {
        switch CarLineup.style(model) {
        case .coupe: CGSize(width: 33, height: 56)
        case .muscle, .fastback: CGSize(width: 35, height: 60)
        case .luxury: CGSize(width: 35, height: 62)
        case .suv: CGSize(width: 37, height: 60)
        case .ev: CGSize(width: 34, height: 58)
        case .supercar, .wedge: CGSize(width: 36, height: 58)
        case .finned: CGSize(width: 36, height: 66)
        case .cruiserBike: CGSize(width: 17, height: 40)
        default: CGSize(width: 33.6, height: 57.6)
        }
    }

    static func lineupColor(_ model: VehicleID) -> UIColor {
        switch model {
        case .kestrel: color(0xF2F4F7)
        case .kestrelMidnight: color(0x1B1F3A)
        case .bruiser: color(0x2E6BE6)
        case .solace: color(0x1E2A36)
        case .summit: color(0x6E7F3A)
        case .arc: color(0xD8E6EE)
        case .razor: color(0xFFB000)
        case .razorNoir: color(0x15161A)
        case .vandal: color(0x7A1E22)
        case .stormhawk: color(0xC8341F)
        case .seabreeze: color(0x7FD3C8)
        case .ombra: color(0xE8E2D2)
        default: color(0xC9CED8)
        }
    }

    /// Accent trim per car: stripes, pinstripes, two-tone roofs.
    private static func trim(_ model: VehicleID) -> UIColor? {
        switch model {
        case .kestrelMidnight: color(0x8E6BFF)
        case .razorNoir: color(0xE2B13C)
        case .bruiser, .stormhawk: color(0xF4EBD9)
        case .seabreeze: color(0xF7F3EA)
        case .ombra: color(0x1A1C22)
        case .kestrel: color(0xE8314B)
        default: nil
        }
    }

    // MARK: Rims

    /// A wheel seen from above with the rim's colour showing between the tyre walls.
    static func rimWheel(_ g: CGContext, _ r: CGRect, rims: RimSetup?) {
        fill(g, rounded(r, 1.6), color(0x07080B))
        let face = r.insetBy(dx: r.width * 0.26, dy: r.height * 0.14)
        let c = rims.map { color(RimColors.hex[$0.color % RimColors.hex.count]) } ?? color(0x2A2D35)
        fill(g, rounded(face, 1), rims == nil ? c : c.darker(0.1))
        guard let rims, rims.style != .stock else { return }
        // Spoke ticks along the visible slice.
        let n = max(3, rims.style.spokes / 3)
        for i in 0..<n {
            let y = face.minY + face.height * (CGFloat(i) + 0.5) / CGFloat(n)
            fill(g, CGPath(rect: CGRect(x: face.minX, y: y - 0.25, width: face.width, height: 0.5), transform: nil),
                 UIColor(white: 0, alpha: 0.45))
        }
        fill(g, CGPath(rect: CGRect(x: face.minX, y: face.minY, width: face.width * 0.35, height: face.height), transform: nil),
             UIColor(white: 1, alpha: 0.3))
    }

    /// Big side-on rim for the garage's wheel picker.
    static func rimImage(_ rims: RimSetup, size: CGFloat) -> UIImage {
        render(CGSize(width: size, height: size)) { g in
            let c = CGPoint(x: size / 2, y: size / 2)
            let tyre = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 1, dy: 1)
            fill(g, CGPath(ellipseIn: tyre, transform: nil), color(0x0B0C0F))
            // Sidewall lettering ring.
            stroke(g, CGPath(ellipseIn: tyre.insetBy(dx: size * 0.07, dy: size * 0.07), transform: nil), color(0x2A2D35), size * 0.02)
            let rimR = size * 0.36
            let base = color(RimColors.hex[rims.color % RimColors.hex.count])
            let rimRect = CGRect(x: c.x - rimR, y: c.y - rimR, width: rimR * 2, height: rimR * 2)
            g.saveGState()
            g.addPath(CGPath(ellipseIn: rimRect, transform: nil))
            g.clip()
            linear(g, [base.lighter(0.35), base, base.darker(0.35)], [0, 0.5, 1],
                   from: CGPoint(x: rimRect.minX, y: rimRect.minY), to: CGPoint(x: rimRect.maxX, y: rimRect.maxY))
            g.restoreGState()
            let dark = base.darker(0.55)
            switch rims.style {
            case .stock:
                for i in 0..<8 {
                    let a = CGFloat(i) / 8 * 2 * .pi
                    let p = CGPoint(x: c.x + cos(a) * rimR * 0.62, y: c.y + sin(a) * rimR * 0.62)
                    fill(g, CGPath(ellipseIn: CGRect(x: p.x - rimR * 0.1, y: p.y - rimR * 0.1, width: rimR * 0.2, height: rimR * 0.2), transform: nil), dark)
                }
            case .deepDish:
                fill(g, CGPath(ellipseIn: rimRect.insetBy(dx: rimR * 0.18, dy: rimR * 0.18), transform: nil), dark.withAlphaComponent(0.55))
                spokes(g, c, inner: rimR * 0.18, outer: rimR * 0.82, count: 6, width: rimR * 0.16, color: base.lighter(0.15))
            case .turbofan:
                for i in 0..<12 {
                    let a = CGFloat(i) / 12 * 2 * .pi
                    let blade = CGMutablePath()
                    blade.move(to: CGPoint(x: c.x + cos(a) * rimR * 0.25, y: c.y + sin(a) * rimR * 0.25))
                    blade.addLine(to: CGPoint(x: c.x + cos(a) * rimR * 0.9, y: c.y + sin(a) * rimR * 0.9))
                    blade.addLine(to: CGPoint(x: c.x + cos(a + 0.35) * rimR * 0.9, y: c.y + sin(a + 0.35) * rimR * 0.9))
                    blade.closeSubpath()
                    fill(g, blade, dark)
                }
            default:
                let count = rims.style.spokes
                spokes(g, c, inner: rimR * 0.2, outer: rimR * 0.92, count: count,
                       width: rims.style == .wire ? rimR * 0.025 : rimR * (rims.style == .mesh ? 0.06 : 0.1), color: dark)
                if rims.style == .mesh {
                    stroke(g, CGPath(ellipseIn: rimRect.insetBy(dx: rimR * 0.4, dy: rimR * 0.4), transform: nil), dark, rimR * 0.05)
                }
            }
            stroke(g, CGPath(ellipseIn: rimRect, transform: nil), base.lighter(0.4), size * 0.015)
            // Centre cap and lug nuts.
            fill(g, CGPath(ellipseIn: CGRect(x: c.x - rimR * 0.18, y: c.y - rimR * 0.18, width: rimR * 0.36, height: rimR * 0.36), transform: nil), base.darker(0.2))
            for i in 0..<5 {
                let a = CGFloat(i) / 5 * 2 * .pi
                let p = CGPoint(x: c.x + cos(a) * rimR * 0.12, y: c.y + sin(a) * rimR * 0.12)
                fill(g, CGPath(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4), transform: nil), base.lighter(0.5))
            }
        }
    }

    private static func spokes(_ g: CGContext, _ c: CGPoint, inner: CGFloat, outer: CGFloat, count: Int, width: CGFloat, color: UIColor) {
        g.setStrokeColor(color.cgColor)
        g.setLineWidth(width)
        g.setLineCap(.round)
        for i in 0..<count {
            let a = CGFloat(i) / CGFloat(count) * 2 * .pi
            g.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
            g.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
        }
        g.strokePath()
    }

    // MARK: Cars

    static func drawLineup(_ g: CGContext, _ s: CGSize, model: VehicleID, design: PaintDesign?, rims: RimSetup?) {
        let style = CarLineup.style(model)
        if style == .cruiserBike {
            drawCruiserBike(g, s, model: model, design: design, rims: rims)
            return
        }
        let base = lineupColor(model)
        let accent = trim(model)
        // Proportions per style: where the windscreen and roof sit, how pointed the nose is.
        struct Shape { var nose: CGFloat; var tail: CGFloat; var waist: CGFloat; var glass0: CGFloat; var roof0: CGFloat; var roof1: CGFloat; var rear1: CGFloat }
        let shape: Shape = switch style {
        case .coupe: Shape(nose: 9, tail: 7, waist: 1.4, glass0: 0.3, roof0: 0.44, roof1: 0.62, rear1: 0.72)
        case .muscle: Shape(nose: 5, tail: 5, waist: 0.6, glass0: 0.36, roof0: 0.48, roof1: 0.66, rear1: 0.76)
        case .fastback: Shape(nose: 5, tail: 6, waist: 0.8, glass0: 0.38, roof0: 0.5, roof1: 0.62, rear1: 0.84)
        case .luxury: Shape(nose: 6, tail: 6, waist: 0.6, glass0: 0.3, roof0: 0.42, roof1: 0.68, rear1: 0.78)
        case .suv: Shape(nose: 4, tail: 3, waist: 0.3, glass0: 0.24, roof0: 0.34, roof1: 0.82, rear1: 0.88)
        case .ev: Shape(nose: 10, tail: 8, waist: 1, glass0: 0.28, roof0: 0.28, roof1: 0.74, rear1: 0.8)
        case .supercar: Shape(nose: 12, tail: 7, waist: 2.2, glass0: 0.38, roof0: 0.5, roof1: 0.62, rear1: 0.68)
        case .wedge: Shape(nose: 14, tail: 5, waist: 1.2, glass0: 0.4, roof0: 0.52, roof1: 0.64, rear1: 0.7)
        case .finned: Shape(nose: 6, tail: 3, waist: 0.4, glass0: 0.32, roof0: 0.42, roof1: 0.62, rear1: 0.7)
        default: Shape(nose: 7, tail: 6, waist: 0.8, glass0: 0.27, roof0: 0.4, roof1: 0.67, rear1: 0.77)
        }
        let wide = style == .supercar || style == .wedge
        let body = CGRect(x: wide ? 2.2 : 2.8, y: 1.4, width: s.width - (wide ? 4.4 : 5.6), height: s.height - 3)
        let wheelW: CGFloat = style == .suv ? 5 : (wide ? 4.6 : 4)
        let wheelH: CGFloat = style == .suv ? 11 : 10
        let front = s.height * (style == .finned ? 0.14 : 0.16), back = s.height * (style == .wedge ? 0.7 : 0.69)
        for (x, y): (CGFloat, CGFloat) in [(0.6, front), (s.width - wheelW - 0.6, front), (0.6, back), (s.width - wheelW - 0.6, back)] {
            rimWheel(g, CGRect(x: x, y: y, width: wheelW, height: wheelH), rims: rims)
        }

        var path = bodyPath(body, nose: shape.nose, tail: shape.tail, waist: shape.waist)
        if style == .finned {
            // Tail fins: the rear corners sweep out and back.
            let p = CGMutablePath()
            p.addPath(path)
            for side: CGFloat in [-1, 1] {
                let x = side < 0 ? body.minX : body.maxX
                let fin = CGMutablePath()
                fin.move(to: CGPoint(x: x, y: body.maxY - 16))
                fin.addLine(to: CGPoint(x: x + side * 1.6, y: body.maxY - 1))
                fin.addLine(to: CGPoint(x: x - side * 3, y: body.maxY - 2))
                fin.closeSubpath()
                p.addPath(fin)
            }
            path = p
        }
        paintBody(g, path, base: base, design: design)
        g.saveGState()
        g.addPath(path)
        g.clip()
        shadeBody(g, body, strength: model == .razorNoir ? 0.6 : 1)
        if design == nil, let accent {
            switch style {
            case .muscle, .fastback:
                // Twin stripes nose to tail.
                for x in [s.width / 2 - 4.6, s.width / 2 + 1.6] {
                    fill(g, CGPath(rect: CGRect(x: x, y: body.minY, width: 3, height: body.height), transform: nil), accent.withAlphaComponent(0.92))
                }
            case .supercar, .coupe:
                // Pinstripe down each flank.
                for x in [body.minX + 2.2, body.maxX - 2.8] {
                    fill(g, CGPath(rect: CGRect(x: x, y: body.minY + 6, width: 0.6, height: body.height - 12), transform: nil), accent)
                }
            case .wedge:
                // Two-tone: dark lower sides.
                for x in [body.minX, body.maxX - 3.2] {
                    fill(g, CGPath(rect: CGRect(x: x, y: body.minY, width: 3.2, height: body.height), transform: nil), accent.withAlphaComponent(0.9))
                }
            default: break
            }
        }
        let seam = UIColor(white: 0, alpha: 0.32)
        switch style {
        case .muscle, .fastback:
            // Hood scoop.
            fill(g, rounded(CGRect(x: s.width / 2 - 4, y: s.height * 0.12, width: 8, height: 9), 2), base.darker(0.35))
            fill(g, rounded(CGRect(x: s.width / 2 - 3, y: s.height * 0.12, width: 6, height: 2.4), 1), color(0x0B0C0F))
        case .supercar, .wedge:
            // Side intakes and a louvered engine cover behind the cabin.
            for x in [body.minX + 0.6, body.maxX - 3.6] {
                fill(g, rounded(CGRect(x: x, y: s.height * 0.52, width: 3, height: 8), 1), color(0x0B0C0F))
            }
            for i in 0..<4 {
                fill(g, CGPath(rect: CGRect(x: body.minX + 7, y: s.height * 0.72 + CGFloat(i) * 2.4, width: body.width - 14, height: 0.8), transform: nil), seam)
            }
        case .suv:
            // Roof rails.
            for x in [body.minX + 4.4, body.maxX - 5.4] {
                fill(g, CGPath(rect: CGRect(x: x, y: s.height * shape.roof0, width: 1, height: s.height * (shape.roof1 - shape.roof0)), transform: nil), color(0x1A1C22))
            }
        case .luxury:
            // Chrome grille bar and a hood ornament line.
            fill(g, CGPath(rect: CGRect(x: s.width / 2 - 5, y: body.minY + 0.6, width: 10, height: 1.6), transform: nil), color(0xDDE2EA))
            fill(g, CGPath(rect: CGRect(x: s.width / 2 - 0.3, y: body.minY + 3, width: 0.6, height: s.height * 0.2), transform: nil), UIColor(white: 1, alpha: 0.35))
        default:
            break
        }
        // Door seams.
        for y in [s.height * 0.48, s.height * 0.63] where style != .supercar && style != .wedge {
            fill(g, CGPath(rect: CGRect(x: body.minX, y: y, width: 2.2, height: 0.6), transform: nil), seam)
            fill(g, CGPath(rect: CGRect(x: body.maxX - 2.2, y: y, width: 2.2, height: 0.6), transform: nil), seam)
        }
        g.restoreGState()
        mirrors(g, body, y: s.height * (shape.glass0 + 0.02), color: base)
        // Windscreen, roof, rear glass.
        drawGlass(g, glass(body, y0: s.height * shape.glass0, y1: s.height * shape.roof0, topInset: 3.4, bottomInset: 5))
        let roofRect = CGRect(x: body.minX + 4.8, y: s.height * shape.roof0, width: body.width - 9.6, height: s.height * (shape.roof1 - shape.roof0))
        if style == .ev {
            // Panoramic glass roof.
            drawGlass(g, rounded(roofRect, 3), tint: color(0x13233A))
        } else {
            let roofColor: UIColor = (style == .finned && design == nil) ? (accent ?? base) : base
            fill(g, rounded(roofRect, 3.5), roofColor)
            g.saveGState()
            g.addPath(rounded(roofRect, 3.5))
            g.clip()
            linear(g, [UIColor(white: 1, alpha: 0.2), UIColor(white: 1, alpha: 0.02), UIColor(white: 0, alpha: 0.16)],
                   [0, 0.5, 1], from: CGPoint(x: body.minX, y: 0), to: CGPoint(x: body.maxX, y: 0))
            g.restoreGState()
            stroke(g, rounded(roofRect, 3.5), UIColor(white: 0, alpha: 0.3), 0.5)
        }
        drawGlass(g, glass(body, y0: s.height * shape.roof1, y1: s.height * shape.rear1, topInset: 5.2, bottomInset: 4.2, curve: 1))
        if style == .supercar || model == .kestrelMidnight {
            // Rear wing.
            let wing = rounded(CGRect(x: body.minX + 0.4, y: s.height - 8.6, width: body.width - 0.8, height: 2.8), 1.2)
            fill(g, wing, color(0x111318))
            if let accent, design == nil { fill(g, CGPath(rect: CGRect(x: body.minX + 1, y: s.height - 8.2, width: body.width - 2, height: 0.6), transform: nil), accent) }
        }
        outline(g, path)
        // Lights: thin LED bars on modern cars, round lamps on the classics.
        let classic = style == .fastback || style == .finned || style == .wedge
        if style == .ev {
            lamp(g, CGRect(x: body.minX + 3, y: body.minY + 1.6, width: body.width - 6, height: 1.2), color(0xEAF6FF), glow: 2)
            lamp(g, CGRect(x: body.minX + 2, y: body.maxY - 2.6, width: body.width - 4, height: 1.2), color(0xFF2E4A), glow: 2)
        } else {
            let fw: CGFloat = classic ? 4 : 6, fh: CGFloat = classic ? 3.4 : 2.2
            lamp(g, CGRect(x: body.minX + 2.4, y: body.minY + 1.5, width: fw, height: fh), color(0xFFF4D6))
            lamp(g, CGRect(x: body.maxX - 2.4 - fw, y: body.minY + 1.5, width: fw, height: fh), color(0xFFF4D6))
            lamp(g, CGRect(x: body.minX + 2, y: body.maxY - 3.4, width: 6.8, height: 2), color(0xFF2E4A), glow: 1.8)
            lamp(g, CGRect(x: body.maxX - 8.8, y: body.maxY - 3.4, width: 6.8, height: 2), color(0xFF2E4A), glow: 1.8)
        }
        if classic {
            // Chrome bumpers.
            fill(g, rounded(CGRect(x: body.minX + 1, y: body.minY - 0.4, width: body.width - 2, height: 1.4), 0.6), color(0xE3E7EE))
            fill(g, rounded(CGRect(x: body.minX + 1, y: body.maxY - 1, width: body.width - 2, height: 1.4), 0.6), color(0xE3E7EE))
        }
    }

    private static func drawCruiserBike(_ g: CGContext, _ s: CGSize, model: VehicleID, design: PaintDesign?, rims: RimSetup?) {
        let base = lineupColor(model)
        let cx = s.width / 2
        // Fat tyres front and back.
        rimWheel(g, CGRect(x: cx - 2.6, y: 0.5, width: 5.2, height: 9), rims: rims)
        rimWheel(g, CGRect(x: cx - 3.2, y: s.height - 10, width: 6.4, height: 9.5), rims: rims)
        // Wide handlebars.
        fill(g, rounded(CGRect(x: 0.5, y: 8, width: s.width - 1, height: 1.6), 0.8), color(0xC9CED8))
        // Tank and seat.
        let tank = capsule(CGRect(x: cx - 4.4, y: 10, width: 8.8, height: 13))
        paintBody(g, tank, base: base, design: design)
        g.saveGState(); g.addPath(tank); g.clip(); shadeBody(g, tank.boundingBox); g.restoreGState()
        outline(g, tank)
        fill(g, rounded(CGRect(x: cx - 4, y: 22, width: 8, height: 9), 3), color(0x17181C))
        // Exhaust pipes along the right.
        fill(g, rounded(CGRect(x: s.width - 3.2, y: 18, width: 2.2, height: 18), 1), color(0xD7DCE3))
        lamp(g, CGRect(x: cx - 2, y: 1, width: 4, height: 2), color(0xFFF4D6))
        lamp(g, CGRect(x: cx - 1.6, y: s.height - 2.6, width: 3.2, height: 1.6), color(0xFF2E4A), glow: 1.4)
    }
}
