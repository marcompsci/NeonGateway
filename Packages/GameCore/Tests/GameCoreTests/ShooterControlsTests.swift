import XCTest
@testable import GameCore

/// 0.13's landscape shooter controls: AIM lock-on, AUTO FIRE, the weapon bar and the move to
/// the Racer layout.
final class ShooterControlsTests: XCTestCase {
    let district = District.portAuroraDocks
    let dt = VehicleDynamics.fixedStep

    func at(_ col: Int, _ row: Int) -> Vec2 { district.center(of: TileCoord(col: col, row: row)) }

    func armed(_ w: WeaponID, ammo: Int) -> Inventory {
        var inv = Inventory()
        inv.acquire(w, ammo: ammo)
        return inv
    }

    func onFoot(heading: Double, inventory: Inventory) -> City {
        var city = City(district: district, start: SpawnPoint(position: at(12, 4), heading: heading),
                        playerVehicle: nil, inventory: inventory, seed: 7)
        city.crowd.people = []
        return city
    }

    func cruiser(_ offset: Vec2, id: Int = 70) -> Patrol {
        Patrol(id: id, car: VehicleState(position: at(12, 4) + offset, heading: .pi))
    }

    // MARK: AIM

    func testAimTurnsTheBodyToFaceACruiserBehind() {
        // Facing west, cruiser to the east.
        var city = onFoot(heading: .pi, inventory: armed(.pistol, ammo: 20))
        city.pursuit.patrols = [cruiser(Vec2(190, 0))]
        for _ in 0..<30 { _ = city.step(input: VehicleInput(move: .zero, aim: true), actions: .init(), dt: dt) }
        XCTAssertEqual(remainder(city.foot.heading, 2 * .pi), 0, accuracy: 0.25, "turned round to face it (the cruiser moves a little)")
        XCTAssertNotNil(city.aimLock)
    }

    func testAimKeepsMovingTheWayTheStickPoints() {
        // Back away west while locked on to a cruiser to the east.
        var city = onFoot(heading: 0, inventory: armed(.pistol, ammo: 20))
        city.pursuit.patrols = [cruiser(Vec2(190, 0))]
        let start = city.foot.position
        for _ in 0..<30 { _ = city.step(input: VehicleInput(move: Vec2(-1, 0), aim: true), actions: .init(), dt: dt) }
        XCTAssertLessThan(city.foot.position.x, start.x - 40, "still running away")
        XCTAssertEqual(remainder(city.foot.heading, 2 * .pi), 0, accuracy: 0.3, "still facing the cruiser")
    }

    func testNoLockWithoutAimOrWithoutAnyoneInRange() {
        var city = onFoot(heading: .pi, inventory: armed(.pistol, ammo: 20))
        city.pursuit.patrols = [cruiser(Vec2(190, 0))]
        _ = city.step(input: VehicleInput(move: .zero), actions: .init(), dt: dt)
        XCTAssertNil(city.aimLock, "AIM not held")
        city.pursuit.patrols = []
        _ = city.step(input: VehicleInput(move: .zero, aim: true), actions: .init(), dt: dt)
        XCTAssertNil(city.aimLock, "nobody about")
    }

    // MARK: AUTO FIRE

    func testAutoFireShootsACruiserInTheSights() {
        var city = onFoot(heading: 0, inventory: armed(.shotgun, ammo: 8))
        city.pursuit.patrols = [cruiser(Vec2(190, 0))]
        XCTAssertTrue(city.threatInSights)
        var events: [CityEvent] = []
        for _ in 0..<90 { events += city.step(input: VehicleInput(move: .zero), actions: CityActions(autoFire: true), dt: dt) }
        XCTAssertTrue(CityTests.copsAnswered(events, patrol: 70), "auto fire keeps shooting cops in the sights")
    }

    func testAutoFireLeavesBystandersAlone() {
        var city = onFoot(heading: 0, inventory: armed(.pistol, ammo: 20))
        city.pursuit.patrols = []
        XCTAssertFalse(city.threatInSights)
        let before = city.inventory.ammo(for: .pistol)
        for _ in 0..<60 { _ = city.step(input: VehicleInput(move: .zero), actions: CityActions(autoFire: true), dt: dt) }
        XCTAssertEqual(city.inventory.ammo(for: .pistol), before, "nothing to shoot, no rounds spent")
    }

    func testAutoFireWaitsUntilTheCruiserIsInFront() {
        var city = onFoot(heading: .pi, inventory: armed(.pistol, ammo: 20))
        city.pursuit.patrols = [cruiser(Vec2(190, 0))]
        XCTAssertFalse(city.threatInSights, "it's behind")
    }

    // MARK: Weapon bar

    func testEquipPicksALoadedWeapon() {
        var inv = armed(.pistol, ammo: 10)
        inv.acquire(.smg, ammo: 0)
        inv.add(.bat, ammo: 0)
        inv.equipped = .pistol
        XCTAssertTrue(inv.equip(.bat))
        XCTAssertEqual(inv.equipped, .bat)
        XCTAssertFalse(inv.equip(.smg), "empty gun stays put")
        XCTAssertEqual(inv.equipped, .bat)
        XCTAssertFalse(inv.equip(.rifle), "not owned")
    }

    // MARK: Settings

    func testRacerIsTheDefaultAndCarButtonsAreSeeThrough() {
        let s = GameSettings()
        XCTAssertEqual(s.controlStyle, .racer)
        XCTAssertEqual(s.driveOpacity, 0.65, accuracy: 0.001)
        XCTAssertFalse(s.autoFire)
    }

    func testPortraitEraSettingsMoveToTheLandscapeLayout() throws {
        let old = #"{"controlStyle":"stick","controlScale":1.2,"steerOffset":{"x":30,"y":-300}}"#
        let s = try JSONDecoder().decode(GameSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.controlStyle, .racer)
        XCTAssertEqual(s.steerOffset, LayoutOffset())
        XCTAssertEqual(s.controlScale, 1.2, accuracy: 0.001, "the rest is kept")
        XCTAssertEqual(s.layoutVersion, GameSettings.currentLayoutVersion)
    }

    func testLandscapeSettingsRoundTrip() throws {
        var s = GameSettings()
        s.controlStyle = .stick
        s.driveOpacity = 0.4
        s.autoFire = true
        s.steerOffset = LayoutOffset(x: 12, y: -40)
        let back = try JSONDecoder().decode(GameSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }
}
