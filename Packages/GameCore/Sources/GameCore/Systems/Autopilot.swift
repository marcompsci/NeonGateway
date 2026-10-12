import Foundation

/// Point-to-point steering with a recovery move: it brakes for sharp turns, and backs up (a
/// three-point turn) when the target is behind it or the car is stuck against something.
public struct Driver: Sendable {
    /// Optional top speed in points/s (patrols cruise slower than they chase).
    public var speedCap: Double?
    private var reverseTime: Double = 0
    private var stuckTime: Double = 0

    public init(speedCap: Double? = nil) {
        self.speedCap = speedCap
    }

    public mutating func steer(toward target: Vec2, car: VehicleState, dt: Double) -> VehicleInput {
        let toTarget = target - car.position
        let error = remainder(atan2(toTarget.y, toTarget.x) - car.heading, 2 * .pi)
        let speed = car.speed

        if reverseTime <= 0 && ((abs(error) > 2.4 && speed < 80) || stuckTime > 0.8) {
            reverseTime = 0.9
            stuckTime = 0
        }
        if reverseTime > 0 {
            reverseTime -= dt
            // Reversing flips steering, so steer the other way to swing the nose round.
            return VehicleInput(throttle: 0, brake: 1, steer: min(max(error * 2.5, -1), 1))
        }
        stuckTime = speed < 40 ? stuckTime + dt : 0

        let sharpTurn = abs(error) > 0.5 && speed > 230
        let overCap = speedCap.map { speed > $0 } ?? false
        // Well over the cap and still rolling forward: brake, don't just coast.
        let wayOverCap = speedCap.map { car.forwardSpeed > $0 + 30 } ?? false
        return VehicleInput(throttle: sharpTurn || overCap ? 0 : 1, brake: sharpTurn || wayOverCap ? 1 : 0,
                            steer: min(max(-error * 2.5, -1), 1))
    }
}

/// A route-follower. Unit tests use it to check jobs are fair, debug builds use it to drive the
/// app hands-free, and patrol cars use it to get around. The route keeps off the walls.
public struct Autopilot: Sendable {
    public let waypoints: [Vec2]
    public private(set) var index = 0
    public var driver: Driver

    public init?(district: District, from start: Vec2, to target: Vec2, speedCap: Double? = nil) {
        guard let route = district.drivingRoute(from: district.coord(at: start), to: district.coord(at: target)),
              !route.isEmpty else { return nil }
        waypoints = route.map { district.center(of: $0) }
        driver = Driver(speedCap: speedCap)
    }

    public var isFinished: Bool { index >= waypoints.count - 1 }
    public var destination: Vec2 { waypoints[waypoints.count - 1] }

    public mutating func input(for car: VehicleState, dt: Double = VehicleDynamics.fixedStep) -> VehicleInput {
        while index < waypoints.count - 1 && (waypoints[index] - car.position).length < 110 {
            index += 1
        }
        // Arrived: stop rather than circle the last waypoint. (Brake only while rolling forward:
        // holding brake at a stop would reverse.)
        if index == waypoints.count - 1 && (destination - car.position).length < 70 {
            return car.forwardSpeed > 15 ? VehicleInput(brake: 1) : .idle
        }
        var target = waypoints[index]
        if index < waypoints.count - 1 && (waypoints[index] - car.position).length < 200 {
            target = waypoints[index + 1]
        }
        return driver.steer(toward: target, car: car, dt: dt)
    }
}
