import XCTest
@testable import GameCore

final class PursuitTests: XCTestCase {
    let district = District.portAuroraDocks
    let dt = VehicleDynamics.fixedStep

    /// Harbor Avenue (rows 4–5) is a long straight east–west road with nothing in the way.
    func avenue(_ col: Int) -> Vec2 { district.center(of: TileCoord(col: col, row: 4)) }

    // MARK: Vision

    func testPatrolSeesAheadButNotBehind() {
        let patrol = VehicleState(position: avenue(5), heading: 0)  // facing east
        XCTAssertTrue(PatrolBrain.canSee(patrol, target: avenue(8), district: district))
        XCTAssertFalse(PatrolBrain.canSee(patrol, target: avenue(1) + Vec2(-400, 0), district: district))
        XCTAssertFalse(PatrolBrain.canSee(VehicleState(position: avenue(12), heading: 0),
                                          target: avenue(9), district: district), "behind, 384 pt away")
    }

    func testCloseTargetsAreNoticedFromAnyAngle() {
        let patrol = VehicleState(position: avenue(10), heading: 0)
        XCTAssertTrue(PatrolBrain.canSee(patrol, target: avenue(10) + Vec2(-100, 0), district: district))
    }

    func testFarTargetsAreOutOfRange() {
        let patrol = VehicleState(position: avenue(2), heading: 0)
        XCTAssertFalse(PatrolBrain.canSee(patrol, target: avenue(10), district: district), "1024 pt away")
    }

    func testWallsBlockSight() {
        // Row 2 is Lantern Alley's lane; row 4 is the avenue. Row 3 cols 7–9 are buildings.
        let inAlley = district.center(of: TileCoord(col: 8, row: 2))
        let onAvenue = VehicleState(position: district.center(of: TileCoord(col: 8, row: 5)), heading: .pi / 2)
        XCTAssertFalse(PatrolBrain.lineOfSight(from: onAvenue.position, to: inAlley, district: district))
        XCTAssertFalse(PatrolBrain.canSee(onAvenue, target: inAlley, district: district))
    }

    // MARK: Patrol modes

    func makePatrol(at p: Vec2, heading: Double, mode: PatrolMode = .cruise) -> Patrol {
        var patrol = Patrol(id: 0, car: VehicleState(position: p, heading: heading))
        patrol.mode = mode
        return patrol
    }

    func testCruiserIgnoresAPlayerWithNoHeat() {
        var patrol = makePatrol(at: avenue(5), heading: 0)
        var rng = SplitMix64(seed: 3)
        let player = VehicleState(position: avenue(8))
        let saw = PatrolBrain.step(&patrol, player: player, heatStars: 0, district: district, rng: &rng, dt: dt)
        XCTAssertTrue(saw)
        XCTAssertEqual(patrol.mode, .cruise)
    }

    func testCruiserChasesAWantedPlayerItSees() {
        var patrol = makePatrol(at: avenue(5), heading: 0)
        var rng = SplitMix64(seed: 3)
        let player = VehicleState(position: avenue(8))
        _ = PatrolBrain.step(&patrol, player: player, heatStars: 1, district: district, rng: &rng, dt: dt)
        XCTAssertEqual(patrol.mode, .chase)
        XCTAssertEqual(patrol.lastSeen, player.position)
    }

    func testChaseTurnsIntoSearchThenCruiseOnceThePlayerIsGone() {
        var patrol = makePatrol(at: avenue(5), heading: 0, mode: .chase)
        patrol.lastSeen = avenue(6)
        var rng = SplitMix64(seed: 3)
        // Player hidden in the alley behind buildings.
        let hidden = VehicleState(position: district.center(of: TileCoord(col: 8, row: 2)))
        var sawModes: Set<PatrolMode> = []
        for _ in 0..<(60 * 10) {
            _ = PatrolBrain.step(&patrol, player: hidden, heatStars: 2, district: district, rng: &rng, dt: dt)
            sawModes.insert(patrol.mode)
        }
        XCTAssertTrue(sawModes.contains(.search))
        XCTAssertEqual(patrol.mode, .cruise, "gives up after searching the last-seen spot")
    }

    func testChasingPatrolDropsTheChaseWhenHeatIsGone() {
        var patrol = makePatrol(at: avenue(5), heading: 0, mode: .chase)
        var rng = SplitMix64(seed: 3)
        _ = PatrolBrain.step(&patrol, player: VehicleState(position: avenue(8)), heatStars: 0,
                             district: district, rng: &rng, dt: dt)
        XCTAssertEqual(patrol.mode, .cruise)
    }

    func testAChasingPatrolClosesTheGap() {
        var patrol = makePatrol(at: avenue(3), heading: 0, mode: .chase)
        var rng = SplitMix64(seed: 3)
        let player = VehicleState(position: avenue(9))
        let before = (patrol.car.position - player.position).length
        for _ in 0..<90 {
            _ = PatrolBrain.step(&patrol, player: player, heatStars: 2, district: district, rng: &rng, dt: dt)
        }
        XCTAssertLessThan((patrol.car.position - player.position).length, before - 250)
    }

    func testCruisersStayOnDrivableGround() {
        var pursuit = Pursuit(district: district, player: VehicleState(position: avenue(12)), seed: 9)
        var player = VehicleState(position: avenue(12))
        for _ in 0..<(60 * 30) {
            _ = pursuit.step(player: &player, dt: dt)
        }
        for p in pursuit.patrols {
            XCTAssertFalse(district.tile(at: p.car.position).isSolid, "patrol \(p.id) drove into a wall")
        }
    }

    // MARK: Pursuit

    func testCalmDistrictHasTwoCruisers() {
        let pursuit = Pursuit(district: district, player: VehicleState(position: avenue(12)), seed: 1)
        XCTAssertEqual(pursuit.patrols.count, 2)
        XCTAssertTrue(pursuit.patrols.allSatisfy { $0.mode == .cruise })
        for p in pursuit.patrols {
            XCTAssertGreaterThanOrEqual((p.car.position - avenue(12)).length, Pursuit.spawnMinDistance)
        }
    }

    func testHotStartSendsUnitsToThePlayer() {
        let start = VehicleState(position: avenue(12))
        let pursuit = Pursuit(district: district, player: start, startingHeat: 55, seed: 1)  // 3 stars
        XCTAssertEqual(pursuit.patrols.count, 3)
        XCTAssertTrue(pursuit.patrols.allSatisfy { $0.mode == .search && $0.lastSeen == start.position })
        XCTAssertEqual(pursuit.dispatchTime, Pursuit.hotStartDispatch)
    }

    func testDispatchTracksTheLivePlayerAndHoldsTheHeat() {
        var player = VehicleState(position: avenue(12))
        var pursuit = Pursuit(district: district, player: player, startingHeat: 35, seed: 1)
        // The player drives off somewhere else; dispatch keeps feeding the new position.
        player.position = district.center(of: TileCoord(col: 2, row: 19))
        for _ in 0..<(60 * 8) { _ = pursuit.step(player: &player, dt: dt) }
        XCTAssertGreaterThanOrEqual(pursuit.heat.points, 35, "heat can't cool during a dispatch fix")
        XCTAssertTrue(pursuit.patrols.allSatisfy { $0.mode == .chase && $0.lastSeen == player.position })
    }

    func testAHotEscapeCantBeWonQuickly() {
        // Fastest possible cool-down from the escape's start, never seen by anyone after dispatch:
        // 10 s dispatch + 4 s grace + (35 − 10) / 8 s of decay.
        var heat = HeatState(points: MissionDef.tideLineRun.startingHeat)
        var t = 0.0
        while heat.stars > 0 {
            let dispatching = t < Pursuit.hotStartDispatch
            heat = HeatSystem.step(heat, dt: dt, seen: dispatching, inRestricted: false, inSafehouse: false)
            t += dt
        }
        XCTAssertGreaterThan(t, 17)
    }

    func testGainingAStarCallsInABriefDispatch() {
        var player = VehicleState(position: avenue(12))
        var pursuit = Pursuit(district: district, player: player, seed: 6)
        XCTAssertEqual(pursuit.dispatchTime, 0)
        pursuit.add(.missionEvent(12))
        XCTAssertEqual(pursuit.dispatchTime, Pursuit.newStarDispatch)
        _ = pursuit.step(player: &player, dt: dt)
        XCTAssertTrue(pursuit.patrols.allSatisfy { $0.mode == .chase })
    }

    func testMoreStarsBringMoreUnitsUpToFive() {
        var player = VehicleState(position: avenue(12))
        var pursuit = Pursuit(district: district, player: player, seed: 4)
        for _ in 0..<(60 * 6) {
            pursuit.heat.points = 95  // hold 5 stars
            _ = pursuit.step(player: &player, dt: dt)
        }
        XCTAssertEqual(pursuit.patrols.count, Pursuit.maxPatrols)
    }

    func testStoppingNextToAChasingPatrolGetsYouBusted() {
        var player = VehicleState(position: avenue(12))
        var pursuit = Pursuit(district: district, player: player, startingHeat: 35, seed: 2)
        var cop = Patrol(id: 99, car: VehicleState(position: avenue(12) + Vec2(-60, 0), heading: 0))
        cop.mode = .chase
        pursuit.patrols = [cop]
        var events: [PursuitEvent] = []
        var t = 0.0
        while !pursuit.isBusted && t < 10 {
            events += pursuit.step(player: &player, dt: dt)
            player.velocity = .zero  // the player isn't moving
            t += dt
        }
        XCTAssertTrue(pursuit.isBusted)
        XCTAssertTrue(events.contains(.busted))
        XCTAssertEqual(t, Pursuit.bustSeconds, accuracy: 0.5)
    }

    func testDrivingAwayDrainsTheBustMeter() {
        var player = VehicleState(position: avenue(12))
        var pursuit = Pursuit(district: district, player: player, startingHeat: 35, seed: 2)
        var cop = Patrol(id: 99, car: VehicleState(position: avenue(12) + Vec2(-60, 0), heading: 0))
        cop.mode = .chase
        pursuit.patrols = [cop]
        for _ in 0..<60 {
            _ = pursuit.step(player: &player, dt: dt)
            player.velocity = .zero
        }
        XCTAssertGreaterThan(pursuit.bustProgress, 0.5)
        // Now it pulls away fast.
        player.position = avenue(20)
        for _ in 0..<60 {
            player.velocity = Vec2(400, 0)
            _ = pursuit.step(player: &player, dt: dt)
        }
        XCTAssertEqual(pursuit.bustProgress, 0, accuracy: 0.01)
        XCTAssertFalse(pursuit.isBusted)
    }

    func testRammingAPatrolAddsHeat() {
        var player = VehicleState(position: avenue(12), heading: .pi, velocity: Vec2(-300, 0))
        var pursuit = Pursuit(district: district, player: player, seed: 5)
        pursuit.patrols = [Patrol(id: 7, car: VehicleState(position: avenue(12) + Vec2(-25, 0), heading: 0))]
        let events = pursuit.step(player: &player, dt: dt)
        XCTAssertTrue(events.contains(where: Self.isContact))
        XCTAssertGreaterThanOrEqual(pursuit.heat.points, HeatRules.patrolHit)
        XCTAssertEqual(pursuit.patrols[0].mode, .chase)
    }

    func testBeingRammedByAPatrolAddsNoHeat() {
        var player = VehicleState(position: avenue(12))
        var pursuit = Pursuit(district: district, player: player, seed: 5)
        // Patrol driving into a stationary player.
        pursuit.patrols = [Patrol(id: 7, car: VehicleState(position: avenue(12) + Vec2(-25, 0), heading: 0,
                                                           velocity: Vec2(300, 0)))]
        let events = pursuit.step(player: &player, dt: dt)
        XCTAssertTrue(events.contains(where: Self.isContact))
        XCTAssertEqual(pursuit.heat.points, 0)
    }

    func testChasersPinAStoppedPlayerInsteadOfRammingIt() {
        var player = VehicleState(position: avenue(14))
        var pursuit = Pursuit(district: district, player: player, startingHeat: 35, seed: 3)
        var cop = Patrol(id: 1, car: VehicleState(position: avenue(8), heading: 0))
        cop.mode = .chase
        pursuit.patrols = [cop]
        var hardest = 0.0
        for _ in 0..<(60 * 4) where !pursuit.isBusted {
            for case .patrolContact(let impact) in pursuit.step(player: &player, dt: dt) {
                hardest = max(hardest, impact)
            }
            player.velocity = .zero
        }
        XCTAssertLessThan(hardest, 150, "a stopped player gets pinned, not rammed")
        XCTAssertLessThan((pursuit.patrols[0].car.position - player.position).length, Pursuit.bustDistance)
    }

    static func isContact(_ event: PursuitEvent) -> Bool {
        if case .patrolContact = event { return true }
        return false
    }

    func testStarsChangedIsReported() {
        var player = VehicleState(position: avenue(12))
        var pursuit = Pursuit(district: district, player: player, seed: 6)
        XCTAssertEqual(pursuit.add(.missionEvent(12)), [.starsChanged(from: 0, to: 1)])
        XCTAssertEqual(pursuit.add(.wallHit), [])
        _ = pursuit.step(player: &player, dt: dt)
    }

    func testSafehouseWipesHeatAndEndsTheChase() {
        let safe = district.zones[.safehouse]!.rect.center
        var player = VehicleState(position: safe)
        var pursuit = Pursuit(district: district, player: player, startingHeat: 80, seed: 8)
        let events = pursuit.step(player: &player, dt: dt)
        XCTAssertEqual(pursuit.heat.stars, 0)
        XCTAssertTrue(events.contains(.starsChanged(from: 4, to: 0)))
    }
}
