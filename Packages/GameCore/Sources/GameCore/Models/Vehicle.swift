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
    /// Solara State freight: a long diesel rig with a box trailer. Only lent out for freight jobs.
    case hauler

    // Dealership (fictional brands; see `CarLineup`).
    /// Kaze Kestrel RS: a light rear-drive coupe that loves to slide.
    case kestrel
    /// Ironside Bruiser V8: straight-line muscle.
    case bruiser
    /// Halcyon Solace: a quiet luxury sedan.
    case solace
    /// Brisa Summit 4x4: tall, tough SUV.
    case summit
    /// Volta Arc: electric, instant shove off the line.
    case arc
    /// Corvane Razor: the supercar.
    case razor
    /// Ironside Vandal: a low cruiser motorcycle.
    case vandal

    // Exclusive builds (one per player, rep-locked).
    case razorNoir
    case kestrelMidnight

    // Legendary classics: won, never sold.
    case stormhawk
    case seabreeze
    case ombra

    /// Vehicles the player can drive (everything but patrol cruisers).
    public static let drivable: [VehicleID] = [.vesper, .dorado, .ridgeback, .flicker, .kestrel, .bruiser, .solace,
                                               .summit, .arc, .razor, .vandal, .razorNoir, .kestrelMidnight,
                                               .stormhawk, .seabreeze, .ombra]

    public var spec: VehicleSpec {
        switch self {
        case .vesper: .vesper
        case .harborPatrol: .harborPatrol
        case .dorado: .dorado
        case .ridgeback: .ridgeback
        case .flicker: .flicker
        case .hauler: .hauler
        case .kestrel: .kestrel
        case .bruiser: .bruiser
        case .solace: .solace
        case .summit: .summit
        case .arc: .arc
        case .razor: .razor
        case .vandal: .vandal
        case .razorNoir: .razorNoir
        case .kestrelMidnight: .kestrelMidnight
        case .stormhawk: .stormhawk
        case .seabreeze: .seabreeze
        case .ombra: .ombra
        }
    }

    public var isMotorcycle: Bool { self == .flicker || self == .vandal }

    /// Big freight rigs: slow to start, can't drift, can't be kept.
    public var isTruck: Bool { self == .hauler }

    /// What the car is worth to the player's garage, in credits (for the business ledger).
    public var marketValue: Int {
        switch self {
        case .vesper: 3000
        case .dorado: 1800
        case .ridgeback: 2200
        case .flicker: 1500
        case .harborPatrol, .hauler: 0
        default: CarLineup.entry(self)?.price ?? 0
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

    /// The freight rig: heavy, slow to pick up, steady at highway speed, wide turns.
    public static let hauler = VehicleSpec(
        id: .hauler,
        displayName: "Longhaul diesel rig",
        maxSpeed: 430,
        acceleration: 150,
        brakeForce: 520,
        reverseMaxSpeed: 90,
        rollingDrag: 70,
        turnRate: 1.7,
        lateralRetention: 0.35,
        driftLateralRetention: 0.45,
        driftTurnBoost: 1.0,
        radius: 24,
        maxIntegrity: 16
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
    /// On foot with the stick: the direction to move in, screen/world aligned (+y = north),
    /// length 0...1 for how hard the stick is pushed. nil = the tank-style pads.
    public var move: Vec2?
    /// On foot: SPRINT held (burns stamina).
    public var sprint: Bool
    /// On foot: AIM held. The body turns to face the nearest target (a threat first) while
    /// the stick keeps moving it, so you can back away and shoot.
    public var aim: Bool

    public init(throttle: Double = 0, brake: Double = 0, steer: Double = 0, drift: Bool = false,
                move: Vec2? = nil, sprint: Bool = false, aim: Bool = false) {
        self.throttle = throttle
        self.brake = brake
        self.steer = steer
        self.drift = drift
        self.move = move
        self.sprint = sprint
        self.aim = aim
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

extension VehicleSpec {
    // MARK: The lineup (see CarLineup)

    public static let kestrel = VehicleSpec(id: .kestrel, displayName: "Kaze Kestrel RS", maxSpeed: 540, acceleration: 380,
                                         brakeForce: 950, reverseMaxSpeed: 170, rollingDrag: 140, turnRate: 3.3,
                                         lateralRetention: 0.58, driftLateralRetention: 0.93, driftTurnBoost: 1.4,
                                         radius: 15, maxIntegrity: 5)

    public static let bruiser = VehicleSpec(id: .bruiser, displayName: "Ironside Bruiser V8", maxSpeed: 580, acceleration: 420,
                                         brakeForce: 820, reverseMaxSpeed: 160, rollingDrag: 140, turnRate: 2.7,
                                         lateralRetention: 0.62, driftLateralRetention: 0.92, driftTurnBoost: 1.35,
                                         radius: 16, maxIntegrity: 7)

    public static let solace = VehicleSpec(id: .solace, displayName: "Halcyon Solace", maxSpeed: 540, acceleration: 330,
                                         brakeForce: 950, reverseMaxSpeed: 160, rollingDrag: 130, turnRate: 2.9,
                                         lateralRetention: 0.55, driftLateralRetention: 0.86, driftTurnBoost: 1.2,
                                         radius: 16, maxIntegrity: 8)

    public static let summit = VehicleSpec(id: .summit, displayName: "Brisa Summit 4x4", maxSpeed: 470, acceleration: 300,
                                         brakeForce: 880, reverseMaxSpeed: 160, rollingDrag: 150, turnRate: 2.6,
                                         lateralRetention: 0.52, driftLateralRetention: 0.84, driftTurnBoost: 1.15,
                                         radius: 17, maxIntegrity: 10)

    public static let arc = VehicleSpec(id: .arc, displayName: "Volta Arc EV", maxSpeed: 560, acceleration: 520,
                                         brakeForce: 1000, reverseMaxSpeed: 180, rollingDrag: 120, turnRate: 3.0,
                                         lateralRetention: 0.56, driftLateralRetention: 0.86, driftTurnBoost: 1.2,
                                         radius: 15, maxIntegrity: 6)

    public static let razor = VehicleSpec(id: .razor, displayName: "Corvane Razor", maxSpeed: 680, acceleration: 480,
                                         brakeForce: 1100, reverseMaxSpeed: 170, rollingDrag: 130, turnRate: 3.4,
                                         lateralRetention: 0.54, driftLateralRetention: 0.9, driftTurnBoost: 1.35,
                                         radius: 16, maxIntegrity: 5)

    public static let vandal = VehicleSpec(id: .vandal, displayName: "Ironside Vandal cruiser", maxSpeed: 580, acceleration: 420,
                                         brakeForce: 900, reverseMaxSpeed: 90, rollingDrag: 160, turnRate: 3.3,
                                         lateralRetention: 0.47, driftLateralRetention: 0.86, driftTurnBoost: 1.3,
                                         radius: 10, maxIntegrity: 4)

    public static let razorNoir = VehicleSpec(id: .razorNoir, displayName: "Corvane Razor Noir", maxSpeed: 720, acceleration: 500,
                                         brakeForce: 1150, reverseMaxSpeed: 170, rollingDrag: 130, turnRate: 3.5,
                                         lateralRetention: 0.53, driftLateralRetention: 0.9, driftTurnBoost: 1.4,
                                         radius: 16, maxIntegrity: 6)

    public static let kestrelMidnight = VehicleSpec(id: .kestrelMidnight, displayName: "Kaze Kestrel Midnight R", maxSpeed: 600, acceleration: 420,
                                         brakeForce: 1000, reverseMaxSpeed: 170, rollingDrag: 140, turnRate: 3.5,
                                         lateralRetention: 0.57, driftLateralRetention: 0.95, driftTurnBoost: 1.5,
                                         radius: 15, maxIntegrity: 6)

    public static let stormhawk = VehicleSpec(id: .stormhawk, displayName: "'69 Ironside Stormhawk", maxSpeed: 600, acceleration: 440,
                                         brakeForce: 760, reverseMaxSpeed: 150, rollingDrag: 140, turnRate: 2.6,
                                         lateralRetention: 0.64, driftLateralRetention: 0.93, driftTurnBoost: 1.4,
                                         radius: 17, maxIntegrity: 8)

    public static let seabreeze = VehicleSpec(id: .seabreeze, displayName: "'57 Halcyon Seabreeze", maxSpeed: 520, acceleration: 300,
                                         brakeForce: 700, reverseMaxSpeed: 140, rollingDrag: 140, turnRate: 2.5,
                                         lateralRetention: 0.6, driftLateralRetention: 0.9, driftTurnBoost: 1.3,
                                         radius: 17, maxIntegrity: 9)

    public static let ombra = VehicleSpec(id: .ombra, displayName: "'72 Corvane Ombra", maxSpeed: 650, acceleration: 420,
                                         brakeForce: 950, reverseMaxSpeed: 160, rollingDrag: 130, turnRate: 3.2,
                                         lateralRetention: 0.56, driftLateralRetention: 0.9, driftTurnBoost: 1.35,
                                         radius: 16, maxIntegrity: 6)
}
