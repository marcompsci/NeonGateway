import Foundation

// MARK: - Workbench (gun builder)

/// Bolt & Barrel's Workbench: buy parts for a gun you own, swap between owned parts for free,
/// and paint a finish. Parts change the gun's real stats (`GunBuild.apply`).
public enum Workbench {
    public enum Refusal: Error, Equatable {
        case notOwned
        case doesNotFit
        case notEnoughCredits(needed: Int)
        case badFinish
    }

    /// Fits `part` (buying it first if needed), or clears the slot when `part` is nil.
    @discardableResult
    public static func fit(_ part: GunPart?, slot: GunPart.Slot, on weapon: WeaponID,
                           progress: inout PlayerProgress, now: Date = Date()) -> Refusal? {
        guard progress.inventory.owns(weapon) else { return .notOwned }
        var build = progress.inventory.build(for: weapon)
        if let part {
            guard part.fits(weapon), part.slot == slot else { return .doesNotFit }
            if !build.owned.contains(part) {
                guard progress.credits >= part.price else { return .notEnoughCredits(needed: part.price - progress.credits) }
                progress.credits -= part.price
                build.owned.insert(part)
                progress.books.record(-part.price, .mods, "\(part.name) for the \(weapon.spec.name)", on: now)
            }
        }
        build.install(part, in: slot)
        progress.inventory.builds[weapon.rawValue] = build
        if part == .extendedMag { progress.inventory.uncap(weapon) }
        // Taking the extended mag off a gun keeps the ammo you have but caps what you can carry.
        let cap = progress.inventory.ammoCap(for: weapon)
        if progress.inventory.ammo(for: weapon) > cap { progress.inventory.ammo[weapon.rawValue] = cap }
        return nil
    }

    /// Paints the gun. The factory finish (0) is free; any colour costs `GunBuild.finishPrice`.
    @discardableResult
    public static func paint(_ weapon: WeaponID, finish: Int, progress: inout PlayerProgress,
                             now: Date = Date()) -> Refusal? {
        guard progress.inventory.owns(weapon) else { return .notOwned }
        guard (0..<GunBuild.finishCount).contains(finish) else { return .badFinish }
        var build = progress.inventory.build(for: weapon)
        guard build.finish != finish else { return nil }
        if finish != 0 {
            guard progress.credits >= GunBuild.finishPrice else {
                return .notEnoughCredits(needed: GunBuild.finishPrice - progress.credits)
            }
            progress.credits -= GunBuild.finishPrice
            progress.books.record(-GunBuild.finishPrice, .mods, "New finish on the \(weapon.spec.name)", on: now)
        }
        build.finish = finish
        progress.inventory.builds[weapon.rawValue] = build
        return nil
    }
}

// MARK: - Paint designs

/// A car paint design: a small pixel grid laid over any car's body. Cell value 0 keeps the
/// car's own colour; 1...`colorCount` are colours from the design palette.
public struct PaintDesign: Codable, Sendable, Equatable, Identifiable {
    public static let width = 12
    public static let height = 20
    public static let colorCount = 11
    public static let nameLength = 2...20

    public var id: String
    public var name: String
    public var creator: String
    /// Row-major, top (the car's nose) first, `width * height` cells.
    public var cells: [UInt8]
    /// Asking price in the body shop.
    public var price: Int

    public init(id: String, name: String, creator: String, cells: [UInt8], price: Int) {
        self.id = id
        self.name = name
        self.creator = creator
        self.cells = cells
        self.price = price
    }

    public static var blank: [UInt8] { Array(repeating: 0, count: width * height) }

    public func cell(col: Int, row: Int) -> UInt8 {
        guard (0..<Self.width).contains(col), (0..<Self.height).contains(row) else { return 0 }
        return cells[row * Self.width + col]
    }

    /// The design's colour at a point on a car, both as 0...1 fractions (0,0 = nose-left).
    public func sample(u: Double, v: Double) -> UInt8 {
        let col = min(Self.width - 1, max(0, Int(u * Double(Self.width))))
        let row = min(Self.height - 1, max(0, Int(v * Double(Self.height))))
        return cell(col: col, row: row)
    }

    public var isValid: Bool {
        cells.count == Self.width * Self.height && cells.allSatisfy { $0 <= UInt8(Self.colorCount) }
    }

    /// How eye-catching it is, 0.3...1: more painted cells and more colours sell better.
    public var boldness: Double {
        let painted = cells.filter { $0 != 0 }
        let coverage = Double(painted.count) / Double(cells.count)
        let colours = Set(painted).count
        return min(1, max(0.3, 0.3 + coverage * 0.5 + Double(min(colours, 4)) * 0.06))
    }

    // MARK: Starting points for the studio and the house designs

    public enum Template: String, CaseIterable, Sendable {
        case racingStripe, flames, checker, tigerStripes, splitTone, starburst

        public var name: String {
            switch self {
            case .racingStripe: "Racing stripe"
            case .flames: "Flames"
            case .checker: "Checker"
            case .tigerStripes: "Tiger stripes"
            case .splitTone: "Split tone"
            case .starburst: "Starburst"
            }
        }
    }

    /// Cells for a template in colours `a` and `b` (palette indices 1...colorCount).
    public static func cells(_ t: Template, a: UInt8, b: UInt8) -> [UInt8] {
        var g = blank
        let w = width, h = height
        func set(_ c: Int, _ r: Int, _ v: UInt8) { if (0..<w).contains(c) && (0..<h).contains(r) { g[r * w + c] = v } }
        switch t {
        case .racingStripe:
            for r in 0..<h { set(4, r, a); set(5, r, b); set(6, r, b); set(7, r, a) }
        case .flames:
            for c in 0..<w {
                let tongue = 6 + (c % 3 == 1 ? 4 : (c % 3 == 0 ? 2 : 0))
                for r in 0..<tongue { set(c, h - 1 - r, r < tongue - 3 ? a : b) }
            }
        case .checker:
            for r in 0..<h { for c in 0..<w where (r / 2 + c / 2) % 2 == 0 { set(c, r, a) } }
            for r in 0..<h { for c in 0..<w where (r / 2 + c / 2) % 2 == 1 { set(c, r, b) } }
        case .tigerStripes:
            for r in stride(from: 1, to: h, by: 4) {
                for c in 0..<w { let wobble = (c % 4 < 2) ? 0 : 1; set(c, r + wobble, a) }
            }
            for r in 0..<h where r % 4 == 3 { set(0, r, b); set(w - 1, r, b) }
        case .splitTone:
            for r in 0..<h { for c in 0..<w { set(c, r, c < w / 2 ? a : b) } }
        case .starburst:
            let cx = Double(w) / 2 - 0.5, cy = Double(h) / 2 - 0.5
            for r in 0..<h {
                for c in 0..<w {
                    let dx = Double(c) - cx, dy = Double(r) - cy
                    let angle = atan2(dy, dx)
                    if Int(((angle + .pi) / (.pi / 6)).rounded(.down)) % 2 == 0 { set(c, r, a) }
                    if dx * dx + dy * dy < 6 { set(c, r, b) }
                }
            }
        }
        return g
    }
}

/// A design the player put up for sale in the body shop.
public struct DesignListing: Codable, Sendable, Equatable {
    public var designID: String
    public var price: Int
    public var sold = 0
    /// Credits the creator has received (after the platform fee).
    public var earned = 0

    public init(designID: String, price: Int) {
        self.designID = designID
        self.price = price
    }
}

// MARK: - Rankings

/// The city's leaderboard. Offline, the other names are invented rivals with fixed scores; the
/// top five are Legendary, and only Legendary players can sell their own designs.
public enum Ranking {
    public struct Entry: Sendable, Equatable {
        public let name: String
        public let score: Int
        public let isPlayer: Bool
    }

    public enum Tier: String, Sendable, CaseIterable {
        case legendary = "Legendary", elite = "Elite", pro = "Pro", street = "Street"
    }

    /// Invented rivals and their scores.
    public static let rivals: [(String, Int)] = [
        ("Vex Monroe", 4200), ("Lula Kade", 3100), ("Dax Ferro", 2400), ("Mina Sol", 1800),
        ("Rook Halvorsen", 1300), ("Juno Pike", 950), ("Tito Arcade", 700), ("Saffron Lee", 500),
        ("Bram Okafor", 350), ("Kit Vane", 240), ("Ozzie Pell", 160), ("Neve Castillo", 100),
        ("Moss Ferraro", 60), ("Poppy Duarte", 30)
    ]
    public static let legendaryCutoff = 5
    public static let eliteCutoff = 10
    public static let proCutoff = 14

    /// Reputation, jobs done and business profit all count.
    public static func score(_ p: PlayerProgress) -> Int {
        p.reputationXP + p.completedJobs * 10 + max(0, p.books.profit) / 5
    }

    public static func board(_ p: PlayerProgress) -> [Entry] {
        let me = Entry(name: p.profile?.name ?? "You", score: score(p), isPlayer: true)
        let others = rivals.map { Entry(name: $0.0, score: $0.1, isPlayer: false) }
        // Ties go to the player: you earned it.
        return (others + [me]).sorted { $0.score != $1.score ? $0.score > $1.score : $0.isPlayer }
    }

    public static func rank(_ p: PlayerProgress) -> Int {
        (board(p).firstIndex { $0.isPlayer } ?? 0) + 1
    }

    public static func tier(forRank rank: Int) -> Tier {
        switch rank {
        case ...legendaryCutoff: .legendary
        case ...eliteCutoff: .elite
        case ...proCutoff: .pro
        default: .street
        }
    }

    public static func tier(_ p: PlayerProgress) -> Tier { tier(forRank: rank(p)) }

    public static func isLegendary(_ p: PlayerProgress) -> Bool { tier(p) == .legendary }

    /// Points still needed to reach Legendary (0 once there).
    public static func pointsToLegendary(_ p: PlayerProgress) -> Int {
        let fifth = rivals.map(\.1).sorted(by: >)[legendaryCutoff - 1]
        return max(0, fifth - score(p))
    }
}

// MARK: - Body shop and the design market

/// Chrome Coast Body Shop: buy designs from Legendary creators, paint your cars, and (once
/// you're Legendary) sell your own. Offline, the buyers are simulated: each finished job is a
/// market day, and how many people buy depends on price and how bold the design is.
public enum BodyShop {
    public enum Refusal: Error, Equatable {
        case notEnoughCredits(needed: Int)
        case alreadyOwned
        case unknownDesign
        case noSuchCar
        case notLegendary
        case badName
        case badDesign
        case badPrice
        case ownDesign
    }

    /// The body shop keeps this share of every sale (the platform fee).
    public static let platformFee = 0.3
    public static let priceRange = 50...5000
    public static let maxListings = 6

    /// Designs on sale from the rivals at the top of the rankings.
    public static let houseDesigns: [PaintDesign] = [
        PaintDesign(id: "house.midnightRacer", name: "Midnight Racer", creator: "Vex Monroe",
                    cells: PaintDesign.cells(.racingStripe, a: 1, b: 4), price: 300),
        PaintDesign(id: "house.harborFlames", name: "Harbor Flames", creator: "Lula Kade",
                    cells: PaintDesign.cells(.flames, a: 3, b: 2), price: 450),
        PaintDesign(id: "house.checkpoint", name: "Checkpoint", creator: "Dax Ferro",
                    cells: PaintDesign.cells(.checker, a: 1, b: 9), price: 400),
        PaintDesign(id: "house.neonTiger", name: "Neon Tiger", creator: "Mina Sol",
                    cells: PaintDesign.cells(.tigerStripes, a: 7, b: 2), price: 550),
        PaintDesign(id: "house.dusk", name: "Dusk Split", creator: "Rook Halvorsen",
                    cells: PaintDesign.cells(.splitTone, a: 5, b: 3), price: 350),
        PaintDesign(id: "house.supernova", name: "Supernova", creator: "Vex Monroe",
                    cells: PaintDesign.cells(.starburst, a: 2, b: 10), price: 800)
    ]

    public static func design(_ id: String, progress: PlayerProgress) -> PaintDesign? {
        progress.designs.first { $0.id == id } ?? houseDesigns.first { $0.id == id }
    }

    /// Buys a house design (yours to paint on any of your cars, as often as you like).
    @discardableResult
    public static func buy(_ id: String, progress: inout PlayerProgress, now: Date = Date()) -> Refusal? {
        guard let design = houseDesigns.first(where: { $0.id == id }) else { return .unknownDesign }
        guard !progress.designs.contains(where: { $0.id == id }) else { return .alreadyOwned }
        guard progress.credits >= design.price else { return .notEnoughCredits(needed: design.price - progress.credits) }
        progress.credits -= design.price
        progress.designs.append(design)
        progress.books.record(-design.price, .paint, "\"\(design.name)\" by \(design.creator)", on: now)
        return nil
    }

    /// Paints (or, with nil, strips) a car in the garage. Free: the design is already yours.
    @discardableResult
    public static func apply(_ id: String?, toSlot slot: Int, progress: inout PlayerProgress) -> Refusal? {
        guard progress.garage.indices.contains(slot) else { return .noSuchCar }
        if let id, !progress.designs.contains(where: { $0.id == id }) { return .unknownDesign }
        progress.garage[slot].design = id
        return nil
    }

    /// Saves a design the player drew in the studio. Anyone can make designs for their own cars;
    /// selling them takes Legendary rank.
    @discardableResult
    public static func create(name raw: String, cells: [UInt8], progress: inout PlayerProgress) -> Result<PaintDesign, Refusal> {
        let name = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard PaintDesign.nameLength.contains(name.count), ContentFilter.isAllowedPublicName(name) else {
            return .failure(.badName)
        }
        let creator = progress.profile?.name ?? "You"
        let id = "mine.\(progress.designSerial)"
        let design = PaintDesign(id: id, name: name, creator: creator, cells: cells, price: 0)
        guard design.isValid, design.cells.contains(where: { $0 != 0 }) else { return .failure(.badDesign) }
        progress.designSerial += 1
        progress.designs.append(design)
        return .success(design)
    }

    public static func isMine(_ id: String) -> Bool { id.hasPrefix("mine.") }

    /// Puts one of the player's own designs up for sale (Legendary only).
    @discardableResult
    public static func list(_ id: String, price: Int, progress: inout PlayerProgress) -> Refusal? {
        guard Ranking.isLegendary(progress) else { return .notLegendary }
        guard isMine(id), progress.designs.contains(where: { $0.id == id }) else { return .unknownDesign }
        guard priceRange.contains(price) else { return .badPrice }
        if let i = progress.listings.firstIndex(where: { $0.designID == id }) {
            progress.listings[i].price = price
            return nil
        }
        guard progress.listings.count < maxListings else { return .badPrice }
        progress.listings.append(DesignListing(designID: id, price: price))
        return nil
    }

    public static func unlist(_ id: String, progress: inout PlayerProgress) {
        progress.listings.removeAll { $0.designID == id }
    }

    /// What one market day sold.
    public struct Report: Sendable, Equatable {
        public struct Line: Sendable, Equatable {
            public let name: String
            public let sold: Int
            public let gross: Int
            public let fee: Int
            public var net: Int { gross - fee }
        }
        public var lines: [Line] = []
        public var net: Int { lines.reduce(0) { $0 + $1.net } }
        public var isEmpty: Bool { lines.isEmpty }
    }

    /// Expected buyers per day for a design at a price: bolder sells more, pricier sells less.
    public static func expectedSales(boldness: Double, price: Int) -> Double {
        3.0 * boldness * exp(-Double(price) / 400)
    }

    /// One market day: simulated buyers purchase listed designs, and the creator is paid
    /// (minus the platform fee) straight into their credits and books.
    @discardableResult
    public static func marketDay(_ progress: inout PlayerProgress, now: Date = Date()) -> Report {
        progress.marketDay += 1
        var report = Report()
        for i in progress.listings.indices {
            let listing = progress.listings[i]
            guard let design = progress.designs.first(where: { $0.id == listing.designID }) else { continue }
            let expected = expectedSales(boldness: design.boldness, price: listing.price)
            var rng = SplitMix64(seed: stableHash(listing.designID) &+ UInt64(progress.marketDay) &* 0x9E37)
            let whole = Int(expected.rounded(.down))
            let extra = Double(rng.next() % 10_000) / 10_000 < expected - Double(whole) ? 1 : 0
            let sold = whole + extra
            guard sold > 0 else { continue }
            let gross = sold * listing.price
            let fee = Int((Double(gross) * platformFee).rounded())
            progress.listings[i].sold += sold
            progress.listings[i].earned += gross - fee
            progress.earn(gross - fee, .designSales,
                          "\(sold) × \"\(design.name)\" (after \(Int(platformFee * 100))% shop fee)", on: now)
            progress.skills.add(.hustle, xp: sold * 5)
            report.lines.append(.init(name: design.name, sold: sold, gross: gross, fee: fee))
        }
        return report
    }

    /// FNV-1a, so the same design sells the same way on every device and launch.
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }
}
