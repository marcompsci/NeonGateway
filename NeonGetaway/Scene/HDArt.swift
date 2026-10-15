import UIKit
import SpriteKit
import GameCore

/// High-resolution street art (v0.12): vehicles and people drawn with Core Graphics paths,
/// gradients and soft shadows at 3 pixels per point, then filtered smoothly. Nothing is loaded
/// from files; every design is invented for Port Aurora.
///
/// Everything is drawn nose/face up, in point units, so sprites keep the sizes (and collision
/// feel) the pixel versions had.
@MainActor
enum HDArt {
    /// Pixels per point in every generated texture.
    static let density: CGFloat = 3

    // MARK: Shared helpers

    static func render(_ size: CGSize, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = density
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    static func texture(_ image: UIImage) -> SKTexture {
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor { UIColor(hex: hex, alpha: alpha) }

    static func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }

    static func lighter(_ c: UIColor, _ t: CGFloat) -> UIColor { mix(c, .white, t) }
    static func darker(_ c: UIColor, _ t: CGFloat) -> UIColor { mix(c, .black, t) }

    static func linear(_ g: CGContext, _ colors: [UIColor], _ locations: [CGFloat], from: CGPoint, to: CGPoint) {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray,
                                        locations: locations) else { return }
        g.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    static func radial(_ g: CGContext, _ colors: [UIColor], _ locations: [CGFloat], center: CGPoint, radius: CGFloat) {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray,
                                        locations: locations) else { return }
        g.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                             options: [.drawsBeforeStartLocation])
    }

    static func fill(_ g: CGContext, _ path: CGPath, _ color: UIColor) {
        g.addPath(path)
        g.setFillColor(color.cgColor)
        g.fillPath()
    }

    static func stroke(_ g: CGContext, _ path: CGPath, _ color: UIColor, _ width: CGFloat) {
        g.addPath(path)
        g.setStrokeColor(color.cgColor)
        g.setLineWidth(width)
        g.strokePath()
    }

    static func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2),
               transform: nil)
    }

    static func capsule(_ r: CGRect) -> CGPath { rounded(r, min(r.width, r.height) / 2) }

    /// A car body seen from above: rounded nose and tail, slightly pinched waist.
    static func bodyPath(_ r: CGRect, nose: CGFloat, tail: CGFloat, waist: CGFloat = 0.6) -> CGPath {
        let p = CGMutablePath()
        let x0 = r.minX, x1 = r.maxX, y0 = r.minY, y1 = r.maxY
        let midY = r.midY
        p.move(to: CGPoint(x: x0 + nose, y: y0))
        p.addLine(to: CGPoint(x: x1 - nose, y: y0))
        p.addQuadCurve(to: CGPoint(x: x1, y: y0 + nose * 1.2), control: CGPoint(x: x1, y: y0))
        p.addQuadCurve(to: CGPoint(x: x1, y: y1 - tail * 1.1), control: CGPoint(x: x1 - waist, y: midY))
        p.addQuadCurve(to: CGPoint(x: x1 - tail, y: y1), control: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x0 + tail, y: y1))
        p.addQuadCurve(to: CGPoint(x: x0, y: y1 - tail * 1.1), control: CGPoint(x: x0, y: y1))
        p.addQuadCurve(to: CGPoint(x: x0, y: y0 + nose * 1.2), control: CGPoint(x: x0 + waist, y: midY))
        p.addQuadCurve(to: CGPoint(x: x0 + nose, y: y0), control: CGPoint(x: x0, y: y0))
        p.closeSubpath()
        return p
    }

    /// A trapezoid of glass between two rows: `topInset`/`bottomInset` are how far each edge
    /// sits in from the body's sides.
    static func glass(_ body: CGRect, y0: CGFloat, y1: CGFloat, topInset: CGFloat, bottomInset: CGFloat,
                      curve: CGFloat = 1.6) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: body.minX + topInset, y: y0 + curve))
        p.addQuadCurve(to: CGPoint(x: body.maxX - topInset, y: y0 + curve), control: CGPoint(x: body.midX, y: y0 - curve))
        p.addLine(to: CGPoint(x: body.maxX - bottomInset, y: y1))
        p.addQuadCurve(to: CGPoint(x: body.minX + bottomInset, y: y1), control: CGPoint(x: body.midX, y: y1 + curve * 0.6))
        p.closeSubpath()
        return p
    }

    /// Cylinder shading across a body so flat colour reads as a curved panel.
    static func shadeBody(_ g: CGContext, _ r: CGRect, strength: CGFloat = 1) {
        linear(g, [UIColor(white: 0, alpha: 0.42 * strength), UIColor(white: 0, alpha: 0.05),
                   UIColor(white: 1, alpha: 0.22 * strength), UIColor(white: 1, alpha: 0.04),
                   UIColor(white: 0, alpha: 0.12), UIColor(white: 0, alpha: 0.5 * strength)],
               [0, 0.2, 0.36, 0.55, 0.78, 1], from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.maxX, y: 0))
        linear(g, [UIColor(white: 1, alpha: 0.12 * strength), UIColor(white: 1, alpha: 0),
                   UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.22 * strength)],
               [0, 0.25, 0.7, 1], from: CGPoint(x: 0, y: r.minY), to: CGPoint(x: 0, y: r.maxY))
    }

    static func drawGlass(_ g: CGContext, _ path: CGPath, tint given: UIColor? = nil) {
        let tint = given ?? color(0x0E1A30)
        g.saveGState()
        g.addPath(path)
        g.clip()
        let box = path.boundingBox
        linear(g, [lighter(tint, 0.18), tint, darker(tint, 0.3)], [0, 0.5, 1],
               from: CGPoint(x: box.minX, y: box.minY), to: CGPoint(x: box.maxX, y: box.maxY))
        // A sky reflection streak across the glass.
        let streak = CGMutablePath()
        streak.move(to: CGPoint(x: box.minX + box.width * 0.18, y: box.minY))
        streak.addLine(to: CGPoint(x: box.minX + box.width * 0.42, y: box.minY))
        streak.addLine(to: CGPoint(x: box.minX + box.width * 0.24, y: box.maxY))
        streak.addLine(to: CGPoint(x: box.minX, y: box.maxY))
        streak.closeSubpath()
        fill(g, streak, UIColor(white: 1, alpha: 0.2))
        let thin = CGMutablePath()
        thin.move(to: CGPoint(x: box.minX + box.width * 0.5, y: box.minY))
        thin.addLine(to: CGPoint(x: box.minX + box.width * 0.56, y: box.minY))
        thin.addLine(to: CGPoint(x: box.minX + box.width * 0.38, y: box.maxY))
        thin.addLine(to: CGPoint(x: box.minX + box.width * 0.32, y: box.maxY))
        thin.closeSubpath()
        fill(g, thin, UIColor(white: 1, alpha: 0.1))
        g.restoreGState()
        stroke(g, path, UIColor(white: 0, alpha: 0.55), 0.6)
    }

    static func lamp(_ g: CGContext, _ r: CGRect, _ c: UIColor, glow: CGFloat = 2.5) {
        g.saveGState()
        g.setShadow(offset: .zero, blur: glow * density, color: c.withAlphaComponent(0.9).cgColor)
        fill(g, rounded(r, min(r.width, r.height) / 2.2), c)
        g.restoreGState()
        fill(g, rounded(r.insetBy(dx: r.width * 0.25, dy: r.height * 0.25), 1), UIColor(white: 1, alpha: 0.75))
    }

    static func wheel(_ g: CGContext, _ r: CGRect) {
        fill(g, rounded(r, 1.6), color(0x07080B))
        fill(g, rounded(r.insetBy(dx: r.width * 0.3, dy: r.height * 0.18), 1), color(0x2A2D35))
    }

    // MARK: Vehicles

    /// Point size each vehicle is drawn at (matches the old sprites, so collisions still feel right).
    static func vehicleSize(_ model: VehicleID) -> CGSize {
        switch model {
        case .vesper, .harborPatrol: CGSize(width: 33.6, height: 57.6)
        case .dorado: CGSize(width: 33.6, height: 54)
        case .ridgeback: CGSize(width: 38.4, height: 60)
        case .flicker: CGSize(width: 16, height: 36)
        case .hauler: CGSize(width: 44, height: 150)
        default: lineupSize(model)
        }
    }

    /// The colour each model wears from the factory.
    static func factoryColor(_ model: VehicleID) -> UIColor {
        switch model {
        case .vesper: color(0xFF3EA5)
        case .dorado: color(0xF07A2E)
        case .ridgeback: color(0x1F9E94)
        case .flicker: color(0xFF3EA5)
        case .harborPatrol: color(0xEDEFF4)
        case .hauler: color(0xD9342B)
        default: lineupColor(model)
        }
    }

    private static var vehicleCache: [String: SKTexture] = [:]
    private static var shadowCache: [String: SKTexture] = [:]

    static func vehicleTexture(_ model: VehicleID, design: PaintDesign? = nil, lightFrame: Int? = nil,
                               rims: RimSetup? = nil) -> SKTexture {
        let rimKey = rims.map { "\($0.style.rawValue)\($0.color)" } ?? "-"
        let key = "\(model.rawValue)|\(design.map { "\($0.id)-\($0.cells.hashValue)" } ?? "-")|\(lightFrame ?? -1)|\(rimKey)"
        if let cached = vehicleCache[key] { return cached }
        let t = texture(vehicleImage(model, design: design, lightFrame: lightFrame, rims: rims))
        vehicleCache[key] = t
        return t
    }

    /// A soft drop shadow the shape of the vehicle (drawn bigger than the body; see `shadowPadding`).
    static func vehicleShadow(_ model: VehicleID) -> SKTexture {
        if let cached = shadowCache[model.rawValue] { return cached }
        let size = vehicleSize(model)
        let pad = shadowPadding
        let image = render(CGSize(width: size.width + pad * 2, height: size.height + pad * 2)) { g in
            g.setShadow(offset: .zero, blur: 4 * density, color: UIColor(white: 0, alpha: 1).cgColor)
            let r = CGRect(x: pad + 1, y: pad + 1, width: size.width - 2, height: size.height - 2)
            fill(g, model.isMotorcycle ? capsule(r.insetBy(dx: 2, dy: 0)) : rounded(r, 7), UIColor(white: 0, alpha: 0.85))
        }
        let t = texture(image)
        shadowCache[model.rawValue] = t
        return t
    }

    static let shadowPadding: CGFloat = 8

    /// Full-colour vehicle image in points (scale 3). `lightFrame` 0/1 picks which side of a
    /// patrol light bar is lit; nil = both lit (steady).
    static func vehicleImage(_ model: VehicleID, design: PaintDesign? = nil, lightFrame: Int? = nil,
                             rims: RimSetup? = nil) -> UIImage {
        let size = vehicleSize(model)
        return render(size) { g in
            switch model {
            case .vesper: drawVesper(g, size, design: design)
            case .dorado: drawSedan(g, size, design: design)
            case .ridgeback: drawVan(g, size, design: design)
            case .flicker: drawBike(g, size, design: design)
            case .harborPatrol: drawPatrol(g, size, frame: lightFrame)
            case .hauler: drawHauler(g, size)
            default: drawLineup(g, size, model: model, design: design, rims: rims)
            }
        }
    }

    /// Bigger picture for menus (garage, body shop, paint studio): the same art, `points` tall.
    static func vehiclePreview(_ model: VehicleID, design: PaintDesign?, height: CGFloat, rims: RimSetup? = nil) -> UIImage {
        let size = vehicleSize(model)
        let scale = height / size.height
        let base = vehicleImage(model, design: design, rims: rims)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let out = CGSize(width: size.width * scale, height: height)
        return UIGraphicsImageRenderer(size: out, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .high
            base.draw(in: CGRect(origin: .zero, size: out))
        }
    }

    /// Paints the body: the factory colour, or a design's grid stretched over the body.
    static func paintBody(_ g: CGContext, _ path: CGPath, base: UIColor, design: PaintDesign?) {
        fill(g, path, base)
        guard let design else { return }
        g.saveGState()
        g.addPath(path)
        g.clip()
        let box = path.boundingBox
        let cw = box.width / CGFloat(PaintDesign.width), ch = box.height / CGFloat(PaintDesign.height)
        for row in 0..<PaintDesign.height {
            for col in 0..<PaintDesign.width {
                guard let c = PixelArt.designColor(design.cell(col: col, row: row)) else { continue }
                c.setFill()
                g.fill(CGRect(x: box.minX + CGFloat(col) * cw - 0.05, y: box.minY + CGFloat(row) * ch - 0.05,
                              width: cw + 0.1, height: ch + 0.1))
            }
        }
        g.restoreGState()
    }

    static func outline(_ g: CGContext, _ path: CGPath) {
        stroke(g, path, UIColor(white: 0, alpha: 0.7), 0.9)
        g.saveGState()
        g.addPath(path)
        g.clip()
        stroke(g, path, UIColor(white: 1, alpha: 0.18), 1.6)
        g.restoreGState()
    }

    static func mirrors(_ g: CGContext, _ body: CGRect, y: CGFloat, color c: UIColor) {
        for x in [body.minX - 2.2, body.maxX - 0.4] {
            let r = CGRect(x: x, y: y, width: 2.6, height: 3.4)
            fill(g, rounded(r, 1.2), darker(c, 0.25))
        }
    }

    // The player's Vesper GT: a low sports coupe with racing stripes and a rear wing.
    private static func drawVesper(_ g: CGContext, _ s: CGSize, design: PaintDesign?) {
        let base = factoryColor(.vesper)
        let body = CGRect(x: 2.6, y: 1.4, width: s.width - 5.2, height: s.height - 3)
        for (x, y): (CGFloat, CGFloat) in [(0.9, 9.0), (s.width - 4.9, 9.0), (0.9, s.height - 17.5), (s.width - 4.9, s.height - 17.5)] {
            wheel(g, CGRect(x: x, y: y, width: 4, height: 10))
        }
        let path = bodyPath(body, nose: 9, tail: 7, waist: 1.4)
        paintBody(g, path, base: base, design: design)
        g.saveGState()
        g.addPath(path)
        g.clip()
        if design == nil {
            // Twin cream racing stripes nose to tail.
            let stripe = color(0xF4EBD9, 0.95)
            for x in [s.width / 2 - 4.2, s.width / 2 + 1.4] {
                stripe.setFill()
                g.fill(CGRect(x: x, y: body.minY, width: 2.8, height: body.height))
            }
        }
        shadeBody(g, body)
        // Hood vents and panel lines.
        let line = UIColor(white: 0, alpha: 0.35)
        for dx: CGFloat in [-5, 3] {
            fill(g, rounded(CGRect(x: s.width / 2 + dx, y: 9, width: 2.2, height: 5), 0.8), line)
        }
        stroke(g, CGPath(rect: CGRect(x: body.minX + 3, y: s.height * 0.79, width: body.width - 6, height: 0.01),
                         transform: nil), line, 0.5)
        g.restoreGState()
        mirrors(g, body, y: s.height * 0.33, color: base)
        drawGlass(g, glass(body, y0: s.height * 0.3, y1: s.height * 0.44, topInset: 3.4, bottomInset: 5.2))
        // Roof.
        let roof = rounded(CGRect(x: body.minX + 5.2, y: s.height * 0.44, width: body.width - 10.4, height: s.height * 0.2), 3.5)
        g.saveGState()
        g.addPath(roof)
        g.clip()
        linear(g, [UIColor(white: 1, alpha: 0.2), UIColor(white: 1, alpha: 0.02), UIColor(white: 0, alpha: 0.15)],
               [0, 0.5, 1], from: CGPoint(x: body.minX, y: 0), to: CGPoint(x: body.maxX, y: 0))
        g.restoreGState()
        stroke(g, roof, UIColor(white: 0, alpha: 0.3), 0.5)
        drawGlass(g, glass(body, y0: s.height * 0.64, y1: s.height * 0.73, topInset: 5.4, bottomInset: 4.2, curve: 1))
        // Rear wing.
        let wing = rounded(CGRect(x: body.minX + 0.6, y: s.height - 9.5, width: body.width - 1.2, height: 3), 1.2)
        fill(g, wing, color(0x14161C))
        fill(g, rounded(CGRect(x: body.minX + 1.2, y: s.height - 9.2, width: body.width - 2.4, height: 0.9), 0.4),
             UIColor(white: 1, alpha: 0.25))
        outline(g, path)
        lamp(g, CGRect(x: body.minX + 2.6, y: body.minY + 1.4, width: 6.4, height: 2.6), color(0xFFF4D6))
        lamp(g, CGRect(x: body.maxX - 9, y: body.minY + 1.4, width: 6.4, height: 2.6), color(0xFFF4D6))
        lamp(g, CGRect(x: body.minX + 2.2, y: body.maxY - 3.2, width: 7.5, height: 2.2), color(0xFF2E6A), glow: 2)
        lamp(g, CGRect(x: body.maxX - 9.7, y: body.maxY - 3.2, width: 7.5, height: 2.2), color(0xFF2E6A), glow: 2)
    }

    // The Dorado: a plain four-door with chrome bumpers.
    private static func drawSedan(_ g: CGContext, _ s: CGSize, design: PaintDesign?) {
        let base = factoryColor(.dorado)
        let body = CGRect(x: 3, y: 1.5, width: s.width - 6, height: s.height - 3)
        for (x, y): (CGFloat, CGFloat) in [(1.2, 8.5), (s.width - 5.2, 8.5), (1.2, s.height - 17), (s.width - 5.2, s.height - 17)] {
            wheel(g, CGRect(x: x, y: y, width: 4, height: 9.5))
        }
        let path = bodyPath(body, nose: 7, tail: 6, waist: 0.8)
        paintBody(g, path, base: base, design: design)
        g.saveGState()
        g.addPath(path)
        g.clip()
        shadeBody(g, body, strength: 0.9)
        // Chrome bumpers.
        g.saveGState()
        g.clip(to: CGRect(x: body.minX, y: body.minY, width: body.width, height: 2.2))
        linear(g, [color(0xE8ECF2), color(0x8A909C)], [0, 1], from: CGPoint(x: 0, y: body.minY),
               to: CGPoint(x: 0, y: body.minY + 2.2))
        g.restoreGState()
        g.restoreGState()
        g.saveGState()
        g.addPath(path)
        g.clip()
        fill(g, CGPath(rect: CGRect(x: body.minX, y: body.maxY - 2.2, width: body.width, height: 2.2), transform: nil),
             color(0xB9BEC8))
        let line = UIColor(white: 0, alpha: 0.32)
        // Door seams.
        for y in [s.height * 0.47, s.height * 0.62] {
            fill(g, CGPath(rect: CGRect(x: body.minX, y: y, width: 2.4, height: 0.6), transform: nil), line)
            fill(g, CGPath(rect: CGRect(x: body.maxX - 2.4, y: y, width: 2.4, height: 0.6), transform: nil), line)
        }
        g.restoreGState()
        mirrors(g, body, y: s.height * 0.31, color: base)
        drawGlass(g, glass(body, y0: s.height * 0.27, y1: s.height * 0.4, topInset: 3.2, bottomInset: 4.4))
        let roof = rounded(CGRect(x: body.minX + 4.4, y: s.height * 0.4, width: body.width - 8.8, height: s.height * 0.27), 3)
        g.saveGState()
        g.addPath(roof)
        g.clip()
        linear(g, [UIColor(white: 1, alpha: 0.16), UIColor(white: 1, alpha: 0.02), UIColor(white: 0, alpha: 0.18)],
               [0, 0.5, 1], from: CGPoint(x: body.minX, y: 0), to: CGPoint(x: body.maxX, y: 0))
        g.restoreGState()
        stroke(g, roof, UIColor(white: 0, alpha: 0.28), 0.5)
        drawGlass(g, glass(body, y0: s.height * 0.67, y1: s.height * 0.77, topInset: 4.4, bottomInset: 3.6, curve: 1))
        outline(g, path)
        lamp(g, CGRect(x: body.minX + 2, y: body.minY + 2.4, width: 5.6, height: 2.6), color(0xFFF1CF))
        lamp(g, CGRect(x: body.maxX - 7.6, y: body.minY + 2.4, width: 5.6, height: 2.6), color(0xFFF1CF))
        lamp(g, CGRect(x: body.minX + 1.6, y: body.maxY - 4.6, width: 5, height: 2.2), color(0xE8314B), glow: 1.6)
        lamp(g, CGRect(x: body.maxX - 6.6, y: body.maxY - 4.6, width: 5, height: 2.2), color(0xE8314B), glow: 1.6)
    }

    // The Ridgeback: a delivery van, teal cab and a long cream box with roof ribs.
    private static func drawVan(_ g: CGContext, _ s: CGSize, design: PaintDesign?) {
        let cabColor = factoryColor(.ridgeback)
        let boxColor = color(0xEFE6D2)
        let body = CGRect(x: 2.6, y: 1.4, width: s.width - 5.2, height: s.height - 2.8)
        for (x, y): (CGFloat, CGFloat) in [(0.8, 7.0), (s.width - 4.8, 7.0), (0.8, s.height - 15.5), (s.width - 4.8, s.height - 15.5)] {
            wheel(g, CGRect(x: x, y: y, width: 4, height: 10))
        }
        let path = bodyPath(body, nose: 6, tail: 2.5, waist: 0.3)
        fill(g, path, boxColor)
        g.saveGState()
        g.addPath(path)
        g.clip()
        cabColor.setFill()
        g.fill(CGRect(x: body.minX, y: body.minY, width: body.width, height: s.height * 0.27))
        g.restoreGState()
        if let design {
            // A design covers the whole van.
            paintBody(g, path, base: boxColor, design: design)
        }
        g.saveGState()
        g.addPath(path)
        g.clip()
        shadeBody(g, body, strength: 0.8)
        // Roof ribs on the box.
        let rib = UIColor(white: 0, alpha: 0.12), shine = UIColor(white: 1, alpha: 0.14)
        var y = s.height * 0.32
        while y < s.height - 5 {
            rib.setFill(); g.fill(CGRect(x: body.minX + 2, y: y, width: body.width - 4, height: 0.9))
            shine.setFill(); g.fill(CGRect(x: body.minX + 2, y: y + 0.9, width: body.width - 4, height: 0.6))
            y += 4.2
        }
        if design == nil {
            // A teal stripe along each side of the box.
            color(0x2EE6D6, 0.8).setFill()
            g.fill(CGRect(x: body.minX, y: s.height * 0.3, width: 2, height: s.height * 0.62))
            g.fill(CGRect(x: body.maxX - 2, y: s.height * 0.3, width: 2, height: s.height * 0.62))
        }
        g.restoreGState()
        mirrors(g, body, y: s.height * 0.12, color: cabColor)
        drawGlass(g, glass(body, y0: s.height * 0.08, y1: s.height * 0.2, topInset: 3, bottomInset: 3.6))
        // Cab roof and the step down to the box.
        fill(g, CGPath(rect: CGRect(x: body.minX + 1, y: s.height * 0.27, width: body.width - 2, height: 1.2), transform: nil),
             UIColor(white: 0, alpha: 0.35))
        outline(g, path)
        lamp(g, CGRect(x: body.minX + 1.8, y: body.minY + 1.2, width: 6, height: 2.4), color(0xFFF1CF))
        lamp(g, CGRect(x: body.maxX - 7.8, y: body.minY + 1.2, width: 6, height: 2.4), color(0xFFF1CF))
        lamp(g, CGRect(x: body.minX + 1, y: body.maxY - 2.6, width: 4.5, height: 2), color(0xE8314B), glow: 1.6)
        lamp(g, CGRect(x: body.maxX - 5.5, y: body.maxY - 2.6, width: 4.5, height: 2), color(0xE8314B), glow: 1.6)
    }

    // The Longhaul rig: a red cab-over tractor pulling a long ribbed box trailer.
    private static func drawHauler(_ g: CGContext, _ s: CGSize) {
        let cabColor = factoryColor(.hauler)
        let cabH: CGFloat = 36
        let cab = CGRect(x: 3, y: 1.5, width: s.width - 6, height: cabH)
        let trailer = CGRect(x: 1.5, y: cabH + 6, width: s.width - 3, height: s.height - cabH - 7.5)
        // Wheels: steer axle, twin drive axles, and two trailer bogies.
        for y: CGFloat in [6, 28, 34] {
            wheel(g, CGRect(x: 0.6, y: y, width: 4.2, height: 9))
            wheel(g, CGRect(x: s.width - 4.8, y: y, width: 4.2, height: 9))
        }
        for y: CGFloat in [s.height - 30, s.height - 18] {
            wheel(g, CGRect(x: 0, y: y, width: 4.5, height: 10))
            wheel(g, CGRect(x: s.width - 4.5, y: y, width: 4.5, height: 10))
        }
        // Fifth-wheel hitch between cab and trailer.
        fill(g, CGPath(rect: CGRect(x: s.width / 2 - 5, y: cabH - 2, width: 10, height: 10), transform: nil), color(0x1A1C22))
        // Trailer: brushed panels with ribs and a teal stripe.
        let box = rounded(trailer, 3)
        fill(g, box, color(0xE9E4DA))
        g.saveGState()
        g.addPath(box)
        g.clip()
        linear(g, [UIColor(white: 0, alpha: 0.18), UIColor(white: 1, alpha: 0.08), UIColor(white: 0, alpha: 0.22)],
               [0, 0.45, 1], from: CGPoint(x: trailer.minX, y: 0), to: CGPoint(x: trailer.maxX, y: 0))
        var y = trailer.minY + 4
        while y < trailer.maxY - 3 {
            UIColor(white: 0, alpha: 0.13).setFill(); g.fill(CGRect(x: trailer.minX, y: y, width: trailer.width, height: 1))
            UIColor(white: 1, alpha: 0.16).setFill(); g.fill(CGRect(x: trailer.minX, y: y + 1, width: trailer.width, height: 0.7))
            y += 6
        }
        color(0x2EE6D6, 0.85).setFill()
        g.fill(CGRect(x: trailer.minX, y: trailer.minY + 8, width: 2.4, height: trailer.height - 16))
        g.fill(CGRect(x: trailer.maxX - 2.4, y: trailer.minY + 8, width: 2.4, height: trailer.height - 16))
        g.restoreGState()
        stroke(g, box, UIColor(white: 0, alpha: 0.55), 1)
        // Cab: rounded nose, roof fairing, sleeper vents and stacks.
        let cabPath = bodyPath(cab, nose: 5, tail: 2, waist: 0.2)
        fill(g, cabPath, cabColor)
        g.saveGState()
        g.addPath(cabPath)
        g.clip()
        shadeBody(g, cab, strength: 0.9)
        // Roof fairing.
        linear(g, [color(0xFFFFFF, 0.25), color(0xFFFFFF, 0)], [0, 1],
               from: CGPoint(x: 0, y: cab.minY + 9), to: CGPoint(x: 0, y: cab.minY + 26))
        color(0x1A1C22, 0.5).setFill()
        for i in 0..<3 { g.fill(CGRect(x: cab.minX + 8, y: cab.minY + 24 + CGFloat(i) * 3, width: cab.width - 16, height: 1.2)) }
        g.restoreGState()
        mirrors(g, cab, y: cab.minY + 7, color: cabColor)
        drawGlass(g, glass(cab, y0: cab.minY + 3, y1: cab.minY + 9.5, topInset: 3.5, bottomInset: 3.5))
        // Chrome exhaust stacks behind the cab.
        for x in [cab.minX + 1.5, cab.maxX - 5.5] {
            fill(g, capsule(CGRect(x: x, y: cab.maxY - 6, width: 4, height: 6)), color(0xC9CED8))
            fill(g, CGPath(ellipseIn: CGRect(x: x + 1, y: cab.maxY - 5, width: 2, height: 2), transform: nil), color(0x101217))
        }
        outline(g, cabPath)
        lamp(g, CGRect(x: cab.minX + 2, y: cab.minY + 1, width: 7, height: 2.6), color(0xFFF1CF))
        lamp(g, CGRect(x: cab.maxX - 9, y: cab.minY + 1, width: 7, height: 2.6), color(0xFFF1CF))
        // Amber roof markers and red tail lights on the trailer.
        for i in 0..<3 {
            lamp(g, CGRect(x: s.width / 2 - 7 + CGFloat(i) * 5.5, y: cab.minY + 11, width: 3, height: 1.6), color(0xFFB13D), glow: 1.4)
        }
        lamp(g, CGRect(x: trailer.minX + 1, y: trailer.maxY - 3, width: 6, height: 2.2), color(0xE8314B), glow: 2)
        lamp(g, CGRect(x: trailer.maxX - 7, y: trailer.maxY - 3, width: 6, height: 2.2), color(0xE8314B), glow: 2)
    }

    // The Flicker 250: a light bike. The rider is drawn separately when someone's on it.
    private static func drawBike(_ g: CGContext, _ s: CGSize, design: PaintDesign?) {
        let base = factoryColor(.flicker)
        let cx = s.width / 2
        // Tyres.
        fill(g, capsule(CGRect(x: cx - 2.3, y: 1, width: 4.6, height: 10)), color(0x07080B))
        fill(g, capsule(CGRect(x: cx - 2.6, y: s.height - 11.5, width: 5.2, height: 10.5)), color(0x07080B))
        fill(g, capsule(CGRect(x: cx - 0.9, y: 2.5, width: 1.8, height: 7)), color(0x34373F))
        // Frame.
        fill(g, rounded(CGRect(x: cx - 1.4, y: 7, width: 2.8, height: s.height - 14), 1.2), color(0x2A2D35))
        // Handlebar with grips.
        fill(g, capsule(CGRect(x: 1, y: 9, width: s.width - 2, height: 1.8)), color(0x1C1E24))
        fill(g, capsule(CGRect(x: 0.6, y: 8.6, width: 3, height: 2.6)), color(0x0B0C10))
        fill(g, capsule(CGRect(x: s.width - 3.6, y: 8.6, width: 3, height: 2.6)), color(0x0B0C10))
        // Tank and tail in the bike's colour.
        let tank = CGMutablePath()
        tank.addEllipse(in: CGRect(x: cx - 4.6, y: 11, width: 9.2, height: 10))
        let tail = rounded(CGRect(x: cx - 3.2, y: s.height - 13, width: 6.4, height: 7), 2.5)
        let shape = CGMutablePath()
        shape.addPath(tank)
        shape.addPath(tail)
        paintBody(g, shape, base: base, design: design)
        g.saveGState()
        g.addPath(shape)
        g.clip()
        shadeBody(g, CGRect(x: cx - 4.6, y: 11, width: 9.2, height: s.height - 17))
        g.restoreGState()
        outline(g, shape)
        // Seat.
        fill(g, rounded(CGRect(x: cx - 3, y: 20.5, width: 6, height: 8), 2.6), color(0x14161C))
        fill(g, rounded(CGRect(x: cx - 2, y: 21.5, width: 2, height: 6), 1), UIColor(white: 1, alpha: 0.08))
        lamp(g, CGRect(x: cx - 2, y: 0.6, width: 4, height: 2.4), color(0xFFF4D6))
        lamp(g, CGRect(x: cx - 1.8, y: s.height - 6.4, width: 3.6, height: 1.6), color(0xFF2E6A), glow: 1.6)
    }

    // Harbor Patrol: two-tone cruiser (fictional livery) with a light bar.
    private static func drawPatrol(_ g: CGContext, _ s: CGSize, frame: Int?) {
        let white = color(0xEDEFF4), dark = color(0x15171E)
        let body = CGRect(x: 2.6, y: 1.4, width: s.width - 5.2, height: s.height - 3)
        for (x, y): (CGFloat, CGFloat) in [(0.9, 9.0), (s.width - 4.9, 9.0), (0.9, s.height - 17.5), (s.width - 4.9, s.height - 17.5)] {
            wheel(g, CGRect(x: x, y: y, width: 4, height: 10))
        }
        let path = bodyPath(body, nose: 8, tail: 6.5, waist: 0.9)
        fill(g, path, dark)
        g.saveGState()
        g.addPath(path)
        g.clip()
        white.setFill()
        g.fill(CGRect(x: body.minX, y: s.height * 0.27, width: body.width, height: s.height * 0.5))
        // A teal band down each flank.
        color(0x2EE6D6).setFill()
        g.fill(CGRect(x: body.minX, y: s.height * 0.3, width: 1.8, height: s.height * 0.44))
        g.fill(CGRect(x: body.maxX - 1.8, y: s.height * 0.3, width: 1.8, height: s.height * 0.44))
        shadeBody(g, body, strength: 0.9)
        // Push bar.
        fill(g, rounded(CGRect(x: body.minX + 3, y: body.minY - 0.5, width: body.width - 6, height: 2.6), 1), color(0x050608))
        g.restoreGState()
        mirrors(g, body, y: s.height * 0.32, color: white)
        drawGlass(g, glass(body, y0: s.height * 0.28, y1: s.height * 0.41, topInset: 3.4, bottomInset: 4.8))
        let roof = rounded(CGRect(x: body.minX + 4.8, y: s.height * 0.41, width: body.width - 9.6, height: s.height * 0.25), 3)
        fill(g, roof, white)
        g.saveGState()
        g.addPath(roof)
        g.clip()
        linear(g, [UIColor(white: 1, alpha: 0.3), UIColor(white: 0, alpha: 0.12)], [0, 1],
               from: CGPoint(x: body.minX, y: 0), to: CGPoint(x: body.maxX, y: 0))
        g.restoreGState()
        // Unit number on the roof, for the helicopter that isn't there.
        let number = NSAttributedString(string: "07", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 6.2, weight: .heavy),
            .foregroundColor: color(0x15171E, 0.85)])
        UIGraphicsPushContext(g)
        number.draw(at: CGPoint(x: s.width / 2 - 3.9, y: s.height * 0.53))
        UIGraphicsPopContext()
        // Light bar.
        let bar = CGRect(x: body.minX + 3.2, y: s.height * 0.45, width: body.width - 6.4, height: 3.6)
        fill(g, rounded(bar, 1.4), color(0x0B0C10))
        let left = CGRect(x: bar.minX + 0.8, y: bar.minY + 0.7, width: bar.width / 2 - 1.2, height: bar.height - 1.4)
        let right = CGRect(x: bar.midX + 0.4, y: bar.minY + 0.7, width: bar.width / 2 - 1.2, height: bar.height - 1.4)
        let magenta = color(0xFF2E7E), teal = color(0x2EC8FF)
        let leftOn = frame == nil || frame == 0, rightOn = frame == nil || frame == 1
        if leftOn { lamp(g, left, magenta, glow: 3) } else { fill(g, rounded(left, 1), darker(magenta, 0.6)) }
        if rightOn { lamp(g, right, teal, glow: 3) } else { fill(g, rounded(right, 1), darker(teal, 0.6)) }
        drawGlass(g, glass(body, y0: s.height * 0.66, y1: s.height * 0.75, topInset: 5, bottomInset: 4, curve: 1))
        outline(g, path)
        lamp(g, CGRect(x: body.minX + 2.4, y: body.minY + 2, width: 6, height: 2.4), color(0xFFF4D6))
        lamp(g, CGRect(x: body.maxX - 8.4, y: body.minY + 2, width: 6, height: 2.4), color(0xFFF4D6))
        lamp(g, CGRect(x: body.minX + 2, y: body.maxY - 3.4, width: 6, height: 2.2), color(0xE8314B), glow: 1.6)
        lamp(g, CGRect(x: body.maxX - 8, y: body.maxY - 3.4, width: 6, height: 2.2), color(0xE8314B), glow: 1.6)
    }

    // MARK: Light

    /// A soft additive pool of light (street lamps, headlights, light-bar glow).
    static func glowTexture(_ hex: UInt32) -> SKTexture {
        if let cached = glowCache[hex] { return cached }
        let image = render(CGSize(width: 64, height: 64)) { g in
            let c = color(hex)
            radial(g, [c.withAlphaComponent(0.85), c.withAlphaComponent(0.35), c.withAlphaComponent(0)],
                   [0, 0.4, 1], center: CGPoint(x: 32, y: 32), radius: 32)
        }
        let t = texture(image)
        glowCache[hex] = t
        return t
    }

    private static var glowCache: [UInt32: SKTexture] = [:]

    /// A headlight beam pointing up (from the bottom centre).
    static func beamTexture() -> SKTexture {
        if let beamCache { return beamCache }
        let image = render(CGSize(width: 80, height: 120)) { g in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 34, y: 120))
            p.addLine(to: CGPoint(x: 0, y: 8))
            p.addQuadCurve(to: CGPoint(x: 80, y: 8), control: CGPoint(x: 40, y: -8))
            p.addLine(to: CGPoint(x: 46, y: 120))
            p.closeSubpath()
            g.addPath(p)
            g.clip()
            linear(g, [UIColor(red: 1, green: 0.95, blue: 0.82, alpha: 0), UIColor(red: 1, green: 0.95, blue: 0.82, alpha: 0.18),
                       UIColor(red: 1, green: 0.95, blue: 0.82, alpha: 0.55)], [0, 0.55, 1],
                   from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 120))
        }
        let t = texture(image)
        beamCache = t
        return t
    }

    private static var beamCache: SKTexture?

    // MARK: People

    /// Colours for one person seen from above.
    struct Look: Hashable {
        var skin: UInt32
        var hair: UInt32
        var top: UInt32
        var legs: UInt32 = 0x2B3140
        var shoes: UInt32 = 0x0B0C10
        /// Cap instead of hair (the dealer).
        var cap = false
        /// A long coat that hides the legs a little.
        var coat = false
    }

    static let walkFrames = 4
    static let personSize = CGSize(width: 24, height: 24)
    private static var personCache: [String: SKTexture] = [:]

    /// Frame 0 = standing; 1...4 = the walk cycle.
    static func personTexture(_ look: Look, frame: Int) -> SKTexture {
        let key = "\(look.hashValue)|\(frame)"
        if let cached = personCache[key] { return cached }
        let t = texture(personImage(look, frame: frame))
        personCache[key] = t
        return t
    }

    static func personImage(_ look: Look, frame: Int) -> UIImage {
        render(personSize) { g in drawPerson(g, look, frame: frame) }
    }

    private static func drawPerson(_ g: CGContext, _ look: Look, frame: Int) {
        let s = personSize
        let c = CGPoint(x: s.width / 2, y: s.height / 2 + 0.6)
        let stride: CGFloat = frame == 0 ? 0 : sin(CGFloat(frame - 1) / CGFloat(walkFrames) * 2 * .pi) * 3.6
        let skin = color(look.skin), hair = color(look.hair), top = color(look.top)
        let legs = color(look.legs), shoes = color(look.shoes)

        // Soft contact shadow.
        g.saveGState()
        g.setShadow(offset: .zero, blur: 2.2 * density, color: UIColor(white: 0, alpha: 0.6).cgColor)
        let shadow = CGMutablePath()
        shadow.addEllipse(in: CGRect(x: c.x - 6.5 + 1.2, y: c.y - 4.5 + 1.4, width: 13, height: 10))
        fill(g, shadow, UIColor(white: 0, alpha: 0.35))
        g.restoreGState()

        // Legs: one forward, one back.
        for (side, dy) in [(-1.0, -stride), (1.0, stride)] {
            let x = c.x + CGFloat(side) * 2.4 - 1.6
            let leg = capsule(CGRect(x: x, y: c.y - 3 + dy, width: 3.2, height: 7))
            fill(g, leg, legs)
            let foot = capsule(CGRect(x: x - 0.1, y: c.y - 3.8 + dy + (dy < 0 ? 0 : 5), width: 3.4, height: 2.6))
            fill(g, foot, shoes)
        }
        // Arms hang at the sides and swing opposite the legs; a hand shows at the front of the swing.
        for (side, dy) in [(-1.0, stride * 0.7), (1.0, -stride * 0.7)] {
            let x = c.x + CGFloat(side) * 6.4 - 1.4
            let arm = capsule(CGRect(x: x, y: c.y - 1.6 + dy * 0.6, width: 2.8, height: 5.2))
            fill(g, arm, darker(top, 0.12))
            let hand = CGMutablePath()
            let handY = dy < -0.5 ? c.y - 2.4 + dy * 0.6 : c.y + 2.6 + dy * 0.6
            hand.addEllipse(in: CGRect(x: x + 0.2, y: handY, width: 2.4, height: 2.4))
            fill(g, hand, skin)
        }
        // Shoulders and torso.
        let torsoRect = CGRect(x: c.x - 6.6, y: c.y - 3.6, width: 13.2, height: look.coat ? 9 : 7.4)
        let torso = rounded(torsoRect, 3.6)
        fill(g, torso, top)
        g.saveGState()
        g.addPath(torso)
        g.clip()
        radial(g, [UIColor(white: 1, alpha: 0.32), UIColor(white: 1, alpha: 0), UIColor(white: 0, alpha: 0.3)],
               [0, 0.55, 1], center: CGPoint(x: c.x - 2, y: c.y - 2.4), radius: 9)
        g.restoreGState()
        stroke(g, torso, UIColor(white: 0, alpha: 0.55), 0.6)
        // Head: hair from above, a sliver of face at the front.
        let head = CGRect(x: c.x - 3.7, y: c.y - 5.4, width: 7.4, height: 7.4)
        let face = CGMutablePath()
        face.addEllipse(in: head)
        fill(g, face, skin)
        if look.cap {
            let cap = CGMutablePath()
            cap.addEllipse(in: head.insetBy(dx: -0.3, dy: -0.3).offsetBy(dx: 0, dy: 0.6))
            fill(g, cap, hair)
            fill(g, rounded(CGRect(x: head.minX + 0.8, y: head.minY - 1.6, width: head.width - 1.6, height: 2.8), 1.4),
                 darker(hair, 0.25))
        } else {
            let top = CGMutablePath()
            top.addEllipse(in: CGRect(x: head.minX - 0.3, y: head.minY + 1.4, width: head.width + 0.6, height: head.height - 0.6))
            fill(g, top, hair)
            fill(g, rounded(CGRect(x: head.minX + 0.4, y: head.minY + 1.2, width: head.width - 0.8, height: 2.4), 1.2), hair)
        }
        g.saveGState()
        g.addEllipse(in: head)
        g.clip()
        radial(g, [UIColor(white: 1, alpha: 0.28), UIColor(white: 1, alpha: 0)], [0, 1],
               center: CGPoint(x: head.minX + 2.4, y: head.minY + 2.6), radius: 4)
        g.restoreGState()
        let outlinePath = CGMutablePath()
        outlinePath.addEllipse(in: head)
        stroke(g, outlinePath, UIColor(white: 0, alpha: 0.5), 0.5)
    }

    // Looks for the crowd and the player.

    private static let crowdTops: [UInt32] = [0x2EE6D6, 0xFF8A3D, 0xF4EBD9, 0x8E6BFF, 0x5BC26A, 0x3D7BFF, 0xE8D44D, 0xD6456B]
    private static let crowdSkins: [UInt32] = [0x5C3A24, 0x8D5A3B, 0xC68B5E, 0xF1C9A0, 0xB07A52]
    private static let crowdHairs: [UInt32] = [0x15110E, 0x5A3A22, 0xB8873B, 0x2A2522, 0xCFD3DA, 0x7A2E22]
    private static let crowdLegs: [UInt32] = [0x2B3140, 0x3B3F4C, 0x1E2A44, 0x4A3B30, 0x23252C]

    static func crowdLook(_ look: Int) -> Look {
        let l = abs(look)
        return Look(skin: crowdSkins[l % crowdSkins.count], hair: crowdHairs[(l / 2) % crowdHairs.count],
                    top: crowdTops[l % crowdTops.count], legs: crowdLegs[(l / 3) % crowdLegs.count])
    }

    /// Harbor Patrol on foot: navy uniform and cap.
    static func officerLook(_ id: Int) -> Look {
        let skins: [UInt32] = [0x5C3A24, 0x8D5A3B, 0xB07A52, 0xD9A57A, 0xF1C9A0]
        return Look(skin: skins[abs(id) % skins.count], hair: 0x14213D, top: 0x1F3C78, legs: 0x141C30, cap: true)
    }

    static func playerLook(_ profile: PlayerProfile?) -> Look {
        guard let profile else { return Look(skin: 0x8D5A3B, hair: 0x0B0C10, top: 0xFF3EA5) }
        let n = profile.normalized
        let skins: [UInt32] = [0x5C3A24, 0x8D5A3B, 0xB07A52, 0xD9A57A, 0xF1C9A0]
        let hairs: [UInt32] = [0x15110E, 0x5A3A22, 0xD8B04A, 0xC2412D, 0xCFD3DA]
        let jackets: [UInt32] = [0xFF3EA5, 0x2EE6D6, 0xFF8A3D, 0xF4EBD9, 0x8E6BFF, 0x7BD14B, 0x3D7BFF, 0x23252C]
        return Look(skin: skins[n.skin % skins.count], hair: hairs[n.hair % hairs.count],
                    top: jackets[n.jacket % jackets.count], legs: 0x2B3140)
    }

    static let dealerLook = Look(skin: 0x8D5A3B, hair: 0xFF8A3D, top: 0x23252C, legs: 0x15161C, cap: true, coat: true)
}
