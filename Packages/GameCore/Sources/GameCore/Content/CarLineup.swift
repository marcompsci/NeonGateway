import Foundation

/// Fictional car makers. Every brand and model is invented for Neon Getaway.
public enum CarBrand: String, Sendable, CaseIterable {
    case vesper = "Vesper"
    case kaze = "Kaze"
    case ironside = "Ironside"
    case halcyon = "Halcyon"
    case brisa = "Brisa"
    case volta = "Volta"
    case corvane = "Corvane"
    case aurora = "Aurora Motor Works"

    public var tagline: String {
        switch self {
        case .vesper: "Port Aurora's own sports coupés."
        case .kaze: "Light, rev-happy rear-drive cars built to slide."
        case .ironside: "Big engines, loud pipes, straight-line speed."
        case .halcyon: "Quiet luxury: soft rides and long hoods."
        case .brisa: "Tough 4x4s for every road in Solara."
        case .volta: "Electric: instant shove, no gears, no fuel."
        case .corvane: "Hand-built supercars from the coast."
        case .aurora: "Everyday cars and vans for Port Aurora."
        }
    }
}

/// How a car is drawn (top-down and side-on).
public enum BodyStyle: String, Sendable {
    case coupe, sedan, van, bike, cruiserBike, muscle, luxury, suv, ev, supercar, fastback, finned, wedge, truck, patrol
}

/// Where a car comes from.
public enum CarTier: String, Sendable, CaseIterable {
    /// On the streets of Port Aurora (take one and keep it).
    case street
    /// The dealership: pay and drive.
    case dealer
    /// Limited builds: one per player, rep-locked, special trim.
    case exclusive
    /// Old legends won by racing (Street Challenge golds). Never for sale.
    case legendary

    public var label: String {
        switch self {
        case .street: "Street"
        case .dealer: "Dealership"
        case .exclusive: "Exclusive build"
        case .legendary: "Legendary"
        }
    }
}

public struct CarEntry: Sendable, Equatable, Identifiable {
    public let model: VehicleID
    public let brand: CarBrand
    public let tier: CarTier
    public let style: BodyStyle
    public let price: Int
    public let repLevel: Int
    /// Legendary: lifetime Street Challenge golds needed.
    public let golds: Int
    public let blurb: String
    public var id: String { model.rawValue }
}

/// The cars the player can own and how to get them.
public enum CarLineup {
    public static let all: [CarEntry] = [
        CarEntry(model: .kestrel, brand: .kaze, tier: .dealer, style: .coupe, price: 5_500, repLevel: 1, golds: 0,
                 blurb: "Light and rear-drive: the easiest car in the city to drift."),
        CarEntry(model: .summit, brand: .brisa, tier: .dealer, style: .suv, price: 6_500, repLevel: 1, golds: 0,
                 blurb: "Tall and tough. Shrugs off bumps and long state highways."),
        CarEntry(model: .vandal, brand: .ironside, tier: .dealer, style: .cruiserBike, price: 4_000, repLevel: 1, golds: 0,
                 blurb: "A low cruiser bike with a big engine. Fast, but one bad crash hurts."),
        CarEntry(model: .bruiser, brand: .ironside, tier: .dealer, style: .muscle, price: 7_500, repLevel: 2, golds: 0,
                 blurb: "V8 muscle. Huge straight-line pull; brake early for corners."),
        CarEntry(model: .solace, brand: .halcyon, tier: .dealer, style: .luxury, price: 9_000, repLevel: 2, golds: 0,
                 blurb: "Smooth, solid and quiet. Takes a beating and still looks good."),
        CarEntry(model: .arc, brand: .volta, tier: .dealer, style: .ev, price: 11_000, repLevel: 3, golds: 0,
                 blurb: "Electric motors give full power at zero speed: nothing leaves a light faster."),
        CarEntry(model: .razor, brand: .corvane, tier: .dealer, style: .supercar, price: 24_000, repLevel: 4, golds: 0,
                 blurb: "The fastest thing Corvane sells. Grippy, light, and easy to break."),
        CarEntry(model: .kestrelMidnight, brand: .kaze, tier: .exclusive, style: .coupe, price: 18_000, repLevel: 3, golds: 0,
                 blurb: "Kaze's tuned drift build: stiffer, quicker, midnight paint with violet trim."),
        CarEntry(model: .razorNoir, brand: .corvane, tier: .exclusive, style: .supercar, price: 40_000, repLevel: 5, golds: 0,
                 blurb: "Only a handful built: matte black, gold pinstripe, more power than the Razor."),
        CarEntry(model: .stormhawk, brand: .ironside, tier: .legendary, style: .fastback, price: 0, repLevel: 0, golds: 1,
                 blurb: "A 1969 fastback legend. Win your first Street Challenge gold."),
        CarEntry(model: .seabreeze, brand: .halcyon, tier: .legendary, style: .finned, price: 0, repLevel: 0, golds: 3,
                 blurb: "A 1957 cruiser with tail fins and a two-tone roof. Three Street Challenge golds."),
        CarEntry(model: .ombra, brand: .corvane, tier: .legendary, style: .wedge, price: 0, repLevel: 0, golds: 5,
                 blurb: "The 1972 wedge that made Corvane famous. Five Street Challenge golds."),
    ]

    public static func entry(_ model: VehicleID) -> CarEntry? { all.first { $0.model == model } }

    public static func brand(_ model: VehicleID) -> CarBrand {
        if let e = entry(model) { return e.brand }
        return model == .vesper ? .vesper : .aurora
    }

    public static func style(_ model: VehicleID) -> BodyStyle {
        if let e = entry(model) { return e.style }
        switch model {
        case .vesper: return .coupe
        case .dorado: return .sedan
        case .ridgeback: return .van
        case .flicker: return .bike
        case .hauler: return .truck
        default: return .patrol
        }
    }

    public static func tier(_ model: VehicleID) -> CarTier { entry(model)?.tier ?? .street }

    public enum Refusal: Error, Equatable {
        case notForSale
        case needsRep(Int)
        case needsGolds(Int)
        case notEnoughCredits(needed: Int)
        case garageFull
        case alreadyOwned
    }

    public static func owns(_ model: VehicleID, _ p: PlayerProgress) -> Bool { p.garage.contains { $0.model == model } }

    /// Can the player buy (or claim) this car right now?
    public static func check(_ model: VehicleID, progress p: PlayerProgress) -> Refusal? {
        guard let e = entry(model) else { return .notForSale }
        if e.tier != .dealer, owns(model, p) { return .alreadyOwned }
        guard p.garage.count < GarageRules.slots else { return .garageFull }
        switch e.tier {
        case .legendary:
            return p.challenge.golds >= e.golds ? nil : .needsGolds(e.golds - p.challenge.golds)
        default:
            if ProgressionRules.level(forXP: p.reputationXP) < e.repLevel { return .needsRep(e.repLevel) }
            if p.credits < e.price { return .notEnoughCredits(needed: e.price - p.credits) }
            return nil
        }
    }

    /// Buys a dealer or exclusive car, or claims a won legend. It goes in the garage and is selected.
    @discardableResult
    public static func acquire(_ model: VehicleID, progress p: inout PlayerProgress, now: Date = Date()) -> Refusal? {
        if let refusal = check(model, progress: p) { return refusal }
        let e = entry(model)!
        if e.price > 0 {
            p.credits -= e.price
            p.books.record(-e.price, .investments, "Bought a \(model.spec.displayName)", on: now)
        }
        p.garage.append(OwnedVehicle(model: model))
        p.selectedVehicle = p.garage.count - 1
        return nil
    }

    /// Legends the player has won but not yet driven off with.
    public static func unclaimedLegends(_ p: PlayerProgress) -> [VehicleID] {
        all.filter { $0.tier == .legendary && p.challenge.golds >= $0.golds && !owns($0.model, p) }.map(\.model)
    }
}

// MARK: Rims

public enum RimStyle: String, Codable, Sendable, CaseIterable {
    case stock, fiveSplit, mesh, deepDish, turbofan, wire

    public var name: String {
        switch self {
        case .stock: "Stock steel"
        case .fiveSplit: "Split five-spoke"
        case .mesh: "Cross mesh"
        case .deepDish: "Deep dish"
        case .turbofan: "Turbofan"
        case .wire: "Classic wire"
        }
    }
    public var price: Int {
        switch self {
        case .stock: 0
        case .fiveSplit: 600
        case .mesh: 900
        case .deepDish: 1_200
        case .turbofan: 1_500
        case .wire: 1_800
        }
    }
    /// Spokes drawn on the rim face.
    public var spokes: Int {
        switch self {
        case .stock: 0
        case .fiveSplit: 10
        case .mesh: 16
        case .deepDish: 6
        case .turbofan: 12
        case .wire: 30
        }
    }
}

/// Rim colours: chrome, gunmetal, gloss black, gold, white, neon pink, teal, bronze.
public enum RimColors {
    public static let names = ["Chrome", "Gunmetal", "Gloss black", "Gold", "White", "Neon pink", "Teal", "Bronze"]
    public static let hex: [UInt32] = [0xD7DCE3, 0x4A505A, 0x15171B, 0xE2B13C, 0xF2F2F2, 0xFF3EA5, 0x2EE6D6, 0xA8673A]
    public static let price = 250
}

public struct RimSetup: Codable, Sendable, Equatable {
    public var style: RimStyle
    public var color: Int

    public init(style: RimStyle = .stock, color: Int = 0) {
        self.style = style
        self.color = color
    }
}

public enum RimShop {
    public enum Refusal: Error, Equatable { case notEnoughCredits(needed: Int), noCar }

    public static func cost(from old: RimSetup, to new: RimSetup) -> Int {
        (new.style == old.style ? 0 : new.style.price) + (new.color == old.color ? 0 : RimColors.price)
    }

    @discardableResult
    public static func fit(_ setup: RimSetup, slot: Int, progress p: inout PlayerProgress, now: Date = Date()) -> Refusal? {
        guard p.garage.indices.contains(slot) else { return .noCar }
        let old = p.garage[slot].rims ?? RimSetup()
        let price = cost(from: old, to: setup)
        guard p.credits >= price else { return .notEnoughCredits(needed: price - p.credits) }
        p.credits -= price
        if price > 0 { p.books.record(-price, .mods, "\(setup.style.name) rims, \(RimColors.names[setup.color])", on: now) }
        p.garage[slot].rims = setup
        return nil
    }
}
