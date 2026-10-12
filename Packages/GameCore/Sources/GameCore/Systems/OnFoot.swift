import Foundation

/// The player out of the car. Tank-style controls on the same touch pads as driving: the steer
/// strip turns the body, GAS runs forward, BRAKE backs up. No sliding: feet grip.
public enum FootDynamics {
    public static let runSpeed = 190.0
    public static let backSpeed = 80.0
    /// rad/s at full steer; works standing still (unlike a car).
    public static let turnRate = 4.6
    /// points/s² toward the target speed.
    public static let acceleration = 1100.0
    public static let radius = 9.0

    /// Advances the body `dt` seconds. Walls are resolved by the caller.
    public static func step(_ state: VehicleState, input: VehicleInput, dt: Double,
                            speedScale: Double = 1) -> VehicleState {
        var s = state
        let steer = min(max(input.steer, -1), 1)
        s.heading -= steer * turnRate * dt
        s.heading = remainder(s.heading, 2 * .pi)

        let target: Double
        if input.throttle > 0 {
            target = runSpeed * speedScale * min(input.throttle, 1)
        } else if input.brake > 0 {
            target = -backSpeed * min(input.brake, 1)
        } else {
            target = 0
        }
        let current = s.velocity.dot(s.forward)
        let change = acceleration * dt
        let next = current < target ? min(target, current + change) : max(target, current - change)
        s.velocity = s.forward * next
        s.position += s.velocity * dt
        s.isDrifting = false
        return s
    }
}
