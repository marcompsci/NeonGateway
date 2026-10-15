import XCTest
@testable import GameCore

final class FistsTests: XCTestCase {
    let district = District.portAuroraDocks
    let dt = VehicleDynamics.fixedStep
    func at(_ c: Int, _ r: Int) -> Vec2 { district.center(of: TileCoord(col: c, row: r)) }

    func city(with offset: Vec2?) -> City {
        var c = City(district: district, start: SpawnPoint(position: at(12, 4), heading: 0), playerVehicle: nil,
                     seed: 3, parked: [], pickups: [])
        c.crowd.people = offset.map { [Pedestrian(id: 8, position: at(12, 4) + $0, heading: .pi, target: at(12, 4) + $0, look: 1)] } ?? []
        c.pursuit.patrols = []
        return c
    }

    func throwStrike(_ c: inout City, _ s: Strike) -> [CityEvent] {
        var events = c.step(input: .idle, actions: CityActions(strike: s), dt: dt)
        for _ in 0..<30 { events += c.step(input: .idle, actions: .init(), dt: dt) }   // recover
        return events
    }

    func testPunchLandsOnSomeoneInFront() {
        var c = city(with: Vec2(40, 0))
        let e = throwStrike(&c, .jab)
        XCTAssertTrue(e.contains(.punch(.jab, hit: true)))
    }

    func testPunchingAirMisses() {
        var c = city(with: nil)
        XCTAssertTrue(throwStrike(&c, .jab).contains(.punch(.jab, hit: false)))
    }

    func testHooksReachTheirOwnSide() {
        // Facing east; someone up-left (north-east-ish, anticlockwise side) is a left-hook target.
        var c = city(with: Vec2(28, 26))
        XCTAssertTrue(throwStrike(&c, .left).contains(.punch(.left, hit: true)))
        var d = city(with: Vec2(28, 26))
        XCTAssertTrue(throwStrike(&d, .right).contains(.punch(.right, hit: false)), "a right hook swings the other way")
    }

    func testTwoHooksKnockSomeoneDown() {
        var c = city(with: Vec2(40, 0))
        var events = throwStrike(&c, .left)
        XCTAssertFalse(events.contains(.pedestrianDown(8)))
        // They got pushed back a step; follow up.
        c.crowd.people[0].position = at(12, 4) + Vec2(40, 0)
        events = throwStrike(&c, .right)
        XCTAssertTrue(events.contains(.pedestrianDown(8)))
    }

    func testPunchingAnOfficerStartsTheShooting() {
        var c = city(with: nil)
        c.pursuit.add(.missionEvent(35))
        c.officers = [Officer(id: 1, patrolID: 99, position: at(12, 4) + Vec2(40, 0), heading: .pi, fireCooldown: 1)]
        c.standoff = .warning(5)
        let e = throwStrike(&c, .jab)
        XCTAssertTrue(e.contains(.copsOpenFire))
    }
}
