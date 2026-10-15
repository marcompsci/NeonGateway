import Foundation

/// "Point where you want to go" driving for a touch stick or a game controller's left stick.
/// The stick is in world space (+y = north, the top of the screen; the camera never rotates),
/// so pushing up always drives up the screen, whichever way the car faces. The driver steers
/// the nose round to the stick, feeds gas with how far the stick is pushed, lifts off for
/// tight corners, and backs up when the stick points behind a slow car (pull back to reverse).
public struct StickDriver: Sendable, Equatable {
    /// Below this push the stick counts as centred.
    public static let deadZone = 0.14
    /// Steering gain: radians of heading error for full lock.
    public static let steerGain = 2.4
    /// The stick this far (radians) behind the car means "brake / reverse".
    public static let reverseAngle = 2.15
    /// Within this of dead astern, pulling back brakes in a straight line.
    public static let straightBack = 2.7
    /// Slower than this (points/s) and pulling back reverses instead of braking.
    public static let reverseSpeed = 70.0

    public private(set) var reversing = false

    public init() {}

    public mutating func input(stick: Vec2, brake: Bool, drift: Bool, car: VehicleState,
                               spec: VehicleSpec) -> VehicleInput {
        let push = min(1, stick.length)
        guard push >= Self.deadZone else {
            reversing = false
            return VehicleInput(throttle: 0, brake: brake ? 1 : 0, steer: 0, drift: drift)
        }
        // Rescale so the first bit past the dead zone is gentle and the edge is full.
        let amount = min(1, (push - Self.deadZone) / (0.85 - Self.deadZone))
        let wanted = atan2(stick.y, stick.x)
        let error = Self.wrap(wanted - car.heading)
        let forward = car.forwardSpeed

        if reversing {
            // Keep backing up while the stick stays behind; let go of reverse once it's in front.
            if abs(error) < .pi / 2 || brake {
                reversing = false
            } else {
                // Backing up: the tail is what points at the stick, and steering is mirrored.
                let tailError = Self.wrap(wanted - (car.heading + .pi))
                return VehicleInput(throttle: 0, brake: amount, steer: max(-1, min(1, tailError * Self.steerGain)),
                                    drift: false)
            }
        }

        if abs(error) > Self.reverseAngle {
            if forward > Self.reverseSpeed {
                // Moving and the stick's pulled back. Straight back = stop dead (then reverse);
                // back and to one side = brake while swinging round toward the stick.
                let steer = abs(error) > Self.straightBack ? 0 : Self.steer(for: error)
                return VehicleInput(throttle: 0, brake: 1, steer: steer, drift: drift)
            }
            reversing = true
            let tailError = Self.wrap(wanted - (car.heading + .pi))
            return VehicleInput(throttle: 0, brake: amount, steer: max(-1, min(1, tailError * Self.steerGain)),
                                drift: false)
        }

        // Ease off the gas in a tight corner at speed so the nose comes round instead of
        // ploughing on; flat out once it's lined up.
        let speedShare = max(0, forward) / max(1, spec.maxSpeed)
        var throttle = amount
        if abs(error) > 0.9 && speedShare > 0.45 { throttle *= 0.25 } else if abs(error) > 0.5 && speedShare > 0.6 {
            throttle *= 0.6
        }
        // A very sharp turn at speed gets a dab of brake too.
        let dab: Double = abs(error) > 1.3 && speedShare > 0.55 && !drift ? 0.5 : 0
        return VehicleInput(throttle: dab > 0 ? 0 : throttle, brake: brake ? 1 : dab, steer: Self.steer(for: error),
                            drift: drift)
    }

    /// Positive steer = right = heading decreases, so a positive (left) error steers left.
    static func steer(for error: Double) -> Double {
        max(-1, min(1, -error * steerGain))
    }

    static func wrap(_ a: Double) -> Double { remainder(a, 2 * .pi) }
}
