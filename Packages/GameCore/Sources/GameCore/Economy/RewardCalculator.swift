import Foundation

/// Everything about a finished run that pay and records depend on.
public struct MissionResult: Sendable, Equatable {
    public var missionID: MissionID
    public var kind: MissionKind
    public var outcome: MissionOutcome
    public var elapsed: Double
    public var timeLimit: Double?
    public var hits: Int
    public var driftScore: Double
    /// Seconds on the job clock; differs from `elapsed` when only part of the job was timed.
    public var clockElapsed: Double

    public init(missionID: MissionID, kind: MissionKind, outcome: MissionOutcome, elapsed: Double,
                timeLimit: Double?, hits: Int, driftScore: Double, clockElapsed: Double? = nil) {
        self.missionID = missionID
        self.kind = kind
        self.outcome = outcome
        self.elapsed = elapsed
        self.timeLimit = timeLimit
        self.hits = hits
        self.driftScore = driftScore
        self.clockElapsed = clockElapsed ?? elapsed
    }

    public var isClean: Bool { hits == 0 }
}

/// What a run pays out, itemised so the results screen can show each line.
public struct Payout: Sendable, Equatable {
    public var base: Int = 0
    public var timeBonus: Int = 0
    public var driftBonus: Int = 0
    public var damagePenalty: Int = 0
    public var credits: Int = 0
    public var repXP: Int = 0
    public var score: Int = 0

    public init() {}
}

public enum RewardCalculator {
    /// Time bonus tops out at this share of base pay, reached at half the time limit or faster.
    public static let maxTimeBonusShare = 0.5
    /// Drift bonus: 1 credit per this many drift points, capped at 25% of base.
    public static let driftPointsPerCredit = 10.0
    public static let maxDriftBonusShare = 0.25
    /// Each hit costs this share of base; pay never drops under `payFloorShare` of base.
    public static let penaltyPerHitShare = 0.05
    public static let payFloorShare = 0.5
    public static let cleanRunXP = 10

    public static func payout(for r: MissionResult, def: MissionDef) -> Payout {
        var p = Payout()
        guard r.outcome.isSuccess else { return p }
        let base = Double(def.baseReward)
        p.base = def.baseReward

        if let limit = r.timeLimit, limit > 0 {
            let speed = min(max((limit - r.clockElapsed) / (limit / 2), 0), 1)
            p.timeBonus = Int((base * maxTimeBonusShare * speed).rounded())
        }
        p.driftBonus = Int(min(r.driftScore / driftPointsPerCredit, base * maxDriftBonusShare).rounded(.down))

        let beforePenalty = p.base + p.timeBonus + p.driftBonus
        let penalty = Int((base * penaltyPerHitShare * Double(r.hits)).rounded())
        let floor = Int((base * payFloorShare).rounded())
        p.credits = max(floor, beforePenalty - penalty)
        p.damagePenalty = beforePenalty - p.credits

        p.repXP = def.baseRepXP + (r.isClean ? cleanRunXP : 0)
        p.score = score(for: r)
        return p
    }

    /// Score for records: rewards speed, style and a clean car. Failed runs score 0.
    public static func score(for r: MissionResult) -> Int {
        guard r.outcome.isSuccess else { return 0 }
        let timeLeft = r.timeLimit.map { max(0, $0 - r.clockElapsed) } ?? 0
        let raw = 1000 + timeLeft * 20 + r.driftScore + (r.isClean ? 250 : 0) - Double(r.hits * 50)
        return max(0, Int(raw.rounded()))
    }
}
