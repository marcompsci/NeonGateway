import XCTest
@testable import GameCore

final class StateJobsTests: XCTestCase {
    let d = SolaraState.district
    let dt = VehicleDynamics.fixedStep

    func city(at depot: ZoneID, vehicle: VehicleID? = .vesper) -> City {
        let start = SpawnPoint(position: d.zones[depot]!.rect.center, heading: .pi / 2)
        return City(district: d, start: start, playerVehicle: vehicle, seed: 3,
                    parked: [], pickups: [], dealer: nil)
    }

    func testEveryDepotHasCourierCityRunAndFreight() {
        for depot in ZoneID.stateDepots {
            let board = StateJobs.board(at: depot, seed: 1)
            XCTAssertTrue(board.contains { $0.kind == .courier }, "\(depot)")
            XCTAssertTrue(board.contains { $0.kind == .intercity })
            XCTAssertTrue(board.contains { $0.kind == .freight })
            XCTAssertTrue(board.allSatisfy { $0.from == depot && $0.to != depot })
            XCTAssertTrue(board.filter { $0.kind != .courier }.allSatisfy { ZoneID.stateDepots.contains($0.to) })
            XCTAssertEqual(board, StateJobs.board(at: depot, seed: 1), "same seed, same board")
        }
    }

    func testFreightPaysMostAndLongerTripsPayMore() {
        let board = StateJobs.board(at: .depotAurora, seed: 7)
        let freight = board.filter { $0.kind == .freight }.map(\.pay).max()!
        let courier = board.first { $0.kind == .courier }!.pay
        XCTAssertGreaterThan(freight, courier * 2)
        XCTAssertTrue(board.filter { $0.kind == .freight }.allSatisfy { $0.timeLimit == nil })
        XCTAssertTrue(board.filter { $0.kind != .freight }.allSatisfy { $0.timeLimit != nil })
        let jobs = board.sorted { $0.distance < $1.distance }
        let sameKind = jobs.filter { $0.kind == .freight }
        if sameKind.count == 2 { XCTAssertLessThan(sameKind[0].pay, sameKind[1].pay) }
    }

    func testFreightLendsARigAndDeliveringLeavesACarAndABike() throws {
        var c = city(at: .depotAurora)
        var runner = StateJobRunner()
        let job = StateJobs.board(at: .depotAurora, seed: 2).first { $0.kind == .freight }!
        _ = runner.accept(job, city: &c)
        XCTAssertEqual(c.currentVehicle?.model, .hauler, "behind the wheel of the rig")
        let rig = c.currentVehicleIndex!
        // Teleport to the destination yard (the autopilot test below drives a real haul).
        c.teleport(to: d.zones[job.to]!.rect.center, heading: 0)
        let events = runner.step(city: &c, dt: dt)
        guard case .delivered(_, let payout)? = events.first else { return XCTFail("not delivered: \(events)") }
        XCTAssertEqual(payout.credits, job.pay)
        XCTAssertTrue(events.contains(.rideHomeReady))
        XCTAssertTrue(c.vehicles[rig].retired, "rig handed back")
        XCTAssertTrue(c.isOnFoot)
        let parked = c.vehicles.suffix(2).map(\.model)
        XCTAssertEqual(Set(parked), [.dorado, .flicker], "car and bike for the drive home")
        XCTAssertNil(runner.active)
        if case .ammo(let w, _) = job.reward { XCTAssertTrue(c.inventory.owns(w), "product crate delivered") }
    }

    func testFreightNeedsTheRig() {
        var c = city(at: .depotAurora)
        var runner = StateJobRunner()
        let job = StateJobs.board(at: .depotAurora, seed: 2).first { $0.kind == .freight }!
        _ = runner.accept(job, city: &c)
        _ = c.step(input: .idle, actions: CityActions(enterExit: true), dt: dt)   // get out
        XCTAssertTrue(c.isOnFoot)
        c.teleport(to: d.zones[job.to]!.rect.center, heading: 0)
        let events = runner.step(city: &c, dt: dt)
        XCTAssertEqual(events, [.needTruck], "on foot at the yard doesn't count")
        XCTAssertNotNil(runner.active)
    }

    func testTimedJobsFailWhenTheClockRunsOut() {
        var c = city(at: .depotRedwood)
        var runner = StateJobRunner()
        let job = StateJobs.board(at: .depotRedwood, seed: 4).first { $0.kind == .courier }!
        _ = runner.accept(job, city: &c)
        var events: [StateJobEvent] = []
        for _ in 0..<Int((job.timeLimit! + 1) / 0.5) { events += runner.step(city: &c, dt: 0.5) }
        XCTAssertTrue(events.contains { if case .failed = $0 { return true } else { return false } })
        XCTAssertNil(runner.active)
    }

    func testRigDamageCutsThePay() {
        var c = city(at: .depotAurora)
        var runner = StateJobRunner()
        let job = StateJobs.board(at: .depotAurora, seed: 2).first { $0.kind == .freight }!
        _ = runner.accept(job, city: &c)
        c.vehicles[c.currentVehicleIndex!].damage = 4
        c.teleport(to: d.zones[job.to]!.rect.center, heading: 0)
        guard case .delivered(_, let payout)? = runner.step(city: &c, dt: dt).first else { return XCTFail() }
        XCTAssertEqual(payout.damageCut, 4 * job.pay / 20)
        XCTAssertEqual(payout.credits, job.pay - payout.damageCut)
    }

    /// A whole haul down the real highway with the autopilot at the wheel of the rig.
    func testAutopilotCanHaulFreightBetweenCities() {
        var c = city(at: .depotAurora)
        var runner = StateJobRunner()
        let job = StateJobs.board(at: .depotAurora, seed: 2).first { $0.kind == .freight }!
        _ = runner.accept(job, city: &c)
        c.pursuit.patrols = []
        var pilot = Autopilot(district: d, from: c.player.position, to: d.zones[job.to]!.rect.center)!
        var delivered = false
        var seconds = 0.0
        while seconds < 400 && !delivered {
            var body = c.player
            let input = pilot.input(for: body, dt: dt)
            body = c.player
            _ = c.step(input: input, actions: .init(), dt: dt)
            c.pursuit.patrols = []
            for e in runner.step(city: &c, dt: dt) { if case .delivered = e { delivered = true } }
            seconds += dt
        }
        XCTAssertTrue(delivered, "rig reached \(job.to) (\(Int(seconds)) s)")
        XCTAssertGreaterThan(seconds, 40, "a long haul, not a hop")
    }
}
