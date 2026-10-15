import XCTest
@testable import GameCore

/// v0.12: point-to-drive stick steering, direct on-foot movement, sprint and cruisers that
/// don't flatten runners.
final class ControlFeelTests: XCTestCase {
    private let dt = VehicleDynamics.fixedStep

    private func drive(_ car: inout VehicleState, stick: Vec2, seconds: Double,
                       spec: VehicleSpec = .vesper, brake: Bool = false) {
        var driver = StickDriver()
        for _ in 0..<Int(seconds * 60) {
            let input = driver.input(stick: stick, brake: brake, drift: false, car: car, spec: spec)
            car = VehicleDynamics.step(car, input: input, spec: spec, dt: dt)
        }
    }

    func testStickUpDrivesNorthFromAStandstill() {
        var car = VehicleState(position: .zero, heading: .pi / 2)
        drive(&car, stick: Vec2(0, 1), seconds: 1.5)
        XCTAssertGreaterThan(car.position.y, 200)
        XCTAssertEqual(car.position.x, 0, accuracy: 1)
    }

    func testStickTurnsTheCarToFaceTheStick() {
        // Facing north at speed; push the stick east and the car swings round to head east.
        var car = VehicleState(position: .zero, heading: .pi / 2, velocity: Vec2(0, 300))
        drive(&car, stick: Vec2(1, 0), seconds: 1.5)
        XCTAssertEqual(remainder(car.heading, 2 * .pi), 0, accuracy: 0.15)
        XCTAssertGreaterThan(car.velocity.x, 150)
    }

    func testStickIsScreenAlignedWhicheverWayTheCarFaces() {
        // Facing south (down the screen): pushing left still goes left (west), not the car's left.
        var car = VehicleState(position: .zero, heading: -.pi / 2, velocity: Vec2(0, -250))
        drive(&car, stick: Vec2(-1, 0), seconds: 1.5)
        XCTAssertLessThan(car.position.x, -150)
    }

    func testPullingBackAtSpeedBrakesThenReverses() {
        var car = VehicleState(position: .zero, heading: .pi / 2, velocity: Vec2(0, 400))
        var driver = StickDriver()
        let first = driver.input(stick: Vec2(0, -1), brake: false, drift: false, car: car, spec: .vesper)
        XCTAssertEqual(first.brake, 1)
        XCTAssertEqual(first.throttle, 0)
        drive(&car, stick: Vec2(0, -1), seconds: 2.5)
        // Stopped, then backed up south without spinning round.
        XCTAssertLessThan(car.forwardSpeed, -20)
        XCTAssertEqual(remainder(car.heading - .pi / 2, 2 * .pi), 0, accuracy: 0.3)
    }

    func testCentredStickCoasts() {
        var driver = StickDriver()
        let car = VehicleState(position: .zero, heading: 0, velocity: Vec2(200, 0))
        let input = driver.input(stick: Vec2(0.05, 0), brake: false, drift: false, car: car, spec: .vesper)
        XCTAssertEqual(input.throttle, 0)
        XCTAssertEqual(input.steer, 0)
    }

    func testCarCanTakeARightAngleTurnWithinTwoLanes() {
        // Flat out north, then the stick goes east: the car should be heading east within the
        // width of a two-lane road (256 points) of forward travel.
        var car = VehicleState(position: .zero, heading: .pi / 2, velocity: Vec2(0, VehicleSpec.vesper.maxSpeed))
        var driver = StickDriver()
        var turned = false
        for _ in 0..<180 {
            let input = driver.input(stick: Vec2(1, 0), brake: false, drift: false, car: car, spec: .vesper)
            car = VehicleDynamics.step(car, input: input, spec: .vesper, dt: dt)
            if abs(remainder(car.heading, 2 * .pi)) < 0.2 { turned = true; break }
        }
        XCTAssertTrue(turned)
        XCTAssertLessThan(car.position.y, 256)
    }

    // MARK: On foot

    func testFootStickRunsTheWayItPoints() {
        var body = VehicleState(position: .zero, heading: .pi / 2)
        var stamina = 1.0
        for _ in 0..<60 {
            body = FootDynamics.step(body, input: VehicleInput(move: Vec2(-1, 0)), dt: dt, stamina: &stamina)
        }
        XCTAssertLessThan(body.position.x, -180)
        XCTAssertEqual(body.position.y, 0, accuracy: 2)
        XCTAssertEqual(body.speed, FootDynamics.runSpeed, accuracy: 1)
        XCTAssertEqual(remainder(body.heading - .pi, 2 * .pi), 0, accuracy: 0.01)
    }

    func testFootStopsQuicklyWhenTheStickIsReleased() {
        var body = VehicleState(position: .zero, heading: 0, velocity: Vec2(FootDynamics.runSpeed, 0))
        var stamina = 1.0
        for _ in 0..<12 {
            body = FootDynamics.step(body, input: VehicleInput(move: .zero), dt: dt, stamina: &stamina)
        }
        XCTAssertEqual(body.speed, 0, accuracy: 0.01)
    }

    func testSprintIsFasterAndRunsOutThenRefills() {
        var body = VehicleState(position: .zero, heading: 0)
        var stamina = 1.0
        for _ in 0..<30 {
            body = FootDynamics.step(body, input: VehicleInput(move: Vec2(1, 0), sprint: true), dt: dt, stamina: &stamina)
        }
        XCTAssertEqual(body.speed, FootDynamics.sprintSpeed, accuracy: 1)
        for _ in 0..<Int(FootDynamics.sprintSeconds * 60) {
            body = FootDynamics.step(body, input: VehicleInput(move: Vec2(1, 0), sprint: true), dt: dt, stamina: &stamina)
        }
        for _ in 0..<20 {
            body = FootDynamics.step(body, input: VehicleInput(move: Vec2(1, 0), sprint: true), dt: dt, stamina: &stamina)
        }
        XCTAssertEqual(stamina, 0)
        XCTAssertEqual(body.speed, FootDynamics.runSpeed, accuracy: 1)
        for _ in 0..<Int(FootDynamics.refillSeconds * 60) + 2 {
            body = FootDynamics.step(body, input: VehicleInput(move: .zero), dt: dt, stamina: &stamina)
        }
        XCTAssertEqual(stamina, 1)
    }

    func testRunningIsFasterThanBefore() {
        XCTAssertGreaterThanOrEqual(FootDynamics.runSpeed, 230)
        XCTAssertGreaterThan(FootDynamics.sprintSpeed, PatrolBrain.footChaseSpeed)
        XCTAssertGreaterThan(PatrolBrain.footChaseSpeed, FootDynamics.runSpeed)
    }

    func testCruiserChasingARunnerKeepsUnderTheFootChaseCap() {
        let district = District.portAuroraDocks
        // A straight stretch of Harbor Avenue: patrol behind a runner, both heading east.
        let start = district.center(of: TileCoord(col: 3, row: 4))
        var patrol = Patrol(id: 1, car: VehicleState(position: start, heading: 0, velocity: Vec2(200, 0)))
        patrol.mode = .chase
        var rng = SplitMix64(seed: 3)
        var runner = VehicleState(position: start + Vec2(400, 0), heading: 0, velocity: Vec2(FootDynamics.runSpeed, 0))
        var top = 0.0
        for _ in 0..<120 {
            runner.position += runner.velocity * dt
            _ = PatrolBrain.step(&patrol, player: runner, playerOnFoot: true, heatStars: 3, district: district,
                                 rng: &rng, dt: dt)
            top = max(top, patrol.car.speed)
        }
        XCTAssertLessThanOrEqual(top, PatrolBrain.footChaseSpeed + 30)
    }

    func testCityWalksWithTheStickAndSpendsStamina() {
        var city = City(district: .portAuroraDocks, start: GameCoreSpawns.safehouseRoad, playerVehicle: nil,
                        tuning: UpgradeLevels(), inventory: Inventory(), startingHeat: 0, seed: 1)
        let before = city.foot.position
        for _ in 0..<30 {
            _ = city.step(input: VehicleInput(move: Vec2(1, 0), sprint: true), actions: CityActions(), dt: dt)
        }
        XCTAssertGreaterThan(city.foot.position.x, before.x + 80)
        XCTAssertLessThan(city.stamina, 1)
    }
}
