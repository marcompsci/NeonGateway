import XCTest
@testable import GameCore

final class ContentValidationTests: XCTestCase {
    let district = District.portAuroraDocks

    func testMapIsTheSizeWeExpect() {
        XCTAssertEqual(district.cols, 24)
        XCTAssertEqual(district.rows, 32)
        XCTAssertEqual(district.tiles.count, 24 * 32)
    }

    func testEveryDrivableTileIsReachableFromTheSafehouse() {
        let safe = district.coord(at: district.zones[.safehouse]!.rect.center)
        let reachable = district.reachable(from: safe)
        let drivable = (0..<district.rows).flatMap { r in
            (0..<district.cols).map { TileCoord(col: $0, row: r) }
        }.filter { !district.tile($0).isSolid }
        XCTAssertEqual(Set(drivable), reachable, "every road, alley and dock tile should connect")
    }

    func testEveryZoneSitsOnDrivableTilesOnly() {
        for zone in district.zones.values {
            let t = district.tileSize
            var y = zone.rect.minY + t / 2
            while y < zone.rect.maxY {
                var x = zone.rect.minX + t / 2
                while x < zone.rect.maxX {
                    XCTAssertFalse(district.tile(at: Vec2(x, y)).isSolid, "\(zone.name) covers a solid tile")
                    x += t
                }
                y += t
            }
        }
    }

    func testEveryMissionStartsOnARoadAndCanReachEachObjective() {
        for def in MissionDef.all {
            let start = district.coord(at: def.start.position)
            XCTAssertFalse(district.tile(start).isSolid, "\(def.title) spawns inside a wall")
            for objective in def.objectives {
                for zoneID in objective.zones {
                    let zone = try! XCTUnwrap(district.zones[zoneID], "\(zoneID) missing")
                    let target = district.coord(at: zone.rect.center)
                    XCTAssertNotNil(district.pathLength(from: start, to: target),
                                    "\(def.title) can't reach \(zone.name)")
                }
            }
        }
    }

    func testSpawnIsClearOfWalls() {
        for def in MissionDef.all {
            let state = VehicleState(position: def.start.position, heading: def.start.heading)
            let solids = district.solids(near: state.position, radius: VehicleSpec.vesper.radius)
            XCTAssertFalse(Collision.resolve(state, radius: VehicleSpec.vesper.radius, solids: solids).hit)
        }
    }

    func testTileLookupMatchesTheMapStrings() {
        // Top-left corner is a building; bottom row is water; row 4 is Harbor Avenue.
        XCTAssertEqual(district.tile(TileCoord(col: 0, row: 0)), .building)
        XCTAssertEqual(district.tile(TileCoord(col: 5, row: 31)), .water)
        XCTAssertEqual(district.tile(TileCoord(col: 5, row: 4)), .road)
        // World point in the lower-left tile is row 31.
        XCTAssertEqual(district.coord(at: Vec2(10, 10)), TileCoord(col: 0, row: 31))
        // Off the map counts as solid.
        XCTAssertTrue(district.tile(TileCoord(col: -1, row: 4)).isSolid)
    }

    func testSolidsNearOnlyReturnsNearbyWalls() {
        let road = district.center(of: TileCoord(col: 12, row: 4))
        XCTAssertTrue(district.solids(near: road, radius: 15).isEmpty)
        let besideBuilding = Vec2(district.rect(of: TileCoord(col: 12, row: 3)).center.x,
                                  district.rect(of: TileCoord(col: 12, row: 4)).maxY - 5)
        XCTAssertEqual(district.solids(near: besideBuilding, radius: 15).count, 1)
    }

    func testNeighborhoodNames() {
        XCTAssertEqual(district.neighborhood(at: district.zones[.lanternAlleyDrop]!.rect.center), "The Alleys")
        XCTAssertEqual(district.neighborhood(at: MissionDef.coldCrate.start.position), "The Docks")
        XCTAssertEqual(district.neighborhood(at: district.center(of: TileCoord(col: 14, row: 13))), "Downtown")
    }

    /// Drives a job with the autopilot through the real physics and walls (no patrols), always
    /// heading for the nearest unfinished target. Returns the finished run and the hard knocks.
    func autopilotRun(_ def: MissionDef, limit: Double = 120) throws -> (MissionRunState, Int) {
        let spec = VehicleSpec.vesper
        var car = VehicleState(position: def.start.position, heading: def.start.heading)
        var run = MissionRunState()
        var hits = 0
        var pilot: Autopilot?
        var pilotTarget: ZoneID?
        let dt = VehicleDynamics.fixedStep
        for _ in 0..<Int(limit * 60) where !run.isFinished {
            let targets = MissionRunner.activeZones(run, def: def)
            let nearest = targets.min {
                (district.zones[$0]!.rect.center - car.position).length < (district.zones[$1]!.rect.center - car.position).length
            }
            if nearest != pilotTarget, let id = nearest {
                pilot = Autopilot(district: district, from: car.position, to: district.zones[id]!.rect.center)
                pilotTarget = id
            }
            let input = pilot?.input(for: car) ?? .idle
            car = VehicleDynamics.step(car, input: input, spec: spec, dt: dt)
            let contact = Collision.resolve(car, radius: spec.radius,
                                            solids: district.solids(near: car.position, radius: spec.radius))
            car = contact.state
            if contact.impactSpeed > 90 { hits += 1 }
            run = MissionRunner.step(run, def: def, district: district, carPosition: car.position, dt: dt).0
        }
        return (run, hits)
    }

    /// A plain line-follower must beat each clock with plenty to spare, or the job is unfair on
    /// a phone (where patrols will also be in the way).
    func testEveryTimedJobIsBeatableWithRoomToSpare() throws {
        for def in MissionDef.all {
            let (run, hits) = try autopilotRun(def)
            XCTAssertEqual(run.outcome, .success, "\(def.title) autopilot didn't finish")
            if let limit = def.timeLimit {
                XCTAssertLessThan(run.clockElapsed, limit * 0.6, "\(def.title): \(run.clockElapsed)s of \(limit)s")
            }
            XCTAssertGreaterThan(run.elapsed, 5, "\(def.title) should not be a few seconds long")
            XCTAssertLessThanOrEqual(hits, 4, "\(def.title) route forces the car into walls")
        }
    }

    func testJobsAreDistinct() {
        XCTAssertEqual(Set(MissionDef.all.map(\.kind)), [.timedDelivery, .escape, .pickupRun, .double])
        XCTAssertEqual(Set(MissionDef.all.map(\.title)).count, MissionDef.all.count)
        XCTAssertEqual(MissionDef.all.map(\.id), MissionID.jobs, "every job is on the map, in order")
        XCTAssertEqual(Set(MissionDef.all.map(\.id)).count, MissionDef.all.count)
        XCTAssertGreaterThan(MissionDef.tideLineRun.startingHeat, HeatRules.starThresholds[0])
        XCTAssertNil(MissionDef.tideLineRun.timeLimit)
        XCTAssertGreaterThan(MissionDef.lanternSweep.pickupHeat, 0)
    }

    func testEscapeStartsInsideTheCustomsYard() {
        XCTAssertTrue(district.zones[.customsYard]!.rect.contains(MissionDef.tideLineRun.start.position))
    }
}
