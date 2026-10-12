import Foundation

/// Arcade top-down car model. Pure function of (state, input, spec, dt) so it is unit-tested
/// without SpriteKit. The scene calls `step` at a fixed 1/60 s.
public enum VehicleDynamics {
    public static let fixedStep: Double = 1.0 / 60.0

    /// Sideways speed (points/s) above which the car counts as drifting.
    public static let driftThreshold: Double = 80

    /// Below this forward speed, the brake pedal becomes reverse.
    public static let reverseEngageSpeed: Double = 12

    public static func step(_ state: VehicleState, input rawInput: VehicleInput,
                            spec: VehicleSpec, dt: Double) -> VehicleState {
        var s = state
        let input = clamped(rawInput)

        var forwardSpeed = s.forwardSpeed
        var sideways = s.sidewaysSpeed

        // Pedals.
        if input.throttle > 0 {
            if forwardSpeed < 0 {
                // Throttle while rolling backwards acts as a brake first.
                forwardSpeed = min(0, forwardSpeed + spec.brakeForce * input.throttle * dt)
            } else {
                forwardSpeed += spec.acceleration * input.throttle * dt
            }
        }
        if input.brake > 0 {
            if forwardSpeed > reverseEngageSpeed {
                forwardSpeed = max(0, forwardSpeed - spec.brakeForce * input.brake * dt)
            } else {
                forwardSpeed -= spec.acceleration * 0.6 * input.brake * dt
            }
        }
        if input.throttle == 0 && input.brake == 0 {
            forwardSpeed = approach(forwardSpeed, 0, by: spec.rollingDrag * dt)
        }
        forwardSpeed = min(max(forwardSpeed, -spec.reverseMaxSpeed), spec.maxSpeed)

        // Steering scales with speed so the car never spins in place; reversing flips it.
        let speedFactor = min(1, abs(forwardSpeed) / (spec.maxSpeed * 0.25))
        let direction: Double = forwardSpeed >= 0 ? 1 : -1
        let boost = input.drift ? spec.driftTurnBoost : 1
        // Positive steer = right = clockwise = heading decreases.
        s.heading -= input.steer * spec.turnRate * boost * speedFactor * direction * dt
        s.heading = normalized(s.heading)

        // The velocity still points where the car was facing. Split it along the NEW heading:
        // whatever no longer lines up with the nose is sideways slip, which grip then bleeds off.
        let oldForward = state.forward, oldRight = state.right
        let worldVelocity = oldForward * forwardSpeed + oldRight * sideways
        forwardSpeed = worldVelocity.dot(s.forward)
        sideways = worldVelocity.dot(s.right)

        // Grip, frame-rate independent. Drift keeps more of the slip so the tail swings out.
        let retention = input.drift ? spec.driftLateralRetention : spec.lateralRetention
        sideways *= pow(retention, dt * 60)

        s.velocity = s.forward * forwardSpeed + s.right * sideways
        s.position += s.velocity * dt

        s.isDrifting = abs(sideways) > driftThreshold && abs(forwardSpeed) > spec.maxSpeed * 0.2
        if s.isDrifting {
            s.driftScore += abs(sideways) * dt * 0.1
        }
        return s
    }

    static func clamped(_ i: VehicleInput) -> VehicleInput {
        VehicleInput(throttle: min(max(i.throttle, 0), 1),
                     brake: min(max(i.brake, 0), 1),
                     steer: min(max(i.steer, -1), 1),
                     drift: i.drift)
    }

    static func approach(_ value: Double, _ target: Double, by amount: Double) -> Double {
        if value > target { return max(target, value - amount) }
        return min(target, value + amount)
    }

    static func normalized(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }
}
