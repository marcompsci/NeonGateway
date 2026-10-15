import XCTest
@testable import GameCore

final class StreetChallengeTests: XCTestCase {
    let district = District.portAuroraDocks

    func testWeeksStartOnMondayUTC() {
        let monday = StreetChallenge.epoch
        XCTAssertEqual(StreetChallenge.week(of: monday), 0)
        XCTAssertEqual(StreetChallenge.week(of: monday.addingTimeInterval(7 * 86_400 - 1)), 0)
        XCTAssertEqual(StreetChallenge.week(of: monday.addingTimeInterval(7 * 86_400)), 1)
        XCTAssertEqual(StreetChallenge.ends(week: 0), monday.addingTimeInterval(7 * 86_400))
        // 13 October 2026 is in week 40.
        let oct13 = Date(timeIntervalSince1970: 1_791_950_000)
        XCTAssertEqual(StreetChallenge.week(of: oct13), 40)
    }

    func testRouteIsFiveDifferentReachableCheckpointsAndStableForTheWeek() {
        for week in 0..<30 {
            let route = StreetChallenge.route(week: week)
            XCTAssertEqual(route.count, StreetChallenge.checkpointCount)
            XCTAssertEqual(Set(route).count, route.count, "week \(week) repeats a checkpoint")
            XCTAssertTrue(route.allSatisfy { StreetChallenge.pool.contains($0) })
            XCTAssertEqual(route, StreetChallenge.route(week: week), "same week, same route")
        }
        XCTAssertNotEqual(StreetChallenge.route(week: 1), StreetChallenge.route(week: 2), "routes change")
    }

    func testChallengeIsNotOnTheJobLadder() {
        XCTAssertFalse(MissionDef.all.contains { $0.id == .streetChallenge })
        XCTAssertFalse(MissionID.jobs.contains(.streetChallenge))
        XCTAssertEqual(MissionDef.with(.streetChallenge)?.objectives.count, StreetChallenge.checkpointCount)
    }

    /// Nova (the autopilot) must finish every week's route well inside the clock, so the ghost
    /// always reaches the end and gold is always possible.
    func testNovaFinishesEveryRouteWithTimeToSpare() {
        for week in 0..<26 {
            let def = StreetChallenge.def(week: week)
            let ghost = StreetChallenge.rival(for: def)
            XCTAssertGreaterThan(ghost.duration, 15, "week \(week) is too short")
            XCTAssertLessThan(ghost.duration, StreetChallenge.timeLimit * 0.7, "week \(week): Nova took \(ghost.duration)s")
            // The ghost ends at the last checkpoint.
            let last = district.zones[def.objectives.last!.zones[0]]!.rect
            let end = ghost.pose(at: ghost.duration + 5)!.position
            XCTAssertTrue(last.contains(end), "week \(week) ghost ends off the route")
        }
    }

    func testRivalIsDeterministic() {
        let def = StreetChallenge.def(week: 7)
        XCTAssertEqual(StreetChallenge.rival(for: def), StreetChallenge.rival(for: def))
    }

    func testGhostInterpolatesBetweenFrames() {
        let g = Ghost(frames: [GhostFrame(t: 0, x: 0, y: 0, heading: 0),
                               GhostFrame(t: 0.1, x: 10, y: 0, heading: 0.2)])
        let mid = g.pose(at: 0.05)!
        XCTAssertEqual(mid.position.x, 5, accuracy: 0.001)
        XCTAssertEqual(mid.heading, 0.1, accuracy: 0.001)
        XCTAssertEqual(g.pose(at: 9)!.position.x, 10, "parks at the end")
        XCTAssertNil(Ghost().pose(at: 1))
    }

    func testRecorderSamplesEveryTenthOfASecond() {
        var r = GhostRecorder()
        for i in 0..<60 { r.record(t: Double(i) / 60, position: Vec2(Double(i), 0), heading: 0) }
        XCTAssertEqual(r.ghost.frames.count, 10, accuracy: 1)
    }

    func testMedals() {
        XCTAssertEqual(StreetChallenge.medal(time: 40, rival: 41), .gold)
        XCTAssertEqual(StreetChallenge.medal(time: 45, rival: 41), .silver)
        XCTAssertEqual(StreetChallenge.medal(time: 60, rival: 41), .bronze)
        XCTAssertTrue(Medal.gold > Medal.silver && Medal.silver > Medal.bronze)
    }

    func testRecordKeepsTheBestGhostAndPaysEachMedalOnce() {
        var p = PlayerProgress()
        let slow = Ghost(frames: [GhostFrame(t: 60, x: 0, y: 0, heading: 0)])
        let fast = Ghost(frames: [GhostFrame(t: 39, x: 0, y: 0, heading: 0)])

        let first = StreetChallenge.record(time: 60, ghost: slow, rivalTime: 40, week: 3, progress: &p)
        XCTAssertEqual(first.medal, .bronze)
        XCTAssertEqual(first.bonus, Medal.bronze.bonus)
        XCTAssertEqual(p.credits, Medal.bronze.bonus)

        let again = StreetChallenge.record(time: 61, ghost: slow, rivalTime: 40, week: 3, progress: &p)
        XCTAssertFalse(again.newBest)
        XCTAssertEqual(again.bonus, 0, "bronze already paid this week")

        let gold = StreetChallenge.record(time: 39, ghost: fast, rivalTime: 40, week: 3, progress: &p)
        XCTAssertTrue(gold.newBest)
        XCTAssertEqual(gold.bonus, Medal.gold.bonus - Medal.bronze.bonus, "tops up to the gold bonus")
        XCTAssertEqual(gold.gapToRival, -1, accuracy: 0.001)
        XCTAssertEqual(p.challenge.bestTime, 39)
        XCTAssertEqual(p.challenge.ghost, fast)
        XCTAssertEqual(p.challenge.golds, 1)
        XCTAssertEqual(p.credits, Medal.gold.bonus)

        // A new week starts clean but keeps the gold count.
        let next = StreetChallenge.record(time: 70, ghost: slow, rivalTime: 40, week: 4, progress: &p)
        XCTAssertNil(next.previousBest)
        XCTAssertEqual(p.challenge.medal, .bronze)
        XCTAssertEqual(p.challenge.golds, 1)
        XCTAssertEqual(StreetChallenge.state(week: 5, progress: p).bestTime, nil)
    }

    func testChallengeSurvivesASaveRoundTripAndOldSavesLoad() throws {
        var p = PlayerProgress()
        StreetChallenge.record(time: 50, ghost: Ghost(frames: [GhostFrame(t: 0, x: 1, y: 2, heading: 3)]),
                               rivalTime: 45, week: 9, progress: &p)
        let back = try JSONDecoder().decode(PlayerProgress.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.challenge, p.challenge)
        let old = try JSONDecoder().decode(PlayerProgress.self, from: Data(#"{"credits":5}"#.utf8))
        XCTAssertEqual(old.challenge, ChallengeState())
    }
}
