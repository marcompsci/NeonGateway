import XCTest
@testable import GameCore

final class SolaraStateTests: XCTestCase {
    let d = SolaraState.district

    func testTheStateIsBigWithSixCitiesAndTenLandmarkStops() {
        XCTAssertEqual(d.cols, 300)
        XCTAssertEqual(d.rows, 220)
        XCTAssertTrue(d.isLarge)
        XCTAssertEqual(SolaraState.cities.count, 6)
        XCTAssertEqual(Set(SolaraState.cities.map(\.depot)), Set(ZoneID.stateDepots))
        for id in ZoneID.stateDepots + ZoneID.stateLandmarks {
            XCTAssertNotNil(d.zones[id], "\(id) zone missing")
        }
        XCTAssertEqual(Set(SolaraState.landmarks.map(\.zone)), Set(ZoneID.stateLandmarks))
        XCTAssertEqual(Set(SolaraState.landmarks.map(\.id)).count, SolaraState.landmarks.count, "art ids unique")
    }

    func testHighwaysBridgesAndCountryAreAllThere() {
        let kinds = Set(d.tiles)
        for k: TileKind in [.highway, .bridge, .grass, .sand, .forest, .rock, .landmark, .water, .road, .building] {
            XCTAssertTrue(kinds.contains(k), "no \(k) tiles")
        }
        // The Crimson Span crosses the bay on the Coast Highway.
        XCTAssertEqual(d.tile(TileCoord(col: 16, row: 78)), .bridge)
        XCTAssertGreaterThan(d.roadTiles.count, 4000)
    }

    func testEveryDepotAndStopCanBeDrivenToFromTheStart() {
        let start = d.coord(at: SolaraState.start.position)
        XCTAssertFalse(d.tile(start).isSolid, "start is on open ground")
        for zone in d.zones.values {
            let target = d.coord(at: zone.rect.center)
            XCTAssertFalse(d.tile(target).isSolid, "\(zone.id) centre is solid")
            XCTAssertNotNil(d.drivingRoute(from: start, to: target), "can't drive to \(zone.id)")
        }
    }

    func testCitiesAreFarApartSoTripsTakeAWhile() {
        let aurora = d.zones[.depotAurora]!.rect.center
        let cinder = d.zones[.depotCinder]!.rect.center
        XCTAssertGreaterThan((cinder - aurora).length, 20_000, "Port Aurora → Cinder Flats is a real drive")
        let route = d.drivingRoute(from: d.coord(at: aurora), to: d.coord(at: cinder))!
        let onRoad = route.filter { d.tile($0).isRoad || d.tile($0) == .safehouse }.count
        XCTAssertGreaterThan(Double(onRoad) / Double(route.count), 0.9, "the route sticks to the highway")
    }

    func testNearbyRoadLookupFindsOnlyLocalRoads() {
        let p = d.zones[.depotCinder]!.rect.center
        let near = d.roadTiles(near: p, radius: 1500)
        XCTAssertFalse(near.isEmpty)
        XCTAssertTrue(near.allSatisfy { (d.center(of: $0) - p).length < 1500 + 16 * 128 * 1.5 })
    }

    func testRouteFindingIsQuickOnTheBigMap() {
        let a = d.coord(at: d.zones[.depotStarline]!.rect.center)
        let b = d.coord(at: d.zones[.depotSteamvale]!.rect.center)
        let t0 = Date()
        XCTAssertNotNil(d.drivingRoute(from: a, to: b))
        // 0.3 s optimised; an unoptimised test build on a busy Mac can be ~100× slower.
        #if DEBUG
        let limit = 120.0
        #else
        let limit = 5.0
        #endif
        XCTAssertLessThan(Date().timeIntervalSince(t0), limit, "corner to corner")
    }

    func testCrowdAndPatrolsStayNearThePlayerOnTheBigMap() {
        var city = City(district: d, start: SolaraState.start, playerVehicle: .vesper, seed: 4,
                        parked: SolaraState.parked, pickups: SolaraState.pickups, dealer: nil)
        let p = city.player.position
        XCTAssertTrue(city.crowd.people.allSatisfy { ($0.position - p).length < 5000 }, "walkers start nearby")
        city.pursuit.heat.points = 40
        for _ in 0..<600 { _ = city.step(input: .idle, actions: .init(), dt: VehicleDynamics.fixedStep) }
        XCTAssertFalse(city.pursuit.patrols.isEmpty)
        XCTAssertTrue(city.pursuit.patrols.allSatisfy { ($0.car.position - p).length < 6000 }, "cruisers come from nearby")
    }
}
