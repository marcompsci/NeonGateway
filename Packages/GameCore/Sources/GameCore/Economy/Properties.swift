import Foundation

/// Businesses the player can buy. Each one takes money from customers every hour (real time,
/// even with the app closed), pays its running costs out of that, and holds the profit in its
/// till until the player collects it. Tills fill up, so checking in matters, but nothing ever
/// blocks play.
public enum PropertyID: String, Codable, Sendable, CaseIterable, Identifiable {
    case tacoTruck, carWash, laundromat, printShop, arcade

    public var id: String { rawValue }
    public var spec: PropertySpec { PropertySpec.all[self]! }
}

public struct PropertySpec: Sendable, Equatable {
    public let id: PropertyID
    public let name: String
    public let blurb: String
    public let price: Int
    /// What customers pay per hour at level 1.
    public let revenuePerHour: Int
    /// Share of revenue that goes on supplies, wages and rent.
    public let costShare: Double
    /// Reputation level needed to buy it.
    public let requiredRepLevel: Int

    public var profitPerHour: Double { Double(revenuePerHour) * (1 - costShare) }

    static let all: [PropertyID: PropertySpec] = [
        .tacoTruck: PropertySpec(id: .tacoTruck, name: "Taco truck", blurb: "Cheap to start, small margins: ingredients eat almost half.",
                                 price: 1_500, revenuePerHour: 120, costShare: 0.45, requiredRepLevel: 0),
        .carWash: PropertySpec(id: .carWash, name: "Suds car wash", blurb: "Water and soap are cheap; the machines did the hard work.",
                               price: 4_000, revenuePerHour: 260, costShare: 0.35, requiredRepLevel: 1),
        .laundromat: PropertySpec(id: .laundromat, name: "Spin City laundromat", blurb: "Steady customers every day. Rent and power are the big costs.",
                                  price: 7_500, revenuePerHour: 420, costShare: 0.40, requiredRepLevel: 2),
        .printShop: PropertySpec(id: .printShop, name: "Inkwell print shop", blurb: "Flyers, posters, menus. High margins once the press is paid for.",
                                 price: 12_000, revenuePerHour: 640, costShare: 0.30, requiredRepLevel: 3),
        .arcade: PropertySpec(id: .arcade, name: "Pixel Palace arcade", blurb: "The big one: lots of customers, staff on every shift.",
                              price: 20_000, revenuePerHour: 1_000, costShare: 0.35, requiredRepLevel: 4)
    ]
}

public struct OwnedProperty: Codable, Sendable, Equatable, Identifiable {
    public var kind: PropertyID
    /// 1...3.
    public var level = 1
    /// When the till was last emptied.
    public var lastCollected: Date
    /// Spent on it so far (purchase plus upgrades).
    public var invested: Int
    public var lifetimeProfit = 0

    public var id: String { kind.rawValue }

    public init(kind: PropertyID, lastCollected: Date, invested: Int) {
        self.kind = kind
        self.lastCollected = lastCollected
        self.invested = invested
    }
}

public enum Properties {
    public static let maxLevel = 3
    /// Revenue multiplier at level 1, 2, 3.
    public static let levelRevenue = [1.0, 1.6, 2.4]
    /// Hours of takings the till holds at level 1, 2, 3.
    public static let tillHours = [8.0, 10.0, 12.0]
    /// Selling a business returns this share of what went into it.
    public static let resaleShare = 0.6

    public enum Refusal: Error, Equatable {
        case notEnoughCredits(needed: Int)
        case alreadyOwned
        case notOwned
        case maxLevel
        case locked(level: Int)
        case nothingToCollect
    }

    public struct Till: Sendable, Equatable {
        public var revenue: Int
        public var costs: Int
        public var hours: Double
        public var isFull: Bool
        public var profit: Int { revenue - costs }
    }

    public static func owned(_ id: PropertyID, in p: PlayerProgress) -> OwnedProperty? {
        p.properties.first { $0.kind == id }
    }

    public static func upgradePrice(_ property: OwnedProperty) -> Int? {
        guard property.level < maxLevel else { return nil }
        let price = Double(property.kind.spec.price)
        return Int(price * (property.level == 1 ? 0.6 : 1.0))
    }

    /// Profit per hour at a level, with the Hustle skill's bonus.
    public static func profitPerHour(_ id: PropertyID, level: Int, hustle: Int = 0) -> Double {
        id.spec.profitPerHour * levelRevenue[min(max(level, 1), maxLevel) - 1] * Skills.hustleMultiplier(hustle)
    }

    /// Hours of profit it takes to earn back what was paid (the payback period).
    public static func paybackHours(_ id: PropertyID) -> Double {
        Double(id.spec.price) / id.spec.profitPerHour
    }

    public static func till(_ property: OwnedProperty, hustle: Int = 0, now: Date = Date()) -> Till {
        let spec = property.kind.spec
        let cap = tillHours[property.level - 1]
        let elapsed = max(0, now.timeIntervalSince(property.lastCollected)) / 3_600
        let hours = min(cap, elapsed)
        let revenue = Int((Double(spec.revenuePerHour) * levelRevenue[property.level - 1]
                           * Skills.hustleMultiplier(hustle) * hours).rounded(.down))
        let costs = Int((Double(revenue) * spec.costShare).rounded())
        return Till(revenue: revenue, costs: costs, hours: hours, isFull: elapsed >= cap)
    }

    public static func resaleValue(_ property: OwnedProperty) -> Int {
        Int((Double(property.invested) * resaleShare).rounded())
    }

    @discardableResult
    public static func buy(_ id: PropertyID, progress p: inout PlayerProgress, now: Date = Date()) -> Refusal? {
        let spec = id.spec
        guard owned(id, in: p) == nil else { return .alreadyOwned }
        let level = ProgressionRules.level(forXP: p.reputationXP)
        guard level >= spec.requiredRepLevel else { return .locked(level: spec.requiredRepLevel) }
        guard p.credits >= spec.price else { return .notEnoughCredits(needed: spec.price - p.credits) }
        p.credits -= spec.price
        p.books.record(-spec.price, .investments, "Bought the \(spec.name)", on: now)
        p.properties.append(OwnedProperty(kind: id, lastCollected: now, invested: spec.price))
        return nil
    }

    @discardableResult
    public static func upgrade(_ id: PropertyID, progress p: inout PlayerProgress, now: Date = Date()) -> Refusal? {
        guard let i = p.properties.firstIndex(where: { $0.kind == id }) else { return .notOwned }
        guard let price = upgradePrice(p.properties[i]) else { return .maxLevel }
        guard p.credits >= price else { return .notEnoughCredits(needed: price - p.credits) }
        // Empty the till first, so takings so far are paid at the old rate.
        collect(id, progress: &p, now: now)
        p.credits -= price
        p.properties[i].level += 1
        p.properties[i].invested += price
        p.books.record(-price, .investments, "Upgraded the \(id.spec.name) to level \(p.properties[i].level)", on: now)
        return nil
    }

    /// Empties a till: revenue and running costs go in the books, profit into credits.
    @discardableResult
    public static func collect(_ id: PropertyID, progress p: inout PlayerProgress, now: Date = Date(),
                               timeZone: TimeZone = .current) -> Till? {
        guard let i = p.properties.firstIndex(where: { $0.kind == id }) else { return nil }
        let till = till(p.properties[i], hustle: p.skills.level(.hustle), now: now)
        p.properties[i].lastCollected = now
        guard till.revenue > 0 else { return nil }
        let name = id.spec.name
        p.earn(till.revenue, .businessRevenue, "\(name) takings", on: now, timeZone: timeZone)
        p.earn(-till.costs, .businessCosts, "\(name) supplies, wages, rent", on: now, timeZone: timeZone)
        p.properties[i].lifetimeProfit += till.profit
        p.skills.add(.hustle, xp: max(1, till.profit / 20))
        return till
    }

    /// Collects every till; returns the combined takings.
    @discardableResult
    public static func collectAll(progress p: inout PlayerProgress, now: Date = Date(),
                                  timeZone: TimeZone = .current) -> Till {
        var total = Till(revenue: 0, costs: 0, hours: 0, isFull: false)
        for property in p.properties {
            if let till = collect(property.kind, progress: &p, now: now, timeZone: timeZone) {
                total.revenue += till.revenue
                total.costs += till.costs
                total.hours = max(total.hours, till.hours)
            }
        }
        return total
    }

    /// Sells a business back for part of what went into it, after emptying its till.
    @discardableResult
    public static func sell(_ id: PropertyID, progress p: inout PlayerProgress, now: Date = Date()) -> Int? {
        guard owned(id, in: p) != nil else { return nil }
        collect(id, progress: &p, now: now)
        guard let i = p.properties.firstIndex(where: { $0.kind == id }) else { return nil }
        let value = resaleValue(p.properties[i])
        p.properties.remove(at: i)
        p.credits += value
        // Getting cash back out of an asset: the opposite of investing.
        p.books.record(value, .investments, "Sold the \(id.spec.name)", on: now)
        return value
    }
}

// MARK: - Skills

/// Skills grow by doing: drive to get better at driving, and so on. Each level is a small,
/// real edge, never a wall.
public enum Skill: String, Codable, Sendable, CaseIterable, Identifiable {
    case driving, shooting, stamina, hustle

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .driving: "Driving"
        case .shooting: "Shooting"
        case .stamina: "Stamina"
        case .hustle: "Hustle"
        }
    }

    public var effect: String {
        switch self {
        case .driving: "+3% steering per level"
        case .shooting: "+6% auto-aim cone per level"
        case .stamina: "+4% running speed per level"
        case .hustle: "+5% business takings per level"
        }
    }

    public var howToTrain: String {
        switch self {
        case .driving: "Drive anywhere."
        case .shooting: "Land hits with any weapon."
        case .stamina: "Run on foot."
        case .hustle: "Collect from your businesses and sell designs."
        }
    }
}

public struct SkillBook: Codable, Sendable, Equatable {
    public var xp: [String: Int] = [:]

    public init() {}

    public func xp(_ skill: Skill) -> Int { xp[skill.rawValue] ?? 0 }
    public func level(_ skill: Skill) -> Int { Skills.level(forXP: xp(skill)) }

    public mutating func add(_ skill: Skill, xp amount: Int) {
        guard amount > 0 else { return }
        xp[skill.rawValue, default: 0] += amount
    }

    public var levels: SkillLevels {
        SkillLevels(driving: level(.driving), shooting: level(.shooting), stamina: level(.stamina),
                    hustle: level(.hustle))
    }
}

/// Skill levels as the city uses them.
public struct SkillLevels: Sendable, Equatable {
    public var driving = 0
    public var shooting = 0
    public var stamina = 0
    public var hustle = 0

    public init(driving: Int = 0, shooting: Int = 0, stamina: Int = 0, hustle: Int = 0) {
        self.driving = driving
        self.shooting = shooting
        self.stamina = stamina
        self.hustle = hustle
    }
}

public enum Skills {
    /// XP for level 0...5.
    public static let thresholds = [0, 150, 500, 1_200, 2_600, 5_000]
    public static var maxLevel: Int { thresholds.count - 1 }

    public static func level(forXP xp: Int) -> Int { (thresholds.lastIndex { xp >= $0 }) ?? 0 }

    /// XP still to go for the next level, or nil at the top.
    public static func xpToNext(_ xp: Int) -> Int? {
        let next = level(forXP: xp) + 1
        return next < thresholds.count ? thresholds[next] - xp : nil
    }

    public static func steeringMultiplier(_ level: Int) -> Double { 1 + 0.03 * Double(level) }
    public static func aimMultiplier(_ level: Int) -> Double { 1 + 0.06 * Double(level) }
    public static func runMultiplier(_ level: Int) -> Double { 1 + 0.04 * Double(level) }
    public static func hustleMultiplier(_ level: Int) -> Double { 1 + 0.05 * Double(level) }

    /// Points travelled per XP.
    public static let drivePointsPerXP = 400.0
    public static let runPointsPerXP = 150.0
    public static let xpPerHit = 6

    /// Folds what the player did in one trip into their skills. Returns the XP gained.
    @discardableResult
    public static func award(_ stats: RunStats, to p: inout PlayerProgress) -> [Skill: Int] {
        let gains: [Skill: Int] = [
            .driving: Int(stats.driven / drivePointsPerXP),
            .stamina: Int(stats.run / runPointsPerXP),
            .shooting: stats.hitsLanded * xpPerHit
        ]
        for (skill, xp) in gains { p.skills.add(skill, xp: xp) }
        p.career.driven += stats.driven
        p.career.run += stats.run
        p.career.hitsLanded += stats.hitsLanded
        return gains.filter { $0.value > 0 }
    }
}

/// What the player did in one trip into the city, for skills and career stats.
public struct RunStats: Sendable, Equatable {
    public var driven = 0.0
    public var run = 0.0
    public var hitsLanded = 0
    public var ticketsPaid = 0
    /// Knocks taken while driving (wear on the car).
    public var knocks = 0

    public init() {}
}

/// Lifetime totals the trophies and stats screens read.
public struct CareerStats: Codable, Sendable, Equatable {
    public var driven = 0.0
    public var run = 0.0
    public var hitsLanded = 0
    public var tickets = 0
    public var photos = 0

    public init() {}

    private enum CodingKeys: String, CodingKey { case driven, run, hitsLanded, tickets, photos }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        driven = (try? c.decodeIfPresent(Double.self, forKey: .driven)) ?? 0
        run = (try? c.decodeIfPresent(Double.self, forKey: .run)) ?? 0
        hitsLanded = (try? c.decodeIfPresent(Int.self, forKey: .hitsLanded)) ?? 0
        tickets = (try? c.decodeIfPresent(Int.self, forKey: .tickets)) ?? 0
        photos = (try? c.decodeIfPresent(Int.self, forKey: .photos)) ?? 0
    }
}
