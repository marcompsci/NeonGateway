import UIKit
import SpriteKit
import GameCore

/// Street furniture that stands above the ground layer (v0.12): tree canopies and palms that
/// cars pass under, street lamps with pools of light, and neon shop signs on building fronts.
/// Positions come from the tile grid with a fixed hash, so the city looks the same every run.
@MainActor
enum HDProps {
    enum Kind: Hashable {
        case tree(Int)
        case palm(Int)
        /// A lamp on the kerb; `facing` is the direction (radians) the head points, toward the road.
        case lamp(facing: Double)
        case sign(String, UInt32)
    }

    struct Prop {
        let kind: Kind
        let position: CGPoint
    }

    static let signWords = ["NOODLES", "ARCADE", "HOTEL", "24H", "PAWN", "KARAOKE", "TACOS", "LAUNDRY",
                            "RAMEN", "TATTOO", "VINYL", "DINER", "BAR", "BOBA"]
    private static let signColors: [UInt32] = [0xFF3EA5, 0x2EE6D6, 0xFF8A3D, 0x8E6BFF, 0xFFE14D, 0x7BD14B]

    private static var cache: [String: [Prop]] = [:]

    static func props(for d: District) -> [Prop] {
        if let cached = cache[d.name] { return cached }
        var out: [Prop] = []
        let t = d.tileSize
        let zones = d.zones.values.map(\.rect)
        func world(_ c: TileCoord, _ dx: Double, _ dy: Double) -> CGPoint {
            // dx right, dy down within the tile (0...1), converted to world (y up).
            CGPoint(x: (Double(c.col) + dx) * t, y: (Double(d.rows - 1 - c.row) + (1 - dy)) * t)
        }
        func kind(_ c: TileCoord, _ dc: Int, _ dr: Int) -> TileKind { d.tile(TileCoord(col: c.col + dc, row: c.row + dr)) }
        func inZone(_ p: CGPoint) -> Bool { zones.contains { $0.contains(Vec2(Double(p.x), Double(p.y))) } }

        for row in 0..<d.rows {
            for col in 0..<d.cols {
                let c = TileCoord(col: col, row: row)
                let h = HDWorld.hash(c, 77)
                switch d.tile(c) {
                case .sidewalk:
                    // Which side the road is on, if any.
                    let roadSide: (Double, Double)? =
                        kind(c, 1, 0) == .road ? (1, 0) : kind(c, -1, 0) == .road ? (-1, 0)
                        : kind(c, 0, 1) == .road ? (0, 1) : kind(c, 0, -1) == .road ? (0, -1) : nil
                    if h % 10 < 3 {
                        // A tree on the kerb side, or the middle of a plain path.
                        let (sx, sy) = roadSide ?? (0, 0)
                        let p = world(c, 0.5 + sx * 0.28, 0.5 + sy * 0.28)
                        guard !inZone(p) else { continue }
                        let variant = Int(h / 10 % 3)
                        out.append(Prop(kind: row >= 14 && h % 2 == 0 ? .palm(variant) : .tree(variant), position: p))
                    } else if let side = roadSide, (col + row) % 2 == 0 {
                        let (sx, sy) = side
                        let p = world(c, 0.5 + sx * 0.4, 0.5 + sy * 0.4)
                        // World y is flipped from map rows.
                        out.append(Prop(kind: .lamp(facing: atan2(-sy, sx)), position: p))
                    }
                case .plaza:
                    if h % 3 == 0 {
                        out.append(Prop(kind: .tree(Int(h % 3)), position: world(c, 0.3 + Double(h % 5) * 0.1, 0.35)))
                    }
                case .building:
                    // A neon sign on some south-facing fronts, over the upper windows.
                    if !kind(c, 0, 1).isSolid && h % 3 == 0 {
                        let word = signWords[Int(h / 3 % UInt64(signWords.count))]
                        let colour = signColors[Int(h / 7 % UInt64(signColors.count))]
                        let south = Double(d.rows - 1 - row) * t
                        let p = CGPoint(x: (Double(col) + 0.5) * t, y: south + Double(HDWorld.facade) - 10)
                        out.append(Prop(kind: .sign(word, colour), position: p))
                    }
                case .grass where d.isLarge:
                    // The odd lone tree out in the country.
                    if h % 29 == 0 {
                        out.append(Prop(kind: .tree(Int(h / 29 % 3)), position: world(c, 0.5, 0.5)))
                    }
                case .sand where d.isLarge:
                    if h % 61 == 0 {
                        out.append(Prop(kind: .palm(Int(h / 61 % 3)), position: world(c, 0.5, 0.5)))
                    }
                default:
                    break
                }
            }
        }
        cache[d.name] = out
        return out
    }

    private static var chunkCache: [String: [Int: [Prop]]] = [:]

    /// Props whose spot falls in the chunk with top-left tile (`col0`, `row0`) (big maps stream them).
    static func props(for d: District, chunkCol0 col0: Int, row0: Int) -> [Prop] {
        let size = HDWorld.chunkTiles(for: d)
        if chunkCache[d.name] == nil {
            var buckets: [Int: [Prop]] = [:]
            let t = d.tileSize
            for prop in props(for: d) {
                let col = Int(Double(prop.position.x) / t)
                let row = d.rows - 1 - Int(Double(prop.position.y) / t)
                let key = (row / size * size) * 100_000 + (col / size * size)
                buckets[key, default: []].append(prop)
            }
            chunkCache[d.name] = buckets
        }
        return chunkCache[d.name]?[row0 * 100_000 + col0] ?? []
    }

    // MARK: Art

    private static var textures: [Kind: SKTexture] = [:]

    static func texture(_ requested: Kind) -> SKTexture {
        var kind = requested
        if case .lamp = kind { kind = .lamp(facing: 0) }
        if let t = textures[kind] { return t }
        let t: SKTexture
        switch kind {
        case .tree(let v): t = HDArt.texture(treeImage(v))
        case .palm(let v): t = HDArt.texture(palmImage(v))
        case .lamp: t = HDArt.texture(lampImage())
        case .sign(let word, let hex): t = HDArt.texture(signImage(word, hex))
        }
        textures[kind] = t
        return t
    }

    static let treeSize = CGSize(width: 84, height: 84)
    static let palmSize = CGSize(width: 92, height: 92)
    static let lampSize = CGSize(width: 34, height: 12)

    private static func treeImage(_ v: Int) -> UIImage {
        let greens: [[UInt32]] = [[0x163828, 0x245C40, 0x3D8A5C, 0x8CCB8A],
                                  [0x1D3527, 0x2E5A3C, 0x4F8650, 0xA9CF7E],
                                  [0x143537, 0x225C59, 0x3A8C80, 0x86D3B8]]
        let pal = greens[v % greens.count]
        return HDArt.render(treeSize) { g in
            let c = CGPoint(x: treeSize.width / 2, y: treeSize.height / 2)
            var rng = SeededRandom(seed: UInt64(41 + v))
            func rnd() -> CGFloat { CGFloat(rng.next() % 1000) / 1000 }
            // Underside mass with a soft shadow.
            g.saveGState()
            g.setShadow(offset: CGSize(width: 1.5, height: 2), blur: 3 * HDArt.density, color: UIColor(white: 0, alpha: 0.55).cgColor)
            let mass = CGMutablePath()
            mass.addEllipse(in: CGRect(x: c.x - 33, y: c.y - 31, width: 66, height: 64))
            HDArt.fill(g, mass, HDArt.color(pal[0]))
            g.restoreGState()
            // Leaf clumps, back to front: each one lit from the north-west with a dark rim.
            var clumps: [(CGPoint, CGFloat)] = []
            for k in 0..<13 {
                let a = rnd() * 2 * .pi, d = k == 0 ? 0 : 6 + rnd() * 20
                clumps.append((CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d), 11 + rnd() * 7))
            }
            // Clumps further south-east first so the lit north-west ones sit on top.
            clumps.sort { ($0.0.x + $0.0.y) > ($1.0.x + $1.0.y) }
            for (p, r) in clumps {
                let clump = CGMutablePath()
                clump.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                g.saveGState()
                g.setShadow(offset: CGSize(width: 1.2, height: 1.6), blur: 1.5 * HDArt.density, color: HDArt.color(pal[0], 0.9).cgColor)
                HDArt.fill(g, clump, HDArt.color(pal[1]))
                g.restoreGState()
                g.saveGState()
                g.addPath(clump)
                g.clip()
                HDArt.radial(g, [HDArt.color(pal[3], 0.85), HDArt.color(pal[2], 0.9), HDArt.color(pal[1], 0)],
                             [0, 0.45, 1], center: CGPoint(x: p.x - r * 0.4, y: p.y - r * 0.45), radius: r * 1.25)
                g.restoreGState()
            }
            // A few bright leaf glints.
            for _ in 0..<18 {
                let a = rnd() * 2 * .pi, d = rnd() * 24
                let leaf = CGMutablePath()
                leaf.addEllipse(in: CGRect(x: c.x - 8 + cos(a) * d, y: c.y - 8 + sin(a) * d, width: 2.6, height: 1.8))
                HDArt.fill(g, leaf, HDArt.color(pal[3], 0.55))
            }
        }
    }

    private static func palmImage(_ v: Int) -> UIImage {
        HDArt.render(palmSize) { g in
            let c = CGPoint(x: palmSize.width / 2, y: palmSize.height / 2)
            var rng = SeededRandom(seed: UInt64(91 + v))
            func rnd() -> CGFloat { CGFloat(rng.next() % 1000) / 1000 }
            let fronds = 9
            g.saveGState()
            g.setShadow(offset: .zero, blur: 2.5 * HDArt.density, color: UIColor(white: 0, alpha: 0.5).cgColor)
            for i in 0..<fronds {
                let a = CGFloat(i) / CGFloat(fronds) * 2 * .pi + rnd() * 0.4
                let len = 34 + rnd() * 8
                let tip = CGPoint(x: c.x + cos(a) * len, y: c.y + sin(a) * len)
                let bend = CGPoint(x: c.x + cos(a + 0.25) * len * 0.6, y: c.y + sin(a + 0.25) * len * 0.6)
                let side = CGPoint(x: cos(a + .pi / 2) * 6, y: sin(a + .pi / 2) * 6)
                let leaf = CGMutablePath()
                leaf.move(to: c)
                leaf.addQuadCurve(to: tip, control: CGPoint(x: bend.x + side.x, y: bend.y + side.y))
                leaf.addQuadCurve(to: c, control: CGPoint(x: bend.x - side.x, y: bend.y - side.y))
                HDArt.fill(g, leaf, HDArt.color(i % 2 == 0 ? 0x2F7A4A : 0x3E9356))
                // Midrib.
                let rib = CGMutablePath()
                rib.move(to: c)
                rib.addQuadCurve(to: tip, control: bend)
                HDArt.stroke(g, rib, HDArt.color(0x9ED08A, 0.45), 0.8)
            }
            g.restoreGState()
            let crown = CGMutablePath()
            crown.addEllipse(in: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
            HDArt.fill(g, crown, HDArt.color(0x6B4E33))
            let nut = CGMutablePath()
            nut.addEllipse(in: CGRect(x: c.x - 3, y: c.y - 4, width: 5, height: 5))
            HDArt.fill(g, nut, HDArt.color(0x3A2A1C))
        }
    }

    /// A lamp seen from above: the post's cap at the left, the arm and the lit head at the right.
    private static func lampImage() -> UIImage {
        HDArt.render(lampSize) { g in
            let s = lampSize
            g.saveGState()
            g.setShadow(offset: CGSize(width: 1.5, height: 2), blur: 1.5 * HDArt.density, color: UIColor(white: 0, alpha: 0.6).cgColor)
            let post = CGMutablePath()
            post.addEllipse(in: CGRect(x: 1, y: s.height / 2 - 4, width: 8, height: 8))
            HDArt.fill(g, post, HDArt.color(0x3A3F4B))
            HDArt.fill(g, HDArt.capsule(CGRect(x: 5, y: s.height / 2 - 1.2, width: s.width - 14, height: 2.4)), HDArt.color(0x4A4F5C))
            HDArt.fill(g, HDArt.rounded(CGRect(x: s.width - 13, y: s.height / 2 - 3.5, width: 12, height: 7), 3), HDArt.color(0x2A2D35))
            g.restoreGState()
            HDArt.lamp(g, CGRect(x: s.width - 11.5, y: s.height / 2 - 2, width: 9, height: 4), HDArt.color(0xFFE2A8), glow: 2.5)
        }
    }

    static func signSize(_ word: String) -> CGSize {
        CGSize(width: CGFloat(word.count) * 10 + 20, height: 22)
    }

    private static func signImage(_ word: String, _ hex: UInt32) -> UIImage {
        let size = signSize(word)
        return HDArt.render(size) { g in
            let neon = HDArt.color(hex)
            let box = CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4)
            HDArt.fill(g, HDArt.rounded(box, 4), HDArt.color(0x0B0C10, 0.85))
            g.saveGState()
            g.setShadow(offset: .zero, blur: 3 * HDArt.density, color: neon.cgColor)
            HDArt.stroke(g, HDArt.rounded(box.insetBy(dx: 1.5, dy: 1.5), 3), neon, 1.4)
            let text = NSAttributedString(string: word, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .heavy),
                .foregroundColor: HDArt.lighter(neon, 0.35),
                .kern: 1.0
            ])
            let tsize = text.size()
            UIGraphicsPushContext(g)
            text.draw(at: CGPoint(x: (size.width - tsize.width) / 2, y: (size.height - tsize.height) / 2))
            UIGraphicsPopContext()
            g.restoreGState()
        }
    }
}
