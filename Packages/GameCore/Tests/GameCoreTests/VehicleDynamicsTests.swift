import XCTest
@testable import GameCore

final class VehicleDynamicsTests: XCTestCase {
    let spec = VehicleSpec.vesper
    let dt = VehicleDynamics.fixedStep

    func run(_ state: VehicleState, _ input: VehicleInput, seconds: Double) -> VehicleState {
        var s = state
        for _ in 0..<Int((seconds / dt).rounded()) {
            s = VehicleDynamics.step(s, input: input, spec: spec, dt: dt)
        }
        return s
    }

    func testFullThrottleReachesButNeverExceedsTopSpeed() {
        let s = run(VehicleState(), VehicleInput(throttle: 1), seconds: 4)
        XCTAssertEqual(s.forwardSpeed, spec.maxSpeed, accuracy: 0.001)
        let later = run(s, VehicleInput(throttle: 1), seconds: 2)
        XCTAssertLessThanOrEqual(later.speed, spec.maxSpeed + 0.001)
    }

    func testCarMovesInTheDirectionItFaces() {
        let start = VehicleState(position: .zero, heading: .pi / 2)  // facing +y
        let s = run(start, VehicleInput(throttle: 1), seconds: 1)
        XCTAssertGreaterThan(s.position.y, 100)
        XCTAssertEqual(s.position.x, 0, accuracy: 0.001)
    }

    func testBrakeStopsTheCarThenReversesUpToCap() {
        let moving = run(VehicleState(), VehicleInput(throttle: 1), seconds: 2)
        let stopped = run(moving, VehicleInput(brake: 1), seconds: 0.6)
        XCTAssertLessThan(stopped.forwardSpeed, moving.forwardSpeed * 0.5)

        let reversing = run(moving, VehicleInput(brake: 1), seconds: 5)
        XCTAssertLessThan(reversing.forwardSpeed, 0, "holding brake at a stop should reverse")
        XCTAssertGreaterThanOrEqual(reversing.forwardSpeed, -spec.reverseMaxSpeed - 0.001)
    }

    func testCoastingSlowsToAStop() {
        let moving = run(VehicleState(), VehicleInput(throttle: 1), seconds: 2)
        let coasted = run(moving, .idle, seconds: 6)
        XCTAssertEqual(coasted.speed, 0, accuracy: 0.001)
    }

    func testNoSpinInPlaceAtRest() {
        let start = VehicleState(heading: 0.3)
        let s = run(start, VehicleInput(steer: 1), seconds: 2)
        XCTAssertEqual(s.heading, 0.3, accuracy: 0.0001)
        XCTAssertEqual(s.position, .zero)
    }

    func testSteerRightTurnsClockwise() {
        let moving = run(VehicleState(heading: .pi / 2), VehicleInput(throttle: 1), seconds: 1)
        let turned = run(moving, VehicleInput(throttle: 1, steer: 1), seconds: 0.3)
        XCTAssertLessThan(turned.heading, moving.heading, "steering right should decrease heading")
        XCTAssertGreaterThan(turned.position.x, moving.position.x, "car should drift toward +x")
    }

    func testReversingFlipsSteering() {
        let reversing = run(VehicleState(heading: .pi / 2), VehicleInput(brake: 1), seconds: 2)
        let turned = run(reversing, VehicleInput(brake: 1, steer: 1), seconds: 0.3)
        XCTAssertGreaterThan(turned.heading, reversing.heading)
    }

    func testDriftKeepsMoreSidewaysSlideThanGrip() {
        let fast = run(VehicleState(), VehicleInput(throttle: 1), seconds: 3)
        let grip = run(fast, VehicleInput(throttle: 1, steer: 1), seconds: 0.5)
        let drift = run(fast, VehicleInput(throttle: 1, steer: 1, drift: true), seconds: 0.5)
        XCTAssertGreaterThan(abs(drift.sidewaysSpeed), abs(grip.sidewaysSpeed) * 2)
        XCTAssertTrue(drift.isDrifting)
        XCTAssertGreaterThan(drift.driftScore, 0)
    }

    func testNormalCorneringIsNotScoredAsDrift() {
        let fast = run(VehicleState(), VehicleInput(throttle: 1), seconds: 3)
        let grip = run(fast, VehicleInput(throttle: 1, steer: 1), seconds: 0.5)
        XCTAssertFalse(grip.isDrifting)
        XCTAssertEqual(grip.driftScore, 0)
    }

    func testRoughlyFrameRateIndependent() {
        var a = VehicleState(), b = VehicleState()
        let input = VehicleInput(throttle: 1, steer: 0.5)
        for _ in 0..<120 { a = VehicleDynamics.step(a, input: input, spec: spec, dt: 1.0 / 60) }
        for _ in 0..<240 { b = VehicleDynamics.step(b, input: input, spec: spec, dt: 1.0 / 120) }
        XCTAssertLessThan((a.position - b.position).length, 25)
    }

    func testInputIsClamped() {
        let wild = run(VehicleState(), VehicleInput(throttle: 9, steer: -40), seconds: 4)
        XCTAssertLessThanOrEqual(wild.speed, spec.maxSpeed + 0.001)
    }

    func testHeadingStaysNormalized() {
        let fast = run(VehicleState(), VehicleInput(throttle: 1), seconds: 2)
        let spun = run(fast, VehicleInput(throttle: 1, steer: 1), seconds: 10)
        XCTAssertLessThanOrEqual(abs(spun.heading), .pi + 0.0001)
    }
}
