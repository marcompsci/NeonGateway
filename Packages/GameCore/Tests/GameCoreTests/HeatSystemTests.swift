import XCTest
@testable import GameCore

final class HeatSystemTests: XCTestCase {
    func testStarThresholdsAndLabels() {
        XCTAssertEqual(HeatRules.stars(for: 0), 0)
        XCTAssertEqual(HeatRules.stars(for: 9.9), 0)
        XCTAssertEqual(HeatRules.stars(for: 10), 1)
        XCTAssertEqual(HeatRules.stars(for: 30), 2)
        XCTAssertEqual(HeatRules.stars(for: 50), 3)
        XCTAssertEqual(HeatRules.stars(for: 70), 4)
        XCTAssertEqual(HeatRules.stars(for: 90), 5)
        XCTAssertEqual(HeatRules.stars(for: 100), 5)
        XCTAssertEqual(HeatState(points: 35).label, "Wanted")
        XCTAssertEqual(HeatRules.labels.count, 6, "one label per star count, 0...5")
    }

    func testEventsAddTheRightPoints() {
        var s = HeatState()
        s = HeatSystem.apply(.wallHit, to: s)
        XCTAssertEqual(s.points, 4)
        s = HeatSystem.apply(.patrolHit, to: s)
        XCTAssertEqual(s.points, 19)
        s = HeatSystem.apply(.missionEvent(12), to: s)
        XCTAssertEqual(s.points, 31)
    }

    func testHeatIsClampedToZeroAndOneHundred() {
        XCTAssertEqual(HeatSystem.apply(.missionEvent(500), to: HeatState(points: 90)).points, 100)
        XCTAssertEqual(HeatSystem.apply(.missionEvent(-50), to: HeatState(points: 10)).points, 0)
        XCTAssertEqual(HeatState(points: 400).points, 100)
    }

    func testRestrictedZoneAddsFourPerSecond() {
        var s = HeatState()
        for _ in 0..<60 { s = HeatSystem.step(s, dt: 1.0 / 60, seen: true, inRestricted: true, inSafehouse: false) }
        XCTAssertEqual(s.points, 4, accuracy: 0.001)
    }

    func testHeatHoldsDuringTheGracePeriodThenDecays() {
        var s = HeatState(points: 40)
        // 4 s unseen: inside the grace period, nothing drops.
        for _ in 0..<240 { s = HeatSystem.step(s, dt: 1.0 / 60, seen: false, inRestricted: false, inSafehouse: false) }
        XCTAssertEqual(s.points, 40, accuracy: 0.001)
        // 1 more second: −8.
        for _ in 0..<60 { s = HeatSystem.step(s, dt: 1.0 / 60, seen: false, inRestricted: false, inSafehouse: false) }
        XCTAssertEqual(s.points, 32, accuracy: 0.2)
    }

    func testBeingSeenResetsTheGraceTimer() {
        var s = HeatState(points: 40)
        for _ in 0..<200 { s = HeatSystem.step(s, dt: 1.0 / 60, seen: false, inRestricted: false, inSafehouse: false) }
        s = HeatSystem.step(s, dt: 1.0 / 60, seen: true, inRestricted: false, inSafehouse: false)
        XCTAssertEqual(s.timeUnseen, 0)
        for _ in 0..<200 { s = HeatSystem.step(s, dt: 1.0 / 60, seen: false, inRestricted: false, inSafehouse: false) }
        XCTAssertEqual(s.points, 40, accuracy: 0.001, "a fresh sighting restarts the 4 s grace")
    }

    func testSafehouseClearsHeat() {
        let s = HeatSystem.step(HeatState(points: 95), dt: 1.0 / 60, seen: true, inRestricted: false, inSafehouse: true)
        XCTAssertEqual(s.points, 0)
        XCTAssertEqual(s.stars, 0)
    }

    func testLosingTwoStarsTakesAboutEightSecondsUnseen() {
        var s = HeatState(points: 35)
        var t = 0.0
        while s.stars > 0 && t < 60 {
            s = HeatSystem.step(s, dt: 1.0 / 60, seen: false, inRestricted: false, inSafehouse: false)
            t += 1.0 / 60
        }
        XCTAssertEqual(t, 4 + 25.0 / 8, accuracy: 0.1, "4 s grace, then 35 → 10 points at 8/s")
    }
}
