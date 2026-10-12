import Foundation

public enum ProgressionRules {
    /// XP needed to reach rep level 0, 1, 2, ...
    public static let levelThresholds = [0, 100, 300, 600, 1000, 1500]

    public static func level(forXP xp: Int) -> Int {
        (levelThresholds.lastIndex { xp >= $0 }) ?? 0
    }

    /// XP still needed for the next level, or nil at the top level.
    public static func xpToNextLevel(_ xp: Int) -> Int? {
        let next = level(forXP: xp) + 1
        guard next < levelThresholds.count else { return nil }
        return levelThresholds[next] - xp
    }

    public static func isUnlocked(_ def: MissionDef, progress: PlayerProgress) -> Bool {
        level(forXP: progress.reputationXP) >= def.requiredRepLevel
    }

    /// Jobs that a run's level-up just opened, for the results screen.
    public static func jobsUnlocked(atLevel level: Int) -> [MissionDef] {
        MissionDef.all.filter { $0.requiredRepLevel == level }
    }

    /// What applying a run changed, for the results screen.
    public struct Update: Sendable, Equatable {
        public var payout: Payout
        public var newBestScore: Bool
        public var newBestTime: Bool
        public var leveledUpTo: Int?
        /// Jobs this run's level-up opened on the map, in map order.
        public var unlockedJobs: [MissionID] = []
    }

    /// Folds a finished run into saved progress.
    public static func apply(_ result: MissionResult, def: MissionDef,
                             to progress: inout PlayerProgress, now: Date = Date()) -> Update {
        let payout = RewardCalculator.payout(for: result, def: def)
        let levelBefore = level(forXP: progress.reputationXP)

        progress.reputationXP += payout.repXP
        progress.earn(payout.credits, .jobPay, def.title, on: now)

        var newBestScore = false
        var newBestTime = false
        if result.outcome.isSuccess {
            progress.completedJobs += 1
            let key = result.missionID.rawValue
            var best = progress.missionBests[key] ?? MissionBest(bestScore: 0, bestTime: nil, timesCompleted: 0)
            if payout.score > best.bestScore {
                best.bestScore = payout.score
                newBestScore = true
            }
            if best.bestTime.map({ result.elapsed < $0 }) ?? true {
                best.bestTime = result.elapsed
                newBestTime = true
            }
            best.timesCompleted += 1
            progress.missionBests[key] = best
        }

        if result.kind.endsInEscape {
            if result.outcome.isSuccess {
                progress.currentEscapeStreak += 1
                progress.bestEscapeStreak = max(progress.bestEscapeStreak, progress.currentEscapeStreak)
            } else if result.outcome != .quit {
                progress.currentEscapeStreak = 0
            }
        }
        if result.outcome == .busted {
            progress.currentEscapeStreak = 0
        }

        progress.lastUpdated = now
        let levelAfter = level(forXP: progress.reputationXP)
        let unlocked = MissionDef.all
            .filter { $0.requiredRepLevel > levelBefore && $0.requiredRepLevel <= levelAfter }
            .map(\.id)
        return Update(payout: payout, newBestScore: newBestScore, newBestTime: newBestTime,
                      leveledUpTo: levelAfter > levelBefore ? levelAfter : nil, unlockedJobs: unlocked)
    }
}
