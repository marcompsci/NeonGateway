import Foundation

/// Calendar days and weeks for streaks, the league and interest. Days are counted in the
/// player's own time zone so "today" matches their clock; weeks start on Monday.
public enum GameClock {
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> Int {
        let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        return Int((local / 86_400).rounded(.down))
    }

    /// 1 Jan 1970 was a Thursday, so +3 puts week boundaries on Mondays.
    public static func week(_ date: Date, timeZone: TimeZone = .current) -> Int {
        week(ofDay: day(date, timeZone: timeZone))
    }

    public static func week(ofDay day: Int) -> Int {
        Int((Double(day + 3) / 7).rounded(.down))
    }

    /// How far through its week `date` is, 0...1.
    public static func weekFraction(_ date: Date, timeZone: TimeZone = .current) -> Double {
        let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        let days = local / 86_400 + 3
        return min(1, max(0, (days - (days / 7).rounded(.down) * 7) / 7))
    }

    /// Seconds until the current week ends (Monday 00:00 local).
    public static func secondsLeftInWeek(_ date: Date, timeZone: TimeZone = .current) -> Double {
        (1 - weekFraction(date, timeZone: timeZone)) * 7 * 86_400
    }
}

// MARK: - Weekly league

/// Leagues climb from Bronze to Neon. Each week the player races 14 rivals in their division on
/// money earned by working: job pay, design sales, business profit and daily bonuses.
public enum Division: Int, Codable, Sendable, CaseIterable, Comparable {
    case bronze, silver, gold, platinum, neon

    public static func < (a: Division, b: Division) -> Bool { a.rawValue < b.rawValue }

    public var name: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        case .neon: "Neon"
        }
    }

    /// First-place prize is 4× this; see `League.prizeMultipliers`.
    public var prizeBase: Int {
        switch self {
        case .bronze: 300
        case .silver: 600
        case .gold: 1_000
        case .platinum: 1_600
        case .neon: 2_500
        }
    }

    /// What the weakest and strongest rivals here earn in a full week.
    public var rivalRange: ClosedRange<Int> {
        switch self {
        case .bronze: 400...4_000
        case .silver: 1_200...8_000
        case .gold: 2_500...14_000
        case .platinum: 5_000...24_000
        case .neon: 9_000...40_000
        }
    }

    public var next: Division? { Division(rawValue: rawValue + 1) }
    public var previous: Division? { Division(rawValue: rawValue - 1) }
}

/// How one finished week went.
public struct LeagueResult: Codable, Sendable, Equatable {
    public var week: Int
    public var division: Division
    public var rank: Int
    public var earnings: Int
    public var prize: Int
    /// +1 promoted, −1 relegated, 0 stayed.
    public var movement: Int
}

public struct LeagueState: Codable, Sendable, Equatable {
    /// The week being played (`GameClock.week`), or −1 before the first one.
    public var week = -1
    public var division: Division = .bronze
    /// League earnings so far this week.
    public var earnings = 0
    /// Finished weeks, newest last (kept short).
    public var history: [LeagueResult] = []
    /// A finished week the player hasn't been shown yet.
    public var unseen: LeagueResult?
    public var wins = 0
    public var bestDivision: Division = .bronze
    public var totalPrizes = 0

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case week, division, earnings, history, unseen, wins, bestDivision, totalPrizes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = (try? c.decodeIfPresent(Int.self, forKey: .week)) ?? -1
        division = (try? c.decodeIfPresent(Division.self, forKey: .division)) ?? .bronze
        earnings = (try? c.decodeIfPresent(Int.self, forKey: .earnings)) ?? 0
        history = (try? c.decodeIfPresent([LeagueResult].self, forKey: .history)) ?? []
        unseen = try? c.decodeIfPresent(LeagueResult.self, forKey: .unseen)
        wins = (try? c.decodeIfPresent(Int.self, forKey: .wins)) ?? 0
        bestDivision = (try? c.decodeIfPresent(Division.self, forKey: .bestDivision)) ?? division
        totalPrizes = (try? c.decodeIfPresent(Int.self, forKey: .totalPrizes)) ?? 0
    }
}

public enum League {
    public static let size = 15
    public static let promoted = 3
    public static let relegated = 3
    public static let keepHistory = 12
    /// Prize for 1st, 2nd, ... as a multiple of the division's base. Places past the list win nothing.
    public static let prizeMultipliers: [Double] = [4, 2.5, 2, 1, 1, 0.5, 0.5, 0.5, 0.5, 0.5]

    public struct Entry: Sendable, Equatable {
        public let name: String
        public let earnings: Int
        public let isPlayer: Bool
    }

    static let names = [
        "Vex Monroe", "Lula Kade", "Dax Ferro", "Mina Sol", "Rook Halvorsen", "Juno Pike", "Tito Arcade",
        "Saffron Lee", "Bram Okafor", "Kit Vane", "Ozzie Pell", "Neve Castillo", "Moss Ferraro", "Poppy Duarte",
        "Cass Ivers", "Remy Achebe", "Wren Talbot", "Ike Moreno", "Hana Brisk", "Gus Delacroix", "Pia Lund",
        "Otis Crane", "Zuri Bello", "Leo Marsh", "Ada Quill", "Rafi Stone", "Nell Okoro", "Benny Sato"
    ]

    public static func prize(rank: Int, division: Division) -> Int {
        guard rank >= 1, rank <= prizeMultipliers.count else { return 0 }
        return Int((Double(division.prizeBase) * prizeMultipliers[rank - 1]).rounded())
    }

    /// The 14 rivals for a week and division: names and what they'll have earned by week's end.
    /// Deterministic, so the same week looks the same on every launch.
    static func rivals(week: Int, division: Division) -> [(name: String, final: Int, pace: Double)] {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(week)) &* 0x9E37_79B9 &+ UInt64(division.rawValue) &* 7_919)
        var pool = names
        var picked: [(String, Int, Double)] = []
        let range = division.rivalRange
        for _ in 0..<(size - 1) {
            let i = Int(rng.next() % UInt64(pool.count))
            let name = pool.remove(at: i)
            // Skewed toward the low end: a few big earners, most modest.
            let u = Double(rng.next() % 10_000) / 10_000
            let final = range.lowerBound + Int(Double(range.upperBound - range.lowerBound) * pow(u, 1.6))
            // Some start fast, some finish strong.
            let pace = 0.7 + Double(rng.next() % 700) / 1_000
            picked.append((name, final, pace))
        }
        return picked
    }

    /// What a rival has earned `fraction` of the way through the week.
    static func earned(final: Int, pace: Double, fraction: Double) -> Int {
        Int((Double(final) * pow(min(1, max(0, fraction)), pace)).rounded())
    }

    /// This week's table, best first. Ties go to the player.
    public static func board(_ p: PlayerProgress, now: Date = Date(), timeZone: TimeZone = .current) -> [Entry] {
        let week = GameClock.week(now, timeZone: timeZone)
        let fraction = GameClock.weekFraction(now, timeZone: timeZone)
        let mine = p.league.week == week ? p.league.earnings : 0
        return table(week: week, division: p.league.division, fraction: fraction,
                     playerName: p.profile?.name ?? "You", playerEarnings: mine)
    }

    static func table(week: Int, division: Division, fraction: Double, playerName: String,
                      playerEarnings: Int) -> [Entry] {
        let others = rivals(week: week, division: division).map {
            Entry(name: $0.name, earnings: earned(final: $0.final, pace: $0.pace, fraction: fraction), isPlayer: false)
        }
        let me = Entry(name: playerName, earnings: playerEarnings, isPlayer: true)
        return (others + [me]).sorted { $0.earnings != $1.earnings ? $0.earnings > $1.earnings : $0.isPlayer }
    }

    public static func rank(_ p: PlayerProgress, now: Date = Date(), timeZone: TimeZone = .current) -> Int {
        (board(p, now: now, timeZone: timeZone).firstIndex { $0.isPlayer } ?? 0) + 1
    }

    /// Credits still needed to pass the next driver up (0 when first).
    public static func gapToNext(_ p: PlayerProgress, now: Date = Date(), timeZone: TimeZone = .current) -> Int {
        let board = board(p, now: now, timeZone: timeZone)
        guard let i = board.firstIndex(where: { $0.isPlayer }), i > 0 else { return 0 }
        return board[i - 1].earnings - board[i].earnings + 1
    }

    public static func zone(forRank rank: Int, division: Division) -> Int {
        if rank <= promoted && division.next != nil { return 1 }
        if rank > size - relegated && division.previous != nil { return -1 }
        return 0
    }

    /// Counts money earned by working toward this week's league (settling last week first).
    public static func tally(_ amount: Int, progress p: inout PlayerProgress, now: Date = Date(),
                             timeZone: TimeZone = .current) {
        refresh(&p, now: now, timeZone: timeZone)
        p.league.earnings = max(0, p.league.earnings + amount)
    }

    /// Settles a finished week if the calendar has moved on: final places, prize money and
    /// promotion or relegation. Returns the result once, when it's settled.
    @discardableResult
    public static func refresh(_ p: inout PlayerProgress, now: Date = Date(), timeZone: TimeZone = .current) -> LeagueResult? {
        let week = GameClock.week(now, timeZone: timeZone)
        if p.league.week < 0 {
            p.league.week = week
            return nil
        }
        guard week > p.league.week else { return nil }
        defer {
            p.league.week = week
            p.league.earnings = 0
        }
        // Sat a week out: nothing to settle, no prize, no relegation.
        guard p.league.earnings > 0 else { return nil }
        let division = p.league.division
        let table = table(week: p.league.week, division: division, fraction: 1,
                          playerName: p.profile?.name ?? "You", playerEarnings: p.league.earnings)
        let rank = (table.firstIndex { $0.isPlayer } ?? 0) + 1
        let prize = prize(rank: rank, division: division)
        let movement = zone(forRank: rank, division: division)
        if prize > 0 {
            p.credits += prize
            p.books.record(prize, .prizes, "\(division.name) league, #\(rank) of \(size)", on: now)
            p.league.totalPrizes += prize
        }
        if rank == 1 { p.league.wins += 1 }
        if movement > 0, let up = division.next { p.league.division = up }
        if movement < 0, let down = division.previous { p.league.division = down }
        p.league.bestDivision = max(p.league.bestDivision, division, p.league.division)
        let result = LeagueResult(week: p.league.week, division: division, rank: rank,
                                  earnings: p.league.earnings, prize: prize, movement: movement)
        p.league.history.append(result)
        if p.league.history.count > keepHistory { p.league.history.removeFirst(p.league.history.count - keepHistory) }
        p.league.unseen = result
        return result
    }
}

extension PlayerProgress {
    /// Money earned by working: into credits, the books, and this week's league.
    public mutating func earn(_ amount: Int, _ category: LedgerCategory, _ note: String, on date: Date = Date(),
                              timeZone: TimeZone = .current) {
        guard amount != 0 else { return }
        credits += amount
        books.record(amount, category, note, on: date)
        if category.countsForLeague { League.tally(amount, progress: &self, now: date, timeZone: timeZone) }
    }
}

// MARK: - Daily streak and Job of the day

public struct DailyState: Codable, Sendable, Equatable {
    /// The last day (`GameClock.day`) the player finished a job, or −1.
    public var lastDay = -1
    public var streak = 0
    public var best = 0
    /// Each one covers a single missed day. Earned by finishing a 7-day run.
    public var shields = 0
    /// The day the Job of the day was last paid double.
    public var featuredDay = -1

    public init() {}

    private enum CodingKeys: String, CodingKey { case lastDay, streak, best, shields, featuredDay }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastDay = (try? c.decodeIfPresent(Int.self, forKey: .lastDay)) ?? -1
        streak = (try? c.decodeIfPresent(Int.self, forKey: .streak)) ?? 0
        best = (try? c.decodeIfPresent(Int.self, forKey: .best)) ?? 0
        shields = (try? c.decodeIfPresent(Int.self, forKey: .shields)) ?? 0
        featuredDay = (try? c.decodeIfPresent(Int.self, forKey: .featuredDay)) ?? -1
    }
}

/// Crossword-app style dailies, tuned for a money game: the first job each day pays a streak
/// bonus that grows for a week, and one job a day pays double.
public enum Daily {
    /// Bonus for day 1, 2, ... of a streak; day 7 and on pay the last one.
    public static let streakBonuses = [100, 150, 200, 250, 300, 400, 500]
    public static let maxShields = 2

    public struct Update: Sendable, Equatable {
        /// Paid for the first job of the day.
        public var streakBonus: Int?
        public var streak: Int
        /// Paid for finishing the Job of the day.
        public var featuredBonus: Int?
        /// A shield covered a missed day.
        public var usedShield = false
        public var earnedShield = false

        public var total: Int { (streakBonus ?? 0) + (featuredBonus ?? 0) }
    }

    public static func bonus(forStreak streak: Int) -> Int {
        streakBonuses[min(max(streak, 1), streakBonuses.count) - 1]
    }

    /// Today's double-pay job: the same for everyone on a given day, picked from jobs the
    /// player can take.
    public static func featured(day: Int, progress p: PlayerProgress) -> MissionDef? {
        let open = MissionDef.all.filter { ProgressionRules.isUnlocked($0, progress: p) }
        guard !open.isEmpty else { return nil }
        let pick = BodyShop.stableHash("featured.\(day)") % UInt64(open.count)
        return open[Int(pick)]
    }

    /// The streak as it stands today: it's still alive if the last job was today or yesterday
    /// (or the gap is covered by shields).
    public static func liveStreak(_ p: PlayerProgress, today: Int) -> Int {
        guard p.daily.lastDay >= 0 else { return 0 }
        let missed = today - p.daily.lastDay - 1
        return missed <= p.daily.shields ? p.daily.streak : 0
    }

    /// Pays the daily bonuses for a finished job.
    @discardableResult
    public static func recordJob(_ def: MissionDef, success: Bool, progress p: inout PlayerProgress,
                                 now: Date = Date(), timeZone: TimeZone = .current) -> Update {
        let today = GameClock.day(now, timeZone: timeZone)
        var update = Update(streak: liveStreak(p, today: today))
        guard success else { return update }

        if p.daily.lastDay != today {
            let missed = p.daily.lastDay < 0 ? 0 : today - p.daily.lastDay - 1
            if p.daily.lastDay >= 0, missed > 0, missed <= p.daily.shields {
                p.daily.shields -= missed
                update.usedShield = true
            } else if missed > 0 {
                p.daily.streak = 0
            }
            p.daily.streak += 1
            p.daily.lastDay = today
            p.daily.best = max(p.daily.best, p.daily.streak)
            if p.daily.streak % 7 == 0 && p.daily.shields < maxShields {
                p.daily.shields += 1
                update.earnedShield = true
            }
            let bonus = bonus(forStreak: p.daily.streak)
            p.earn(bonus, .bonuses, "Daily streak, day \(p.daily.streak)", on: now, timeZone: timeZone)
            update.streakBonus = bonus
        }
        update.streak = p.daily.streak

        if p.daily.featuredDay != today, featured(day: today, progress: p)?.id == def.id {
            p.daily.featuredDay = today
            p.earn(def.baseReward, .bonuses, "Job of the day: \(def.title)", on: now, timeZone: timeZone)
            update.featuredBonus = def.baseReward
        }
        return update
    }
}

// MARK: - Bank

public struct BankAccount: Codable, Sendable, Equatable {
    public var balance = 0
    /// The last day interest was worked out, or −1 before the first deposit.
    public var lastInterestDay = -1
    public var interestEarned = 0

    public init() {}

    private enum CodingKeys: String, CodingKey { case balance, lastInterestDay, interestEarned }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        balance = (try? c.decodeIfPresent(Int.self, forKey: .balance)) ?? 0
        lastInterestDay = (try? c.decodeIfPresent(Int.self, forKey: .lastInterestDay)) ?? -1
        interestEarned = (try? c.decodeIfPresent(Int.self, forKey: .interestEarned)) ?? 0
    }
}

/// Harbor Savings: money parked here earns 1% a day, compounded, on up to 25,000. Cash in your
/// pocket earns nothing and pays tickets; savings are safe.
public enum Bank {
    public static let dailyRate = 0.01
    public static let interestCap = 25_000
    /// Interest stops building after this many days away (it's a game, not a pension).
    public static let maxCatchUpDays = 30

    public enum Refusal: Error, Equatable {
        case badAmount
        case notEnoughCash(needed: Int)
        case notEnoughSaved(needed: Int)
    }

    /// Adds interest for every whole day since it was last worked out. Returns the interest paid.
    @discardableResult
    public static func accrue(_ p: inout PlayerProgress, now: Date = Date(), timeZone: TimeZone = .current) -> Int {
        let today = GameClock.day(now, timeZone: timeZone)
        guard p.bank.lastInterestDay >= 0 else {
            p.bank.lastInterestDay = today
            return 0
        }
        let days = min(maxCatchUpDays, max(0, today - p.bank.lastInterestDay))
        p.bank.lastInterestDay = max(p.bank.lastInterestDay, today)
        var paid = 0
        for _ in 0..<days {
            let interest = Int((Double(min(p.bank.balance, interestCap)) * dailyRate).rounded(.down))
            guard interest > 0 else { break }
            p.bank.balance += interest
            paid += interest
        }
        if paid > 0 {
            p.bank.interestEarned += paid
            p.books.record(paid, .interest, days == 1 ? "Interest, 1 day" : "Interest, \(days) days", on: now)
        }
        return paid
    }

    /// Moves cash into savings. Not income or spending, so the books don't change.
    @discardableResult
    public static func deposit(_ amount: Int, progress p: inout PlayerProgress, now: Date = Date(),
                               timeZone: TimeZone = .current) -> Refusal? {
        guard amount > 0 else { return .badAmount }
        guard p.credits >= amount else { return .notEnoughCash(needed: amount - p.credits) }
        accrue(&p, now: now, timeZone: timeZone)
        p.credits -= amount
        p.bank.balance += amount
        return nil
    }

    @discardableResult
    public static func withdraw(_ amount: Int, progress p: inout PlayerProgress, now: Date = Date(),
                                timeZone: TimeZone = .current) -> Refusal? {
        guard amount > 0 else { return .badAmount }
        accrue(&p, now: now, timeZone: timeZone)
        guard p.bank.balance >= amount else { return .notEnoughSaved(needed: amount - p.bank.balance) }
        p.bank.balance -= amount
        p.credits += amount
        return nil
    }

    /// What a balance grows to after `days` days of interest (for the savings calculator).
    public static func projected(_ balance: Int, days: Int) -> Int {
        var b = balance
        for _ in 0..<max(0, days) {
            b += Int((Double(min(b, interestCap)) * dailyRate).rounded(.down))
        }
        return b
    }
}

// MARK: - Net worth

/// Cash plus what everything you own would sell for. A second leaderboard, because rich and
/// high-earning aren't the same thing.
public enum NetWorth {
    public struct Breakdown: Sendable, Equatable {
        public var cash: Int
        public var savings: Int
        public var vehicles: Int
        public var businesses: Int
        public var weapons: Int
        public var total: Int { cash + savings + vehicles + businesses + weapons }
    }

    public static func breakdown(_ p: PlayerProgress) -> Breakdown {
        let vehicles = p.garage.reduce(0) { $0 + GarageRules.resaleValue($1.model) }
        let businesses = p.properties.reduce(0) { $0 + Properties.resaleValue($1) }
        let weapons = WeaponID.allCases.filter { p.inventory.owns($0) && !p.inventory.isCapped($0) }
            .reduce(0) { $0 + Int(Double($1.spec.price) * 0.3) }
        return Breakdown(cash: p.credits, savings: p.bank.balance, vehicles: vehicles,
                         businesses: businesses, weapons: weapons)
    }

    public static func total(_ p: PlayerProgress) -> Int { breakdown(p).total }

    public struct Entry: Sendable, Equatable {
        public let name: String
        public let worth: Int
        public let isPlayer: Bool
    }

    static let rivalWorths: [(String, Int)] = [
        ("Vex Monroe", 480_000), ("Lula Kade", 260_000), ("Mina Sol", 150_000), ("Dax Ferro", 95_000),
        ("Rook Halvorsen", 60_000), ("Juno Pike", 38_000), ("Saffron Lee", 24_000), ("Tito Arcade", 15_000),
        ("Bram Okafor", 9_000), ("Kit Vane", 5_500), ("Neve Castillo", 3_200), ("Ozzie Pell", 1_800),
        ("Moss Ferraro", 900), ("Poppy Duarte", 400)
    ]

    public static func board(_ p: PlayerProgress) -> [Entry] {
        let me = Entry(name: p.profile?.name ?? "You", worth: total(p), isPlayer: true)
        let others = rivalWorths.map { Entry(name: $0.0, worth: $0.1, isPlayer: false) }
        return (others + [me]).sorted { $0.worth != $1.worth ? $0.worth > $1.worth : $0.isPlayer }
    }

    public static func rank(_ p: PlayerProgress) -> Int {
        (board(p).firstIndex { $0.isPlayer } ?? 0) + 1
    }
}
