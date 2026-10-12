import XCTest
@testable import GameCore

final class RewardCalculatorTests: XCTestCase {
    let def = MissionDef.coldCrate  // base 200 credits, 60 XP, 35 s

    func result(_ outcome: MissionOutcome = .success, elapsed: Double = 30, hits: Int = 0,
                drift: Double = 0) -> MissionResult {
        MissionResult(missionID: def.id, kind: def.kind, outcome: outcome, elapsed: elapsed,
                      timeLimit: def.timeLimit, hits: hits, driftScore: drift)
    }

    func testFailedRunsPayNothing() {
        for outcome in [MissionOutcome.timeUp, .busted, .wrecked, .quit] {
            XCTAssertEqual(RewardCalculator.payout(for: result(outcome), def: def), Payout())
        }
    }

    func testFinishingAtTheLimitPaysBaseOnly() {
        let p = RewardCalculator.payout(for: result(elapsed: 35), def: def)
        XCTAssertEqual(p.timeBonus, 0)
        XCTAssertEqual(p.credits, 200)
    }

    func testTimeBonusIsFullAtHalfTimeOrFaster() {
        XCTAssertEqual(RewardCalculator.payout(for: result(elapsed: 17.5), def: def).timeBonus, 100)
        XCTAssertEqual(RewardCalculator.payout(for: result(elapsed: 5), def: def).timeBonus, 100)
        XCTAssertEqual(RewardCalculator.payout(for: result(elapsed: 26.25), def: def).timeBonus, 50)
    }

    func testDriftBonusIsCapped() {
        XCTAssertEqual(RewardCalculator.payout(for: result(elapsed: 35, drift: 120), def: def).driftBonus, 12)
        XCTAssertEqual(RewardCalculator.payout(for: result(elapsed: 35, drift: 99_999), def: def).driftBonus, 50)
    }

    func testHitsCostButNeverBelowHalfBase() {
        let threeHits = RewardCalculator.payout(for: result(elapsed: 35, hits: 3), def: def)
        XCTAssertEqual(threeHits.credits, 170)
        XCTAssertEqual(threeHits.damagePenalty, 30)
        let wrecked = RewardCalculator.payout(for: result(elapsed: 35, hits: 50), def: def)
        XCTAssertEqual(wrecked.credits, 100)
        XCTAssertEqual(wrecked.damagePenalty, 100)
    }

    func testCleanRunEarnsExtraXP() {
        XCTAssertEqual(RewardCalculator.payout(for: result(hits: 0), def: def).repXP, 70)
        XCTAssertEqual(RewardCalculator.payout(for: result(hits: 1), def: def).repXP, 60)
    }

    func testScoreRewardsSpeedStyleAndCleanDriving() {
        // 1000 + 5 s left × 20 + 40 drift + 250 clean = 1390
        XCTAssertEqual(RewardCalculator.score(for: result(elapsed: 30, drift: 40)), 1390)
        // Two hits: no clean bonus, −100.
        XCTAssertEqual(RewardCalculator.score(for: result(elapsed: 30, hits: 2, drift: 40)), 1040)
        XCTAssertEqual(RewardCalculator.score(for: result(.timeUp)), 0)
    }

    func testLineItemsAddUp() {
        let p = RewardCalculator.payout(for: result(elapsed: 20, hits: 1, drift: 300), def: def)
        XCTAssertEqual(p.base + p.timeBonus + p.driftBonus - p.damagePenalty, p.credits)
    }
}
