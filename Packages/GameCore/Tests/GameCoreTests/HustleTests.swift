import XCTest
@testable import GameCore

/// The weekly money league, dailies, the bank, businesses, skills and trophies.
final class HustleTests: XCTestCase {
    let utc = TimeZone(secondsFromGMT: 0)!

    /// Monday 12 Oct 2026, 09:00 UTC, plus `days`.
    func date(_ days: Double = 0, hour: Double = 9) -> Date {
        Date(timeIntervalSince1970: 1_791_763_200 + days * 86_400 + hour * 3_600)
    }

    func player(xp: Int = 0, credits: Int = 0) -> PlayerProgress {
        var p = PlayerProgress()
        p.reputationXP = xp
        p.credits = credits
        return p
    }

    // MARK: Clock

    func testWeeksStartOnMonday() {
        XCTAssertEqual(GameClock.weekFraction(date(0, hour: 0), timeZone: utc), 0, accuracy: 0.0001)
        let monday = GameClock.week(date(0), timeZone: utc)
        XCTAssertEqual(GameClock.week(date(6, hour: 23), timeZone: utc), monday, "Sunday night, same week")
        XCTAssertEqual(GameClock.week(date(7, hour: 0), timeZone: utc), monday + 1, "next Monday")
        XCTAssertEqual(GameClock.day(date(1), timeZone: utc), GameClock.day(date(0), timeZone: utc) + 1)
        // Late Sunday evening in California is already Monday in UTC.
        let la = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(GameClock.week(date(0, hour: 3), timeZone: la), monday - 1)
    }

    // MARK: League

    func testEarningsCountTowardTheWeekAndPassRivals() {
        var p = player()
        League.refresh(&p, now: date(), timeZone: utc)
        let startRank = League.rank(p, now: date(3), timeZone: utc)
        XCTAssertEqual(startRank, League.size, "no earnings yet: last")
        p.earn(5_000, .jobPay, "Big job", on: date(3), timeZone: utc)
        XCTAssertEqual(p.league.earnings, 5_000)
        XCTAssertLessThan(League.rank(p, now: date(3), timeZone: utc), startRank)
        // Selling a car isn't earned income.
        p.earn(800, .vehicleSale, "Sold a car", on: date(3), timeZone: utc)
        XCTAssertEqual(p.league.earnings, 5_000)
        XCTAssertEqual(p.credits, 5_800)
    }

    func testRivalsEarnThroughTheWeekAndTheBoardIsStable() {
        let p = player()
        let monday = League.board(p, now: date(0, hour: 1), timeZone: utc)
        let sunday = League.board(p, now: date(6, hour: 22), timeZone: utc)
        let total = { (b: [League.Entry]) in b.reduce(0) { $0 + $1.earnings } }
        XCTAssertGreaterThan(total(sunday), total(monday) * 3)
        XCTAssertEqual(League.board(p, now: date(4), timeZone: utc), League.board(p, now: date(4), timeZone: utc))
        XCTAssertEqual(Set(sunday.map(\.name)).count, League.size, "no duplicate names")
        XCTAssertGreaterThan(League.gapToNext(p, now: date(4), timeZone: utc), 0)
    }

    func testWinningTheWeekPaysAPrizeAndPromotes() {
        var p = player()
        League.refresh(&p, now: date(), timeZone: utc)
        p.earn(Division.bronze.rivalRange.upperBound + 1, .jobPay, "Huge week", on: date(2), timeZone: utc)
        let credits = p.credits
        // Nothing settles mid-week.
        XCTAssertNil(League.refresh(&p, now: date(5), timeZone: utc))
        let result = League.refresh(&p, now: date(7.5), timeZone: utc)
        XCTAssertEqual(result?.rank, 1)
        XCTAssertEqual(result?.prize, League.prize(rank: 1, division: .bronze))
        XCTAssertEqual(result?.movement, 1)
        XCTAssertEqual(p.credits, credits + Division.bronze.prizeBase * 4)
        XCTAssertEqual(p.league.division, .silver)
        XCTAssertEqual(p.league.wins, 1)
        XCTAssertEqual(p.league.earnings, 0, "new week, fresh start")
        XCTAssertEqual(p.league.unseen, result)
        XCTAssertEqual(p.books.total(.prizes), League.prize(rank: 1, division: .bronze))
        XCTAssertEqual(p.league.earnings, 0, "the prize doesn't count toward the new week")
        XCTAssertNil(League.refresh(&p, now: date(8), timeZone: utc), "settled once")
    }

    func testAQuietWeekRelegatesButASkippedWeekDoesNot() {
        var p = player()
        p.league.division = .gold
        League.refresh(&p, now: date(), timeZone: utc)
        // Sat it out: no change.
        XCTAssertNil(League.refresh(&p, now: date(7.5), timeZone: utc))
        XCTAssertEqual(p.league.division, .gold)
        // Earned a little, finished near the bottom: down a division, no prize.
        p.earn(50, .jobPay, "Small job", on: date(8), timeZone: utc)
        let result = League.refresh(&p, now: date(14.5), timeZone: utc)
        XCTAssertEqual(result?.movement, -1)
        XCTAssertEqual(result?.prize, 0)
        XCTAssertEqual(p.league.division, .silver)
        XCTAssertEqual(p.league.bestDivision, .gold)
    }

    func testPrizeTable() {
        XCTAssertEqual(League.prize(rank: 1, division: .neon), 10_000)
        XCTAssertGreaterThan(League.prize(rank: 2, division: .bronze), League.prize(rank: 3, division: .bronze))
        XCTAssertEqual(League.prize(rank: 11, division: .neon), 0)
        XCTAssertEqual(League.zone(forRank: 1, division: .neon), 0, "nowhere higher than Neon")
        XCTAssertEqual(League.zone(forRank: 15, division: .bronze), 0, "nowhere lower than Bronze")
    }

    // MARK: Daily

    func testStreakGrowsDailyAndResetsAfterAMissedDay() {
        var p = player()
        let def = MissionDef.all[0]
        var update = Daily.recordJob(def, success: true, progress: &p, now: date(0), timeZone: utc)
        XCTAssertEqual(update.streakBonus, Daily.streakBonuses[0])
        update = Daily.recordJob(def, success: true, progress: &p, now: date(0, hour: 15), timeZone: utc)
        XCTAssertNil(update.streakBonus, "once a day")
        update = Daily.recordJob(def, success: true, progress: &p, now: date(1), timeZone: utc)
        XCTAssertEqual(update.streak, 2)
        XCTAssertEqual(update.streakBonus, Daily.streakBonuses[1])
        XCTAssertNil(Daily.recordJob(def, success: false, progress: &p, now: date(2), timeZone: utc).streakBonus)
        // Missed day 2, back on day 3: starts over.
        XCTAssertEqual(Daily.liveStreak(p, today: GameClock.day(date(3), timeZone: utc)), 0)
        update = Daily.recordJob(def, success: true, progress: &p, now: date(3), timeZone: utc)
        XCTAssertEqual(update.streak, 1)
        XCTAssertEqual(p.daily.best, 2)
        XCTAssertGreaterThanOrEqual(p.books.total(.bonuses), Daily.streakBonuses[0] * 2 + Daily.streakBonuses[1])
    }

    func testASevenDayStreakEarnsAShieldThatCoversAMiss() {
        var p = player()
        let def = MissionDef.all[0]
        for d in 0..<7 { Daily.recordJob(def, success: true, progress: &p, now: date(Double(d)), timeZone: utc) }
        XCTAssertEqual(p.daily.streak, 7)
        XCTAssertEqual(p.daily.shields, 1)
        let update = Daily.recordJob(def, success: true, progress: &p, now: date(8), timeZone: utc)
        XCTAssertTrue(update.usedShield)
        XCTAssertEqual(update.streak, 8)
        XCTAssertEqual(update.streakBonus, Daily.streakBonuses.last)
        XCTAssertEqual(p.daily.shields, 0)
    }

    func testJobOfTheDayPaysDoubleOnce() {
        var p = player()
        let today = GameClock.day(date(), timeZone: utc)
        guard let featured = Daily.featured(day: today, progress: p) else { return XCTFail("a featured job") }
        XCTAssertTrue(ProgressionRules.isUnlocked(featured, progress: p))
        let first = Daily.recordJob(featured, success: true, progress: &p, now: date(), timeZone: utc)
        XCTAssertEqual(first.featuredBonus, featured.baseReward)
        let again = Daily.recordJob(featured, success: true, progress: &p, now: date(0, hour: 12), timeZone: utc)
        XCTAssertNil(again.featuredBonus)
        // Different days feature different jobs at least sometimes.
        let picks = Set((0..<14).compactMap { Daily.featured(day: today + $0, progress: player(xp: 5_000))?.id })
        XCTAssertGreaterThan(picks.count, 2)
    }

    // MARK: Bank

    func testSavingsEarnCompoundInterest() {
        var p = player(credits: 10_000)
        XCTAssertNil(Bank.deposit(10_000, progress: &p, now: date(), timeZone: utc))
        XCTAssertEqual(p.credits, 0)
        XCTAssertEqual(p.books.entryCount, 0, "moving your own money isn't income or spending")
        XCTAssertEqual(Bank.accrue(&p, now: date(0, hour: 20), timeZone: utc), 0, "same day")
        let paid = Bank.accrue(&p, now: date(2), timeZone: utc)
        XCTAssertEqual(paid, 100 + 101, "1% a day, on yesterday's interest too")
        XCTAssertEqual(p.bank.balance, 10_201)
        XCTAssertEqual(p.books.total(.interest), 201)
        XCTAssertEqual(Bank.projected(10_000, days: 2), 10_201)
        XCTAssertEqual(Bank.withdraw(20_000, progress: &p, now: date(2), timeZone: utc), .notEnoughSaved(needed: 9_799))
        XCTAssertNil(Bank.withdraw(201, progress: &p, now: date(2), timeZone: utc))
        XCTAssertEqual(p.credits, 201)
    }

    func testInterestIsCappedAndCatchUpIsLimited() {
        var p = player(credits: 100_000)
        Bank.deposit(100_000, progress: &p, now: date(), timeZone: utc)
        XCTAssertEqual(Bank.accrue(&p, now: date(1), timeZone: utc), Bank.interestCap / 100)
        var q = player(credits: 1_000)
        Bank.deposit(1_000, progress: &q, now: date(), timeZone: utc)
        let paid = Bank.accrue(&q, now: date(365), timeZone: utc)
        XCTAssertEqual(q.bank.balance, Bank.projected(1_000, days: Bank.maxCatchUpDays))
        XCTAssertEqual(paid, q.bank.balance - 1_000)
    }

    // MARK: Businesses

    func testBuyingABusinessIsAnInvestmentNotAnExpense() {
        var p = player(credits: 2_000)
        XCTAssertNil(Properties.buy(.tacoTruck, progress: &p, now: date()))
        XCTAssertEqual(p.credits, 500)
        XCTAssertEqual(p.books.invested, 1_500)
        XCTAssertEqual(p.books.expenses, 0)
        XCTAssertEqual(Properties.buy(.tacoTruck, progress: &p, now: date()), .alreadyOwned)
        XCTAssertEqual(Properties.buy(.arcade, progress: &p, now: date()), .locked(level: 4))
        var rich = player(credits: 1_000)
        XCTAssertEqual(Properties.buy(.tacoTruck, progress: &rich, now: date()), .notEnoughCredits(needed: 500))
    }

    func testTheTillFillsHourlyUpToItsCap() {
        var p = player(credits: 2_000)
        Properties.buy(.tacoTruck, progress: &p, now: date())
        let owned = Properties.owned(.tacoTruck, in: p)!
        let twoHours = Properties.till(owned, now: date(0, hour: 11))
        XCTAssertEqual(twoHours.revenue, 240)
        XCTAssertEqual(twoHours.costs, 108)
        XCTAssertFalse(twoHours.isFull)
        let later = Properties.till(owned, now: date(3))
        XCTAssertTrue(later.isFull)
        XCTAssertEqual(later.revenue, 120 * 8, "the till holds 8 hours")

        League.refresh(&p, now: date(), timeZone: utc)
        let till = Properties.collect(.tacoTruck, progress: &p, now: date(0, hour: 11), timeZone: utc)
        XCTAssertEqual(till?.profit, 132)
        XCTAssertEqual(p.credits, 500 + 132)
        XCTAssertEqual(p.books.total(.businessRevenue), 240)
        XCTAssertEqual(p.books.total(.businessCosts), -108)
        XCTAssertEqual(p.league.earnings, 132, "profit counts in the league")
        XCTAssertNil(Properties.collect(.tacoTruck, progress: &p, now: date(0, hour: 11), timeZone: utc), "empty till")
        XCTAssertGreaterThan(p.skills.xp(.hustle), 0)
    }

    func testUpgradesRaiseTakingsAndPaybackIsHonest() {
        var p = player(xp: 5_000, credits: 50_000)
        Properties.buy(.carWash, progress: &p, now: date())
        XCTAssertNil(Properties.upgrade(.carWash, progress: &p, now: date()))
        XCTAssertNil(Properties.upgrade(.carWash, progress: &p, now: date()))
        XCTAssertEqual(Properties.upgrade(.carWash, progress: &p, now: date()), .maxLevel)
        let owned = Properties.owned(.carWash, in: p)!
        XCTAssertEqual(owned.level, 3)
        XCTAssertEqual(owned.invested, 4_000 + 2_400 + 4_000)
        let hour = Properties.till(owned, now: date(0, hour: 10))
        XCTAssertEqual(hour.revenue, Int(260 * 2.4))
        XCTAssertEqual(Properties.paybackHours(.tacoTruck), 1_500 / 66.0, accuracy: 0.01)
        let value = Properties.sell(.carWash, progress: &p, now: date(0, hour: 10))
        XCTAssertEqual(value, Int((Double(owned.invested) * Properties.resaleShare).rounded()))
        XCTAssertTrue(p.properties.isEmpty)
    }

    // MARK: Skills

    func testSkillsLevelUpFromWhatYouDo() {
        var p = player()
        var stats = RunStats()
        stats.driven = Skills.drivePointsPerXP * 600
        stats.run = Skills.runPointsPerXP * 20
        stats.hitsLanded = 3
        let gains = Skills.award(stats, to: &p)
        XCTAssertEqual(gains[.driving], 600)
        XCTAssertEqual(p.skills.level(.driving), 2)
        XCTAssertEqual(p.skills.level(.stamina), 0)
        XCTAssertEqual(p.skills.xp(.shooting), 3 * Skills.xpPerHit)
        XCTAssertEqual(Skills.xpToNext(600), 1_200 - 600)
        XCTAssertNil(Skills.xpToNext(99_999))
        XCTAssertEqual(p.skills.levels.driving, 2)
        XCTAssertEqual(p.career.hitsLanded, 3)
    }

    // MARK: Net worth and trophies

    func testNetWorthCountsAssetsAtWhatTheydSellFor() {
        var p = player(credits: 3_000)
        p.garage.append(OwnedVehicle(model: .dorado))
        Properties.buy(.tacoTruck, progress: &p, now: date())
        Bank.deposit(500, progress: &p, now: date(), timeZone: utc)
        let worth = NetWorth.breakdown(p)
        XCTAssertEqual(worth.cash, 1_000)
        XCTAssertEqual(worth.savings, 500)
        XCTAssertEqual(worth.businesses, 900)
        XCTAssertEqual(worth.vehicles, GarageRules.resaleValue(.vesper) + GarageRules.resaleValue(.dorado))
        XCTAssertEqual(NetWorth.total(p), worth.total)
        XCTAssertLessThan(NetWorth.rank(player(credits: 1_000_000)), 2)
    }

    func testTrophiesTrackProgressAndPayOnce() {
        var p = player()
        XCTAssertEqual(Set(Achievements.all.map(\.id)).count, Achievements.all.count, "unique ids")
        XCTAssertEqual(Achievements.claim("firstJob", progress: &p), .notDone)
        p.completedJobs = 1
        XCTAssertTrue(Achievements.claimable(p).contains { $0.id == "firstJob" })
        XCTAssertNil(Achievements.claim("firstJob", progress: &p))
        XCTAssertEqual(p.credits, 100)
        XCTAssertEqual(Achievements.claim("firstJob", progress: &p), .alreadyClaimed)
        XCTAssertEqual(Achievements.claim("nope", progress: &p), .unknown)
        XCTAssertGreaterThan(Achievements.completion(p), 0)
        let jobs = Achievements.all.first { $0.id == "jobs25" }!
        XCTAssertEqual(jobs.progress(p), 1)
    }

    // MARK: Saves

    func testOldSavesLoadWithTheNewFieldsEmpty() throws {
        var old = player(credits: 1_234)
        old.books.record(500, .jobPay, "Job")
        var json = try JSONSerialization.jsonObject(with: SaveCodec.encode(old)!) as! [String: Any]
        for key in ["league", "daily", "bank", "properties", "skills", "career", "claimedAchievements"] {
            json.removeValue(forKey: key)
        }
        json["schemaVersion"] = 2
        let loaded = SaveCodec.loadProgress(from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(loaded.credits, 1_234)
        XCTAssertEqual(loaded.books.total(.jobPay), 500)
        XCTAssertEqual(loaded.league, LeagueState())
        XCTAssertTrue(loaded.properties.isEmpty)
        XCTAssertEqual(loaded.schemaVersion, PlayerProgress.currentSchema)

        var full = player(xp: 5_000, credits: 30_000)
        Properties.buy(.laundromat, progress: &full, now: date())
        Bank.deposit(1_000, progress: &full, now: date(), timeZone: utc)
        full.earn(300, .jobPay, "Job", on: date(), timeZone: utc)
        full.skills.add(.driving, xp: 700)
        full.claimedAchievements = ["firstJob"]
        let round = SaveCodec.loadProgress(from: SaveCodec.encode(full))
        XCTAssertEqual(round, full)
    }

    func testSettingsFromOlderBuildsKeepTheirValues() throws {
        let old = #"{"soundOn":false,"hapticsOn":true,"crtOn":true}"#.data(using: .utf8)!
        let settings = SaveCodec.loadSettings(from: old)
        XCTAssertFalse(settings.soundOn)
        XCTAssertTrue(settings.crtOn)
        XCTAssertEqual(settings.aimAssist, .standard)
        XCTAssertEqual(settings.frameRate, 60)
    }
}
