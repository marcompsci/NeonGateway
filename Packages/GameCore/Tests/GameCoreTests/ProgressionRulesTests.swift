import XCTest
@testable import GameCore

final class ProgressionRulesTests: XCTestCase {
    let def = MissionDef.coldCrate

    func result(_ outcome: MissionOutcome = .success, elapsed: Double = 30, hits: Int = 0,
                kind: MissionKind = .timedDelivery) -> MissionResult {
        MissionResult(missionID: def.id, kind: kind, outcome: outcome, elapsed: elapsed,
                      timeLimit: def.timeLimit, hits: hits, driftScore: 0)
    }

    func testLevelThresholds() {
        XCTAssertEqual(ProgressionRules.level(forXP: 0), 0)
        XCTAssertEqual(ProgressionRules.level(forXP: 99), 0)
        XCTAssertEqual(ProgressionRules.level(forXP: 100), 1)
        XCTAssertEqual(ProgressionRules.level(forXP: 1499), 4)
        XCTAssertEqual(ProgressionRules.level(forXP: 50_000), 5)
        XCTAssertEqual(ProgressionRules.xpToNextLevel(70), 30)
        XCTAssertNil(ProgressionRules.xpToNextLevel(1500))
    }

    func testSuccessAddsCreditsXPJobsAndBests() {
        var p = PlayerProgress()
        let update = ProgressionRules.apply(result(elapsed: 30), def: def, to: &p)
        XCTAssertEqual(p.credits, update.payout.credits)
        XCTAssertEqual(p.reputationXP, 70)
        XCTAssertEqual(p.completedJobs, 1)
        XCTAssertEqual(p.missionBests["coldCrate"]?.bestTime, 30)
        XCTAssertEqual(p.missionBests["coldCrate"]?.timesCompleted, 1)
        XCTAssertTrue(update.newBestScore)
        XCTAssertTrue(update.newBestTime)
    }

    func testSlowerRepeatKeepsTheOldBest() {
        var p = PlayerProgress()
        _ = ProgressionRules.apply(result(elapsed: 20), def: def, to: &p)
        let second = ProgressionRules.apply(result(elapsed: 30), def: def, to: &p)
        XCTAssertFalse(second.newBestTime)
        XCTAssertFalse(second.newBestScore)
        XCTAssertEqual(p.missionBests["coldCrate"]?.bestTime, 20)
        XCTAssertEqual(p.missionBests["coldCrate"]?.timesCompleted, 2)
        XCTAssertEqual(p.completedJobs, 2)
    }

    func testFailureChangesNothingButTheTimestamp() {
        var p = PlayerProgress()
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        _ = ProgressionRules.apply(result(.timeUp), def: def, to: &p, now: now)
        var expected = PlayerProgress()
        expected.lastUpdated = now
        XCTAssertEqual(p, expected)
    }

    func testLevelUpIsReported() {
        var p = PlayerProgress()
        p.reputationXP = 50
        let update = ProgressionRules.apply(result(), def: def, to: &p)
        XCTAssertEqual(update.leveledUpTo, 1)
        let again = ProgressionRules.apply(result(hits: 1), def: def, to: &p)
        XCTAssertNil(again.leveledUpTo)
    }

    func testEscapeStreaks() {
        var p = PlayerProgress()
        _ = ProgressionRules.apply(result(kind: .escape), def: def, to: &p)
        _ = ProgressionRules.apply(result(kind: .escape), def: def, to: &p)
        XCTAssertEqual(p.currentEscapeStreak, 2)
        _ = ProgressionRules.apply(result(.quit, kind: .escape), def: def, to: &p)
        XCTAssertEqual(p.currentEscapeStreak, 2, "quitting doesn't break a streak")
        _ = ProgressionRules.apply(result(.busted, kind: .escape), def: def, to: &p)
        XCTAssertEqual(p.currentEscapeStreak, 0)
        XCTAssertEqual(p.bestEscapeStreak, 2)
    }

    func testMissionUnlocking() {
        let p = PlayerProgress()
        XCTAssertTrue(ProgressionRules.isUnlocked(def, progress: p))
    }
}
