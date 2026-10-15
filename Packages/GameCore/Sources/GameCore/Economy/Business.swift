import Foundation

/// What a credit movement was for. Income categories are positive, costs negative.
public enum LedgerCategory: String, Codable, Sendable, CaseIterable {
    case jobPay
    case upgrades
    case weapons
    case ammo
    case vehicleSale
    case mods
    case paint
    case designSales
    /// A business the player owns: what customers paid (income) and what it cost to run.
    case businessRevenue
    case businessCosts
    /// Buying or upgrading a business: cash turned into an asset, not an everyday cost.
    case investments
    /// Interest the savings account paid.
    case interest
    /// Daily streak and Job-of-the-day bonuses.
    case bonuses
    /// League prizes and achievement rewards.
    case prizes
    /// Tickets from Harbor Patrol.
    case fines

    public var label: String {
        switch self {
        case .jobPay: "Job pay"
        case .upgrades: "Car upgrades"
        case .weapons: "Weapons"
        case .ammo: "Ammo"
        case .vehicleSale: "Vehicle sales"
        case .mods: "Gun mods"
        case .paint: "Paint designs"
        case .designSales: "Design sales"
        case .businessRevenue: "Business revenue"
        case .businessCosts: "Business running costs"
        case .investments: "Investments"
        case .interest: "Savings interest"
        case .bonuses: "Bonuses"
        case .prizes: "Prizes"
        case .fines: "Fines"
        }
    }

    public var isIncome: Bool {
        switch self {
        case .jobPay, .vehicleSale, .designSales, .businessRevenue, .interest, .bonuses, .prizes: true
        default: false
        }
    }

    /// Buying an asset swaps cash for something worth money; it isn't counted as an expense.
    public var isInvestment: Bool { self == .investments }

    /// Money the player earned by working this week: what the weekly league counts. Selling
    /// things you own, interest and prizes don't count; running costs come off business pay.
    public var countsForLeague: Bool {
        switch self {
        case .jobPay, .designSales, .businessRevenue, .businessCosts, .bonuses: true
        default: false
        }
    }
}

public struct LedgerEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var date: Date
    /// Signed credits: + money in, − money out.
    public var amount: Int
    public var category: LedgerCategory
    public var note: String
}

/// The player's books: every credit in and out, kept like a small business would. Totals are
/// running sums, so trimming old entries never changes them.
public struct Books: Codable, Sendable, Equatable {
    public static let keepEntries = 150

    public private(set) var entries: [LedgerEntry] = []
    /// Lifetime totals per category (signed).
    public private(set) var totals: [String: Int] = [:]
    private var nextID = 0

    public init() {}

    private enum CodingKeys: String, CodingKey { case entries, totals, nextID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Entries from a newer build with a category this one doesn't know are skipped, not fatal.
        entries = ((try? c.decodeIfPresent([Lossy<LedgerEntry>].self, forKey: .entries)) ?? []).compactMap(\.value)
        totals = (try? c.decodeIfPresent([String: Int].self, forKey: .totals)) ?? [:]
        nextID = (try? c.decodeIfPresent(Int.self, forKey: .nextID)) ?? entries.count
    }

    public mutating func record(_ amount: Int, _ category: LedgerCategory, _ note: String, on date: Date = Date()) {
        guard amount != 0 else { return }
        // Whole seconds, so a saved ledger reads back exactly the same.
        let stamp = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        entries.append(LedgerEntry(id: nextID, date: stamp, amount: amount, category: category, note: note))
        nextID += 1
        totals[category.rawValue, default: 0] += amount
        if entries.count > Self.keepEntries { entries.removeFirst(entries.count - Self.keepEntries) }
    }

    public func total(_ category: LedgerCategory) -> Int { totals[category.rawValue] ?? 0 }

    /// Money in, lifetime.
    public var income: Int { LedgerCategory.allCases.filter(\.isIncome).reduce(0) { $0 + total($1) } }
    /// Money out, lifetime, as a positive number.
    public var expenses: Int {
        -LedgerCategory.allCases.filter { !$0.isIncome && !$0.isInvestment }.reduce(0) { $0 + total($1) }
    }
    /// Cash put into businesses (a positive number).
    public var invested: Int { -total(.investments) }
    public var profit: Int { income - expenses }
    /// Share of income kept after costs, 0...1 (nil before any income).
    public var margin: Double? { income > 0 ? Double(profit) / Double(income) : nil }
    public var entryCount: Int { nextID }
}

/// Decodes an element if it can, else nil, so one bad element doesn't sink a whole array.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// A car in the player's garage.
public struct OwnedVehicle: Codable, Sendable, Equatable {
    public var model: VehicleID
    /// The paint design on it (a `PaintDesign.id`), if any.
    public var design: String?
    /// Aftermarket wheels (nil = the factory rims).
    public var rims: RimSetup?
    /// How worn each part is (nil = brand new). The mechanic reads and fixes this.
    public var wear: CarWear?

    public init(model: VehicleID, design: String? = nil) {
        self.model = model
        self.design = design
    }
}


/// Garage rules: slots, keeping and selling cars.
public enum GarageRules {
    public static let slots = 6
    /// Selling a street car pays this share of its market value (it's second-hand).
    public static let resaleShare = 0.4

    public static func resaleValue(_ model: VehicleID) -> Int {
        Int((Double(model.marketValue) * resaleShare).rounded())
    }

    /// Adds a car to the garage if there's a free slot.
    @discardableResult
    public static func keep(_ model: VehicleID, progress: inout PlayerProgress) -> Bool {
        guard progress.garage.count < slots, model != .harborPatrol else { return false }
        progress.garage.append(OwnedVehicle(model: model))
        return true
    }

    /// Sells the car in `slot`. The starter Vesper (slot 0) can't be sold.
    @discardableResult
    public static func sell(slot: Int, progress: inout PlayerProgress, now: Date = Date()) -> Int? {
        guard slot > 0, progress.garage.indices.contains(slot) else { return nil }
        let model = progress.garage.remove(at: slot).model
        let value = resaleValue(model)
        progress.credits += value
        progress.books.record(value, .vehicleSale, "Sold \(model.spec.displayName)", on: now)
        if progress.selectedVehicle >= progress.garage.count { progress.selectedVehicle = 0 }
        if progress.selectedVehicle == slot { progress.selectedVehicle = 0 }
        return value
    }

    /// What the garage is worth: an asset, not cash.
    public static func assetValue(_ progress: PlayerProgress) -> Int {
        progress.garage.reduce(0) { $0 + $1.model.marketValue }
    }
}

/// Bolt & Barrel, the gun store on Signal Street.
/// Who's selling: Bolt & Barrel (full range, ammo, mods) or the alley dealer (guns only,
/// cheaper, no questions).
public enum GunSeller: String, Sendable, CaseIterable {
    case store
    case dealer

    public var name: String {
        switch self {
        case .store: "Bolt & Barrel"
        case .dealer: "Alley dealer"
        }
    }

    public func price(_ weapon: WeaponID) -> Int {
        switch self {
        case .store: weapon.spec.price
        case .dealer: Int((Double(weapon.spec.price) * GunStore.dealerDiscount).rounded())
        }
    }

    public var sellsAmmoAndMods: Bool { self == .store }
}

public enum GunStore {
    public enum Refusal: Error, Equatable {
        case notEnoughCredits(needed: Int)
        case alreadyOwned
        case notOwned
        case full
        case notCapped
        case notSoldHere
    }

    /// The Extended Mag mod lifts a starter gun's 35-round cap.
    public static let extendedMagPrice = 250
    /// The dealer undercuts the store.
    public static let dealerDiscount = 0.8

    /// Buys a weapon (with one pack of ammo). A fresh copy of a capped starter gun replaces it
    /// and lifts the cap. Returns why not, or nil when it went through.
    @discardableResult
    public static func buy(_ weapon: WeaponID, from seller: GunSeller = .store, progress: inout PlayerProgress,
                           now: Date = Date()) -> Refusal? {
        let spec = weapon.spec
        let price = seller.price(weapon)
        let replacingStarter = progress.inventory.isCapped(weapon)
        guard !progress.inventory.owns(weapon) || replacingStarter else { return .alreadyOwned }
        guard progress.credits >= price else { return .notEnoughCredits(needed: price - progress.credits) }
        progress.credits -= price
        progress.inventory.acquire(weapon, ammo: spec.ammoPack)
        progress.inventory.equipped = weapon
        let note = replacingStarter ? "New \(spec.name) (no starter limit)" : "Bought \(spec.name)"
        progress.books.record(-price, .weapons, seller == .dealer ? "\(note), from the dealer" : note, on: now)
        return nil
    }

    /// Buys one pack of ammo for a weapon the player owns, up to its cap. Returns why not, or nil.
    @discardableResult
    public static func buyAmmo(_ weapon: WeaponID, progress: inout PlayerProgress, now: Date = Date()) -> Refusal? {
        let spec = weapon.spec
        guard !spec.isMelee else { return .notSoldHere }
        guard progress.inventory.owns(weapon) else { return .notOwned }
        guard progress.inventory.ammo(for: weapon) < progress.inventory.ammoCap(for: weapon) else { return .full }
        guard progress.credits >= spec.ammoPrice else { return .notEnoughCredits(needed: spec.ammoPrice - progress.credits) }
        progress.credits -= spec.ammoPrice
        progress.inventory.add(weapon, ammo: spec.ammoPack)
        progress.books.record(-spec.ammoPrice, .ammo, "\(spec.ammoPack) rounds for the \(spec.name)", on: now)
        return nil
    }

    /// The Extended Mag mod: the starter gun's 35-round cap is gone for good.
    @discardableResult
    public static func buyExtendedMag(_ weapon: WeaponID, progress: inout PlayerProgress, now: Date = Date()) -> Refusal? {
        guard progress.inventory.owns(weapon) else { return .notOwned }
        guard progress.inventory.isCapped(weapon) else { return .notCapped }
        guard progress.credits >= extendedMagPrice else {
            return .notEnoughCredits(needed: extendedMagPrice - progress.credits)
        }
        progress.credits -= extendedMagPrice
        progress.inventory.uncap(weapon)
        // It's the Workbench's extended mag part, fitted.
        var build = progress.inventory.build(for: weapon)
        build.owned.insert(.extendedMag)
        build.magazine = .extendedMag
        progress.inventory.builds[weapon.rawValue] = build
        progress.books.record(-extendedMagPrice, .weapons, "Extended mag for the \(weapon.spec.name)", on: now)
        return nil
    }
}

/// Short money lessons that unlock as the player plays. Plain facts about running a small
/// business, tied to something the player just did.
public struct Lesson: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    let unlocked: @Sendable (PlayerProgress) -> Bool

    public static func == (a: Lesson, b: Lesson) -> Bool { a.id == b.id }

    public func isUnlocked(_ progress: PlayerProgress) -> Bool { unlocked(progress) }

    public static let all: [Lesson] = [
        Lesson(id: "revenue", title: "Revenue isn't profit",
               body: "Revenue is everything a job pays you. Profit is what's left after what you spent to earn it: fuel, repairs, tools. A $200 job that cost you $150 earned you $50.",
               unlocked: { $0.books.total(.jobPay) > 0 }),
        Lesson(id: "books", title: "Track every dollar",
               body: "Small businesses write down every sale and every cost. Without the books you can't tell which work actually pays. Your ledger does this for you: check the Business screen.",
               unlocked: { $0.books.entryCount >= 5 }),
        Lesson(id: "reinvest", title: "Reinvesting",
               body: "Spending profit on better tools so you can earn more is reinvesting. A faster car finishes jobs sooner and earns bigger speed bonuses. It only pays off if the extra earnings beat the cost.",
               unlocked: { $0.books.total(.upgrades) < 0 }),
        Lesson(id: "costs", title: "Cost of doing business",
               body: "Supplies you use up, like ammo, are operating costs. They come back every month. Keep them small compared with what you earn, or your margin shrinks.",
               unlocked: { $0.books.total(.ammo) < 0 || $0.books.total(.weapons) < 0 }),
        Lesson(id: "assets", title: "Cash vs assets",
               body: "Cars in your garage are assets: worth money, but not money yet. Selling one turns it into cash, usually for less than it's worth. Net worth is cash plus assets.",
               unlocked: { $0.garage.count >= 2 }),
        Lesson(id: "diversify", title: "More than one income",
               body: "Relying on one kind of work is risky. People who work for themselves often mix gigs, sales and side hustles so a slow week in one doesn't sink them.",
               unlocked: { $0.missionBests.count >= 3 }),
        Lesson(id: "hustle", title: "Side hustles",
               body: "A side hustle is paid work you choose and schedule yourself, like delivering flyers for a local shop. Small pay, but it's yours, and it builds skills and contacts.",
               unlocked: { $0.missionBests[MissionID.streetFlyers.rawValue] != nil }),
        Lesson(id: "pricing", title: "Price vs demand",
               body: "Charge more and each sale earns more, but fewer people buy. Charge less and more people buy, for less each. The best price is where price × buyers is highest, so try a few and watch your sales.",
               unlocked: { !$0.listings.isEmpty }),
        Lesson(id: "platformFee", title: "Platform fees",
               body: "Selling through someone else's shop or app costs a cut: the body shop keeps 30% of every design sale. App stores, marketplaces and delivery apps all work like this. Price with the fee in mind.",
               unlocked: { $0.books.total(.designSales) > 0 }),
        Lesson(id: "creator", title: "Make once, sell many times",
               body: "A design takes effort once, then sells again and again with no extra cost. That's why creators, writers and app makers can earn while they sleep. The work up front is the investment.",
               unlocked: { $0.designs.contains { BodyShop.isMine($0.id) } }),
        Lesson(id: "passive", title: "Passive income",
               body: "A business you own keeps taking money while you do something else. It isn't free money: you paid for it up front, and supplies, wages and rent come out of every sale. What's left is your profit.",
               unlocked: { !$0.properties.isEmpty }),
        Lesson(id: "payback", title: "Payback period",
               body: "Divide what a business cost by the profit it makes per hour, and you get how long it takes to earn the money back. After that, every hour is profit. Shorter payback means less risk.",
               unlocked: { $0.properties.contains { $0.lifetimeProfit > 0 } }),
        Lesson(id: "compound", title: "Compound interest",
               body: "Savings earn interest, and next time the interest earns interest too. 1% a day on 10,000 is 100 the first day and 101 the next. Start early and let it grow; real banks pay much less, but the maths is the same.",
               unlocked: { $0.bank.interestEarned > 0 }),
        Lesson(id: "networth", title: "Net worth vs income",
               body: "Income is what comes in this week. Net worth is everything you own minus what you owe. Someone can earn a lot and still have a low net worth if they spend it all. The league ranks earning; the net-worth board ranks keeping.",
               unlocked: { $0.league.history.count >= 1 || NetWorth.total($0) >= 10_000 }),
        Lesson(id: "risk", title: "Fines are a cost of risk",
               body: "A ticket comes straight out of your profit. Businesses budget for risks like fines, insurance and breakages, then work to keep them rare. Cutting corners can cost more than it saves.",
               unlocked: { $0.books.total(.fines) < 0 })
    ]
}
