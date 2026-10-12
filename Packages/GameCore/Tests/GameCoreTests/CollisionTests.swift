import XCTest
@testable import GameCore

final class CollisionTests: XCTestCase {
    let wall = Rect(x: 100, y: -500, width: 50, height: 1000)

    func testNoContactLeavesStateUnchanged() {
        let s = VehicleState(position: Vec2(0, 0), velocity: Vec2(100, 0))
        let r = Collision.resolve(s, radius: 15, solids: [wall])
        XCTAssertFalse(r.hit)
        XCTAssertEqual(r.state, s)
    }

    func testHittingAWallPushesOutAndBounces() {
        let s = VehicleState(position: Vec2(90, 0), velocity: Vec2(300, 0))
        let r = Collision.resolve(s, radius: 15, solids: [wall], restitution: 0.5)
        XCTAssertTrue(r.hit)
        XCTAssertEqual(r.impactSpeed, 300, accuracy: 0.001)
        XCTAssertEqual(r.state.position.x, 85, accuracy: 0.001)
        XCTAssertEqual(r.state.velocity.x, -150, accuracy: 0.001)
    }

    func testSlidingAlongAWallKeepsParallelSpeed() {
        let s = VehicleState(position: Vec2(90, 0), velocity: Vec2(50, 400))
        let r = Collision.resolve(s, radius: 15, solids: [wall], restitution: 0)
        XCTAssertEqual(r.state.velocity.y, 400, accuracy: 0.001)
        XCTAssertEqual(r.state.velocity.x, 0, accuracy: 0.001)
    }

    func testMovingAwayIsNotAnImpact() {
        let s = VehicleState(position: Vec2(90, 0), velocity: Vec2(-200, 0))
        let r = Collision.resolve(s, radius: 15, solids: [wall])
        XCTAssertFalse(r.hit)
        XCTAssertEqual(r.state.position.x, 85, accuracy: 0.001, "still pushed out of overlap")
    }

    func testCentreInsideRectIsPushedOutShortestWay() {
        let s = VehicleState(position: Vec2(105, 0), velocity: .zero)
        let r = Collision.resolve(s, radius: 15, solids: [wall])
        XCTAssertLessThanOrEqual(r.state.position.x, 85.001)
    }

    func testCarStaysInsideTheTestLot() {
        let lot = TestLot.standard
        var s = VehicleState(position: lot.spawn, heading: -.pi / 2)  // facing the bottom wall
        for _ in 0..<600 {
            s = VehicleDynamics.step(s, input: VehicleInput(throttle: 1), spec: .vesper,
                                     dt: VehicleDynamics.fixedStep)
            s = Collision.resolve(s, radius: VehicleSpec.vesper.radius, solids: lot.solids).state
        }
        XCTAssertTrue(lot.bounds.contains(s.position))
    }

    func testTestLotSpawnIsClearOfBlocks() {
        let lot = TestLot.standard
        let s = VehicleState(position: lot.spawn)
        XCTAssertFalse(Collision.resolve(s, radius: 15, solids: lot.solids).hit)
        XCTAssertEqual(Collision.resolve(s, radius: 15, solids: lot.solids).state.position, lot.spawn)
    }
}
