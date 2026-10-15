import Foundation

public enum PatrolMode: String, Sendable {
    /// Driving between random road tiles at a relaxed speed.
    case cruise
    /// Has the player in sight (or just lost them) and is driving at them flat out.
    case chase
    /// Lost the player; driving to where they were last seen, then giving up.
    case search
}

/// One Harbor Patrol cruiser.
public struct Patrol: Sendable {
    public let id: Int
    public var car: VehicleState
    public var mode: PatrolMode = .cruise
    public var lastSeen: Vec2?
    /// Seconds since the player was last in sight (chase) or since the search began (search).
    public var modeTime: Double = 0
    /// Shots a cruiser can take before it's disabled and pulls out of the chase.
    public var health = Patrol.maxHealth
    public static let maxHealth = 6
    /// Pulled over with the officers out on foot: the cruiser sits still until they're back.
    public var parked = false
    var pilot: Autopilot?
    var driver = Driver()
    var replanTime: Double = 0

    public init(id: Int, car: VehicleState) {
        self.id = id
        self.car = car
    }
}

public enum PatrolBrain {
    public static let spec = VehicleSpec.harborPatrol
    /// How far ahead a patrol can see, and its field of view either side of the nose.
    public static let visionRange = 440.0
    public static let visionHalfAngle = Double.pi / 4
    /// Anything this close is noticed whichever way the patrol faces.
    public static let nearRange = 150.0
    /// A chase becomes a search after this long out of sight.
    public static let chaseMemory = 1.5
    /// A search gives up after this long.
    public static let searchTime = 6.0
    /// A chasing patrol this close to a slow player stops to box them in.
    public static let boxInDistance = 70.0
    /// Top speed of a cruiser chasing someone on foot (points/s): between a run and a sprint.
    public static let footChaseSpeed = 300.0
    /// Cruising speed cap, points/s.
    public static let cruiseSpeed = 230.0

    /// Clear line of sight between two points (no solid tile in the way).
    public static func lineOfSight(from a: Vec2, to b: Vec2, district: District) -> Bool {
        let delta = b - a
        let length = delta.length
        let steps = max(1, Int(length / 24))
        for i in 1..<steps {
            let p = a + delta * (Double(i) / Double(steps))
            if district.tile(at: p).isSolid { return false }
        }
        return true
    }

    public static func canSee(_ patrol: VehicleState, target: Vec2, district: District) -> Bool {
        let delta = target - patrol.position
        let distance = delta.length
        guard distance <= visionRange else { return false }
        if distance > nearRange {
            let angle = remainder(atan2(delta.y, delta.x) - patrol.heading, 2 * .pi)
            guard abs(angle) <= visionHalfAngle else { return false }
        }
        return lineOfSight(from: patrol.position, to: target, district: district)
    }

    /// Picks a random road tile at least `minDistance` from `away`.
    static func randomRoadPoint(_ district: District, away: Vec2, minDistance: Double,
                                rng: inout SplitMix64) -> Vec2? {
        // On a big map, only roads around the player (otherwise cruisers spawn in another city).
        let roads = district.isLarge ? district.roadTiles(near: away, radius: minDistance + 900) : district.roadTiles
        guard !roads.isEmpty else { return nil }
        for _ in 0..<30 {
            let c = roads[Int(rng.next() % UInt64(roads.count))]
            let p = district.center(of: c)
            if (p - away).length >= minDistance { return p }
        }
        return nil
    }

    /// Advances one patrol by `dt`. Returns whether it saw the player this step.
    public static func step(_ patrol: inout Patrol, player: VehicleState, playerOnFoot: Bool = false,
                            heatStars: Int, district: District, rng: inout SplitMix64, dt: Double) -> Bool {
        let sees = canSee(patrol.car, target: player.position, district: district)
        if sees { patrol.lastSeen = player.position }

        // Mode changes.
        switch patrol.mode {
        case .cruise, .search:
            if sees && heatStars > 0 {
                patrol.mode = .chase
                patrol.modeTime = 0
                patrol.pilot = nil
            }
        case .chase:
            if heatStars == 0 {
                patrol.mode = .cruise
                patrol.pilot = nil
            } else if sees {
                patrol.modeTime = 0
            }
        }
        // A search only counts down once the patrol reaches the spot where it lost the player.
        let atLastSeen = patrol.lastSeen.map { ($0 - patrol.car.position).length < 250 } ?? true
        if patrol.mode != .search || atLastSeen {
            patrol.modeTime += dt
        }
        if patrol.mode == .chase && patrol.modeTime > chaseMemory {
            patrol.mode = .search
            patrol.modeTime = 0
            patrol.pilot = nil
        }
        if patrol.mode == .search && patrol.modeTime > searchTime {
            patrol.mode = .cruise
            patrol.pilot = nil
        }

        // Driving.
        var input = VehicleInput.idle
        patrol.replanTime -= dt
        if patrol.parked {
            // Officers are out: roll to a stop and wait.
            input = patrol.car.forwardSpeed > 5 ? VehicleInput(brake: 1) : .idle
            patrol.car = VehicleDynamics.step(patrol.car, input: input, spec: spec, dt: dt)
            if patrol.car.speed < 8 { patrol.car.velocity = .zero }
            return sees
        }
        switch patrol.mode {
        case .chase:
            if sees && lineOfSight(from: patrol.car.position, to: player.position, district: district) {
                // Aim a little ahead of the player.
                if (player.position - patrol.car.position).length < boxInDistance && player.speed < 120 {
                    // Right on top of a slow player: pull up and box them in rather than ram.
                    // (Brake only while rolling: holding brake at a stop would reverse.)
                    input = patrol.car.forwardSpeed > 15 ? VehicleInput(brake: 1) : .idle
                } else {
                    // Closing on a slow player: ease off with distance so it pins them, not rams them.
                    let gap = (player.position - patrol.car.position).length
                    if playerOnFoot {
                        // A runner: officers creep after them on the kerb rather than flooring it
                        // down a pavement full of people. A sprint opens a gap; a jog doesn't.
                        patrol.driver.speedCap = min(footChaseSpeed, max(110, gap * 1.3))
                    } else {
                        patrol.driver.speedCap = player.speed < 150 ? max(90, gap * 1.6) : nil
                    }
                    let lead = player.position + player.velocity * 0.35
                    input = patrol.driver.steer(toward: lead, car: patrol.car, dt: dt)
                }
            } else {
                input = follow(&patrol, to: patrol.lastSeen ?? player.position, district: district,
                               cap: nil, replanEvery: 0.6, dt: dt)
            }
        case .search:
            input = follow(&patrol, to: patrol.lastSeen ?? patrol.car.position, district: district,
                           cap: nil, replanEvery: 999, dt: dt)
        case .cruise:
            if patrol.pilot == nil || patrol.pilot!.isFinished {
                let target = randomRoadPoint(district, away: patrol.car.position, minDistance: 600, rng: &rng)
                patrol.pilot = target.flatMap {
                    Autopilot(district: district, from: patrol.car.position, to: $0, speedCap: cruiseSpeed)
                }
            }
            input = patrol.pilot?.input(for: patrol.car, dt: dt) ?? .idle
        }

        patrol.car = VehicleDynamics.step(patrol.car, input: input, spec: spec, dt: dt)
        patrol.car = Collision.resolve(patrol.car, radius: spec.radius,
                                       solids: district.solids(near: patrol.car.position, radius: spec.radius)).state
        return sees
    }

    private static func follow(_ patrol: inout Patrol, to target: Vec2, district: District,
                               cap: Double?, replanEvery: Double, dt: Double) -> VehicleInput {
        if patrol.pilot == nil || patrol.replanTime <= 0 {
            patrol.pilot = Autopilot(district: district, from: patrol.car.position, to: target, speedCap: cap)
            patrol.replanTime = replanEvery
        }
        return patrol.pilot?.input(for: patrol.car, dt: dt) ?? .idle
    }
}
