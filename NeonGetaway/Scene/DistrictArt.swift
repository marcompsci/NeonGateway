import UIKit
import SpriteKit
import GameCore

/// Draws a district into pixel-art images. Everything is generated from the tile grid: no
/// image files. The world texture uses 32 px per tile (one texture pixel = 4 points), and the
/// map images use a few pixels per tile.
@MainActor
enum DistrictArt {
    static let pixelsPerTile = 32

    private static var textureCache: [String: SKTexture] = [:]
    private static var mapCache: [String: UIImage] = [:]

    /// The whole district as one texture, nearest-neighbour filtered.
    static func worldTexture(for district: District) -> SKTexture {
        if let cached = textureCache[district.name] { return cached }
        let texture = SKTexture(image: drawWorld(district))
        texture.filteringMode = .nearest
        textureCache[district.name] = texture
        return texture
    }

    /// Flat-colour map for the minimap and mission-select screen, `scale` px per tile.
    static func mapImage(for district: District, scale: Int) -> UIImage {
        let key = "\(district.name)#\(scale)"
        if let cached = mapCache[key] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: district.cols * scale, height: district.rows * scale)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            for row in 0..<district.rows {
                for col in 0..<district.cols {
                    mapColor(district.tile(TileCoord(col: col, row: row))).setFill()
                    ctx.fill(CGRect(x: col * scale, y: row * scale, width: scale, height: scale))
                }
            }
        }
        mapCache[key] = image
        return image
    }

    static func mapColor(_ kind: TileKind) -> UIColor {
        switch kind {
        case .road: UIColor(hex: 0x4A505E)
        case .sidewalk: UIColor(hex: 0x323744)
        case .alley: UIColor(hex: 0x3A3346)
        case .dock: UIColor(hex: 0x383D49)
        case .plaza: UIColor(hex: 0x245058)
        case .safehouse: Palette.UI.sunset
        case .building: UIColor(hex: 0x15171D)
        case .container: UIColor(hex: 0x1F1A22)
        case .fence: UIColor(hex: 0x5A2347)
        case .water: UIColor(hex: 0x0B2638)
        case .highway: UIColor(hex: 0x6A7080)
        case .bridge: UIColor(hex: 0xC8322B)
        case .grass: UIColor(hex: 0x2F5A2C)
        case .sand: UIColor(hex: 0x9C7E52)
        case .forest: UIColor(hex: 0x173A1E)
        case .rock: UIColor(hex: 0x5E5752)
        case .landmark: Palette.UI.magenta
        }
    }

    // MARK: World texture

    private static func drawWorld(_ d: District) -> UIImage {
        let t = pixelsPerTile
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: d.cols * t, height: d.rows * t)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let g = ctx.cgContext
            var rng = SeededRandom(seed: 0x50A7)
            for row in 0..<d.rows {
                for col in 0..<d.cols {
                    let c = TileCoord(col: col, row: row)
                    let origin = CGPoint(x: col * t, y: row * t)
                    drawTile(d, c, at: origin, in: g, rng: &rng)
                }
            }
            // Lane dashes go on top so they can straddle the seam between two road tiles.
            for row in 0..<d.rows {
                for col in 0..<d.cols {
                    drawLaneMarks(d, TileCoord(col: col, row: row), in: g)
                }
            }
        }
    }

    private static func fill(_ g: CGContext, _ color: UIColor, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        g.setFillColor(color.cgColor)
        g.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    private static func neighbor(_ d: District, _ c: TileCoord, _ dc: Int, _ dr: Int) -> TileKind {
        d.tile(TileCoord(col: c.col + dc, row: c.row + dr))
    }

    private static func speckle(_ g: CGContext, _ o: CGPoint, count: Int, colors: [UIColor], rng: inout SeededRandom) {
        let t = UInt64(pixelsPerTile)
        for _ in 0..<count {
            let x = CGFloat(rng.next() % t), y = CGFloat(rng.next() % t)
            let color = colors[Int(rng.next() % UInt64(colors.count))]
            fill(g, color, o.x + x, o.y + y, 1, 1)
        }
    }

    private static func drawTile(_ d: District, _ c: TileCoord, at o: CGPoint, in g: CGContext,
                                 rng: inout SeededRandom) {
        let t = CGFloat(pixelsPerTile)
        let kind = d.tile(c)
        switch kind {
        case .road:
            fill(g, Palette.UI.asphalt, o.x, o.y, t, t)
            speckle(g, o, count: 40, colors: [UIColor(hex: 0x1C1F27), UIColor(hex: 0x0F1115)], rng: &rng)
            // Kerb line where the road meets a sidewalk or plaza.
            let kerb = UIColor(hex: 0x4A4F5C)
            if neighbor(d, c, 0, -1) != .road { fill(g, kerb, o.x, o.y, t, 1) }
            if neighbor(d, c, 0, 1) != .road { fill(g, kerb, o.x, o.y + t - 1, t, 1) }
            if neighbor(d, c, -1, 0) != .road { fill(g, kerb, o.x, o.y, 1, t) }
            if neighbor(d, c, 1, 0) != .road { fill(g, kerb, o.x + t - 1, o.y, 1, t) }

        case .sidewalk:
            fill(g, UIColor(hex: 0x2A2E38), o.x, o.y, t, t)
            let seam = UIColor(hex: 0x222630)
            for i in stride(from: 0, to: t, by: 8) {
                fill(g, seam, o.x + i, o.y, 1, t)
                fill(g, seam, o.x, o.y + i, t, 1)
            }

        case .alley:
            fill(g, UIColor(hex: 0x1A1A22), o.x, o.y, t, t)
            speckle(g, o, count: 30, colors: [UIColor(hex: 0x24222C), UIColor(hex: 0x121218)], rng: &rng)
            if (c.col + c.row) % 3 == 0 {
                // A puddle catching neon.
                fill(g, Palette.UI.magenta.withAlphaComponent(0.25), o.x + 9, o.y + 13, 9, 4)
                fill(g, Palette.UI.magenta.withAlphaComponent(0.25), o.x + 11, o.y + 12, 5, 6)
            }

        case .dock:
            fill(g, UIColor(hex: 0x23272F), o.x, o.y, t, t)
            let seam = UIColor(hex: 0x1B1E25)
            for i in stride(from: 3, to: t, by: 8) { fill(g, seam, o.x, o.y + i, t, 1) }
            speckle(g, o, count: 12, colors: [UIColor(hex: 0x2C303A)], rng: &rng)
            // Safety edge where the dock meets water.
            if neighbor(d, c, 0, 1) == .water {
                for i in stride(from: 0, to: t, by: 8) {
                    fill(g, Palette.UI.sunset, o.x + i, o.y + t - 3, 4, 2)
                }
            }
            if neighbor(d, c, -1, 0) == .water { fill(g, Palette.UI.sunset.withAlphaComponent(0.7), o.x, o.y, 2, t) }
            if neighbor(d, c, 1, 0) == .water { fill(g, Palette.UI.sunset.withAlphaComponent(0.7), o.x + t - 2, o.y, 2, t) }

        case .plaza:
            fill(g, UIColor(hex: 0x1D2B30), o.x, o.y, t, t)
            for y in stride(from: 0, to: t, by: 8) {
                for x in stride(from: 0, to: t, by: 8) where Int(x / 8 + y / 8) % 2 == 0 {
                    fill(g, UIColor(hex: 0x223339), o.x + x, o.y + y, 8, 8)
                }
            }

        case .safehouse:
            fill(g, UIColor(hex: 0x262A33), o.x, o.y, t, t)
            // Hazard stripes along the garage edges.
            for (dc, dr) in [(0, -1), (0, 1), (-1, 0), (1, 0)] where neighbor(d, c, dc, dr) != .safehouse {
                for i in stride(from: 0, to: t, by: 6) {
                    let color = Int(i / 6) % 2 == 0 ? Palette.UI.sunset : Palette.UI.ink
                    switch (dc, dr) {
                    case (0, -1): fill(g, color, o.x + i, o.y, 6, 3)
                    case (0, 1): fill(g, color, o.x + i, o.y + t - 3, 6, 3)
                    case (-1, 0): fill(g, color, o.x, o.y + i, 3, 6)
                    default: fill(g, color, o.x + t - 3, o.y + i, 3, 6)
                    }
                }
            }

        case .building:
            fill(g, UIColor(hex: 0x262A33), o.x, o.y, t, t)
            fill(g, UIColor(hex: 0x1E2129), o.x + 2, o.y + 2, t - 4, t - 4)
            if (c.col + c.row) % 2 == 0 {
                fill(g, UIColor(hex: 0x3B4150), o.x + 7, o.y + 7, 5, 5)
                fill(g, UIColor(hex: 0x3B4150), o.x + 20, o.y + 18, 5, 5)
            }
            // Neon trim on any side that faces something drivable.
            let neon = [Palette.UI.teal, Palette.UI.magenta, Palette.UI.sunset][(c.col / 4 + c.row / 4) % 3]
            if !neighbor(d, c, 0, -1).isSolid { fill(g, neon, o.x, o.y + 1, t, 2) }
            if !neighbor(d, c, 0, 1).isSolid { fill(g, neon, o.x, o.y + t - 3, t, 2) }
            if !neighbor(d, c, -1, 0).isSolid { fill(g, neon, o.x + 1, o.y, 2, t) }
            if !neighbor(d, c, 1, 0).isSolid { fill(g, neon, o.x + t - 3, o.y, 2, t) }

        case .container:
            fill(g, UIColor(hex: 0x23272F), o.x, o.y, t, t)
            let colors = [UIColor(hex: 0xB4612C), UIColor(hex: 0x1F8F86), UIColor(hex: 0xA3306D)]
            let base = colors[(c.row + c.col / 4) % 3]
            fill(g, base, o.x + 1, o.y + 2, t - 2, t - 4)
            let ridge = base.withAlphaComponent(1).mixed(with: .black, 0.35)
            for i in stride(from: 4, to: t - 2, by: 4) { fill(g, ridge, o.x + i, o.y + 2, 1, t - 4) }
            fill(g, Palette.UI.ink, o.x + 1, o.y + 2, t - 2, 1)

        case .fence:
            fill(g, UIColor(hex: 0x23272F), o.x, o.y, t, t)
            let wire = UIColor(hex: 0x8A8F9A)
            for i in 0..<Int(t) where i % 4 == 0 {
                for j in 0..<Int(t) where (i + j) % 8 == 0 {
                    fill(g, wire, o.x + CGFloat(j), o.y + CGFloat(i), 1, 1)
                }
            }
            fill(g, Palette.UI.magenta, o.x + 14, o.y + 14, 4, 4)

        case .water:
            fill(g, UIColor(hex: 0x0C1C2B), o.x, o.y, t, t)
            for _ in 0..<4 {
                let x = CGFloat(rng.next() % 26), y = CGFloat(rng.next() % 30)
                fill(g, UIColor(hex: 0x16405A), o.x + x, o.y + y, 6, 1)
            }
            if neighbor(d, c, 0, -1) == .dock || neighbor(d, c, 0, -1) == .building {
                fill(g, Palette.UI.cream.withAlphaComponent(0.25), o.x, o.y, t, 2)
            }

        case .highway, .bridge, .grass, .sand, .forest, .rock, .landmark:
            // The old pixel renderer only ever drew Port Aurora; Solara uses HDWorld.
            fill(g, mapColor(d.tile(c)), o.x, o.y, t, t)
        }
    }

    private static func isRoad(_ d: District, _ c: TileCoord, _ dc: Int, _ dr: Int) -> Bool {
        neighbor(d, c, dc, dr) == .road
    }

    private static func drawLaneMarks(_ d: District, _ c: TileCoord, in g: CGContext) {
        guard d.tile(c) == .road else { return }
        let t = CGFloat(pixelsPerTile)
        let o = CGPoint(x: CGFloat(c.col) * t, y: CGFloat(c.row) * t)
        let paint = Palette.UI.cream.withAlphaComponent(0.75)
        // Left lane of a north-south road pair: dashes on its right edge.
        if isRoad(d, c, 1, 0) && !isRoad(d, c, -1, 0) && isRoad(d, c, 0, -1) && isRoad(d, c, 0, 1)
            && !isRoad(d, c, 2, 0) {
            for y in stride(from: 4, to: t, by: 16) { fill(g, paint, o.x + t - 1, o.y + y, 2, 8) }
        }
        // Top lane of an east-west road pair: dashes on its bottom edge.
        if isRoad(d, c, 0, 1) && !isRoad(d, c, 0, -1) && isRoad(d, c, -1, 0) && isRoad(d, c, 1, 0)
            && !isRoad(d, c, 0, 2) {
            for x in stride(from: 4, to: t, by: 16) { fill(g, paint, o.x + x, o.y + t - 1, 8, 2) }
        }
    }
}

private extension UIColor {
    func mixed(with other: UIColor, _ amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount,
                       blue: b1 + (b2 - b1) * amount, alpha: a1)
    }
}
