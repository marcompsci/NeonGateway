import Foundation

public enum VehicleID: String, Codable, Sendable, CaseIterable {
    /// The player's starter coupe. Invented for Port Aurora.
    case vesper
    /// Generic Harbor Patrol cruiser (fictional, no real agency).
    case harborPatrol
    /// A plain four-door that's everywhere in Port Aurora. Slower, tougher.
    case dorado
    /// A delivery van: slow, heavy, hard to wreck.
    case ridgeback
    /// A light motorcycle: quickest off the line and in the turns, but fragile.
    case flicker

    /// Vehicles the player can drive (everything but patrol cruisers).
    public static let drivable: [VehicleID] = [.vesper, .dorado, .ridgeback, .flicker]

    public var spec: VehicleSpec {
        switch self {
        case .vesper: .vesper
        case .harborPatrol: .harborPatrol
        case .dorado: .dorado
        case .ridgeback: .ridgeback
        case .flicker: .flicker
        }
    }

    public var isMotorcycle: Bool { self == .flicker }

    /// What the car is worth to the player's garage, in credits (for the business ledger).
    public var marketValue: Int {
        switch self {
        case .vesper: 3000
        case .dorado: 1800
        case .ridgeback: 2200
        case .flicker: 1500
        case .harborPatrol: 0
        }
    }
}

/// Handling numbers for one car. Units: scene points and seconds.
public struct VehicleSpec: Sendable, Equatable {
    public let id: VehicleID
    public let displayName: String
    public var maxSpeed: Double          // points/s, forward
    public var acceleration: Double      // points/s²
    public var brakeForce: Double        // points/s²
    public var reverseMaxSpeed: Double   // points/s
    public var rollingDrag: Double       // points/s² with no pedal held
    public var turnRate: Double          // rad/s at full lock and speed
    /// Fraction of sideways speed kept per 1/60 s with normal grip. Lower = more planted.
    public var lateralRetention: Double
    /// Fraction of sideways speed kept per 1/60 s while DRIFT is held. Higher = longer slides.
    public var driftLateralRetention: Double
    public var driftTurnBoost: Double    // turn-rate multiplier while drifting
    public var radius: Double            // collision circle, points
    public var maxIntegrity: Int         // hits before wrecked (used from Phase 4)

    public init(id: VehicleID, displayName: String, maxSpeed: Double, acceleration: Double,
                brakeForce: Double, reverseMaxSpeed: Double, rollingDrag: Double, turnRate: Double,
                lateralRetention: Double, driftLateralRetention: Double, driftTurnBoost: Double,
                radius: Double, maxIntegrity: Int) {
        self.id = id
        self.displayName = displayName
        self.maxSpeed = maxSpeed
        self.acceleration = acceleration
        self.brakeForce = brakeForce
        self.reverseMaxSpeed = reverseMaxSpeed
        self.rollingDrag = rollingDrag
        self.turnRate = turnRate
        self.lateralRetention = lateralRetention
        self.driftLateralRetention = driftLateralRetention
        self.driftTurnBoost = driftTurnBoost
        self.radius = radius
        self.maxIntegrity = maxIntegrity
    }

    /// Starting values for tuning on a phone. All handling numbers live here.
    public static let vesper = VehicleSpec(
        id: .vesper,
        displayName: "Vesper GT",
        maxSpeed: 520,
        acceleration: 360,
        brakeForce: 900,
        reverseMaxSpeed: 170,
        rollingDrag: 140,
        turnRate: 3.1,
        lateralRetention: 0.60,
        driftLateralRetention: 0.90,
        driftTurnBoost: 1.3,
        radius: 15,
        maxIntegrity: 5
    )

    public static let dorado = VehicleSpec(
        id: .dorado,
        displayName: "Dorado sedan",
        maxSpeed: 460,
        acceleration: 300,
        brakeForce: 850,
        reverseMaxSpeed: 160,
        rollingDrag: 140,
        turnRate: 2.8,
        lateralRetention: 0.58,
        driftLateralRetention: 0.88,
        driftTurnBoost: 1.25,
        radius: 15,
        maxIntegrity: 7
    )

    public static let ridgeback = VehicleSpec(
        id: .ridgeback,
        displayName: "Ridgeback van",
        maxSpeed: 400,
        acceleration: 240,
        brakeForce: 800,
        reverseMaxSpeed: 140,
        rollingDrag: 150,
        turnRate: 2.4,
        lateralRetention: 0.5,
        driftLateralRetention: 0.85,
        driftTurnBoost: 1.15,
        radius: 17,
        maxIntegrity: 10
    )

    public static let flicker = VehicleSpec(
        id: .flicker,
        displayName: "Flicker 250 motorcycle",
        maxSpeed: 560,
        acceleration: 440,
        brakeForce: 950,
        reverseMaxSpeed: 90,
        rollingDrag: 160,
        turnRate: 3.6,
        lateralRetention: 0.45,
        driftLateralRetention: 0.85,
        driftTurnBoost: 1.3,
        radius: 10,
        maxIntegrity: 3
    )

    /// Patrol cruisers: a little slower than the Vesper at the top end, so a clean line escapes,
    /// but they corner hard and never tire.
    public static let harborPatrol = VehicleSpec(
        id: .harborPatrol,
        displayName: "Harbor Patrol cruiser",
        maxSpeed: 470,
        acceleration: 340,
        brakeForce: 900,
        reverseMaxSpeed: 160,
        rollingDrag: 140,
        turnRate: 3.0,
        lateralRetention: 0.55,
        driftLateralRetention: 0.9,
        driftTurnBoost: 1.2,
        radius: 15,
        maxIntegrity: 99
    )
}

/// What the player is pressing this step. Values are clamped by VehicleDynamics.
public struct VehicleInput: Sendable, Equatable {
    public var throttle: Double   // 0...1
    public var brake: Double      // 0...1 (also reverse when nearly stopped)
    public var steer: Double      // -1 (left) ... 1 (right)
    public var drift: Bool

    public init(throttle: Double = 0, brake: Double = 0, steer: Double = 0, drift: Bool = false) {
        self.throttle = throttle
        self.brake = brake
        self.steer = steer
        self.drift = drift
    }

    public static let idle = VehicleInput()
}

/// The car's moving state in world space.
public struct VehicleState: Sendable, Equatable {
    public var position: Vec2
    /// Radians, 0 = facing +x, counter-clockwise positive (SpriteKit's convention).
    public var heading: Double
    public var velocity: Vec2
    /// True while the car is sliding sideways fast enough to score drift.
    public var isDrifting: Bool
    /// Drift points banked this run (feeds the drift bonus from Phase 4).
    public var driftScore: Double

    public init(position: Vec2 = .zero, heading: Double = .pi / 2, velocity: Vec2 = .zero,
                isDrifting: Bool = false, driftScore: Double = 0) {
        self.position = position
        self.heading = heading
        self.velocity = velocity
        self.isDrifting = isDrifting
        self.driftScore = driftScore
    }

    public var forward: Vec2 { Vec2.unit(heading) }
    /// Unit vector to the car's right.
    public var right: Vec2 { Vec2.unit(heading - .pi / 2) }
    public var forwardSpeed: Double { velocity.dot(forward) }
    public var sidewaysSpeed: Double { velocity.dot(right) }
    public var speed: Double { velocity.length }
}
