import XCTest
@testable import GameCore

final class MissionRunnerTests: XCTestCase {
    let district = District.portAuroraDocks
    let def = MissionDef.coldCrate
    var dropCenter: Vec2 { district.zones[.lanternAlleyDrop]!.rect.center }
    var away: Vec2 { def.start.position }

    func testReachingTheDropOffSucceeds() {
        var s = MissionRunState()
        (s, _) = MissionRunner.step(s, def: def, district: district, carPosition: away, dt: 1)
        XCTAssertNil(s.outcome)
        let (done, events) = MissionRunner.step(s, def: def, district: district, carPosition: dropCenter, dt: 1)
        XCTAssertEqual(done.outcome, .success)
        XCTAssertEqual(done.elapsed, 2)
        XCTAssertEqual(events, [.objectiveComplete(index: 0), .finished(.success)])
    }

    func testRunningOutOfTimeFails() {
        var s = MissionRunState()
        var last: [MissionRunner.Event] = []
        for _ in 0..<40 {
            (s, last) = MissionRunner.step(s, def: def, district: district, carPosition: away, dt: 1)
            if s.isFinished { break }
        }
        XCTAssertEqual(s.outcome, .timeUp)
        XCTAssertEqual(s.elapsed, def.timeLimit!, "clock stops exactly at the limit")
        XCTAssertEqual(last, [.finished(.timeUp)])
    }

    func testArrivingOnTheLastStepStillCounts() {
        var s = MissionRunState()
        s.elapsed = def.timeLimit! - 0.5
        s.clockElapsed = s.elapsed
        let (done, _) = MissionRunner.step(s, def: def, district: district, carPosition: dropCenter, dt: 1)
        XCTAssertEqual(done.outcome, .success, "reaching the zone on the final step wins")
    }

    func testFinishedRunsDoNotChange() {
        var s = MissionRunState()
        s.outcome = .success
        s.elapsed = 12
        let (after, events) = MissionRunner.step(s, def: def, district: district, carPosition: away, dt: 1)
        XCTAssertEqual(after, s)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(MissionRunner.end(s, with: .quit).outcome, .success)
    }

    func testQuitEndsARun() {
        XCTAssertEqual(MissionRunner.end(MissionRunState(), with: .quit).outcome, .quit)
    }

    func testTimeRemainingAndActiveZones() {
        var s = MissionRunState()
        s.elapsed = 10
        s.clockElapsed = 10
        XCTAssertEqual(MissionRunner.timeRemaining(s, def: def), def.timeLimit! - 10)
        XCTAssertEqual(MissionRunner.activeZones(s, def: def), [.lanternAlleyDrop])
        s.objectiveIndex = 1
        XCTAssertEqual(MissionRunner.activeZones(s, def: def), [])
    }

    func testCollectObjectiveNeedsEveryZoneInAnyOrder() {
        let pickup = MissionDef(
            id: .lanternSweep, title: "Test sweep", brief: "", kind: .pickupRun, requiredRepLevel: 0,
            start: def.start, objectives: [.collect([.pier4, .pier9]), .returnTo(.safehouse)],
            timeLimit: nil, baseReward: 100, baseRepXP: 10,
            objectiveLines: ["Collect", "Return"])
        let pier9 = district.zones[.pier9]!.rect.center
        let pier4 = district.zones[.pier4]!.rect.center
        let safe = district.zones[.safehouse]!.rect.center

        var s = MissionRunState()
        var events: [MissionRunner.Event]
        (s, events) = MissionRunner.step(s, def: pickup, district: district, carPosition: pier9, dt: 1)
        XCTAssertEqual(events, [.collected(.pier9)])
        XCTAssertEqual(MissionRunner.activeZones(s, def: pickup), [.pier4])
        (s, events) = MissionRunner.step(s, def: pickup, district: district, carPosition: pier4, dt: 1)
        XCTAssertEqual(events, [.collected(.pier4), .objectiveComplete(index: 0)])
        XCTAssertNil(s.outcome)
        (s, _) = MissionRunner.step(s, def: pickup, district: district, carPosition: safe, dt: 100)
        XCTAssertEqual(s.outcome, .success, "untimed jobs never run out of time")
    }

    func testCalmObjectiveWaitsForZeroStars() {
        let def = MissionDef.tideLineRun
        let pier = district.zones[.pier4]!.rect.center
        var s = MissionRunState()
        (s, _) = MissionRunner.step(s, def: def, district: district, carPosition: pier, heatStars: 1, dt: 1)
        XCTAssertNil(s.outcome, "still has heat")
        XCTAssertTrue(MissionRunner.isWaitingForCalm(s, def: def, district: district, carPosition: pier, heatStars: 1))
        XCTAssertFalse(MissionRunner.isWaitingForCalm(s, def: def, district: district, carPosition: away, heatStars: 1))
        (s, _) = MissionRunner.step(s, def: def, district: district, carPosition: pier, heatStars: 0, dt: 1)
        XCTAssertEqual(s.outcome, .success)
    }

    func testEscapeHasNoClock() {
        var s = MissionRunState()
        (s, _) = MissionRunner.step(s, def: .tideLineRun, district: district, carPosition: away, heatStars: 2, dt: 10_000)
        XCTAssertNil(s.outcome)
        XCTAssertNil(MissionRunner.timeRemaining(s, def: .tideLineRun))
    }
}
