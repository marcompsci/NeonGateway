import XCTest
@testable import GameCore

/// Harbor Patrol on foot: pulling over, the 5-second warning, shooting back, giving up.
final class OfficersTests: XCTestCase {
    let district = District.portAuroraDocks
    let dt = VehicleDynamics.fixedStep

    func at(_ col: Int, _ row: Int) -> Vec2 { district.center(of: TileCoord(col: col, row: row)) }

    /// On foot on the avenue with a chasing cruiser a little way east.
    func standoffCity(stars: Double = 35, armed: Bool = false) -> City {
        var inv = Inventory()
        if armed { inv.add(.pistol, ammo: 30) }
        var city = City(district: district, start: SpawnPoint(position: at(12, 4), heading: 0), playerVehicle: nil,
                        inventory: inv, seed: 7, parked: [], pickups: [])
        city.crowd.people = []
        if stars > 0 { city.pursuit.add(.missionEvent(stars)) }
        var patrol = Patrol(id: 50, car: VehicleState(position: at(12, 4) + Vec2(220, 0), heading: .pi))
        patrol.mode = .chase
        city.pursuit.patrols = [patrol]
        return city
    }

    /// Pacing up and down (so it isn't giving up), for `seconds`.
    func pace(_ city: inout City, seconds: Double, fire: Bool = false) -> [CityEvent] {
        var events: [CityEvent] = []
        let steps = Int((seconds / dt).rounded())
        for n in 0..<steps {
            let dir = (n / 30) % 2 == 0 ? Vec2(-1, 0) : Vec2(1, 0)
            events += city.step(input: VehicleInput(move: dir), actions: CityActions(fire: fire), dt: dt)
            if events.contains(.busted) { break }
        }
        return events
    }

    static func copShots(_ events: [CityEvent]) -> Int {
        events.filter { if case .copShot = $0 { return true } else { return false } }.count
    }

    func testOfficersGetOutAndWarnFiveSecondsBeforeShooting() {
        var city = standoffCity()
        var events = pace(&city, seconds: 0.5)
        XCTAssertTrue(events.contains(.officersOut(50)), "the cruiser pulls over")
        XCTAssertTrue(events.contains(.copsWarning))
        XCTAssertEqual(city.officers.count, 2)
        XCTAssertEqual(city.standoff.secondsLeft, 5)
        events = pace(&city, seconds: 4.3)
        XCTAssertEqual(Self.copShots(events), 0, "no shots during the warning")
        XCTAssertNotNil(city.standoff.secondsLeft)
        events = pace(&city, seconds: 3)
        XCTAssertTrue(events.contains(.copsOpenFire))
        XCTAssertGreaterThan(Self.copShots(events), 0, "they shoot once the warning is up")
        XCTAssertLessThan(city.health, City.maxHealth)
    }

    func testShootingAtCopsMeansImmediateReturnFire() {
        var city = standoffCity(stars: 0, armed: true)
        // Facing the cruiser (east), pull the trigger once.
        let first = city.step(input: .idle, actions: CityActions(fire: true), dt: dt)
        XCTAssertTrue(first.contains(.copsOpenFire), "no warning after shooting at a cruiser")
        XCTAssertTrue(first.contains(.officersOut(50)), "the officers jump out")
        XCTAssertTrue(city.standoff.isFiring)
        XCTAssertGreaterThanOrEqual(city.pursuit.heat.stars, 2)
        let events = pace(&city, seconds: 1.2)
        XCTAssertGreaterThan(Self.copShots(events), 0, "they fire back within about a second")
    }

    func testStandingStillIsGivingUp() {
        var city = standoffCity()
        var events: [CityEvent] = []
        for _ in 0..<Int(4.5 / dt) {
            events += city.step(input: .idle, actions: .init(), dt: dt)
            if events.contains(.busted) { break }
        }
        XCTAssertTrue(events.contains(.busted), "hands up before the warning ends: arrested, not shot")
        XCTAssertEqual(Self.copShots(events), 0)
    }

    func testOfficersCanBeKnockedDown() {
        var city = standoffCity(armed: true)
        _ = pace(&city, seconds: 0.3)
        XCTAssertEqual(city.officers.count, 2)
        // Face the nearest officer and fire until one goes down.
        var downed = false
        for _ in 0..<Int(4 / dt) where !downed {
            if let o = city.officers.filter({ !$0.isDown }).min(by: {
                ($0.position - city.foot.position).length < ($1.position - city.foot.position).length }) {
                let d = o.position - city.foot.position
                city.foot.heading = atan2(d.y, d.x)
            }
            let events = city.step(input: .idle, actions: CityActions(fire: true), dt: dt)
            downed = events.contains { if case .officerDown = $0 { return true } else { return false } }
        }
        XCTAssertTrue(downed)
        XCTAssertTrue(city.standoff.isFiring, "shooting an officer ends the warning")
    }

    func testOfficersGoBackWhenTheHeatIsGone() {
        var city = standoffCity()
        _ = pace(&city, seconds: 0.5)
        XCTAssertFalse(city.officers.isEmpty)
        city.pursuit.calmDown()
        _ = pace(&city, seconds: 6)
        XCTAssertTrue(city.officers.isEmpty, "back in the cruiser")
        XCTAssertEqual(city.standoff, .none)
        XCTAssertFalse(city.pursuit.patrols.first { $0.id == 50 }?.parked ?? false)
    }

    func testLowHeatStaysInTheCar() {
        var city = standoffCity(stars: 12)   // one star: a ticket, not a standoff
        let events = pace(&city, seconds: 1)
        XCTAssertFalse(events.contains(.officersOut(50)))
        XCTAssertTrue(city.officers.isEmpty)
    }
}
