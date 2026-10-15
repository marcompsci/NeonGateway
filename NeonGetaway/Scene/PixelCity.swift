import UIKit
import SpriteKit
import GameCore

/// Street-level pixel art: the other vehicles, people and weapons. Drawn from grids like the
/// rest of `PixelArt`, nose/face pointing up. Invented designs, no outside assets.
@MainActor
extension PixelArt {
    /// Draw scale for every street sprite (cells → points).
    static let streetScale: CGFloat = 2.4

    // MARK: Vehicles

    static let sedanRows: [String] = [
        "..............",
        "...bbbbbbbb...",
        "..bbbbbbbbbb..",
        ".kbbbbbbbbbbk.",
        ".kbwwwwwwwwbk.",
        ".kbwwwwwwwwbk.",
        "..bbbbbbbbbb..",
        "..bbbbbbbbbb..",
        "..bbcbbbbcbb..",
        "..bbcbbbbcbb..",
        "..bbbbbbbbbb..",
        "..bbbbbbbbbb..",
        "..bbcbbbbcbb..",
        "..bwwwwwwwwb..",
        "..bwwwwwwwwb..",
        ".kbbbbbbbbbbk.",
        ".kbbbbbbbbbbk.",
        ".kbbbbbbbbbbk.",
        "..bbbbbbbbbb..",
        "..obbbbbbbbo..",
        "..oo......oo..",
        "..............",
    ]

    static let vanRows: [String] = [
        "................",
        "..bbbbbbbbbbbb..",
        ".bbbbbbbbbbbbbb.",
        ".bwwwwwwwwwwwwb.",
        "kbwwwwwwwwwwwwbk",
        "kbbbbbbbbbbbbbbk",
        ".bbbbbbbbbbbbbb.",
        ".kkkkkkkkkkkkkk.",
        ".cccccccccccccc.",
        ".cccccccccccccc.",
        ".cccccccccccccc.",
        ".cccccccccccccc.",
        ".ssssssssssssss.",
        ".cccccccccccccc.",
        ".cccccccccccccc.",
        ".cccccccccccccc.",
        "kcccccccccccccck",
        "kcccccccccccccck",
        ".cccccccccccccc.",
        ".cccccccccccccc.",
        ".cccccccccccccc.",
        ".cccccccccccccc.",
        ".cccccccccccccc.",
        ".oobbbbbbbbbboo.",
        "................",
    ]

    static let bikeRows: [String] = [
        "..ww..",
        "..kk..",
        ".kmmk.",
        "..mm..",
        ".mmmm.",
        "kmmmmk",
        ".mssm.",
        ".mssm.",
        ".mssm.",
        ".mmmm.",
        "..mm..",
        "..oo..",
        "..kk..",
        "..kk..",
    ]

    private static var vehicleCache: [VehicleID: SKTexture] = [:]
    private static var paintedCache: [String: SKTexture] = [:]

    // MARK: Paint designs

    /// The design palette: index 1...11 in `PaintDesign.cells` (0 keeps the car's own colour).
    static let designColors: [UIColor] = [
        Palette.UI.magenta, Palette.UI.teal, Palette.UI.sunset, Palette.UI.cream,
        UIColor(hex: 0x8E6BFF), UIColor(hex: 0x7BD14B), UIColor(hex: 0x3D7BFF), UIColor(hex: 0xFFE14D),
        UIColor(hex: 0x15161C), UIColor(hex: 0xE23B3B), UIColor(hex: 0xC9CED8)
    ]
    static let designColorNames = ["Magenta", "Teal", "Sunset", "Cream", "Violet", "Lime", "Cobalt",
                                   "Yellow", "Ink", "Red", "Chrome"]

    static func designColor(_ value: UInt8) -> UIColor? {
        value == 0 ? nil : designColors[(Int(value) - 1) % designColors.count]
    }

    /// Body cells per model: the characters in each sprite's grid that a design paints over.
    private static func bodyCells(_ model: VehicleID) -> Set<Character> {
        switch model {
        case .vesper: ["m", "w"]
        case .dorado: ["b", "c"]
        case .ridgeback: ["b", "c", "s"]
        case .flicker: ["m"]
        case .harborPatrol, .hauler: []
        default: model.isMotorcycle ? ["m"] : ["m", "w"]
        }
    }

    private static func rows(_ model: VehicleID) -> [String] {
        switch model {
        case .vesper: carRows
        case .dorado: sedanRows
        case .ridgeback, .hauler: vanRows
        case .flicker: bikeRows
        case .harborPatrol: patrolRows
        default: model.isMotorcycle ? bikeRows : carRows
        }
    }

    /// Menu pictures of a vehicle (garage, body shop, paint studio): the high-resolution street
    /// art, as tall as the old pixel sprite was at `scale`.
    static func vehicleImage(_ model: VehicleID, design: PaintDesign?, scale: CGFloat = 1, rims: RimSetup? = nil) -> UIImage {
        HDArt.vehiclePreview(model, design: design, height: CGFloat(rows(model).count) * scale, rims: rims)
    }

    /// The old pixel version (kept for reference and tests of the design mapping).
    static func pixelVehicleImage(_ model: VehicleID, design: PaintDesign?, scale: CGFloat = 1) -> UIImage {
        let base = pixelVehicleImage(model, scale: 1)
        guard let design, let cg = base.cgImage else { return scale == 1 ? base : pixelVehicleImage(model, scale: scale) }
        let grid = rows(model)
        let body = bodyCells(model)
        let h = grid.count, w = grid.map(\.count).max() ?? 1
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            base.draw(in: CGRect(origin: .zero, size: size))
            for (y, row) in grid.enumerated() {
                for (x, ch) in row.enumerated() where body.contains(ch) {
                    let u = (Double(x) + 0.5) / Double(w), v = (Double(y) + 0.5) / Double(h)
                    guard let colour = designColor(design.sample(u: u, v: v)) else { continue }
                    colour.setFill()
                    ctx.fill(CGRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: scale, height: scale))
                }
            }
        }
    }

    static func vehicleTexture(_ model: VehicleID, design: PaintDesign?) -> SKTexture {
        guard let design else { return vehicleTexture(model) }
        let key = "\(model.rawValue)|\(design.id)|\(design.cells.hashValue)"
        if let cached = paintedCache[key] { return cached }
        let texture = SKTexture(image: vehicleImage(model, design: design, scale: 1))
        texture.filteringMode = .nearest
        paintedCache[key] = texture
        return texture
    }

    // MARK: Gun finishes

    /// Workbench finishes: index 0 is the factory cream.
    static let finishColors: [UIColor] = [
        Palette.UI.cream, Palette.UI.magenta, Palette.UI.teal, Palette.UI.sunset,
        UIColor(hex: 0xFFE14D), UIColor(hex: 0x8E6BFF), UIColor(hex: 0x7BD14B), UIColor(hex: 0xC9CED8)
    ]
    static let finishNames = ["Factory", "Magenta", "Teal", "Sunset", "Gold", "Violet", "Lime", "Chrome"]

    static func weaponImage(_ weapon: WeaponID, finish: Int, scale: CGFloat = 4) -> UIImage {
        GunArt.image(weapon, finish: finish, height: weaponHeight(weapon, scale: scale))
    }

    /// Drawn guns are taller than the old pixel rows so they read at the same width.
    static func weaponHeight(_ weapon: WeaponID, scale: CGFloat) -> CGFloat {
        let rows = CGFloat(weaponRows(weapon).count)
        let cols = CGFloat(weaponRows(weapon).first?.count ?? 1)
        // Keep the old width: height = width / aspect.
        return max(rows * scale, cols * scale / GunArt.aspect(weapon))
    }

    static func vehicleTexture(_ model: VehicleID) -> SKTexture {
        if let cached = vehicleCache[model] { return cached }
        let image: UIImage
        switch model {
        case .vesper:
            image = carImage()
        case .harborPatrol:
            image = PixelArt.image(rows: patrolRows, palette: [
                "w": Palette.UI.cream, "k": Palette.UI.ink, "t": Palette.UI.teal, "o": Palette.UI.sunset,
                "r": Palette.UI.magenta, "b": Palette.UI.teal
            ])
        case .dorado:
            image = PixelArt.image(rows: sedanRows, palette: [
                "b": Palette.UI.sunset, "w": Palette.UI.teal.withAlphaComponent(0.8), "c": UIColor(hex: 0xC9652A),
                "k": Palette.UI.ink, "o": Palette.UI.cream
            ])
        case .ridgeback, .hauler:
            image = PixelArt.image(rows: vanRows, palette: [
                "b": UIColor(hex: 0x2A8C84), "w": Palette.UI.cream.withAlphaComponent(0.85), "c": Palette.UI.cream,
                "s": Palette.UI.teal, "k": Palette.UI.ink, "o": Palette.UI.sunset
            ])
        case .flicker:
            image = PixelArt.image(rows: bikeRows, palette: [
                "m": Palette.UI.magenta, "w": Palette.UI.cream, "s": Palette.UI.ink, "k": UIColor(hex: 0x050608),
                "o": Palette.UI.sunset
            ])
        default:
            image = HDArt.vehicleImage(model)
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        vehicleCache[model] = texture
        return texture
    }

    // MARK: People

    static let personRows: [String] = [
        "..hhh..",
        ".hhhhh.",
        ".hhhhh.",
        "sbbbbbs",
        "sbbbbbs",
        ".bbbbb.",
        "..b.b..",
    ]

    /// Shirt colours for the crowd, chosen by `Pedestrian.look`.
    private static let shirts: [UIColor] = [
        UIColor(hex: 0x2EE6D6), UIColor(hex: 0xFF8A3D), UIColor(hex: 0xF4EBD9),
        UIColor(hex: 0x8E6BFF), UIColor(hex: 0x5BC26A), UIColor(hex: 0x3D7BFF)
    ]
    private static let skins: [UIColor] = [UIColor(hex: 0x8D5A3B), UIColor(hex: 0xC68B5E), UIColor(hex: 0xF1C9A0)]
    private static let hairs: [UIColor] = [UIColor(hex: 0x15110E), UIColor(hex: 0x5A3A22), UIColor(hex: 0xB8873B)]
    private static var personCache: [Int: SKTexture] = [:]

    /// A bystander (look 0...5) or the player (look -1: magenta jacket).
    static func personTexture(look: Int) -> SKTexture {
        if let cached = personCache[look] { return cached }
        let shirt = look < 0 ? Palette.UI.magenta : shirts[look % shirts.count]
        let skin = look < 0 ? skins[0] : skins[look % skins.count]
        let hair = look < 0 ? Palette.UI.ink : hairs[(look / 2) % hairs.count]
        let texture = SKTexture(image: PixelArt.image(rows: personRows, palette: ["h": hair, "s": skin, "b": shirt]))
        texture.filteringMode = .nearest
        personCache[look] = texture
        return texture
    }

    // MARK: The player's look

    /// Palettes the character creator offers. Index = `PlayerProfile.skin/hair/jacket`.
    static let lookSkins: [UIColor] = [UIColor(hex: 0x5C3A24), UIColor(hex: 0x8D5A3B), UIColor(hex: 0xB07A52),
                                       UIColor(hex: 0xD9A57A), UIColor(hex: 0xF1C9A0)]
    static let lookHairs: [UIColor] = [UIColor(hex: 0x15110E), UIColor(hex: 0x5A3A22), UIColor(hex: 0xD8B04A),
                                       UIColor(hex: 0xC2412D), UIColor(hex: 0xCFD3DA)]
    static let lookHairNames = ["Black", "Brown", "Blond", "Red", "Silver"]
    static let lookJackets: [UIColor] = [Palette.UI.magenta, Palette.UI.teal, Palette.UI.sunset, Palette.UI.cream,
                                         UIColor(hex: 0x8E6BFF), UIColor(hex: 0x7BD14B), UIColor(hex: 0x3D7BFF),
                                         UIColor(hex: 0x23252C)]
    static let lookJacketNames = ["Magenta", "Teal", "Sunset", "Cream", "Violet", "Lime", "Cobalt", "Black"]

    /// Front-facing portrait for the creator and the ID card.
    static let portraitRows: [String] = [
        "....hhhh....",
        "...hhhhhh...",
        "..hhhhhhhh..",
        "..hssssssh..",
        "..skssssks..",
        "..ssssssss..",
        "...sskkss...",
        "....ssss....",
        "..jjjjjjjj..",
        ".jjjjttjjjj.",
        "jjjjjttjjjjj",
        "sjjjjttjjjjs",
        "sjjjjttjjjjs",
        ".jjjjjjjjjj.",
        "..pppppppp..",
        "..ppp..ppp..",
        "..ppp..ppp..",
        "..kkk..kkk..",
    ]

    private static func lookPalette(_ p: PlayerProfile) -> [Character: UIColor] {
        let n = p.normalized
        return ["h": lookHairs[n.hair], "s": lookSkins[n.skin], "j": lookJackets[n.jacket],
                "t": n.jacket == 3 ? Palette.UI.ink : Palette.UI.cream,
                "p": UIColor(hex: 0x2B3140), "k": UIColor(hex: 0x0B0C10)]
    }

    static func portraitImage(_ profile: PlayerProfile, scale: CGFloat = 10) -> UIImage {
        PixelArt.image(rows: portraitRows, palette: lookPalette(profile), scale: scale)
    }

    /// The player seen from above, in their own colours.
    static func playerTexture(_ profile: PlayerProfile?) -> SKTexture {
        guard let profile else { return personTexture(look: -1) }
        let palette = lookPalette(profile)
        let texture = SKTexture(image: PixelArt.image(rows: personRows,
                                                      palette: ["h": palette["h"]!, "s": palette["s"]!, "b": palette["j"]!]))
        texture.filteringMode = .nearest
        return texture
    }

    // MARK: Weapons

    static let batRows = ["..........kkkk", "......kkkkkkkk", "kkkkkkkkkkkk..", "kkk..........."]
    static let rifleRows = ["kkkkkkkkkkkkkkkk", "kkkkkkkkkkkkkkkk", "...kkkk.....kk..", "...kk..........."]
    static let pistolRows = ["kkkkkk..", "kkkkkkk.", "..kk....", "..k....."]
    static let smgRows = ["kkkkkkkkk.", "kkkkkkkkkk", "..kk.kk...", "..k..k...."]
    static let shotgunRows = ["kkkkkkkkkkkk", "kkkkkkkkkkkk", "kkkk........", "kk.........."]

    private static var weaponCache: [WeaponID: SKTexture] = [:]

    static func weaponRows(_ weapon: WeaponID) -> [String] {
        switch weapon {
        case .bat: batRows
        case .pistol: pistolRows
        case .smg: smgRows
        case .shotgun: shotgunRows
        case .rifle: rifleRows
        }
    }

    /// The alley dealer: long dark coat, sunset cap.
    static func dealerTexture() -> SKTexture {
        let texture = SKTexture(image: PixelArt.image(rows: personRows, palette: [
            "h": Palette.UI.sunset, "s": UIColor(hex: 0x8D5A3B), "b": UIColor(hex: 0x23252C)
        ]))
        texture.filteringMode = .nearest
        return texture
    }

    static func weaponTexture(_ weapon: WeaponID) -> SKTexture {
        if let cached = weaponCache[weapon] { return cached }
        let image = GunArt.image(weapon, height: weaponHeight(weapon, scale: 1) * 3)
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        weaponCache[weapon] = texture
        return texture
    }

    /// The same icon for SwiftUI (gun store, HUD).
    static func weaponImage(_ weapon: WeaponID, scale: CGFloat = 4) -> UIImage {
        GunArt.image(weapon, height: weaponHeight(weapon, scale: scale))
    }

    static func vehicleImage(_ model: VehicleID, scale: CGFloat = 4) -> UIImage {
        HDArt.vehiclePreview(model, design: nil, height: CGFloat(rows(model).count) * scale)
    }

    static func pixelVehicleImage(_ model: VehicleID, scale: CGFloat = 4) -> UIImage {
        let texture = vehicleTexture(model)
        let cg = texture.cgImage()
        let size = CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
