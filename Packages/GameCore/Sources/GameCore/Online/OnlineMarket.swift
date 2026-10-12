import Foundation

/// A design another player put on the online market (one iCloud public record).
public struct MarketDesign: Sendable, Equatable, Identifiable {
    /// The iCloud record name.
    public var id: String
    public var name: String
    public var creatorID: String
    public var creatorName: String
    public var cells: [UInt8]
    public var price: Int
    public var created: Date
    /// Copies sold so far (counted from purchase records).
    public var sales: Int
    /// Reports from other players.
    public var reports: Int

    public init(id: String, name: String, creatorID: String, creatorName: String, cells: [UInt8], price: Int,
                created: Date, sales: Int = 0, reports: Int = 0) {
        self.id = id
        self.name = name
        self.creatorID = creatorID
        self.creatorName = creatorName
        self.cells = cells
        self.price = price
        self.created = created
        self.sales = sales
        self.reports = reports
    }

    /// The design as the buyer owns it.
    public var localID: String { OnlineMarket.localID(forRecord: id) }

    public var asPaint: PaintDesign {
        PaintDesign(id: localID, name: name, creator: creatorName, cells: cells, price: price)
    }
}

/// One player buying one design (one iCloud public record, written by the buyer). The creator's
/// game reads these and pays itself; that's how creators get paid without a server.
public struct MarketPurchase: Sendable, Equatable, Identifiable {
    public var id: String
    public var designID: String
    public var designName: String
    public var creatorID: String
    public var buyerID: String
    public var price: Int
    public var created: Date

    public init(id: String, designID: String, designName: String, creatorID: String, buyerID: String, price: Int,
                created: Date) {
        self.id = id
        self.designID = designID
        self.designName = designName
        self.creatorID = creatorID
        self.buyerID = buyerID
        self.price = price
        self.created = created
    }
}

/// What the player has done online, saved with their progress.
public struct OnlineState: Codable, Sendable, Equatable {
    /// Players whose designs and live-play avatars are hidden.
    public var blocked: [String] = []
    /// Designs the player has reported (so they report each once).
    public var reported: [String] = []
    /// Purchase records already paid out to this player (newest kept).
    public var paidPurchases: [String] = []
    /// Local design id → its iCloud record, for designs this player published.
    public var published: [String: String] = [:]
    /// Lifetime online design earnings, after fees.
    public var onlineEarnings = 0
    /// Live-play record.
    public var knockouts = 0
    public var gunsTaken = 0

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case blocked, reported, paidPurchases, published, onlineEarnings, knockouts, gunsTaken
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocked = (try? c.decodeIfPresent([String].self, forKey: .blocked)) ?? []
        reported = (try? c.decodeIfPresent([String].self, forKey: .reported)) ?? []
        paidPurchases = (try? c.decodeIfPresent([String].self, forKey: .paidPurchases)) ?? []
        published = (try? c.decodeIfPresent([String: String].self, forKey: .published)) ?? [:]
        onlineEarnings = (try? c.decodeIfPresent(Int.self, forKey: .onlineEarnings)) ?? 0
        knockouts = (try? c.decodeIfPresent(Int.self, forKey: .knockouts)) ?? 0
        gunsTaken = (try? c.decodeIfPresent(Int.self, forKey: .gunsTaken)) ?? 0
    }
}

/// The online design market's rules. The iCloud reads and writes live in the app; everything
/// that decides money, visibility and safety is here, so it's tested.
public enum OnlineMarket {
    /// A design with this many reports is hidden for everyone.
    public static let hideAtReports = 3
    public static let keepPaidPurchases = 500

    public enum Refusal: Error, Equatable {
        case notEnoughCredits(needed: Int)
        case alreadyOwned
        case ownDesign
        case hidden
        case notLegendary
        case badName
        case badDesign
        case badPrice
        case alreadyPublished
    }

    public static func localID(forRecord record: String) -> String { "cloud.\(record)" }
    public static func isOnline(_ localID: String) -> Bool { localID.hasPrefix("cloud.") }

    /// What a player should see: no blocked creators, nothing reported too often, nothing whose
    /// name fails the filter.
    public static func visible(_ designs: [MarketDesign], for p: PlayerProgress) -> [MarketDesign] {
        designs.filter {
            !p.online.blocked.contains($0.creatorID)
                && $0.reports < hideAtReports
                && ContentFilter.isAllowedPublicName($0.name)
                && ContentFilter.isAllowedPublicName($0.creatorName)
                && PaintDesign(id: "x", name: $0.name, creator: "", cells: $0.cells, price: 0).isValid
        }
    }

    /// Buys a copy: credits out (a cost in the ledger), the design is the player's to paint.
    /// The app then writes the purchase record that pays the creator.
    @discardableResult
    public static func buy(_ design: MarketDesign, myID: String, progress p: inout PlayerProgress,
                           now: Date = Date()) -> Refusal? {
        guard design.creatorID != myID else { return .ownDesign }
        guard !p.designs.contains(where: { $0.id == design.localID }) else { return .alreadyOwned }
        guard !visible([design], for: p).isEmpty else { return .hidden }
        guard p.credits >= design.price else { return .notEnoughCredits(needed: design.price - p.credits) }
        p.credits -= design.price
        p.designs.append(design.asPaint)
        p.books.record(-design.price, .paint, "\"\(design.name)\" by \(design.creatorName) (online)", on: now)
        return nil
    }

    /// Checks a design before it's published for everyone (Legendary only).
    public static func checkPublish(_ localID: String, price: Int, progress p: PlayerProgress) -> Refusal? {
        guard Ranking.isLegendary(p) else { return .notLegendary }
        guard p.online.published[localID] == nil else { return .alreadyPublished }
        guard BodyShop.isMine(localID), let design = p.designs.first(where: { $0.id == localID }) else {
            return .badDesign
        }
        guard design.isValid, design.cells.contains(where: { $0 != 0 }) else { return .badDesign }
        guard ContentFilter.isAllowedPublicName(design.name) else { return .badName }
        guard BodyShop.priceRange.contains(price) else { return .badPrice }
        return nil
    }

    public static func markPublished(_ localID: String, record: String, progress p: inout PlayerProgress) {
        p.online.published[localID] = record
    }

    public struct Payout: Sendable, Equatable {
        public var sales = 0
        public var gross = 0
        public var fee = 0
        public var net: Int { gross - fee }
    }

    /// Pays the player for every sale of their designs they haven't been paid for yet. Each
    /// purchase pays once, whatever order or how often the records arrive.
    @discardableResult
    public static func collectSales(_ purchases: [MarketPurchase], myID: String, progress p: inout PlayerProgress,
                                    now: Date = Date()) -> Payout {
        var payout = Payout()
        var paid = Set(p.online.paidPurchases)
        for purchase in purchases.sorted(by: { $0.created < $1.created })
        where purchase.creatorID == myID && purchase.buyerID != myID && !paid.contains(purchase.id) {
            let price = max(0, min(purchase.price, BodyShop.priceRange.upperBound))
            let fee = Int((Double(price) * BodyShop.platformFee).rounded())
            paid.insert(purchase.id)
            p.online.paidPurchases.append(purchase.id)
            payout.sales += 1
            payout.gross += price
            payout.fee += fee
            p.earn(price - fee, .designSales, "Online sale: \"\(purchase.designName)\" (after 30% shop fee)", on: now)
            p.skills.add(.hustle, xp: 5)
        }
        p.online.onlineEarnings += payout.net
        if p.online.paidPurchases.count > keepPaidPurchases {
            p.online.paidPurchases.removeFirst(p.online.paidPurchases.count - keepPaidPurchases)
        }
        return payout
    }

    public static func block(_ playerID: String, progress p: inout PlayerProgress) {
        guard !p.online.blocked.contains(playerID) else { return }
        p.online.blocked.append(playerID)
    }

    public static func unblock(_ playerID: String, progress p: inout PlayerProgress) {
        p.online.blocked.removeAll { $0 == playerID }
    }

    /// Marks a design reported by this player. False if they already reported it.
    @discardableResult
    public static func markReported(_ designID: String, progress p: inout PlayerProgress) -> Bool {
        guard !p.online.reported.contains(designID) else { return false }
        p.online.reported.append(designID)
        return true
    }

    /// Why a design can be reported.
    public enum ReportReason: String, CaseIterable, Sendable {
        case offensive = "Offensive or hateful"
        case sexual = "Sexual"
        case copied = "Copied from someone else"
        case other = "Something else"
    }
}

/// Game Center leaderboards. The weekly one is a recurring leaderboard that resets on Monday.
public enum OnlineBoards {
    public static let weekly = "neon.weekly.earnings"
    public static let allTime = "neon.alltime.score"
    public static let netWorth = "neon.networth"

    /// The scores to post for a player right now.
    public static func scores(_ p: PlayerProgress) -> [String: Int] {
        [weekly: p.league.earnings, allTime: Ranking.score(p), netWorth: max(0, NetWorth.total(p))]
    }
}
