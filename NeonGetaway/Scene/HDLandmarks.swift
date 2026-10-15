import UIKit
import SpriteKit
import GameCore

/// Solara's landmarks, drawn from above with a long south-east shadow so they read as tall.
/// All original designs: they're meant to feel like road-trip icons, not copy real ones.
@MainActor
enum HDLandmarks {
    private static var textures: [String: SKTexture] = [:]

    /// The node for one landmark, centred on its footprint (nil for ones drawn by the ground, like the lake).
    static func node(for landmark: Landmark, lightLevel: CGFloat, reduceMotion: Bool) -> SKNode? {
        let f = landmark.footprint
        let size = CGSize(width: f.width, height: f.height)
        let node = SKNode()
        node.position = CGPoint(x: f.center.x, y: f.center.y)
        node.zPosition = 30
        switch landmark.kind {
        case .lake:
            return nil
        case .suspensionBridge:
            node.addChild(sprite("bridge", size) { bridge($0, size) })
        case .needleTower:
            node.addChild(shadow(size, length: 420))
            node.addChild(sprite("needle", size) { needle($0, size) })
            if lightLevel > 0 { node.addChild(glow(0xFFE14D, radius: size.width * 0.9, alpha: 0.45 * lightLevel)) }
        case .ferrisWheel:
            node.addChild(shadow(size, length: 180))
            let wheel = sprite("wheel", size) { ferrisWheel($0, size) }
            if !reduceMotion { wheel.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 60))) }
            node.addChild(wheel)
            if lightLevel > 0 { node.addChild(glow(0xFF3EA5, radius: size.width * 0.8, alpha: 0.5 * lightLevel)) }
        case .observatory:
            node.addChild(shadow(size, length: 120))
            node.addChild(sprite("observatory", size) { observatory($0, size) })
        case .giantTrees:
            node.addChild(shadow(size, length: 260, roundness: 1))
            node.addChild(sprite("titan\(Int(f.minX) % 3)", size) { giantTree($0, size, variant: Int(f.minX) % 3) })
        case .graniteDome:
            node.addChild(shadow(size, length: 260, roundness: 0.9))
            node.addChild(sprite("dome", size) { graniteDome($0, size) })
        case .glowTower:
            node.addChild(shadow(size, length: 520))
            node.addChild(sprite("glow", size) { glowTower($0, size) })
            node.addChild(glow(0x2EE6D6, radius: size.width * 1.1, alpha: 0.25 + 0.5 * lightLevel))
            node.addChild(glow(0xFF3EA5, radius: size.width * 0.6, alpha: 0.3 + 0.5 * lightLevel))
        case .arches:
            node.addChild(shadow(size, length: 90))
            node.addChild(sprite("arch", size) { arch($0, size) })
        case .geyser:
            node.addChild(sprite("geyser", size) { geyser($0, size) })
            if !reduceMotion { node.addChild(eruption(size)) }
        }
        return node
    }

    // MARK: Plumbing

    private static func sprite(_ key: String, _ size: CGSize, _ draw: (CGContext) -> Void) -> SKSpriteNode {
        let fullKey = "\(key)|\(Int(size.width))x\(Int(size.height))"
        if let t = textures[fullKey] { return SKSpriteNode(texture: t, size: size) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
        let t = SKTexture(image: image)
        t.filteringMode = .linear
        textures[fullKey] = t
        return SKSpriteNode(texture: t, size: size)
    }

    /// A soft dark shape thrown to the south-east (tall things cast long shadows).
    private static func shadow(_ size: CGSize, length: CGFloat, roundness: CGFloat = 0.5) -> SKSpriteNode {
        let s = SKSpriteNode(texture: HDArt.glowTexture(0x000000), size: CGSize(width: size.width * (0.8 + roundness * 0.2),
                                                                                  height: size.height * (0.8 + roundness * 0.2)))
        s.color = .black
        s.colorBlendFactor = 1
        s.alpha = 0.55
        s.position = CGPoint(x: length * 0.35, y: -length * 0.45)
        s.zPosition = -29
        return s
    }

    private static func glow(_ hex: UInt32, radius: CGFloat, alpha: CGFloat) -> SKSpriteNode {
        let g = SKSpriteNode(texture: HDArt.glowTexture(hex), size: CGSize(width: radius * 2, height: radius * 2))
        g.blendMode = .add
        g.alpha = alpha
        g.zPosition = DriveScene.lightZ - 30
        return g
    }

    private static func circle(_ g: CGContext, _ c: CGPoint, _ r: CGFloat, _ color: UIColor) {
        HDArt.fill(g, CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil), color)
    }

    // MARK: The landmarks

    /// The Crimson Span: two red towers astride the deck, main cables along both edges, suspenders.
    private static func bridge(_ g: CGContext, _ s: CGSize) {
        let red = HDArt.color(0xC8322B), redLight = HDArt.color(0xF0614F), redDark = HDArt.color(0x7E1C17)
        // Deck runs north–south through the middle two tiles of the footprint.
        let deckL = s.width / 2 - 128, deckR = s.width / 2 + 128
        let towers: [CGFloat] = [s.height * 0.22, s.height * 0.78]
        // Main cables: slight sag drawn as a curve between the towers on each side.
        for x in [deckL - 6, deckR + 6] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: towers[0]))
            p.addQuadCurve(to: CGPoint(x: x, y: towers[1]), control: CGPoint(x: x + (x < s.width / 2 ? 10 : -10), y: s.height / 2))
            p.addLine(to: CGPoint(x: x, y: s.height))
            HDArt.stroke(g, p, redDark, 9)
            HDArt.stroke(g, p, red, 6)
            HDArt.stroke(g, p, redLight, 1.5)
        }
        // Suspenders across the deck edges.
        for y in stride(from: CGFloat(20), to: s.height, by: 34) {
            HDArt.color(0xE04A3E, 0.8).setFill()
            g.fill(CGRect(x: deckL - 10, y: y, width: 10, height: 2))
            g.fill(CGRect(x: deckR, y: y, width: 10, height: 2))
        }
        // Towers: two legs outside the deck joined by portal beams, lit from the north-west.
        for y in towers {
            for x in [deckL - 40, deckR + 6] {
                let leg = CGRect(x: x, y: y - 22, width: 34, height: 44)
                HDArt.fill(g, HDArt.rounded(leg.offsetBy(dx: 16, dy: 20), 4), UIColor(white: 0, alpha: 0.4))
                HDArt.fill(g, HDArt.rounded(leg, 4), red)
                HDArt.linear(g, [redLight, red, redDark], [0, 0.5, 1], from: CGPoint(x: leg.minX, y: leg.minY),
                             to: CGPoint(x: leg.maxX, y: leg.maxY))
                HDArt.stroke(g, HDArt.rounded(leg, 4), redDark, 2)
                // Aircraft light on top.
                circle(g, CGPoint(x: leg.midX, y: leg.midY), 4, HDArt.color(0xFF3B3B))
            }
            for dy: CGFloat in [-16, 10] {
                HDArt.fill(g, CGPath(rect: CGRect(x: deckL - 10, y: y + dy, width: deckR - deckL + 20, height: 7), transform: nil), red)
                redDark.setFill()
                g.fill(CGRect(x: deckL - 10, y: y + dy + 6, width: deckR - deckL + 20, height: 1.5))
            }
        }
    }

    private static func needle(_ g: CGContext, _ s: CGSize) {
        let c = CGPoint(x: s.width / 2, y: s.height / 2)
        // Base legs flaring out.
        for a in stride(from: CGFloat(0), to: .pi * 2, by: .pi / 3) {
            let p = CGMutablePath()
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + cos(a) * s.width * 0.48, y: c.y + sin(a) * s.width * 0.48))
            HDArt.stroke(g, p, HDArt.color(0xD8DCE4), 10)
        }
        // Saucer: halo ring, window band, roof.
        circle(g, c, s.width * 0.36, HDArt.color(0x2B2F3A))
        circle(g, c, s.width * 0.33, HDArt.color(0xF4EBD9))
        for i in 0..<36 {
            let a = CGFloat(i) / 36 * .pi * 2
            circle(g, CGPoint(x: c.x + cos(a) * s.width * 0.3, y: c.y + sin(a) * s.width * 0.3), 4, HDArt.color(0xFFC23D))
        }
        circle(g, c, s.width * 0.24, HDArt.color(0xE04A3E))
        HDArt.radial(g, [UIColor(white: 1, alpha: 0.4), UIColor(white: 1, alpha: 0)], [0, 1],
                     center: CGPoint(x: c.x - 20, y: c.y - 20), radius: s.width * 0.3)
        circle(g, c, 12, HDArt.color(0xF4EBD9))
    }

    private static func ferrisWheel(_ g: CGContext, _ s: CGSize) {
        let c = CGPoint(x: s.width / 2, y: s.height / 2)
        let r = s.width * 0.45
        let rim = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
        HDArt.stroke(g, rim, HDArt.color(0xF4EBD9), 8)
        for i in 0..<16 {
            let a = CGFloat(i) / 16 * .pi * 2
            let p = CGMutablePath()
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            HDArt.stroke(g, p, HDArt.color(0xC9CED8, 0.9), 2.5)
            let colours: [UInt32] = [0xFF3EA5, 0x2EE6D6, 0xFFE14D, 0xFF8A3D]
            let gp = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            HDArt.fill(g, HDArt.rounded(CGRect(x: gp.x - 14, y: gp.y - 11, width: 28, height: 22), 6),
                       HDArt.color(colours[i % colours.count]))
            HDArt.stroke(g, HDArt.rounded(CGRect(x: gp.x - 14, y: gp.y - 11, width: 28, height: 22), 6), HDArt.color(0x101217), 2)
        }
        circle(g, c, 22, HDArt.color(0xF4EBD9))
        circle(g, c, 10, HDArt.color(0xFF3EA5))
    }

    private static func observatory(_ g: CGContext, _ s: CGSize) {
        let c = CGPoint(x: s.width / 2, y: s.height / 2)
        // Octagonal base building.
        let base = CGMutablePath()
        for i in 0..<8 {
            let a = CGFloat(i) / 8 * .pi * 2 + .pi / 8
            let p = CGPoint(x: c.x + cos(a) * s.width * 0.48, y: c.y + sin(a) * s.width * 0.48)
            if i == 0 { base.move(to: p) } else { base.addLine(to: p) }
        }
        base.closeSubpath()
        HDArt.fill(g, base, HDArt.color(0xD9D3C4))
        HDArt.stroke(g, base, HDArt.color(0x8A8576), 4)
        // The dome, lit from the north-west, with its open slit.
        let r = s.width * 0.34
        g.saveGState()
        g.addPath(CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil))
        g.clip()
        HDArt.radial(g, [HDArt.color(0xFFFFFF), HDArt.color(0xC8CCD4), HDArt.color(0x7E848F)], [0, 0.6, 1],
                     center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35), radius: r * 1.5)
        HDArt.color(0x1A1C26).setFill()
        g.fill(CGRect(x: c.x - 14, y: c.y - r, width: 28, height: r * 1.1))
        HDArt.color(0x2EE6D6, 0.5).setFill()
        g.fill(CGRect(x: c.x - 4, y: c.y - r * 0.6, width: 8, height: r * 0.4))
        g.restoreGState()
        HDArt.stroke(g, CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil),
                     HDArt.color(0x5C626C), 3)
    }

    private static func giantTree(_ g: CGContext, _ s: CGSize, variant: Int) {
        let c = CGPoint(x: s.width / 2, y: s.height / 2)
        var rng = SeededRandom(seed: UInt64(900 + variant))
        func rnd() -> CGFloat { CGFloat(rng.next() % 1000) / 1000 }
        // Layered crown: dark mass, then lit clumps toward the north-west.
        circle(g, c, s.width * 0.48, HDArt.color(0x12301A))
        for k in 0..<26 {
            let a = rnd() * .pi * 2, d = rnd() * s.width * 0.34
            let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
            let r = s.width * (0.08 + rnd() * 0.08)
            let tone = HDArt.mix(HDArt.color(0x1F5426), HDArt.color(0x4C9A44), CGFloat(k) / 26)
            g.saveGState()
            g.addPath(CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2), transform: nil))
            g.clip()
            HDArt.radial(g, [HDArt.mix(tone, .white, 0.2), tone, HDArt.mix(tone, .black, 0.4)], [0, 0.5, 1],
                         center: CGPoint(x: p.x - r * 0.4, y: p.y - r * 0.4), radius: r * 1.4)
            g.restoreGState()
        }
        // A glimpse of the huge red trunk in the middle.
        circle(g, c, s.width * 0.05, HDArt.color(0x7A3A22))
    }

    private static func graniteDome(_ g: CGContext, _ s: CGSize) {
        let rect = CGRect(x: s.width * 0.04, y: s.height * 0.04, width: s.width * 0.92, height: s.height * 0.92)
        let dome = CGPath(ellipseIn: rect, transform: nil)
        g.saveGState()
        g.addPath(dome)
        g.clip()
        HDArt.radial(g, [HDArt.color(0xEDE9E1), HDArt.color(0xB9B3A8), HDArt.color(0x6F6A62)], [0, 0.55, 1],
                     center: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.midY - rect.height * 0.2), radius: rect.width * 0.75)
        // The sheer face: cut straight down on the north-east side.
        HDArt.color(0x4E4A44, 0.85).setFill()
        let face = CGMutablePath()
        face.move(to: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.minY))
        face.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        face.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        face.closeSubpath()
        HDArt.fill(g, face, HDArt.color(0x4E4A44, 0.85))
        // Streaks and cracks.
        var rng = SeededRandom(seed: 77)
        for _ in 0..<40 {
            let x = rect.minX + CGFloat(rng.next() % UInt64(rect.width))
            let y = rect.minY + CGFloat(rng.next() % UInt64(rect.height))
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + CGFloat(rng.next() % 30) - 15, y: y + 30 + CGFloat(rng.next() % 50)))
            HDArt.stroke(g, p, UIColor(white: 0, alpha: 0.18), 2)
        }
        g.restoreGState()
        HDArt.stroke(g, dome, HDArt.color(0x4E4A44), 4)
        // Pines clinging round the base.
        var pines = SeededRandom(seed: 78)
        for _ in 0..<26 {
            let a = CGFloat(pines.next() % 628) / 100
            let p = CGPoint(x: rect.midX + cos(a) * rect.width * 0.47, y: rect.midY + sin(a) * rect.height * 0.47)
            circle(g, p, 16 + CGFloat(pines.next() % 10), HDArt.color(0x214D2A))
            circle(g, CGPoint(x: p.x - 4, y: p.y - 4), 8, HDArt.color(0x3A7A3E))
        }
    }

    private static func glowTower(_ g: CGContext, _ s: CGSize) {
        let c = CGPoint(x: s.width / 2, y: s.height / 2)
        circle(g, c, s.width * 0.46, HDArt.color(0x14101E))
        for (i, hex) in [0xFF3EA5, 0x2EE6D6, 0xFF3EA5, 0xFFE14D].enumerated() {
            let r = s.width * (0.42 - CGFloat(i) * 0.09)
            HDArt.stroke(g, CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil),
                         HDArt.color(UInt32(hex)), 7)
        }
        circle(g, c, 18, HDArt.color(0xF4EBD9))
    }

    private static func arch(_ g: CGContext, _ s: CGSize) {
        // A sandstone horseshoe seen from above: thick band, lighter on top, dark underside gap.
        let band = CGMutablePath()
        band.addRoundedRect(in: CGRect(x: 6, y: 10, width: s.width - 12, height: s.height - 20), cornerWidth: 40, cornerHeight: 40)
        HDArt.fill(g, band, HDArt.color(0xB4532F))
        g.saveGState()
        g.addPath(band)
        g.clip()
        HDArt.linear(g, [HDArt.color(0xE08A55), HDArt.color(0xB4532F), HDArt.color(0x7A2E18)], [0, 0.5, 1],
                     from: CGPoint(x: 0, y: 10), to: CGPoint(x: 0, y: s.height - 10))
        // Strata lines.
        for y in stride(from: CGFloat(18), to: s.height - 14, by: 12) {
            HDArt.color(0x6E2A16, 0.35).setFill()
            g.fill(CGRect(x: 0, y: y, width: s.width, height: 2))
        }
        g.restoreGState()
        // The opening: you can see the desert through it.
        let gap = HDArt.rounded(CGRect(x: s.width * 0.22, y: s.height * 0.32, width: s.width * 0.56, height: s.height * 0.36), 30)
        HDArt.fill(g, gap, HDArt.color(0xD8B47A))
        HDArt.stroke(g, gap, HDArt.color(0x5E2312), 4)
    }

    private static func geyser(_ g: CGContext, _ s: CGSize) {
        let c = CGPoint(x: s.width / 2, y: s.height / 2)
        // Mineral terraces in orange and cream rings, a blue pool in the middle.
        circle(g, c, s.width * 0.48, HDArt.color(0xE0A15A))
        circle(g, c, s.width * 0.4, HDArt.color(0xF2E2C2))
        circle(g, c, s.width * 0.32, HDArt.color(0xE88A3A))
        g.saveGState()
        let r = s.width * 0.25
        g.addPath(CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil))
        g.clip()
        HDArt.radial(g, [HDArt.color(0x1B4E8C), HDArt.color(0x2EA8C8), HDArt.color(0x9BE3D6)], [0, 0.6, 1],
                     center: c, radius: r)
        g.restoreGState()
    }

    /// Old Steady goes up every 30 seconds or so: a column of steam puffs that rise and fade.
    private static func eruption(_ s: CGSize) -> SKNode {
        let node = SKNode()
        node.zPosition = 40
        let cycle = 30.0
        for i in 0..<14 {
            let puff = SKSpriteNode(texture: HDArt.glowTexture(0xFFFFFF), size: CGSize(width: 90, height: 90))
            puff.alpha = 0
            let home = CGPoint(x: CGFloat(i % 3) * 14 - 14, y: 0)
            puff.position = home
            node.addChild(puff)
            let delay = Double(i) * 0.12
            let rise = SKAction.group([
                .moveBy(x: CGFloat(i % 5) * 20 - 40, y: 120 + CGFloat(i) * 22, duration: 3),
                .scale(to: 3 + CGFloat(i % 4), duration: 3),
                .sequence([.fadeAlpha(to: 0.85, duration: 0.3), .fadeOut(withDuration: 2.7)])
            ])
            let reset = SKAction.group([.move(to: home, duration: 0), .scale(to: 1, duration: 0)])
            puff.run(.repeatForever(.sequence([.wait(forDuration: 6 + delay), rise, reset,
                                               .wait(forDuration: cycle - 9 - delay)])))
        }
        return node
    }
}
