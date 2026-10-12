import Foundation

/// Trophies with a progress bar and a credit reward to claim. Worked out from the save, so they
/// can't drift out of step with what the player has actually done.
public struct Achievement: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let goal: Int
    public let reward: Int
    let measure: @Sendable (PlayerProgress) -> Int

    public func progress(_ p: PlayerProgress) -> Int { min(goal, max(0, measure(p))) }
    public func isDone(_ p: PlayerProgress) -> Bool { measure(p) >= goal }
}

public enum Achievements {
    public enum Refusal: Error, Equatable {
        case unknown, notDone, alreadyClaimed
    }

    public static let all: [Achievement] = [
        Achievement(id: "firstJob", title: "Open for business", detail: "Finish your first job.",
                    goal: 1, reward: 100) { $0.completedJobs },
        Achievement(id: "jobs25", title: "Regular", detail: "Finish 25 jobs.",
                    goal: 25, reward: 500) { $0.completedJobs },
        Achievement(id: "jobs100", title: "Port Aurora's finest", detail: "Finish 100 jobs.",
                    goal: 100, reward: 2_000) { $0.completedJobs },
        Achievement(id: "everyJob", title: "Seen it all", detail: "Finish every job on the map.",
                    goal: MissionDef.all.count, reward: 1_500) { p in
            MissionDef.all.filter { p.missionBests[$0.id.rawValue] != nil }.count
        },
        Achievement(id: "streak3", title: "Showing up", detail: "Reach a 3-day streak.",
                    goal: 3, reward: 200) { $0.daily.best },
        Achievement(id: "streak7", title: "Full week", detail: "Reach a 7-day streak.",
                    goal: 7, reward: 750) { $0.daily.best },
        Achievement(id: "firstBusiness", title: "Owner", detail: "Buy your first business.",
                    goal: 1, reward: 300) { $0.properties.count },
        Achievement(id: "tycoon", title: "Tycoon", detail: "Own every business in Port Aurora.",
                    goal: PropertyID.allCases.count, reward: 5_000) { $0.properties.count },
        Achievement(id: "maxedOut", title: "Fully loaded", detail: "Upgrade a business to level 3.",
                    goal: Properties.maxLevel, reward: 800) { $0.properties.map(\.level).max() ?? 0 },
        Achievement(id: "passive", title: "Money while you sleep", detail: "Earn 10,000 profit from businesses.",
                    goal: 10_000, reward: 1_000) { $0.properties.reduce(0) { $0 + $1.lifetimeProfit } },
        Achievement(id: "saver", title: "Rainy-day fund", detail: "Save 5,000 in the bank.",
                    goal: 5_000, reward: 400) { $0.bank.balance },
        Achievement(id: "compound", title: "Compound interest", detail: "Earn 1,000 in savings interest.",
                    goal: 1_000, reward: 500) { $0.bank.interestEarned },
        Achievement(id: "worth50k", title: "Net worth 50K", detail: "Reach a net worth of 50,000.",
                    goal: 50_000, reward: 1_000) { NetWorth.total($0) },
        Achievement(id: "worth250k", title: "Net worth 250K", detail: "Reach a net worth of 250,000.",
                    goal: 250_000, reward: 5_000) { NetWorth.total($0) },
        Achievement(id: "leagueWin", title: "Top of the table", detail: "Win a weekly league.",
                    goal: 1, reward: 1_000) { $0.league.wins },
        Achievement(id: "goldLeague", title: "Gold", detail: "Get promoted to the Gold league.",
                    goal: Division.gold.rawValue, reward: 600) { $0.league.bestDivision.rawValue },
        Achievement(id: "neonLeague", title: "Neon", detail: "Get promoted to the Neon league.",
                    goal: Division.neon.rawValue, reward: 2_500) { $0.league.bestDivision.rawValue },
        Achievement(id: "legendary", title: "Legendary", detail: "Reach the top five of the all-time rankings.",
                    goal: 1, reward: 1_500) { Ranking.isLegendary($0) ? 1 : 0 },
        Achievement(id: "designer", title: "Designer", detail: "Draw and save a paint design.",
                    goal: 1, reward: 150) { p in p.designs.filter { BodyShop.isMine($0.id) }.count },
        Achievement(id: "creator", title: "Creator economy", detail: "Sell a design to another driver.",
                    goal: 1, reward: 400) { $0.listings.reduce(0) { $0 + $1.sold } },
        Achievement(id: "gunsmith", title: "Gunsmith", detail: "Fit a part at the Workbench.",
                    goal: 1, reward: 150) { p in
            WeaponID.allCases.contains { !p.inventory.build(for: $0).owned.isEmpty } ? 1 : 0
        },
        Achievement(id: "collector", title: "Collector", detail: "Keep four vehicles in your garage.",
                    goal: 4, reward: 500) { $0.garage.count },
        Achievement(id: "skilled", title: "Specialist", detail: "Take any skill to level 5.",
                    goal: Skills.maxLevel, reward: 1_000) { p in Skill.allCases.map { p.skills.level($0) }.max() ?? 0 },
        Achievement(id: "marathon", title: "Marathon", detail: "Run 40,000 m on foot.",
                    goal: 40_000, reward: 300) { Int($0.career.run / 12.8) },
        Achievement(id: "photographer", title: "Say cheese", detail: "Take a photo in photo mode.",
                    goal: 1, reward: 100) { $0.career.photos }
    ]

    public static func isClaimed(_ id: String, _ p: PlayerProgress) -> Bool { p.claimedAchievements.contains(id) }

    /// Done but not yet claimed.
    public static func claimable(_ p: PlayerProgress) -> [Achievement] {
        all.filter { $0.isDone(p) && !isClaimed($0.id, p) }
    }

    /// Share of trophies done, 0...1.
    public static func completion(_ p: PlayerProgress) -> Double {
        Double(all.filter { $0.isDone(p) }.count) / Double(all.count)
    }

    @discardableResult
    public static func claim(_ id: String, progress p: inout PlayerProgress, now: Date = Date()) -> Refusal? {
        guard let a = all.first(where: { $0.id == id }) else { return .unknown }
        guard !isClaimed(id, p) else { return .alreadyClaimed }
        guard a.isDone(p) else { return .notDone }
        p.claimedAchievements.append(id)
        p.credits += a.reward
        p.books.record(a.reward, .prizes, "Trophy: \(a.title)", on: now)
        return nil
    }
}
