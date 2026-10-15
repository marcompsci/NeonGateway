import XCTest
@testable import GameCore

/// On foot, switching vehicles, guns and the crowd: the open-city layer of Port Aurora.
final class CityTests: XCTestCase {
    let district = District.portAuroraDocks
    let dt = VehicleDynamics.fixedStep

    func at(_ col: Int, _ row: Int) -> Vec2 { district.center(of: TileCoord(col: col, row: row)) }

    func onFoot(_ col: Int, _ row: Int, heading: Double, parked: [ParkedSpawn] = [],
                pickups: [PickupSpawn] = [], inventory: Inventory = .init()) -> City {
        City(district: district, start: SpawnPoint(position: at(col, row), heading: heading), playerVehicle: nil,
             inventory: inventory, seed: 7, parked: parked, pickups: pickups)
    }

    /// Runs the city for `seconds` with the same input; returns every event.
    @discardableResult
    func run(_ city: inout City, seconds: Double, input: VehicleInput = .idle,
             actions: CityActions = .init()) -> [CityEvent] {
        var events: [CityEvent] = []
        for _ in 0..<Int((seconds / dt).rounded()) { events += city.step(input: input, actions: actions, dt: dt) }
        return events
    }

    func tap(_ city: inout City) -> [CityEvent] {
        city.step(input: .idle, actions: CityActions(enterExit: true), dt: dt)
    }

    // MARK: Content

    func testParkedVehiclesAndPickupsSitInTheOpen() {
        for spot in District.docksParked {
            XCTAssertFalse(district.tile(spot.tile).isSolid, "\(spot.model) at \(spot.tile)")
            let state = VehicleState(position: district.center(of: spot.tile), heading: spot.heading)
            let solids = district.solids(near: state.position, radius: spot.model.spec.radius)
            XCTAssertFalse(Collision.resolve(state, radius: spot.model.spec.radius, solids: solids).hit,
                           "\(spot.model) at \(spot.tile) touches a wall")
        }
        for spot in District.docksPickups {
            XCTAssertFalse(district.tile(spot.tile).isSolid, "\(spot.weapon) pickup at \(spot.tile)")
        }
        XCTAssertTrue(District.docksParked.contains { $0.model.isMotorcycle }, "a bike to find")
        XCTAssertEqual(district.zones[.gunStore]?.kind, .shop)
    }

    func testNewVehiclesFeelDifferent() {
        XCTAssertGreaterThan(VehicleSpec.flicker.acceleration, VehicleSpec.vesper.acceleration)
        XCTAssertLessThan(VehicleSpec.flicker.maxIntegrity, VehicleSpec.vesper.maxIntegrity)
        XCTAssertGreaterThan(VehicleSpec.ridgeback.maxIntegrity, VehicleSpec.dorado.maxIntegrity)
        XCTAssertLessThan(VehicleSpec.ridgeback.maxSpeed, VehicleSpec.dorado.maxSpeed)
        XCTAssertTrue([VehicleID.vesper, .dorado, .ridgeback, .flicker].allSatisfy(VehicleID.drivable.contains))
        XCTAssertFalse(VehicleID.drivable.contains(.harborPatrol))
        XCTAssertFalse(VehicleID.drivable.contains(.hauler))
    }

    // MARK: On foot

    func testRunningOnFootIsSlowerThanDrivingAndStopsAtWalls() {
        // Harbor Avenue, facing north into the buildings at row 3.
        var city = onFoot(14, 4, heading: .pi / 2)
        run(&city, seconds: 2, input: VehicleInput(throttle: 1))
        XCTAssertFalse(district.tile(at: city.foot.position).isSolid)
        XCTAssertEqual(district.coord(at: city.foot.position).row, 4, "stopped at the wall")

        var open = onFoot(6, 4, heading: 0)
        run(&open, seconds: 1, input: VehicleInput(throttle: 1))
        XCTAssertEqual(open.foot.speed, FootDynamics.runSpeed, accuracy: 1)
        XCTAssertLessThan(FootDynamics.runSpeed, VehicleSpec.dorado.maxSpeed * 0.55)
    }

    func testTurningOnTheSpot() {
        var city = onFoot(6, 4, heading: 0)
        run(&city, seconds: 0.5, input: VehicleInput(steer: -1))
        XCTAssertGreaterThan(city.foot.heading, 1, "turned left while standing still")
        XCTAssertEqual(city.foot.position.x, at(6, 4).x, accuracy: 0.001)
    }

    // MARK: Vehicles

    func testWalkUpToAParkedCarAndTakeIt() {
        let parked = [ParkedSpawn(model: .dorado, tile: TileCoord(col: 12, row: 9), heading: .pi / 2)]
        var city = onFoot(12, 7, heading: -.pi / 2, parked: parked)
        XCTAssertNil(city.enterableVehicle, "too far away at first")
        run(&city, seconds: 1.3, input: VehicleInput(throttle: 1))
        XCTAssertEqual(city.enterableVehicle, 0)
        let events = tap(&city)
        XCTAssertEqual(events.first, .entered(vehicle: 0, stolen: true))
        XCTAssertEqual(city.mode, .driving(vehicle: 0))
        XCTAssertEqual(city.currentVehicle?.model, .dorado)
        XCTAssertEqual(city.playerPosition, city.vehicles[0].state.position)
    }

    func testStealingInFrontOfAPatrolAddsHeat() {
        let parked = [ParkedSpawn(model: .dorado, tile: TileCoord(col: 12, row: 9), heading: .pi / 2)]
        var city = onFoot(12, 7, heading: -.pi / 2, parked: parked)
        run(&city, seconds: 1.3, input: VehicleInput(throttle: 1))
        let heatBefore = city.pursuit.heat.points
        // A cruiser right behind the player, nose toward them.
        city.pursuit.patrols = [Patrol(id: 90, car: VehicleState(position: city.foot.position + Vec2(0, 110),
                                                                  heading: -.pi / 2))]
        run(&city, seconds: dt)
        XCTAssertTrue(city.pursuit.isSeen)
        _ = tap(&city)
        XCTAssertGreaterThanOrEqual(city.pursuit.heat.points, heatBefore + City.theftHeat)
    }

    func testCantBailOutAtSpeedButCanOnceSlow() {
        var city = City(district: district, start: SpawnPoint(position: at(4, 4), heading: 0),
                        playerVehicle: .vesper, seed: 3)
        run(&city, seconds: 1, input: VehicleInput(throttle: 1))
        XCTAssertGreaterThan(city.player.speed, City.exitMaxSpeed)
        XCTAssertTrue(tap(&city).isEmpty)
        XCTAssertFalse(city.isOnFoot)
        // Brake to a stop (holding it longer would start reversing), then roll to rest.
        run(&city, seconds: 0.4, input: VehicleInput(brake: 1))
        run(&city, seconds: 1)
        XCTAssertTrue(city.canExit)
        XCTAssertEqual(tap(&city), [.exited(vehicle: 0)])
        XCTAssertTrue(city.isOnFoot)
        XCTAssertFalse(district.tile(at: city.foot.position).isSolid)
        XCTAssertLessThan((city.foot.position - city.vehicles[0].state.position).length, City.enterDistance,
                          "you get out right beside it, so you can get back in")
    }

    func testAWreckThrowsThePlayerClear() {
        var city = City(district: district, start: SpawnPoint(position: at(6, 4), heading: 0),
                        playerVehicle: .flicker, seed: 3)
        city.vehicles[0].damage = city.vehicles[0].spec.maxIntegrity
        let events = run(&city, seconds: dt)
        XCTAssertTrue(events.contains(.wrecked(vehicle: 0)))
        XCTAssertTrue(city.isOnFoot)
        XCTAssertEqual(city.health, City.maxHealth - City.wreckHealthLoss)
        XCTAssertNil(city.enterableVehicle, "a wreck can't be driven")
    }

    func testKeepingAStolenCarMakesItYoursAndTuned() {
        let parked = [ParkedSpawn(model: .dorado, tile: TileCoord(col: 12, row: 9), heading: .pi / 2)]
        var tuning = UpgradeLevels()
        tuning.speed = 2
        var city = City(district: district, start: SpawnPoint(position: at(12, 7), heading: -.pi / 2),
                        playerVehicle: nil, tuning: tuning, seed: 7, parked: parked, pickups: [])
        run(&city, seconds: 1.3, input: VehicleInput(throttle: 1))
        _ = tap(&city)
        XCTAssertEqual(city.currentVehicle?.spec.maxSpeed, VehicleSpec.dorado.maxSpeed, "stock while stolen")
        XCTAssertEqual(city.keepCurrentVehicle(), .dorado)
        XCTAssertTrue(city.currentVehicle!.owned)
        XCTAssertGreaterThan(city.currentVehicle!.spec.maxSpeed, VehicleSpec.dorado.maxSpeed)
        XCTAssertNil(city.keepCurrentVehicle(), "already yours")
    }

    func testRunningSomeoneOverKnocksThemDownAndAddsHeat() {
        var city = City(district: district, start: SpawnPoint(position: at(5, 4), heading: 0),
                        playerVehicle: .vesper, seed: 3, parked: [], pickups: [])
        city.crowd.people = [Pedestrian(id: 1, position: at(9, 4), heading: 0, target: at(9, 4), look: 0),
                             // A witness across the road.
                             Pedestrian(id: 2, position: at(7, 5), heading: 0, target: at(7, 5), look: 0)]
        let events = run(&city, seconds: 2, input: VehicleInput(throttle: 1))
        XCTAssertTrue(events.contains(.pedestrianDown(1)))
        XCTAssertTrue(events.contains(.witnessed))
        XCTAssertLessThan(city.pursuit.heat.points, 1, "no heat until the call goes through")
        XCTAssertTrue(callGoesThrough(&city))
        XCTAssertGreaterThanOrEqual(city.pursuit.heat.points, City.pedestrianHitHeat - 1)
    }

    /// Idles until a witness's call lands; true if one did.
    func callGoesThrough(_ city: inout City) -> Bool {
        for _ in 0..<Int((City.reportDelay + 1) / dt) {
            if city.step(input: .idle, actions: .init(), dt: dt).contains(.reported) { return true }
        }
        return false
    }

    // MARK: Witnesses and tickets

    func testNoWitnessNoHeat() {
        var city = onFoot(12, 4, heading: 0, inventory: armed(.pistol, ammo: 10))
        city.pursuit.patrols = []
        city.crowd.people = [Pedestrian(id: 4, position: at(12, 4) + Vec2(200, 0), heading: 0,
                                        target: at(12, 4) + Vec2(200, 0), look: 0)]
        let events = city.step(input: .idle, actions: CityActions(fire: true), dt: dt)
        XCTAssertTrue(events.contains(.pedestrianDown(4)))
        XCTAssertFalse(events.contains(.witnessed))
        XCTAssertFalse(callGoesThrough(&city))
        XCTAssertEqual(city.pursuit.heat.points, 0)
    }

    func testDitchingTheRideHalvesTheReport() {
        let parked = [ParkedSpawn(model: .dorado, tile: TileCoord(col: 12, row: 9), heading: .pi / 2)]
        var city = onFoot(12, 7, heading: -.pi / 2, parked: parked)
        city.pursuit.patrols = []
        city.crowd.people = [Pedestrian(id: 3, position: at(12, 7), heading: 0, target: at(12, 7), look: 0)]
        run(&city, seconds: 1.3, input: VehicleInput(throttle: 1))
        let events = tap(&city)
        XCTAssertTrue(events.contains(.witnessed), "someone saw the theft")
        XCTAssertEqual(city.reports.first?.ride, 0)
        // Out of the car before the call lands: the description no longer fits.
        _ = tap(&city)
        XCTAssertTrue(city.isOnFoot)
        XCTAssertTrue(callGoesThrough(&city))
        XCTAssertEqual(city.pursuit.heat.points, City.theftHeat * City.wrongRideShare, accuracy: 0.01)
    }

    func testLowHeatGetsATicketNotABust() {
        var city = onFoot(12, 4, heading: 0)
        city.crowd.people = []
        city.pursuit.heat.points = 15  // one star
        var cop = Patrol(id: 5, car: VehicleState(position: at(12, 4) + Vec2(-60, 0), heading: 0))
        cop.mode = .chase
        city.pursuit.patrols = [cop]
        var events: [CityEvent] = []
        for _ in 0..<Int(5 / dt) where !events.contains(.ticketed) {
            events += city.step(input: .idle, actions: .init(), dt: dt)
        }
        XCTAssertTrue(events.contains(.ticketed))
        XCTAssertFalse(events.contains(.busted))
        XCTAssertFalse(city.pursuit.isBusted)
        XCTAssertEqual(city.pursuit.heat.stars, 0)
        XCTAssertEqual(city.stats.ticketsPaid, 1)
    }

    func testRainMakesCarsSlide() {
        let wet = Weather.rain.adjusted(.dorado)
        XCTAssertGreaterThan(wet.lateralRetention, VehicleSpec.dorado.lateralRetention)
        XCTAssertLessThan(wet.brakeForce, VehicleSpec.dorado.brakeForce)
        XCTAssertEqual(Weather.clear.adjusted(.dorado).brakeForce, VehicleSpec.dorado.brakeForce)
        let rainy = (0..<200).filter { Weather.roll(seed: UInt64($0)) == .rain }.count
        XCTAssertGreaterThan(rainy, 30)
        XCTAssertLessThan(rainy, 90)
        XCTAssertEqual(TimeOfDay.at(hour: 23), .night)
        XCTAssertEqual(TimeOfDay.at(hour: 12), .day)
    }

    func testSkillsAndAimAssistChangeTheGame() {
        var fast = City(district: district, start: SpawnPoint(position: at(6, 4), heading: 0), playerVehicle: nil,
                        seed: 7, parked: [], pickups: [], skills: SkillLevels(stamina: 5))
        run(&fast, seconds: 1, input: VehicleInput(throttle: 1))
        XCTAssertEqual(fast.foot.speed, FootDynamics.runSpeed * Skills.runMultiplier(5), accuracy: 1)
        XCTAssertGreaterThan(fast.stats.run, 100)

        // A target 20° off the nose: standard aim hits it, aim assist off doesn't.
        let angle = 20.0 * .pi / 180
        let target = at(12, 4) + Vec2(cos(angle), sin(angle)) * 160
        func shoot(_ assist: AimAssist) -> Bool {
            var c = City(district: district, start: SpawnPoint(position: at(12, 4), heading: 0), playerVehicle: nil,
                         inventory: armed(.pistol, ammo: 5), seed: 7, parked: [], pickups: [],
                         aimAssist: assist.coneMultiplier)
            c.crowd.people = [Pedestrian(id: 9, position: target, heading: 0, target: target, look: 0)]
            return c.step(input: .idle, actions: CityActions(fire: true), dt: dt).contains(.pedestrianDown(9))
        }
        XCTAssertTrue(shoot(.standard))
        XCTAssertFalse(shoot(.off))
    }

    // MARK: Guns

    func armed(_ weapon: WeaponID, ammo: Int) -> Inventory {
        var inv = Inventory()
        inv.add(weapon, ammo: ammo)
        return inv
    }

    func testShootingThePersonInFront() {
        var city = onFoot(12, 4, heading: 0, inventory: armed(.pistol, ammo: 10))
        city.crowd.people = [Pedestrian(id: 4, position: at(12, 4) + Vec2(200, 0), heading: 0,
                                        target: at(12, 4) + Vec2(200, 0), look: 0)]
        let events = city.step(input: .idle, actions: CityActions(fire: true), dt: dt)
        XCTAssertTrue(events.contains(.pedestrianDown(4)))
        XCTAssertTrue(events.contains { if case .shot(let t) = $0 { return t.hit } else { return false } })
        XCTAssertEqual(city.inventory.ammo(for: .pistol), 9)
        XCTAssertEqual(city.stats.hitsLanded, 1)
    }

    func testShotsOnlyHitWhatYoureFacing() {
        var city = onFoot(12, 4, heading: 0, inventory: armed(.pistol, ammo: 10))
        city.crowd.people = [Pedestrian(id: 4, position: at(12, 4) - Vec2(200, 0), heading: 0,
                                        target: at(12, 4) - Vec2(200, 0), look: 0)]
        let events = city.step(input: .idle, actions: CityActions(fire: true), dt: dt)
        XCTAssertFalse(events.contains(.pedestrianDown(4)))
        guard case .shot(let trace)? = events.first(where: { if case .shot = $0 { return true } else { return false } }) else {
            return XCTFail("a shot was fired")
        }
        XCTAssertFalse(trace.hit)
        XCTAssertLessThanOrEqual((trace.to - trace.from).length, WeaponID.pistol.spec.range + 1)
        XCTAssertGreaterThan(trace.to.x, trace.from.x, "flew the way the player faces")
    }

    func testWallsStopShots() {
        // Facing north from Harbor Avenue: the buildings at row 3 are one tile away.
        var city = onFoot(14, 4, heading: .pi / 2, inventory: armed(.pistol, ammo: 10))
        city.crowd.people = [Pedestrian(id: 4, position: at(14, 1), heading: 0, target: at(14, 1), look: 0)]
        let events = city.step(input: .idle, actions: CityActions(fire: true), dt: dt)
        XCTAssertFalse(events.contains(.pedestrianDown(4)))
        if case .shot(let trace)? = events.first(where: { if case .shot = $0 { return true } else { return false } }) {
            XCTAssertFalse(district.tile(at: trace.to).isSolid)
            XCTAssertLessThan(trace.to.y, district.rect(of: TileCoord(col: 14, row: 3)).minY)
        }
    }

    func testFireRateAndNoAmmo() {
        var city = onFoot(12, 4, heading: 0, inventory: armed(.pistol, ammo: 2))
        city.crowd.people = []
        let held = CityActions(fire: true)
        var shots = 0
        var empty = false
        for _ in 0..<60 {
            for event in city.step(input: .idle, actions: held, dt: dt) {
                if case .shot = event { shots += 1 }
                if event == .outOfAmmo { empty = true }
            }
        }
        XCTAssertEqual(shots, 2, "two rounds, then dry")
        XCTAssertTrue(empty)
        XCTAssertFalse(city.inventory.canFire)
    }

    func testRunningDrySwitchesToAnotherLoadedGun() {
        var inv = armed(.pistol, ammo: 1)
        inv.add(.smg, ammo: 30)
        inv.equipped = .pistol
        var city = onFoot(12, 4, heading: 0, inventory: inv)
        city.crowd.people = []
        _ = city.step(input: .idle, actions: CityActions(fire: true), dt: dt)
        XCTAssertEqual(city.inventory.equipped, .smg)
    }

    func testShootingACruiserDisablesItAndBringsHeat() {
        var city = onFoot(12, 4, heading: 0, inventory: armed(.shotgun, ammo: 8))
        city.crowd.people = []
        city.pursuit.patrols = [Patrol(id: 70, car: VehicleState(position: at(12, 4) + Vec2(190, 0), heading: .pi))]
        let events = run(&city, seconds: 1.5, actions: CityActions(fire: true))
        // The officers jump out shooting; the nearest of cruiser or officer takes the hits.
        XCTAssertTrue(events.contains(.copsOpenFire))
        XCTAssertTrue(events.contains(.officersOut(70)))
        XCTAssertTrue(Self.copsAnswered(events, patrol: 70), "something goes down")
        XCTAssertGreaterThanOrEqual(city.pursuit.heat.stars, 2)
    }

    static func copsAnswered(_ events: [CityEvent], patrol: Int) -> Bool {
        events.contains(.patrolDisabled(patrol)) || events.contains { if case .officerDown = $0 { return true } else { return false } }
    }


    func testPickingUpAWeapon() {
        let pickup = PickupSpawn(weapon: .smg, ammo: 60, tile: TileCoord(col: 12, row: 4))
        var city = onFoot(12, 4, heading: 0, pickups: [pickup])
        let events = run(&city, seconds: dt)
        XCTAssertEqual(events.filter { if case .pickedUp = $0 { return true } else { return false } },
                       [.pickedUp(.smg, ammo: 60)])
        XCTAssertEqual(city.inventory.equipped, .smg)
        XCTAssertFalse(city.pickups[0].isAvailable)
        XCTAssertTrue(run(&city, seconds: 1).allSatisfy { if case .pickedUp = $0 { return false } else { return true } })
        run(&city, seconds: City.pickupRespawn + 0.5)
        XCTAssertEqual(city.inventory.ammo(for: .smg), 120, "it came back and was picked up again")
    }

    func testInventoryCapsAndCycles() {
        var inv = Inventory()
        inv.add(.shotgun, ammo: 999)
        XCTAssertEqual(inv.ammo(for: .shotgun), WeaponID.shotgun.spec.maxAmmo)
        inv.add(.pistol, ammo: 5)
        XCTAssertEqual(inv.equipped, .shotgun, "picking up doesn't steal the equipped slot")
        inv.cycle()
        XCTAssertEqual(inv.equipped, .pistol)
        inv.cycle()
        XCTAssertEqual(inv.equipped, .shotgun)
    }

    // MARK: Health and crowd

    func testRunningOutOfHealthKnocksThePlayerOut() {
        var city = onFoot(12, 4, heading: 0)
        city.health = 0
        XCTAssertTrue(run(&city, seconds: dt).contains(.knockedOut))
    }

    func testTheCrowdWalksTheFootpathsAndComesBack() {
        var city = onFoot(19, 2, heading: 0)
        XCTAssertEqual(city.crowd.people.count, City.crowdSize)
        city.crowd.knockDown(0)
        run(&city, seconds: 20)
        for person in city.crowd.people {
            XCTAssertFalse(district.tile(at: person.position).isSolid, "person \(person.id) in a wall")
        }
        XCTAssertFalse(city.crowd.people[0].isDown, "got back up somewhere else")
    }

    func testGunfireScattersTheCrowd() {
        var city = onFoot(12, 4, heading: .pi / 2, inventory: armed(.pistol, ammo: 5))
        city.crowd.people = [Pedestrian(id: 2, position: at(10, 5), heading: 0, target: at(10, 5), look: 0)]
        _ = city.step(input: .idle, actions: CityActions(fire: true), dt: dt)
        XCTAssertEqual(city.crowd.people[0].mode, .flee)
    }

    // MARK: Jobs on foot

    func testStreetFlyersStartsOnFootAndIsRunnable() throws {
        let def = MissionDef.streetFlyers
        XCTAssertTrue(def.startsOnFoot)
        // Nearest-first route on foot, tile steps at running speed, must beat 60% of the clock.
        var here = district.coord(at: def.start.position)
        var left = def.objectives[0].zones.map { district.coord(at: district.zones[$0]!.rect.center) }
        var tiles = 0
        while !left.isEmpty {
            let lengths = left.map { district.pathLength(from: here, to: $0) ?? .max }
            let i = lengths.indices.min { lengths[$0] < lengths[$1] }!
            tiles += lengths[i]
            here = left.remove(at: i)
        }
        tiles += try XCTUnwrap(district.pathLength(from: here, to: district.coord(at: district.zones[.printShop]!.rect.center)))
        let seconds = Double(tiles) * district.tileSize / FootDynamics.runSpeed
        XCTAssertLessThan(seconds, def.timeLimit! * 0.6, "\(seconds) s on foot")
    }
}
