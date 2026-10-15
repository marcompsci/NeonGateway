import Foundation

/// The player out of the car.
///
/// Two control styles share this body:
/// - **Stick** (the default): the body runs the way the stick points, at a speed set by how far
///   it's pushed, and turns to face that way almost at once. SPRINT burns stamina for a burst.
/// - **Classic**: tank-style on the old pads (the steer strip turns, GAS runs, BRAKE backs up).
///
/// Feet grip: no sliding, but a short ramp up and down so starts and stops don't snap.
public enum FootDynamics {
    public static let runSpeed = 235.0
    /// SPRINT with stamina left: quick enough to make a gap on a cruiser crawling after you.
    public static let sprintSpeed = 340.0
    public static let backSpeed = 90.0
    /// Classic: rad/s at full steer; works standing still (unlike a car).
    public static let turnRate = 5.2
    /// Stick: how quickly the body swings round to face the stick (rad/s).
    public static let stickTurnRate = 18.0
    /// points/s² toward the target velocity.
    public static let acceleration = 1500.0
    public static let radius = 9.0

    /// Seconds of sprint on a full tank, and seconds to refill it from empty.
    public static let sprintSeconds = 3.2
    public static let refillSeconds = 4.5
    /// Below this stick push the body stops.
    public static let deadZone = 0.14

    /// Advances the body `dt` seconds. Walls are resolved by the caller. `stamina` (0...1) is
    /// spent while sprinting and refilled otherwise.
    public static func step(_ state: VehicleState, input: VehicleInput, dt: Double,
                            speedScale: Double = 1, stamina: inout Double) -> VehicleState {
        var s = state
        var sprinting = false
        let target: Vec2
        if let move = input.move {
            let push = min(1, move.length)
            if push < deadZone {
                target = .zero
            } else {
                let amount = min(1, (push - deadZone) / (0.8 - deadZone))
                let wanted = atan2(move.y, move.x)
                let error = remainder(wanted - s.heading, 2 * .pi)
                let turn = stickTurnRate * dt
                s.heading = abs(error) <= turn ? wanted : s.heading + (error > 0 ? turn : -turn)
                s.heading = remainder(s.heading, 2 * .pi)
                sprinting = input.sprint && stamina > 0 && amount > 0.5
                let top = (sprinting ? sprintSpeed : runSpeed) * speedScale
                // Run the way the stick points, not where the body faces mid-turn, so dodging works.
                target = Vec2.unit(wanted) * (top * max(0.35, amount))
            }
        } else {
            let steer = min(max(input.steer, -1), 1)
            s.heading -= steer * turnRate * dt
            s.heading = remainder(s.heading, 2 * .pi)
            if input.throttle > 0 {
                sprinting = input.sprint && stamina > 0
                let top = (sprinting ? sprintSpeed : runSpeed) * speedScale
                target = s.forward * (top * min(input.throttle, 1))
            } else if input.brake > 0 {
                target = s.forward * (-backSpeed * min(input.brake, 1))
            } else {
                target = .zero
            }
        }

        if sprinting {
            stamina = max(0, stamina - dt / sprintSeconds)
        } else if input.sprint && stamina <= 0 {
            // Winded: still holding SPRINT on an empty tank. Let go of it to get your breath back.
        } else {
            stamina = min(1, stamina + dt / refillSeconds)
        }

        let delta = target - s.velocity
        let change = acceleration * dt
        let gap = delta.length
        s.velocity = gap <= change ? target : s.velocity + delta * (change / gap)
        s.position += s.velocity * dt
        s.isDrifting = false
        return s
    }

    /// Without stamina tracking (a full tank every step).
    public static func step(_ state: VehicleState, input: VehicleInput, dt: Double,
                            speedScale: Double = 1) -> VehicleState {
        var stamina = 1.0
        return step(state, input: input, dt: dt, speedScale: speedScale, stamina: &stamina)
    }
}
