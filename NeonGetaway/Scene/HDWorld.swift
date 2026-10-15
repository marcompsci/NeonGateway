import UIKit
import SpriteKit
import GameCore

/// The street itself at full resolution (v0.12): asphalt with grain, kerbs, crosswalks and
/// lane paint; paved sidewalks; rooftops with parapets, AC units, skylights and water tanks;
/// lit shopfronts on the south faces of buildings; container yards, timber docks and water.
/// Shadows fall to the south-east from every building.
///
/// Drawn at one pixel per point in 8 × 8-tile chunks (1024 px square) so no single texture is
/// huge. Each tile only paints inside itself, reading its neighbours, so chunks join seamlessly.
@MainActor
enum HDWorld {
    static let chunkTiles = 8

    struct Chunk {
        let texture: SKTexture
        let origin: CGPoint
        let size: CGSize
    }

    private static var cache: [String: [Chunk]] = [:]
    private static var infoCache: [String: BlockInfo] = [:]

    /// Chunk size in tiles: 8 for a district, 4 for Solara State (small chunks build fast enough
    /// to stream in while driving).
    static func chunkTiles(for d: District) -> Int { d.isLarge ? 4 : chunkTiles }

    private static func info(for d: District) -> BlockInfo {
        if let cached = infoCache[d.name] { return cached }
        let made = BlockInfo(d)
        infoCache[d.name] = made
        return made
    }

    /// Every chunk at once (small districts).
    static func chunks(for d: District) -> [Chunk] {
        if let cached = cache[d.name] { return cached }
        var out: [Chunk] = []
        let size = chunkTiles(for: d)
        var row0 = 0
        while row0 < d.rows {
            var col0 = 0
            while col0 < d.cols {
                out.append(chunk(for: d, col0: col0, row0: row0))
                col0 += size
            }
            row0 += size
        }
        cache[d.name] = out
        return out
    }

    /// One chunk whose top-left tile is (`col0`, `row0`), built on demand (big maps stream these).
    static func chunk(for d: District, col0: Int, row0: Int) -> Chunk {
        let size = chunkTiles(for: d)
        let t = CGFloat(d.tileSize)
        let cols = min(size, d.cols - col0), rows = min(size, d.rows - row0)
        let image = drawChunk(d, info(for: d), col0: col0, row0: row0, cols: cols, rows: rows)
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        // World y grows north; map rows grow south.
        let origin = CGPoint(x: CGFloat(col0) * t, y: CGFloat(d.rows - row0 - rows) * t)
        return Chunk(texture: texture, origin: origin, size: CGSize(width: CGFloat(cols) * t, height: CGFloat(rows) * t))
    }

    // MARK: Neighbourhood facts

    /// Which building block each building tile belongs to (for a consistent roof per block).
    struct BlockInfo {
        var block: [Int: Int] = [:]

        init(_ d: District) {
            var next = 0
            for row in 0..<d.rows {
                for col in 0..<d.cols where d.tile(TileCoord(col: col, row: row)) == .building {
                    let key = row * d.cols + col
                    guard block[key] == nil else { continue }
                    var stack = [TileCoord(col: col, row: row)]
                    block[key] = next
                    while let c = stack.popLast() {
                        for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                            let n = TileCoord(col: c.col + dc, row: c.row + dr)
                            guard n.col >= 0, n.row >= 0, n.col < d.cols, n.row < d.rows,
                                  d.tile(n) == .building else { continue }
                            let k = n.row * d.cols + n.col
                            if block[k] == nil {
                                block[k] = next
                                stack.append(n)
                            }
                        }
                    }
                    next += 1
                }
            }
        }

        func id(_ d: District, _ c: TileCoord) -> Int { block[c.row * d.cols + c.col] ?? 0 }
    }

    static func hash(_ c: TileCoord, _ salt: UInt64) -> UInt64 {
        var x = UInt64(bitPattern: Int64(c.col &* 73_856_093 ^ c.row &* 19_349_663)) ^ (salt &* 0x9E37_79B9_7F4A_7C15)
        x ^= x >> 33
        x &*= 0xff51_afd7_ed55_8ccd
        x ^= x >> 33
        x &*= 0xc4ce_b9fe_1a85_ec53
        x ^= x >> 33
        return x
    }

    static func unit(_ c: TileCoord, _ salt: UInt64) -> CGFloat {
        CGFloat(hash(c, salt) % 10_000) / 10_000
    }

    private static func kind(_ d: District, _ c: TileCoord, _ dc: Int, _ dr: Int) -> TileKind {
        d.tile(TileCoord(col: c.col + dc, row: c.row + dr))
    }

    static func isIntersection(_ d: District, _ c: TileCoord) -> Bool {
        d.tile(c) == .road && [(1, 0), (-1, 0), (0, 1), (0, -1)].allSatisfy { kind(d, c, $0.0, $0.1) == .road }
    }

    // MARK: Drawing a chunk

    private static func drawChunk(_ d: District, _ info: BlockInfo, col0: Int, row0: Int, cols: Int, rows: Int) -> UIImage {
        let t = CGFloat(d.tileSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: CGFloat(cols) * t, height: CGFloat(rows) * t)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let g = ctx.cgContext
            func each(_ pad: Int, _ body: (TileCoord, CGPoint) -> Void) {
                for row in (row0 - pad)..<(row0 + rows + pad) {
                    for col in (col0 - pad)..<(col0 + cols + pad) {
                        guard row >= 0, col >= 0, row < d.rows, col < d.cols else { continue }
                        body(TileCoord(col: col, row: row), CGPoint(x: CGFloat(col - col0) * t, y: CGFloat(row - row0) * t))
                    }
                }
            }
            each(0) { c, o in
                g.saveGState()
                g.clip(to: CGRect(x: o.x, y: o.y, width: t, height: t))
                drawTile(g, d, info, c, o, t)
                g.restoreGState()
            }
            // Paint and shadows can cross tile seams, so neighbours outside the chunk join in.
            each(1) { c, o in drawMarkings(g, d, c, o, t) }
            each(1) { c, o in drawShadows(g, d, c, o, t) }
        }
    }

    /// Speckle is drawn once per material into a few tile-sized patterns and stamped, rather
    /// than thousands of single-pixel fills per tile (much faster to build the city).
    private static var noiseCache: [String: CGImage] = [:]

    private static func noise(_ g: CGContext, _ c: TileCoord, _ o: CGPoint, _ t: CGFloat, count: Int,
                              colors: [UIColor], size: CGFloat = 1, salt: UInt64 = 1) {
        let variant = Int(hash(c, salt) % 4)
        let key = "\(colors.map { $0.description }.joined())|\(count)|\(size)|\(salt)|\(variant)|\(t)"
        let image: CGImage
        if let cached = noiseCache[key] {
            image = cached
        } else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let made = UIGraphicsImageRenderer(size: CGSize(width: t, height: t), format: format).image { ctx in
                let p = ctx.cgContext
                var s = UInt64(variant + 1) &* 0x9E37_79B9_7F4A_7C15 ^ salt
                for _ in 0..<count {
                    s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    let x = CGFloat((s >> 16) % UInt64(t)), y = CGFloat((s >> 32) % UInt64(t))
                    colors[Int((s >> 48) % UInt64(colors.count))].setFill()
                    p.fill(CGRect(x: x, y: y, width: size, height: size))
                }
            }
            guard let cg = made.cgImage else { return }
            noiseCache[key] = cg
            image = cg
        }
        g.draw(image, in: CGRect(x: o.x, y: o.y, width: t, height: t))
    }

    private static func drawTile(_ g: CGContext, _ d: District, _ info: BlockInfo, _ c: TileCoord, _ o: CGPoint, _ t: CGFloat) {
        let r = CGRect(x: o.x, y: o.y, width: t, height: t)
        switch d.tile(c) {
        case .road: road(g, d, c, r)
        case .sidewalk: sidewalk(g, d, c, r)
        case .alley: alley(g, d, c, r)
        case .dock: dock(g, d, c, r)
        case .plaza: plaza(g, d, c, r)
        case .safehouse: safehouse(g, d, c, r)
        case .building: building(g, d, info, c, r)
        case .container: container(g, d, c, r)
        case .fence: fence(g, d, c, r)
        case .water: water(g, d, c, r)
        case .highway: highway(g, d, c, r)
        case .bridge: bridge(g, d, c, r)
        case .grass: grass(g, d, c, r)
        case .sand: sand(g, d, c, r)
        case .forest: forest(g, d, c, r)
        case .rock: rock(g, d, c, r)
        case .landmark: landmarkGround(g, d, c, r)
        }
    }

    // MARK: Open country (Solara State)

    private static func asphalt(_ g: CGContext, _ c: TileCoord, _ r: CGRect) {
        HDArt.color(0x22252D).setFill()
        g.fill(r)
        noise(g, c, r.origin, r.width, count: 1200,
              colors: [HDArt.color(0x2A2E38), HDArt.color(0x1A1C22), HDArt.color(0x2D313B)])
    }

    private static func highway(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        asphalt(g, c, r)
        func paved(_ dc: Int, _ dr: Int) -> Bool { kind(d, c, dc, dr).isRoad }
        // White edge lines where the shoulder starts.
        let edge = HDArt.color(0xF4EBD9, 0.75)
        if !paved(0, -1) { edge.setFill(); g.fill(CGRect(x: r.minX, y: r.minY + 6, width: r.width, height: 3)) }
        if !paved(0, 1) { edge.setFill(); g.fill(CGRect(x: r.minX, y: r.maxY - 9, width: r.width, height: 3)) }
        if !paved(-1, 0) { edge.setFill(); g.fill(CGRect(x: r.minX + 6, y: r.minY, width: 3, height: r.height)) }
        if !paved(1, 0) { edge.setFill(); g.fill(CGRect(x: r.maxX - 9, y: r.minY, width: 3, height: r.height)) }
    }

    private static func bridge(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        water(g, d, c, r)
        // Deck with a red railing on the open sides.
        let deck = r.insetBy(dx: 0, dy: 0)
        asphalt(g, c, deck)
        func paved(_ dc: Int, _ dr: Int) -> Bool { kind(d, c, dc, dr).isRoad }
        let rail = HDArt.color(0xC8322B), railLight = HDArt.color(0xF0614F)
        if !paved(-1, 0) {
            rail.setFill(); g.fill(CGRect(x: r.minX, y: r.minY, width: 8, height: r.height))
            railLight.setFill(); g.fill(CGRect(x: r.minX + 1, y: r.minY, width: 2, height: r.height))
        }
        if !paved(1, 0) {
            rail.setFill(); g.fill(CGRect(x: r.maxX - 8, y: r.minY, width: 8, height: r.height))
            railLight.setFill(); g.fill(CGRect(x: r.maxX - 3, y: r.minY, width: 2, height: r.height))
        }
        if !paved(0, -1) {
            rail.setFill(); g.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 8))
        }
        if !paved(0, 1) {
            rail.setFill(); g.fill(CGRect(x: r.minX, y: r.maxY - 8, width: r.width, height: 8))
        }
    }

    private static func grass(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        let tone = unit(TileCoord(col: c.col / 3, row: c.row / 3), 61)
        HDArt.mix(HDArt.color(0x3E7A3A), HDArt.color(0x4C8A3C), tone).setFill()
        g.fill(r)
        noise(g, c, r.origin, r.width, count: 900,
              colors: [HDArt.color(0x5B9A45), HDArt.color(0x34692F), HDArt.color(0x6AA851), HDArt.color(0x2E5E2B)], size: 2, salt: 3)
        // Wildflowers now and then.
        if hash(c, 62) % 5 == 0 {
            noise(g, c, r.origin, r.width, count: 40, colors: [HDArt.color(0xFFE14D), HDArt.color(0xF4EBD9), HDArt.color(0xFF8AC0)],
                  size: 3, salt: 9)
        }
        roadsideDust(g, d, c, r, color: HDArt.color(0x7C6A49, 0.35))
    }

    private static func sand(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        let tone = unit(TileCoord(col: c.col / 4, row: c.row / 4), 71)
        HDArt.mix(HDArt.color(0xD8B47A), HDArt.color(0xE6C48C), tone).setFill()
        g.fill(r)
        noise(g, c, r.origin, r.width, count: 900,
              colors: [HDArt.color(0xC79F66), HDArt.color(0xEED6A4), HDArt.color(0xB98E57)], size: 2, salt: 4)
        // Wind ripples.
        for i in 0..<4 {
            let y = r.minY + 14 + CGFloat(i) * 30 + unit(c, UInt64(80 + i)) * 10
            let p = CGMutablePath()
            p.move(to: CGPoint(x: r.minX, y: y))
            p.addCurve(to: CGPoint(x: r.maxX, y: y + 4), control1: CGPoint(x: r.minX + 40, y: y - 6),
                       control2: CGPoint(x: r.minX + 88, y: y + 10))
            HDArt.stroke(g, p, HDArt.color(0xA87E4A, 0.35), 1.5)
        }
        // Scrub bushes.
        if hash(c, 73) % 4 == 0 {
            let x = r.minX + 20 + unit(c, 74) * 80, y = r.minY + 20 + unit(c, 75) * 80
            let bush = CGMutablePath()
            bush.addEllipse(in: CGRect(x: x, y: y, width: 16, height: 13))
            HDArt.fill(g, bush, HDArt.color(0x6F7A3A))
            let tip = CGMutablePath()
            tip.addEllipse(in: CGRect(x: x + 4, y: y + 2, width: 7, height: 5))
            HDArt.fill(g, tip, HDArt.color(0x95A050))
        }
    }

    /// A strip of dusty verge beside highways.
    private static func roadsideDust(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect, color: UIColor) {
        if kind(d, c, 0, -1).isRoad { HDArt.linear(g, [color, color.withAlphaComponent(0)], [0, 1],
                                                    from: CGPoint(x: 0, y: r.minY), to: CGPoint(x: 0, y: r.minY + 22)) }
        if kind(d, c, 0, 1).isRoad { HDArt.linear(g, [color.withAlphaComponent(0), color], [0, 1],
                                                   from: CGPoint(x: 0, y: r.maxY - 22), to: CGPoint(x: 0, y: r.maxY)) }
        if kind(d, c, -1, 0).isRoad { HDArt.linear(g, [color, color.withAlphaComponent(0)], [0, 1],
                                                    from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.minX + 22, y: 0)) }
        if kind(d, c, 1, 0).isRoad { HDArt.linear(g, [color.withAlphaComponent(0), color], [0, 1],
                                                   from: CGPoint(x: r.maxX - 22, y: 0), to: CGPoint(x: r.maxX, y: 0)) }
    }

    /// Forest from above: overlapping canopies, darker in the gaps, lit from the north-west.
    private static func forest(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        HDArt.color(0x183A1F).setFill()
        g.fill(r)
        var s = hash(c, 91)
        let greens: [UInt32] = [0x2E6B2F, 0x25602B, 0x357A35, 0x1F5426, 0x3F873B]
        for _ in 0..<7 {
            s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let size = CGFloat(38 + (s >> 20) % 34)
            let x = r.minX - 14 + CGFloat((s >> 28) % 130), y = r.minY - 14 + CGFloat((s >> 40) % 130)
            let crown = CGRect(x: x, y: y, width: size, height: size)
            let shadow = CGMutablePath()
            shadow.addEllipse(in: crown.offsetBy(dx: 6, dy: 7))
            HDArt.fill(g, shadow, UIColor(white: 0, alpha: 0.28))
            let p = CGMutablePath()
            p.addEllipse(in: crown)
            let base = HDArt.color(greens[Int((s >> 50) % UInt64(greens.count))])
            g.saveGState()
            g.addPath(p)
            g.clip()
            HDArt.radial(g, [HDArt.mix(base, .white, 0.22), base, HDArt.mix(base, .black, 0.35)], [0, 0.55, 1],
                         center: CGPoint(x: crown.minX + size * 0.35, y: crown.minY + size * 0.35), radius: size * 0.75)
            g.restoreGState()
        }
    }

    private static func rock(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        let desert = c.col > 150
        let base = desert ? HDArt.color(0xA4583A) : HDArt.color(0x6E6A66)
        base.setFill()
        g.fill(r)
        noise(g, c, r.origin, r.width, count: 700,
              colors: [HDArt.mix(base, .white, 0.18), HDArt.mix(base, .black, 0.25)], size: 2, salt: 5)
        // Facets: light on the north-west faces, shade to the south-east.
        var s = hash(c, 95)
        for _ in 0..<4 {
            s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let x = r.minX + CGFloat((s >> 20) % 100), y = r.minY + CGFloat((s >> 32) % 100)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + 30, y: y + 6))
            p.addLine(to: CGPoint(x: x + 18, y: y + 28))
            p.closeSubpath()
            HDArt.fill(g, p, UIColor(white: 1, alpha: 0.08))
            let q = CGMutablePath()
            q.move(to: CGPoint(x: x + 30, y: y + 6))
            q.addLine(to: CGPoint(x: x + 18, y: y + 28))
            q.addLine(to: CGPoint(x: x + 34, y: y + 30))
            q.closeSubpath()
            HDArt.fill(g, q, UIColor(white: 0, alpha: 0.18))
        }
        // Edges facing open ground get a dark lip.
        if !kind(d, c, 0, 1).isSolid {
            HDArt.linear(g, [UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.35)], [0, 1],
                         from: CGPoint(x: 0, y: r.maxY - 18), to: CGPoint(x: 0, y: r.maxY))
        }
    }

    /// Under a landmark: paving (the landmark's own art sits on top).
    private static func landmarkGround(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        HDArt.color(0x3A3F49).setFill()
        g.fill(r)
        noise(g, c, r.origin, r.width, count: 300, colors: [HDArt.color(0x444A55), HDArt.color(0x30343C)])
    }

    // MARK: Ground types

    private static func road(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        HDArt.color(0x20232C).setFill()
        g.fill(r)
        // Tonal patches so the asphalt isn't flat.
        for i in 0..<3 {
            let u = HDWorld.unit(c, UInt64(10 + i)), v = HDWorld.unit(c, UInt64(20 + i))
            let p = CGMutablePath()
            p.addEllipse(in: CGRect(x: r.minX + u * 100 - 20, y: r.minY + v * 100 - 14, width: 70, height: 46))
            HDArt.fill(g, p, i == 0 ? UIColor(white: 1, alpha: 0.015) : UIColor(white: 0, alpha: 0.05))
        }
        noise(g, c, r.origin, r.width, count: 1400,
              colors: [HDArt.color(0x272B35), HDArt.color(0x191B22), HDArt.color(0x2A2E38), HDArt.color(0x16181E)])
        noise(g, c, r.origin, r.width, count: 30, colors: [HDArt.color(0x2F333E)], size: 2, salt: 7)
        // Tyre polish along the lanes: lighter where the wheels run.
        let vertical = kind(d, c, 0, -1) == .road && kind(d, c, 0, 1) == .road
        let horizontal = kind(d, c, -1, 0) == .road && kind(d, c, 1, 0) == .road
        if vertical && !horizontal {
            for x: CGFloat in [26, 58, 74, 106] {
                HDArt.linear(g, [UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: 0.035), UIColor(white: 1, alpha: 0)],
                             [0, 0.5, 1], from: CGPoint(x: r.minX + x - 7, y: 0), to: CGPoint(x: r.minX + x + 7, y: 0))
            }
        }
        // Oil stain or manhole now and then.
        let pick = hash(c, 3) % 9
        if pick == 0 {
            let p = CGMutablePath()
            p.addEllipse(in: CGRect(x: r.minX + 40, y: r.minY + 50, width: 34, height: 22))
            HDArt.fill(g, p, UIColor(white: 0, alpha: 0.22))
            let q = CGMutablePath()
            q.addEllipse(in: CGRect(x: r.minX + 46, y: r.minY + 54, width: 14, height: 9))
            HDArt.fill(g, q, HDArt.color(0x3A1F55, 0.18))
        } else if pick == 1 && !isIntersection(d, c) {
            let p = CGMutablePath()
            p.addEllipse(in: CGRect(x: r.minX + 50, y: r.minY + 46, width: 26, height: 26))
            HDArt.fill(g, p, HDArt.color(0x2A2E37))
            HDArt.stroke(g, p, HDArt.color(0x101217), 2)
            for i in 0..<4 {
                HDArt.color(0x1A1D24).setFill()
                g.fill(CGRect(x: r.minX + 53, y: r.minY + 51 + CGFloat(i) * 5, width: 20, height: 1.5))
            }
        }
        // Kerbs where the road meets a footpath.
        let kerbTop = HDArt.color(0x707684), kerbSide = HDArt.color(0x454A56)
        let walk: Set<TileKind> = [.sidewalk, .plaza, .alley, .dock, .safehouse]
        if walk.contains(kind(d, c, 0, -1)) {
            kerbSide.setFill(); g.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 5))
            kerbTop.setFill(); g.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 2))
        }
        if walk.contains(kind(d, c, 0, 1)) {
            kerbSide.setFill(); g.fill(CGRect(x: r.minX, y: r.maxY - 4, width: r.width, height: 4))
            kerbTop.setFill(); g.fill(CGRect(x: r.minX, y: r.maxY - 2, width: r.width, height: 2))
        }
        if walk.contains(kind(d, c, -1, 0)) {
            kerbSide.setFill(); g.fill(CGRect(x: r.minX, y: r.minY, width: 5, height: r.height))
            kerbTop.setFill(); g.fill(CGRect(x: r.minX, y: r.minY, width: 2, height: r.height))
        }
        if walk.contains(kind(d, c, 1, 0)) {
            kerbSide.setFill(); g.fill(CGRect(x: r.maxX - 4, y: r.minY, width: 4, height: r.height))
            kerbTop.setFill(); g.fill(CGRect(x: r.maxX - 2, y: r.minY, width: 2, height: r.height))
        }
    }

    private static func sidewalk(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        HDArt.color(0x3B404C).setFill()
        g.fill(r)
        // Concrete slabs, each a touch different.
        let slab: CGFloat = 32
        for j in 0..<4 {
            for i in 0..<4 {
                let tone = HDWorld.unit(TileCoord(col: c.col * 4 + i, row: c.row * 4 + j), 5)
                UIColor(white: tone > 0.5 ? 1 : 0, alpha: 0.02 + abs(tone - 0.5) * 0.06).setFill()
                g.fill(CGRect(x: r.minX + CGFloat(i) * slab, y: r.minY + CGFloat(j) * slab, width: slab, height: slab))
            }
        }
        noise(g, c, r.origin, r.width, count: 350, colors: [HDArt.color(0x444A57), HDArt.color(0x33373F)])
        HDArt.color(0x2C3039).setFill()
        for i in stride(from: CGFloat(0), to: r.width, by: slab) {
            g.fill(CGRect(x: r.minX + i, y: r.minY, width: 1.5, height: r.height))
            g.fill(CGRect(x: r.minX, y: r.minY + i, width: r.width, height: 1.5))
        }
        UIColor(white: 1, alpha: 0.05).setFill()
        for i in stride(from: CGFloat(0), to: r.width, by: slab) {
            g.fill(CGRect(x: r.minX + i + 1.5, y: r.minY, width: 1, height: r.height))
            g.fill(CGRect(x: r.minX, y: r.minY + i + 1.5, width: r.width, height: 1))
        }
        // A crack now and then.
        if hash(c, 9) % 4 == 0 {
            let p = CGMutablePath()
            let x = r.minX + 20 + HDWorld.unit(c, 11) * 80
            p.move(to: CGPoint(x: x, y: r.minY + 10))
            p.addLine(to: CGPoint(x: x + 8, y: r.minY + 30))
            p.addLine(to: CGPoint(x: x + 3, y: r.minY + 46))
            HDArt.stroke(g, p, UIColor(white: 0, alpha: 0.3), 1)
        }
        // Tree pits and drain grates are added as sprites; the kerb edge gets a lip here.
        let lip = HDArt.color(0x5A606D)
        if kind(d, c, 0, -1) == .road { lip.setFill(); g.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 3)) }
        if kind(d, c, 0, 1) == .road { lip.setFill(); g.fill(CGRect(x: r.minX, y: r.maxY - 3, width: r.width, height: 3)) }
        if kind(d, c, -1, 0) == .road { lip.setFill(); g.fill(CGRect(x: r.minX, y: r.minY, width: 3, height: r.height)) }
        if kind(d, c, 1, 0) == .road { lip.setFill(); g.fill(CGRect(x: r.maxX - 3, y: r.minY, width: 3, height: r.height)) }
    }

    private static func alley(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        HDArt.color(0x1E1C25).setFill()
        g.fill(r)
        // Cobbles.
        var y: CGFloat = 0, rowIndex = 0
        while y < r.height {
            var x: CGFloat = rowIndex % 2 == 0 ? 0 : -9
            while x < r.width {
                let k = TileCoord(col: c.col * 16 + Int(x / 18 + 2), row: c.row * 16 + rowIndex)
                let tone = HDWorld.unit(k, 4)
                let stone = HDArt.rounded(CGRect(x: r.minX + x + 1, y: r.minY + y + 1, width: 16, height: 10), 3)
                HDArt.fill(g, stone, HDArt.mix(HDArt.color(0x2A2733), HDArt.color(0x34303E), tone))
                HDArt.fill(g, HDArt.rounded(CGRect(x: r.minX + x + 3, y: r.minY + y + 2, width: 9, height: 2.5), 1),
                           UIColor(white: 1, alpha: 0.05))
                x += 18
            }
            y += 12
            rowIndex += 1
        }
        // Puddles that catch the neon.
        if hash(c, 2) % 3 == 0 {
            let p = CGMutablePath()
            let u = HDWorld.unit(c, 6)
            p.addEllipse(in: CGRect(x: r.minX + 20 + u * 40, y: r.minY + 44, width: 56, height: 28))
            g.saveGState()
            g.addPath(p)
            g.clip()
            HDArt.linear(g, [HDArt.color(0x0B0C14), HDArt.color(0xFF3EA5, 0.45), HDArt.color(0x2EE6D6, 0.35),
                             HDArt.color(0x0B0C14)], [0, 0.4, 0.6, 1],
                         from: CGPoint(x: r.minX, y: r.minY + 44), to: CGPoint(x: r.maxX, y: r.minY + 72))
            g.restoreGState()
            HDArt.stroke(g, p, UIColor(white: 1, alpha: 0.12), 1)
        }
        // A bit of litter.
        if hash(c, 8) % 2 == 0 {
            HDArt.fill(g, HDArt.rounded(CGRect(x: r.minX + 90, y: r.minY + 20, width: 9, height: 6), 1),
                       HDArt.color(0xF4EBD9, 0.35))
        }
    }

    private static func dock(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        HDArt.color(0x3A332D).setFill()
        g.fill(r)
        // Timber planks running east-west, staggered joins.
        let plank: CGFloat = 16
        for j in 0..<Int(r.height / plank) {
            let tone = HDWorld.unit(TileCoord(col: c.col, row: c.row * 8 + j), 12)
            HDArt.mix(HDArt.color(0x3E362F), HDArt.color(0x4A4037), tone).setFill()
            g.fill(CGRect(x: r.minX, y: r.minY + CGFloat(j) * plank, width: r.width, height: plank - 2))
            HDArt.color(0x17130F).setFill()
            g.fill(CGRect(x: r.minX, y: r.minY + CGFloat(j) * plank + plank - 2, width: r.width, height: 2))
            // Grain.
            UIColor(white: 0, alpha: 0.12).setFill()
            g.fill(CGRect(x: r.minX, y: r.minY + CGFloat(j) * plank + 5, width: r.width, height: 0.8))
            UIColor(white: 1, alpha: 0.05).setFill()
            g.fill(CGRect(x: r.minX, y: r.minY + CGFloat(j) * plank + 1, width: r.width, height: 1))
            let join = r.minX + CGFloat((j * 37 + c.col * 53) % 110) + 8
            HDArt.color(0x17130F).setFill()
            g.fill(CGRect(x: join, y: r.minY + CGFloat(j) * plank, width: 1.5, height: plank - 2))
            HDArt.color(0x8A8F9A, 0.6).setFill()
            g.fill(CGRect(x: join - 4, y: r.minY + CGFloat(j) * plank + 6, width: 1.6, height: 1.6))
            g.fill(CGRect(x: join + 3, y: r.minY + CGFloat(j) * plank + 6, width: 1.6, height: 1.6))
        }
        // Safety edge and bollards where the dock meets water.
        if kind(d, c, 0, 1) == .water {
            for i in stride(from: CGFloat(0), to: r.width, by: 16) {
                (Int(i / 16) % 2 == 0 ? HDArt.color(0xFFC23D) : HDArt.color(0x14161C)).setFill()
                g.fill(CGRect(x: r.minX + i, y: r.maxY - 7, width: 16, height: 5))
            }
            if hash(c, 4) % 2 == 0 { bollard(g, CGPoint(x: r.minX + 64, y: r.maxY - 20)) }
        }
        if kind(d, c, -1, 0) == .water {
            HDArt.color(0xFFC23D, 0.85).setFill(); g.fill(CGRect(x: r.minX + 2, y: r.minY, width: 4, height: r.height))
            bollard(g, CGPoint(x: r.minX + 18, y: r.midY))
        }
        if kind(d, c, 1, 0) == .water {
            HDArt.color(0xFFC23D, 0.85).setFill(); g.fill(CGRect(x: r.maxX - 6, y: r.minY, width: 4, height: r.height))
            bollard(g, CGPoint(x: r.maxX - 18, y: r.midY))
        }
    }

    private static func bollard(_ g: CGContext, _ p: CGPoint) {
        let base = CGMutablePath()
        base.addEllipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
        g.saveGState()
        g.setShadow(offset: CGSize(width: 3, height: 3), blur: 3, color: UIColor(white: 0, alpha: 0.6).cgColor)
        HDArt.fill(g, base, HDArt.color(0x22252C))
        g.restoreGState()
        g.saveGState()
        g.addPath(base)
        g.clip()
        HDArt.radial(g, [HDArt.color(0x6A707C), HDArt.color(0x22252C)], [0, 1], center: CGPoint(x: p.x - 2, y: p.y - 2), radius: 9)
        g.restoreGState()
    }

    private static func plaza(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        HDArt.color(0x22333A).setFill()
        g.fill(r)
        // Pavers in a herringbone-ish check with a light border.
        let s: CGFloat = 32
        for j in 0..<4 {
            for i in 0..<4 {
                let tile = CGRect(x: r.minX + CGFloat(i) * s + 1.5, y: r.minY + CGFloat(j) * s + 1.5, width: s - 3, height: s - 3)
                let tone = (i + j) % 2 == 0 ? HDArt.color(0x2A3E45) : HDArt.color(0x263840)
                HDArt.fill(g, HDArt.rounded(tile, 2), tone)
                HDArt.stroke(g, HDArt.rounded(tile.insetBy(dx: 0.5, dy: 0.5), 2), UIColor(white: 1, alpha: 0.05), 1)
            }
        }
        noise(g, c, r.origin, r.width, count: 200, colors: [HDArt.color(0x30474E), HDArt.color(0x1C2B31)])
        // A ring motif centred on the plaza.
        let center = CGPoint(x: r.midX, y: r.midY)
        let ring = CGMutablePath()
        ring.addEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
        HDArt.stroke(g, ring, HDArt.color(0x2EE6D6, 0.12), 3)
    }

    private static func safehouse(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        // Sealed garage floor, polished.
        HDArt.linear(g, [HDArt.color(0x30343F), HDArt.color(0x262A33)], [0, 1],
                     from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.maxX, y: r.maxY))
        noise(g, c, r.origin, r.width, count: 200, colors: [HDArt.color(0x3A3F4B), HDArt.color(0x22252C)])
        // Bay lines.
        HDArt.color(0xF4EBD9, 0.4).setFill()
        g.fill(CGRect(x: r.minX + 4, y: r.minY, width: 3, height: r.height))
        // Hazard stripes along the edges.
        for (dc, dr) in [(0, -1), (0, 1), (-1, 0), (1, 0)] where kind(d, c, dc, dr) != .safehouse {
            g.saveGState()
            let band: CGRect
            switch (dc, dr) {
            case (0, -1): band = CGRect(x: r.minX, y: r.minY, width: r.width, height: 10)
            case (0, 1): band = CGRect(x: r.minX, y: r.maxY - 10, width: r.width, height: 10)
            case (-1, 0): band = CGRect(x: r.minX, y: r.minY, width: 10, height: r.height)
            default: band = CGRect(x: r.maxX - 10, y: r.minY, width: 10, height: r.height)
            }
            g.clip(to: band)
            HDArt.color(0x14161C).setFill()
            g.fill(band)
            HDArt.color(0xFF8A3D).setFill()
            var k = -r.width
            while k < r.width * 2 {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: r.minX + k, y: r.minY))
                p.addLine(to: CGPoint(x: r.minX + k + 10, y: r.minY))
                p.addLine(to: CGPoint(x: r.minX + k + 10 + r.height, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX + k + r.height, y: r.maxY))
                p.closeSubpath()
                g.addPath(p)
                g.fillPath()
                k += 20
            }
            g.restoreGState()
        }
    }

    // MARK: Buildings

    private struct RoofStyle {
        let roof: UInt32
        let wall: UInt32
        let neon: UInt32
    }

    private static let roofStyles: [RoofStyle] = [
        RoofStyle(roof: 0x3A3F4C, wall: 0x2A2E39, neon: 0x2EE6D6),
        RoofStyle(roof: 0x463B44, wall: 0x332A33, neon: 0xFF3EA5),
        RoofStyle(roof: 0x35434A, wall: 0x253037, neon: 0xFF8A3D),
        RoofStyle(roof: 0x4B4038, wall: 0x372E28, neon: 0x2EE6D6),
        RoofStyle(roof: 0x2F3340, wall: 0x22252F, neon: 0x8E6BFF),
        RoofStyle(roof: 0x403A4E, wall: 0x2E2939, neon: 0xFF3EA5)
    ]

    /// Facade height (points) on a building's south face.
    static let facade: CGFloat = 46

    private static func building(_ g: CGContext, _ d: District, _ info: BlockInfo, _ c: TileCoord, _ r: CGRect) {
        let style = roofStyles[info.id(d, c) % roofStyles.count]
        let roof = HDArt.color(style.roof)
        let southOpen = !kind(d, c, 0, 1).isSolid
        let roofRect = southOpen ? CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - facade) : r

        // Roof: gravel membrane.
        roof.setFill()
        g.fill(roofRect)
        g.saveGState()
        g.clip(to: roofRect)
        noise(g, c, r.origin, r.width, count: 700,
              colors: [HDArt.lighter(roof, 0.08), HDArt.darker(roof, 0.15), HDArt.darker(roof, 0.3)])
        HDArt.linear(g, [UIColor(white: 1, alpha: 0.05), UIColor(white: 0, alpha: 0.06)], [0, 1],
                     from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.maxX, y: r.maxY))
        g.restoreGState()

        // Parapet walls along the block edges: lit on the north-west, shaded south-east.
        let lip: CGFloat = 7
        let hi = HDArt.lighter(roof, 0.28), lo = HDArt.darker(roof, 0.35)
        if !(kind(d, c, 0, -1) == .building) {
            hi.setFill(); g.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: lip))
            UIColor(white: 0, alpha: 0.25).setFill(); g.fill(CGRect(x: r.minX, y: r.minY + lip, width: r.width, height: 2))
        }
        if !(kind(d, c, -1, 0) == .building) {
            hi.setFill(); g.fill(CGRect(x: r.minX, y: r.minY, width: lip, height: roofRect.height))
            UIColor(white: 0, alpha: 0.25).setFill(); g.fill(CGRect(x: r.minX + lip, y: r.minY, width: 2, height: roofRect.height))
        }
        if !(kind(d, c, 1, 0) == .building) {
            lo.setFill(); g.fill(CGRect(x: r.maxX - lip, y: r.minY, width: lip, height: roofRect.height))
        }
        if !(kind(d, c, 0, 1) == .building) {
            lo.setFill(); g.fill(CGRect(x: r.minX, y: roofRect.maxY - lip, width: r.width, height: lip))
        }

        // Membrane seams, laid per block so neighbouring roofs differ.
        g.saveGState()
        g.clip(to: roofRect)
        let seam = info.id(d, c) % 2 == 0
        UIColor(white: 0, alpha: 0.12).setFill()
        var k: CGFloat = 0
        while k < r.width {
            if seam { g.fill(CGRect(x: r.minX + k, y: r.minY, width: 1, height: roofRect.height)) } else {
                g.fill(CGRect(x: r.minX, y: r.minY + k, width: r.width, height: 1))
            }
            k += 32
        }
        g.restoreGState()

        // Rooftop kit, kept away from the edges.
        let pick = hash(c, 21) % 9
        let inner = roofRect.insetBy(dx: 18, dy: 16)
        if inner.width > 30 && inner.height > 30 {
            switch pick {
            case 0, 1: acUnit(g, CGPoint(x: inner.minX + HDWorld.unit(c, 22) * (inner.width - 34), y: inner.minY + HDWorld.unit(c, 23) * (inner.height - 26)))
            case 2: skylight(g, CGRect(x: inner.minX + 6, y: inner.minY + 4, width: 48, height: 30))
            case 3: tank(g, CGPoint(x: inner.midX, y: inner.midY), radius: 20)
            case 4:
                vents(g, CGPoint(x: inner.minX + 10, y: inner.minY + 10), c)
                acUnit(g, CGPoint(x: inner.maxX - 36, y: inner.maxY - 28))
            case 5: solar(g, CGRect(x: inner.minX, y: inner.minY, width: min(80, inner.width), height: min(44, inner.height)))
            case 6: stairwell(g, CGRect(x: inner.minX + 4, y: inner.minY + 2, width: 40, height: 32))
            case 7: garden(g, CGRect(x: inner.minX, y: inner.minY, width: min(84, inner.width), height: min(52, inner.height)), c)
            default: vents(g, CGPoint(x: inner.midX - 10, y: inner.midY - 6), c)
            }
        }

        if southOpen {
            drawFacade(g, d, c, CGRect(x: r.minX, y: roofRect.maxY, width: r.width, height: facade), style)
        }
    }

    private static func drawFacade(_ g: CGContext, _ d: District, _ c: TileCoord, _ f: CGRect, _ style: RoofStyle) {
        let wall = HDArt.color(style.wall)
        g.saveGState()
        g.clip(to: f)
        defer { g.restoreGState() }
        HDArt.linear(g, [HDArt.lighter(wall, 0.1), wall, HDArt.darker(wall, 0.25)], [0, 0.5, 1],
                     from: CGPoint(x: 0, y: f.minY), to: CGPoint(x: 0, y: f.maxY))
        // Neon trim under the roofline.
        let neon = HDArt.color(style.neon)
        g.saveGState()
        g.setShadow(offset: .zero, blur: 6, color: neon.cgColor)
        neon.setFill()
        g.fill(CGRect(x: f.minX, y: f.minY + 1, width: f.width, height: 2.5))
        g.restoreGState()
        // Upper windows: a row of panes, some lit.
        let lit: [UInt32] = [0xFFD27A, 0xFFE9B8, 0x7FE8FF, 0xFF8FD0]
        for i in 0..<5 {
            let x = f.minX + 6 + CGFloat(i) * 24.4
            let pane = CGRect(x: x, y: f.minY + 8, width: 16, height: 11)
            let on = hash(TileCoord(col: c.col * 5 + i, row: c.row), 31) % 3 != 0
            let col = on ? HDArt.color(lit[Int(hash(TileCoord(col: c.col * 5 + i, row: c.row), 32) % 4)])
                         : HDArt.color(0x151824)
            if on {
                g.saveGState()
                g.setShadow(offset: .zero, blur: 5, color: col.withAlphaComponent(0.8).cgColor)
                HDArt.fill(g, HDArt.rounded(pane, 1), col)
                g.restoreGState()
                UIColor(white: 0, alpha: 0.25).setFill()
                g.fill(CGRect(x: pane.midX - 0.5, y: pane.minY, width: 1, height: pane.height))
            } else {
                HDArt.fill(g, HDArt.rounded(pane, 1), col)
                UIColor(white: 1, alpha: 0.08).setFill()
                g.fill(CGRect(x: pane.minX + 2, y: pane.minY + 1, width: 3, height: pane.height - 2))
            }
        }
        // Street level: a shopfront with an awning, or a door and a wall.
        let ground = CGRect(x: f.minX, y: f.minY + 23, width: f.width, height: f.height - 23)
        let pick = hash(c, 33) % 3
        if pick != 2 {
            let glass = CGRect(x: ground.minX + 10, y: ground.minY + 4, width: ground.width - 20, height: ground.height - 6)
            HDArt.fill(g, CGPath(rect: glass, transform: nil), HDArt.color(0x0F1420))
            g.saveGState()
            g.clip(to: glass)
            HDArt.linear(g, [HDArt.color(0xFFD27A, 0.45), HDArt.color(0xFFD27A, 0.1)], [0, 1],
                         from: CGPoint(x: 0, y: glass.minY), to: CGPoint(x: 0, y: glass.maxY))
            g.restoreGState()
            // Striped awning.
            let awn = CGRect(x: ground.minX + 6, y: ground.minY - 2, width: ground.width - 12, height: 7)
            let colors = [neon, HDArt.color(0xF4EBD9)]
            for k in 0..<Int(awn.width / 10) + 1 {
                colors[k % 2].setFill()
                g.fill(CGRect(x: awn.minX + CGFloat(k) * 10, y: awn.minY, width: 10, height: awn.height).intersection(awn))
            }
            UIColor(white: 0, alpha: 0.35).setFill()
            g.fill(CGRect(x: awn.minX, y: awn.maxY, width: awn.width, height: 2))
        } else {
            let door = CGRect(x: ground.midX - 9, y: ground.minY + 2, width: 18, height: ground.height - 2)
            HDArt.fill(g, CGPath(rect: door, transform: nil), HDArt.color(0x11131A))
            HDArt.color(0xFFE9B8).setFill()
            g.fill(CGRect(x: door.minX - 6, y: door.minY + 2, width: 3, height: 3))
        }
        // Bottom edge: the foot of the wall.
        UIColor(white: 0, alpha: 0.5).setFill()
        g.fill(CGRect(x: f.minX, y: f.maxY - 2, width: f.width, height: 2))
    }

    private static func acUnit(_ g: CGContext, _ p: CGPoint) {
        let box = CGRect(x: p.x, y: p.y, width: 34, height: 26)
        g.saveGState()
        g.setShadow(offset: CGSize(width: 5, height: 6), blur: 4, color: UIColor(white: 0, alpha: 0.55).cgColor)
        HDArt.fill(g, HDArt.rounded(box, 2), HDArt.color(0x9AA0AC))
        g.restoreGState()
        g.saveGState()
        g.clip(to: box)
        HDArt.linear(g, [HDArt.color(0xC3C8D2), HDArt.color(0x7C828E)], [0, 1], from: CGPoint(x: box.minX, y: box.minY),
                     to: CGPoint(x: box.maxX, y: box.maxY))
        g.restoreGState()
        let fan = CGMutablePath()
        fan.addEllipse(in: CGRect(x: box.minX + 5, y: box.minY + 4, width: 18, height: 18))
        HDArt.fill(g, fan, HDArt.color(0x2A2D35))
        for k in 0..<3 {
            let a = CGFloat(k) * 2 * .pi / 3
            let blade = CGMutablePath()
            blade.move(to: CGPoint(x: box.minX + 14, y: box.minY + 13))
            blade.addLine(to: CGPoint(x: box.minX + 14 + cos(a) * 8, y: box.minY + 13 + sin(a) * 8))
            HDArt.stroke(g, blade, HDArt.color(0x6A707C), 2.5)
        }
        UIColor(white: 0, alpha: 0.3).setFill()
        for k in 0..<4 { g.fill(CGRect(x: box.minX + 26, y: box.minY + 5 + CGFloat(k) * 4.5, width: 5, height: 1.5)) }
    }

    /// A raised stair housing with a door and a lamp.
    private static func stairwell(_ g: CGContext, _ r: CGRect) {
        g.saveGState()
        g.setShadow(offset: CGSize(width: 9, height: 10), blur: 6, color: UIColor(white: 0, alpha: 0.6).cgColor)
        HDArt.fill(g, HDArt.rounded(r, 2), HDArt.color(0x4A4F5C))
        g.restoreGState()
        g.saveGState()
        g.clip(to: r)
        HDArt.linear(g, [HDArt.color(0x6A707C), HDArt.color(0x3E434E)], [0, 1], from: CGPoint(x: r.minX, y: r.minY),
                     to: CGPoint(x: r.maxX, y: r.maxY))
        g.restoreGState()
        HDArt.stroke(g, HDArt.rounded(r.insetBy(dx: 2, dy: 2), 1.5), UIColor(white: 1, alpha: 0.12), 1)
        let door = CGRect(x: r.midX - 7, y: r.maxY - 6, width: 14, height: 6)
        HDArt.fill(g, CGPath(rect: door, transform: nil), HDArt.color(0x1A1D24))
        g.saveGState()
        g.setShadow(offset: .zero, blur: 5, color: HDArt.color(0xFFD27A).cgColor)
        HDArt.fill(g, CGPath(rect: CGRect(x: r.midX - 2, y: r.maxY - 9, width: 4, height: 2), transform: nil), HDArt.color(0xFFE9B8))
        g.restoreGState()
    }

    /// Planter boxes on a roof terrace.
    private static func garden(_ g: CGContext, _ r: CGRect, _ c: TileCoord) {
        HDArt.fill(g, HDArt.rounded(r, 3), HDArt.color(0x5B4A3C, 0.9))
        // Decking.
        UIColor(white: 0, alpha: 0.18).setFill()
        var y = r.minY + 6
        while y < r.maxY { g.fill(CGRect(x: r.minX, y: y, width: r.width, height: 1)); y += 7 }
        for i in 0..<3 {
            let box = CGRect(x: r.minX + 4 + CGFloat(i) * (r.width - 8) / 3, y: r.minY + 4, width: (r.width - 8) / 3 - 4, height: 14)
            g.saveGState()
            g.setShadow(offset: CGSize(width: 2, height: 3), blur: 2, color: UIColor(white: 0, alpha: 0.5).cgColor)
            HDArt.fill(g, HDArt.rounded(box, 2), HDArt.color(0x3A2E25))
            g.restoreGState()
            for k in 0..<4 {
                let leaf = CGMutablePath()
                let p = CGPoint(x: box.minX + 4 + CGFloat(k) * (box.width - 8) / 3, y: box.midY)
                leaf.addEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                HDArt.fill(g, leaf, HDArt.color(k % 2 == 0 ? 0x3D8A5C : 0x5BA86A))
            }
        }
        // A string of party lights.
        for i in 0..<6 {
            let p = CGPoint(x: r.minX + 6 + CGFloat(i) * (r.width - 12) / 5, y: r.maxY - 10 + CGFloat(i % 2) * 2)
            g.saveGState()
            g.setShadow(offset: .zero, blur: 4, color: HDArt.color(0xFFD27A).cgColor)
            let bulb = CGMutablePath()
            bulb.addEllipse(in: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2))
            HDArt.fill(g, bulb, HDArt.color(0xFFE9B8))
            g.restoreGState()
        }
    }

    private static func skylight(_ g: CGContext, _ r: CGRect) {
        g.saveGState()
        g.setShadow(offset: CGSize(width: 3, height: 4), blur: 3, color: UIColor(white: 0, alpha: 0.5).cgColor)
        HDArt.fill(g, HDArt.rounded(r, 2), HDArt.color(0x5A606D))
        g.restoreGState()
        let glass = r.insetBy(dx: 3, dy: 3)
        HDArt.drawGlass(g, HDArt.rounded(glass, 1.5), tint: HDArt.color(0x223C5A))
        UIColor(white: 0, alpha: 0.4).setFill()
        g.fill(CGRect(x: glass.midX - 1, y: glass.minY, width: 2, height: glass.height))
    }

    private static func tank(_ g: CGContext, _ p: CGPoint, radius: CGFloat) {
        let disc = CGMutablePath()
        disc.addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        g.saveGState()
        g.setShadow(offset: CGSize(width: 7, height: 8), blur: 5, color: UIColor(white: 0, alpha: 0.55).cgColor)
        HDArt.fill(g, disc, HDArt.color(0x6B5546))
        g.restoreGState()
        g.saveGState()
        g.addPath(disc)
        g.clip()
        HDArt.radial(g, [HDArt.color(0x9A7B62), HDArt.color(0x5A4638)], [0, 1],
                     center: CGPoint(x: p.x - radius * 0.35, y: p.y - radius * 0.35), radius: radius * 1.4)
        g.restoreGState()
        let ring = CGMutablePath()
        ring.addEllipse(in: CGRect(x: p.x - radius * 0.6, y: p.y - radius * 0.6, width: radius * 1.2, height: radius * 1.2))
        HDArt.stroke(g, ring, UIColor(white: 0, alpha: 0.3), 1.5)
    }

    private static func vents(_ g: CGContext, _ p: CGPoint, _ c: TileCoord) {
        for k in 0..<3 {
            let q = CGPoint(x: p.x + CGFloat(k) * 14, y: p.y + CGFloat((k * 7) % 10))
            let cap = CGMutablePath()
            cap.addEllipse(in: CGRect(x: q.x, y: q.y, width: 9, height: 9))
            g.saveGState()
            g.setShadow(offset: CGSize(width: 2, height: 3), blur: 2, color: UIColor(white: 0, alpha: 0.6).cgColor)
            HDArt.fill(g, cap, HDArt.color(0x8A909C))
            g.restoreGState()
            let hole = CGMutablePath()
            hole.addEllipse(in: CGRect(x: q.x + 2.5, y: q.y + 2.5, width: 4, height: 4))
            HDArt.fill(g, hole, HDArt.color(0x1A1D24))
        }
    }

    private static func solar(_ g: CGContext, _ r: CGRect) {
        g.saveGState()
        g.setShadow(offset: CGSize(width: 3, height: 4), blur: 3, color: UIColor(white: 0, alpha: 0.5).cgColor)
        HDArt.fill(g, CGPath(rect: r, transform: nil), HDArt.color(0x14213D))
        g.restoreGState()
        g.saveGState()
        g.clip(to: r)
        HDArt.linear(g, [HDArt.color(0x2B4C80), HDArt.color(0x14213D)], [0, 1], from: CGPoint(x: r.minX, y: r.minY),
                     to: CGPoint(x: r.maxX, y: r.maxY))
        HDArt.color(0x9AA0AC, 0.6).setFill()
        var x = r.minX
        while x < r.maxX { g.fill(CGRect(x: x, y: r.minY, width: 1, height: r.height)); x += 10 }
        var y = r.minY
        while y < r.maxY { g.fill(CGRect(x: r.minX, y: y, width: r.width, height: 1)); y += 11 }
        g.restoreGState()
    }

    // MARK: Yards and water

    private static func container(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        HDArt.color(0x2C3038).setFill()
        g.fill(r)
        let colors: [UInt32] = [0xB4612C, 0x1F8F86, 0xA3306D, 0x3D6BB0, 0xC9A23A]
        let base = HDArt.color(colors[(c.row + c.col / 4) % colors.count])
        let box = CGRect(x: r.minX + 3, y: r.minY + 5, width: r.width - 6, height: r.height - 10)
        g.saveGState()
        g.setShadow(offset: CGSize(width: 6, height: 7), blur: 5, color: UIColor(white: 0, alpha: 0.6).cgColor)
        HDArt.fill(g, CGPath(rect: box, transform: nil), base)
        g.restoreGState()
        g.saveGState()
        g.clip(to: box)
        // Corrugation.
        var x = box.minX + 3
        while x < box.maxX {
            HDArt.darker(base, 0.3).setFill(); g.fill(CGRect(x: x, y: box.minY, width: 2, height: box.height))
            HDArt.lighter(base, 0.18).setFill(); g.fill(CGRect(x: x + 2, y: box.minY, width: 1.2, height: box.height))
            x += 7
        }
        HDArt.linear(g, [UIColor(white: 1, alpha: 0.12), UIColor(white: 0, alpha: 0.2)], [0, 1],
                     from: CGPoint(x: box.minX, y: box.minY), to: CGPoint(x: box.maxX, y: box.maxY))
        // Rust and grime.
        noise(g, c, r.origin, r.width, count: 120, colors: [HDArt.color(0x5A3A22, 0.6), UIColor(white: 0, alpha: 0.25)],
              size: 2, salt: 5)
        g.restoreGState()
        // End frames.
        HDArt.color(0x1A1C22).setFill()
        g.fill(CGRect(x: box.minX, y: box.minY, width: box.width, height: 3))
        g.fill(CGRect(x: box.minX, y: box.maxY - 3, width: box.width, height: 3))
        // Corner castings.
        HDArt.color(0x8A8F9A).setFill()
        for p in [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX - 4, y: box.minY),
                  CGPoint(x: box.minX, y: box.maxY - 4), CGPoint(x: box.maxX - 4, y: box.maxY - 4)] {
            g.fill(CGRect(x: p.x, y: p.y, width: 4, height: 4))
        }
    }

    private static func fence(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        HDArt.color(0x2A2E36).setFill()
        g.fill(r)
        noise(g, c, r.origin, r.width, count: 300, colors: [HDArt.color(0x30343D), HDArt.color(0x22252C)])
        let vertical = kind(d, c, 0, -1) == .fence || kind(d, c, 0, 1) == .fence
        g.saveGState()
        g.setShadow(offset: CGSize(width: 4, height: 5), blur: 3, color: UIColor(white: 0, alpha: 0.6).cgColor)
        let rail = vertical ? CGRect(x: r.midX - 3, y: r.minY, width: 6, height: r.height)
                            : CGRect(x: r.minX, y: r.midY - 3, width: r.width, height: 6)
        HDArt.fill(g, CGPath(rect: rail, transform: nil), HDArt.color(0x9AA0AC))
        g.restoreGState()
        // Chain-link mesh either side of the rail.
        let mesh = HDArt.color(0xB8BDC8, 0.35)
        let band = vertical ? CGRect(x: r.midX - 16, y: r.minY, width: 32, height: r.height)
                            : CGRect(x: r.minX, y: r.midY - 16, width: r.width, height: 32)
        g.saveGState()
        g.clip(to: band)
        var k: CGFloat = -r.width
        while k < r.width * 2 {
            let a = CGMutablePath()
            a.move(to: CGPoint(x: r.minX + k, y: r.minY))
            a.addLine(to: CGPoint(x: r.minX + k + r.height, y: r.maxY))
            HDArt.stroke(g, a, mesh, 1)
            let b = CGMutablePath()
            b.move(to: CGPoint(x: r.minX + k + r.height, y: r.minY))
            b.addLine(to: CGPoint(x: r.minX + k, y: r.maxY))
            HDArt.stroke(g, b, mesh, 1)
            k += 8
        }
        g.restoreGState()
        // Posts.
        for i in stride(from: CGFloat(0), to: r.width, by: 64) {
            let post = CGMutablePath()
            let p = vertical ? CGPoint(x: r.midX, y: r.minY + i + 8) : CGPoint(x: r.minX + i + 8, y: r.midY)
            post.addEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
            HDArt.fill(g, post, HDArt.color(0xD8DCE4))
        }
        if hash(c, 5) % 2 == 0 {
            // A warning sign.
            let sign = CGRect(x: r.midX - 10, y: r.midY - 8, width: 20, height: 16)
            HDArt.fill(g, HDArt.rounded(sign, 2), HDArt.color(0xFF3EA5))
            HDArt.color(0x0B0C10).setFill()
            g.fill(CGRect(x: sign.midX - 1.5, y: sign.minY + 3, width: 3, height: 7))
            g.fill(CGRect(x: sign.midX - 1.5, y: sign.minY + 11.5, width: 3, height: 2.5))
        }
    }

    private static func water(_ g: CGContext, _ d: District, _ c: TileCoord, _ r: CGRect) {
        // Deeper further from shore.
        let depth = CGFloat(max(0, min(3, c.row - 27))) / 3
        HDArt.linear(g, [HDArt.mix(HDArt.color(0x0E2A40), HDArt.color(0x081625), depth),
                         HDArt.mix(HDArt.color(0x0B2236), HDArt.color(0x06111E), depth)], [0, 1],
                     from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.maxX, y: r.maxY))
        // Ripples.
        var s = hash(c, 41)
        for _ in 0..<9 {
            s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let x = r.minX + CGFloat((s >> 16) % 110), y = r.minY + CGFloat((s >> 32) % 120)
            let w = CGFloat(10 + (s >> 40) % 18)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: y))
            p.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x + w / 2, y: y - 3))
            HDArt.stroke(g, p, HDArt.color(0x4FB7D8, 0.25), 1.2)
        }
        // Foam and a reflection of the shore lights along the edge.
        if kind(d, c, 0, -1) == .dock || kind(d, c, 0, -1) == .building || kind(d, c, 0, -1) == .container {
            HDArt.linear(g, [UIColor(white: 1, alpha: 0.3), UIColor(white: 1, alpha: 0)], [0, 1],
                         from: CGPoint(x: 0, y: r.minY), to: CGPoint(x: 0, y: r.minY + 14))
            g.saveGState()
            g.clip(to: CGRect(x: r.minX, y: r.minY + 14, width: r.width, height: 50))
            HDArt.linear(g, [HDArt.color(0xFFC23D, 0.18), HDArt.color(0xFFC23D, 0)], [0, 1],
                         from: CGPoint(x: 0, y: r.minY + 14), to: CGPoint(x: 0, y: r.minY + 64))
            g.restoreGState()
        }
        if kind(d, c, -1, 0) == .dock {
            HDArt.linear(g, [UIColor(white: 1, alpha: 0.25), UIColor(white: 1, alpha: 0)], [0, 1],
                         from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.minX + 10, y: 0))
        }
        if kind(d, c, 1, 0) == .dock {
            HDArt.linear(g, [UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: 0.25)], [0, 1],
                         from: CGPoint(x: r.maxX - 10, y: 0), to: CGPoint(x: r.maxX, y: 0))
        }
    }

    // MARK: Road paint

    private static func drawMarkings(_ g: CGContext, _ d: District, _ c: TileCoord, _ o: CGPoint, _ t: CGFloat) {
        if d.tile(c) == .highway || d.tile(c) == .bridge {
            // Double yellow down the middle of a two-tile-wide highway (on the shared edge).
            let yellow = HDArt.color(0xFFC23D, 0.9)
            func hw(_ dc: Int, _ dr: Int) -> Bool { [.highway, .bridge].contains(kind(d, c, dc, dr)) }
            if hw(1, 0) && !hw(-1, 0) && (hw(0, -1) || hw(0, 1)) {
                yellow.setFill()
                g.fill(CGRect(x: o.x + t - 5, y: o.y, width: 3, height: t))
                g.fill(CGRect(x: o.x + t + 2, y: o.y, width: 3, height: t))
            }
            if hw(0, 1) && !hw(0, -1) && (hw(-1, 0) || hw(1, 0)) {
                yellow.setFill()
                g.fill(CGRect(x: o.x, y: o.y + t - 5, width: t, height: 3))
                g.fill(CGRect(x: o.x, y: o.y + t + 2, width: t, height: 3))
            }
            return
        }
        guard d.tile(c) == .road else { return }
        let paint = HDArt.color(0xF4EBD9, 0.82)
        func road(_ dc: Int, _ dr: Int) -> Bool { kind(d, c, dc, dr) == .road }
        let intersection = isIntersection(d, c)

        if !intersection {
            // Centre line of a two-lane north-south road: dashes along this tile's east edge.
            if road(1, 0) && !road(-1, 0) && !road(2, 0) && road(0, -1) && road(0, 1) {
                for y in stride(from: CGFloat(12), to: t, by: 48) {
                    paint.setFill(); g.fill(CGRect(x: o.x + t - 2, y: o.y + y, width: 4, height: 26))
                }
            }
            // Centre line of a two-lane east-west road: dashes along this tile's south edge.
            if road(0, 1) && !road(0, -1) && !road(0, 2) && road(-1, 0) && road(1, 0) {
                for x in stride(from: CGFloat(12), to: t, by: 48) {
                    paint.setFill(); g.fill(CGRect(x: o.x + x, y: o.y + t - 2, width: 26, height: 4))
                }
            }
        }

        // Zebra crossings on each approach to a junction, with a stop line behind them.
        if !intersection {
            let zebra = HDArt.color(0xF4EBD9, 0.78)
            if isIntersection(d, TileCoord(col: c.col, row: c.row - 1)) {
                for x in stride(from: CGFloat(8), to: t - 8, by: 16) {
                    zebra.setFill(); g.fill(CGRect(x: o.x + x, y: o.y + 6, width: 9, height: 30))
                }
                zebra.setFill(); g.fill(CGRect(x: o.x + 4, y: o.y + 44, width: t - 8, height: 4))
            }
            if isIntersection(d, TileCoord(col: c.col, row: c.row + 1)) {
                for x in stride(from: CGFloat(8), to: t - 8, by: 16) {
                    zebra.setFill(); g.fill(CGRect(x: o.x + x, y: o.y + t - 36, width: 9, height: 30))
                }
                zebra.setFill(); g.fill(CGRect(x: o.x + 4, y: o.y + t - 48, width: t - 8, height: 4))
            }
            if isIntersection(d, TileCoord(col: c.col - 1, row: c.row)) {
                for y in stride(from: CGFloat(8), to: t - 8, by: 16) {
                    zebra.setFill(); g.fill(CGRect(x: o.x + 6, y: o.y + y, width: 30, height: 9))
                }
                zebra.setFill(); g.fill(CGRect(x: o.x + 44, y: o.y + 4, width: 4, height: t - 8))
            }
            if isIntersection(d, TileCoord(col: c.col + 1, row: c.row)) {
                for y in stride(from: CGFloat(8), to: t - 8, by: 16) {
                    zebra.setFill(); g.fill(CGRect(x: o.x + t - 36, y: o.y + y, width: 30, height: 9))
                }
                zebra.setFill(); g.fill(CGRect(x: o.x + t - 48, y: o.y + 4, width: 4, height: t - 8))
            }
        }
    }

    // MARK: Shadows

    /// Buildings, containers and fences throw shadow south-east onto whatever is beside them.
    private static func drawShadows(_ g: CGContext, _ d: District, _ c: TileCoord, _ o: CGPoint, _ t: CGFloat) {
        let here = d.tile(c)
        guard !here.isSolid || here == .water else { return }
        func caster(_ dc: Int, _ dr: Int) -> CGFloat {
            switch kind(d, c, dc, dr) {
            case .building: 1
            case .container: 0.7
            case .fence: 0.35
            default: 0
            }
        }
        let north = caster(0, -1), west = caster(-1, 0), corner = caster(-1, -1)
        let dark = UIColor(white: 0, alpha: 0.5)
        let clear = UIColor(white: 0, alpha: 0)
        let tile = CGRect(x: o.x, y: o.y, width: t, height: t)
        // The building's facade sits on its south edge, so the shadow it casts starts below it.
        if north > 0 {
            let depth = 30 * north
            g.saveGState()
            g.clip(to: CGRect(x: tile.minX, y: tile.minY, width: t, height: depth))
            HDArt.linear(g, [dark.withAlphaComponent(0.42 * north), clear], [0, 1],
                         from: CGPoint(x: 0, y: tile.minY), to: CGPoint(x: 0, y: tile.minY + depth))
            g.restoreGState()
        }
        if west > 0 {
            let depth = 36 * west
            g.saveGState()
            g.clip(to: CGRect(x: tile.minX, y: tile.minY, width: depth, height: t))
            HDArt.linear(g, [dark.withAlphaComponent(0.5 * west), clear], [0, 1],
                         from: CGPoint(x: tile.minX, y: 0), to: CGPoint(x: tile.minX + depth, y: 0))
            g.restoreGState()
        }
        if corner > 0 && north == 0 && west == 0 {
            g.saveGState()
            g.clip(to: CGRect(x: tile.minX, y: tile.minY, width: 36, height: 30))
            HDArt.radial(g, [dark.withAlphaComponent(0.4 * corner), clear], [0, 1],
                         center: CGPoint(x: tile.minX, y: tile.minY), radius: 36)
            g.restoreGState()
        }
    }
}
