import UIKit
import SpriteKit

/// All art in the prototype is generated here from rectangles at 1 px per cell, then scaled up
/// with nearest-neighbour filtering. No image files, no outside assets.
@MainActor
enum PixelArt {
    /// Draws a pixel grid. Each string row is one line of cells; characters map to colours
    /// through `palette`, and '.' is transparent.
    static func image(rows: [String], palette: [Character: UIColor], scale: CGFloat = 1) -> UIImage {
        let height = rows.count
        let width = rows.map(\.count).max() ?? 0
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let color = palette[ch] else { continue }
                    color.setFill()
                    ctx.fill(CGRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: scale, height: scale))
                }
            }
        }
    }

    // MARK: Player car (Vesper GT), nose pointing up.

    static let carRows: [String] = [
        "....cccccc....",
        "...cmmmmmmc...",
        "..mmmmmmmmmm..",
        ".kmmmmmmmmmmk.",
        ".kmmttttttmmk.",
        ".kmttttttttmk.",
        "..mttttttttm..",
        "..mmmmmmmmmm..",
        "..mmwmmmmwmm..",
        "..mmwmmmmwmm..",
        "..mmwmmmmwmm..",
        "..mmwmmmmwmm..",
        "..mmmmmmmmmm..",
        "..mmmmmmmmmm..",
        "..mtttttttm...",
        "..mttttttttm..",
        ".kmmmmmmmmmmk.",
        ".kmmmmmmmmmmk.",
        ".kmmmmmmmmmmk.",
        "..mmmmmmmmmm..",
        "..mmmmmmmmmm..",
        "...ommmmmmo...",
        "...oo....oo...",
        "..............",
    ]

    static var carPalette: [Character: UIColor] {
        [
            "m": Palette.UI.magenta,
            "t": Palette.UI.teal.withAlphaComponent(0.85),
            "c": Palette.UI.cream,
            "o": Palette.UI.sunset,
            "k": Palette.UI.ink,
            "w": UIColor(hex: 0xC02A7C)
        ]
    }

    static func carImage(scale: CGFloat = 1) -> UIImage {
        image(rows: carRows, palette: carPalette, scale: scale)
    }

    static func carTexture() -> SKTexture {
        let texture = SKTexture(image: carImage())
        texture.filteringMode = .nearest
        return texture
    }

    // MARK: Harbor Patrol cruiser, nose up (generic, fictional livery)

    static let patrolRows: [String] = [
        "....wwwwww....",
        "...wwwwwwww...",
        "..wwwwwwwwww..",
        ".kwwwwwwwwwwk.",
        ".kwwkkkkkkwwk.",
        ".kwkkkkkkkkwk.",
        "..wkkkkkkkkw..",
        "..wwwwwwwwww..",
        "..tttttttttt..",
        "..wwwwwwwwww..",
        "..rrrrrbbbbb..",
        "..rrrrrbbbbb..",
        "..wwwwwwwwww..",
        "..tttttttttt..",
        "..wkkkkkkkkw..",
        "..wkkkkkkkkw..",
        ".kwwwwwwwwwwk.",
        ".kwwwwwwwwwwk.",
        ".kwwwwwwwwwwk.",
        "..wwwwwwwwww..",
        "..wwwwwwwwww..",
        "...owwwwwwo...",
        "...oo....oo...",
        "..............",
    ]

    /// Two frames so the light bar can alternate while a patrol is chasing.
    static func patrolTextures() -> (SKTexture, SKTexture) {
        let base: [Character: UIColor] = [
            "w": Palette.UI.cream,
            "k": Palette.UI.ink,
            "t": Palette.UI.teal,
            "o": Palette.UI.sunset
        ]
        var a = base, b = base
        a["r"] = Palette.UI.magenta
        a["b"] = Palette.UI.teal.withAlphaComponent(0.35)
        b["r"] = Palette.UI.magenta.withAlphaComponent(0.35)
        b["b"] = Palette.UI.teal
        let rows = patrolRows
        let ta = SKTexture(image: image(rows: rows, palette: a))
        let tb = SKTexture(image: image(rows: rows, palette: b))
        ta.filteringMode = .nearest
        tb.filteringMode = .nearest
        return (ta, tb)
    }

    /// Both lights lit: the steady frame used with Reduce Motion or while not chasing.
    static func patrolSteadyTexture() -> SKTexture {
        var palette: [Character: UIColor] = [
            "w": Palette.UI.cream, "k": Palette.UI.ink, "t": Palette.UI.teal, "o": Palette.UI.sunset
        ]
        palette["r"] = Palette.UI.magenta
        palette["b"] = Palette.UI.teal
        let rows = patrolRows
        let texture = SKTexture(image: image(rows: rows, palette: palette))
        texture.filteringMode = .nearest
        return texture
    }

    // MARK: Ground

    /// A 32×32 asphalt tile with fixed speckle (seeded, so it is the same every launch).
    static func asphaltTexture() -> SKTexture {
        var rng = SeededRandom(seed: 0xA5F1)
        let base = Palette.UI.asphalt
        let light = UIColor(hex: 0x1C1F27)
        let dark = UIColor(hex: 0x0F1115)
        var rows: [String] = []
        for _ in 0..<32 {
            var row = ""
            for _ in 0..<32 {
                let r = rng.next() % 100
                row.append(r < 8 ? "l" : (r < 14 ? "d" : "b"))
            }
            rows.append(row)
        }
        let texture = SKTexture(image: image(rows: rows, palette: ["b": base, "l": light, "d": dark]))
        texture.filteringMode = .nearest
        return texture
    }

    /// Rooftop tile for blocks: dark slab with vents.
    static func roofTexture() -> SKTexture {
        let rows = [
            "aaaaaaaaaaaaaaaa",
            "abbbbbbbbbbbbbba",
            "abbbbbbbbbbbbbba",
            "abbvvbbbbbbvvbba",
            "abbvvbbbbbbvvbba",
            "abbbbbbbbbbbbbba",
            "abbbbbbbbbbbbbba",
            "abbbbbbbbbbbbbba",
            "abbbbbbbbbbbbbba",
            "abbbbbbbbbbbbbba",
            "abbbbbbbbbbbbbba",
            "abbvvbbbbbbvvbba",
            "abbvvbbbbbbvvbba",
            "abbbbbbbbbbbbbba",
            "abbbbbbbbbbbbbba",
            "aaaaaaaaaaaaaaaa"
        ]
        let texture = SKTexture(image: image(rows: rows, palette: [
            "a": UIColor(hex: 0x30343F), "b": Palette.UI.asphaltLight, "v": UIColor(hex: 0x3B4150)
        ]))
        texture.filteringMode = .nearest
        return texture
    }
}

/// Tiny deterministic RNG (xorshift) so generated art is identical every run.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
