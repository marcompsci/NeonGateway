import Foundation

public enum PursuitEvent: Sendable, Equatable {
    case starsChanged(from: Int, to: Int)
    /// A patrol caught sight of the player while they had heat.
    case spotted
    case patrolContact(impact: Double)
    case busted
    /// Caught with only a little heat: a ticket instead of an arrest. Heat clears.
    case ticketed
}

/// Everything Harbor Patrol: the cruisers, the player's heat, and the bust meter.
/// The scene owns one per run and calls `step` every fixed tick.
public struct Pursuit: Sendable {
    public let district: District
    public internal(set) var patrols: [Patrol] = []
    public internal(set) var heat: HeatState
    /// Seconds spent stopped next to a chasing patrol; at `bustSeconds` the player is busted.
    public private(set) var bustProgress: Double = 0
    public private(set) var isSeen = false
    public private(set) var isBusted = false
    /// Seconds left on a dispatch radio fix: patrols know exactly where the player is, and heat
    /// can't cool. Set on a hot start and topped up briefly whenever a star is gained.
    public private(set) var dispatchTime: Double = 0

    private var rng: SplitMix64
    private var nextID = 0
    private var spawnCooldown = 0.0
    private var contactCooldown = 0.0

    /// Cruisers on the streets even with no heat.
    public static let basePatrols = 2
    public static let maxPatrols = 5
    public static let bustSeconds = 3.0
    public static let bustDistance = 90.0
    /// Below this speed (points/s) next to a chasing patrol, the bust meter fills.
    public static let bustSpeed = 70.0
    public static let spawnMinDistance = 900.0
    public static let despawnDistance = 1100.0
    public static let contactImpact = 40.0
    /// The player has to be driving into a patrol at least this fast for a bump to add heat.
    public static let playerRamSpeed = 100.0
    /// Dispatch fix on a job that starts hot, and on each new star.
    public static let hotStartDispatch = 10.0
    public static let newStarDispatch = 3.0
    /// At this many stars or fewer, getting caught means a ticket, not an arrest.
    public static let ticketMaxStars = 1
    public static let ticketFine = 150

    public init(district: District, player: VehicleState, startingHeat: Double = 0, seed: UInt64 = 1) {
        self.district = district
        heat = HeatState(points: startingHeat)
        rng = SplitMix64(seed: seed)
        for _ in 0..<Self.basePatrols {
            spawn(awayFrom: player.position, minDistance: Self.spawnMinDistance, mode: .cruise, lastSeen: nil)
        }
        // A job that starts hot has units already responding to where the player is.
        for _ in Self.basePatrols..<max(Self.basePatrols, desiredPatrols) {
            spawn(awayFrom: player.position, minDistance: 450, mode: .search, lastSeen: player.position)
        }
        if heat.stars > 0 {
            for i in patrols.indices where patrols[i].mode == .cruise {
                patrols[i].mode = .search
                patrols[i].lastSeen = player.position
            }
            dispatchTime = Self.hotStartDispatch
        }
    }

    public var desiredPatrols: Int { min(Self.maxPatrols, max(Self.basePatrols, heat.stars)) }
    public var chasingCount: Int { patrols.filter { $0.mode == .chase }.count }

    /// Adds heat from something the player did (a crash, a job event).
    @discardableResult
    public mutating func add(_ event: HeatEvent) -> [PursuitEvent] {
        let before = heat.stars
        heat = HeatSystem.apply(event, to: heat)
        if heat.stars > before { dispatchTime = max(dispatchTime, Self.newStarDispatch) }
        return before == heat.stars ? [] : [.starsChanged(from: before, to: heat.stars)]
    }

    /// A job alarm: heat jumps at once, dispatch has a radio fix on the player for
    /// `hotStartDispatch` seconds, and enough units to match the new heat are sent from nearby.
    @discardableResult
    public mutating func raiseAlarm(heat points: Double, at position: Vec2) -> [PursuitEvent] {
        let events = add(.missionEvent(points))
        heat.timeUnseen = 0
        dispatchTime = max(dispatchTime, Self.hotStartDispatch)
        for i in patrols.indices where patrols[i].mode != .chase {
            patrols[i].mode = .search
            patrols[i].modeTime = 0
            patrols[i].lastSeen = position
        }
        while patrols.count < desiredPatrols {
            let before = patrols.count
            spawn(awayFrom: position, minDistance: 450, mode: .search, lastSeen: position)
            if patrols.count == before { break }
        }
        spawnCooldown = 2
        return events
    }

    /// Heat gone and units back on patrol (after a live-play knockout).
    public mutating func calmDown() {
        heat = HeatState()
        bustProgress = 0
        dispatchTime = 0
        isBusted = false
        for i in patrols.indices {
            patrols[i].mode = .cruise
            patrols[i].modeTime = 0
            patrols[i].lastSeen = nil
        }
    }

    /// A witness's call: heat goes up and every unit not already chasing heads to where it
    /// happened (not to where the player is now).
    @discardableResult
    public mutating func report(heat points: Double, at position: Vec2) -> [PursuitEvent] {
        let events = add(.missionEvent(points))
        for i in patrols.indices where patrols[i].mode != .chase {
            patrols[i].mode = .search
            patrols[i].modeTime = 0
            patrols[i].lastSeen = position
        }
        return events
    }

    /// A shot hits a cruiser. Every unit learns where the shooter is. Returns true when that
    /// cruiser is disabled (it's removed; backup arrives through the normal spawn rules).
    @discardableResult
    public mutating func damagePatrol(id: Int, amount: Int, shooter: Vec2) -> Bool {
        guard let i = patrols.firstIndex(where: { $0.id == id }) else { return false }
        patrols[i].health -= amount
        for j in patrols.indices {
            patrols[j].mode = .chase
            patrols[j].modeTime = 0
            patrols[j].lastSeen = shooter
        }
        guard patrols[i].health <= 0 else { return false }
        patrols.remove(at: i)
        spawnCooldown = max(spawnCooldown, 4)
        return true
    }

    public mutating func step(player: inout VehicleState, dt: Double) -> [PursuitEvent] {
        guard !isBusted else { return [] }
        var events: [PursuitEvent] = []
        let starsBefore = heat.stars
        // The bust check uses the player's own speed, before any bump from a patrol.
        let playerSpeed = player.speed

        // Dispatch radio: every unit with heat on the player homes in on their live position.
        dispatchTime = max(0, dispatchTime - dt)
        let dispatching = dispatchTime > 0 && heat.stars > 0
        if dispatching {
            for i in patrols.indices {
                patrols[i].mode = .chase
                patrols[i].modeTime = 0
                patrols[i].lastSeen = player.position
            }
        }

        // Patrols think and drive.
        var seen = false
        for i in patrols.indices {
            if PatrolBrain.step(&patrols[i], player: player, heatStars: heat.stars, district: district,
                                rng: &rng, dt: dt) {
                seen = true
            }
        }

        // Bumps: player against patrols, then patrols against each other.
        contactCooldown -= dt
        for i in patrols.indices {
            // How hard the player was driving into this patrol (not the other way round).
            let toPatrol = patrols[i].car.position - player.position
            let gap = toPatrol.length
            let playerInto = gap > 0.001 ? player.velocity.dot(toPatrol * (1 / gap)) : 0
            let impact = Collision.separate(&player, &patrols[i].car, radius: PatrolBrain.spec.radius)
            if impact > Self.contactImpact && contactCooldown <= 0 {
                contactCooldown = 0.5
                // Ramming a patrol is a crime; being rammed by one isn't.
                if playerInto > Self.playerRamSpeed {
                    heat = HeatSystem.apply(.patrolHit, to: heat)
                }
                events.append(.patrolContact(impact: impact))
                // A patrol that gets hit knows exactly where you are.
                patrols[i].mode = .chase
                patrols[i].modeTime = 0
                patrols[i].lastSeen = player.position
            }
        }
        if patrols.count > 1 {
            for i in 0..<(patrols.count - 1) {
                for j in (i + 1)..<patrols.count {
                    var a = patrols[i].car, b = patrols[j].car
                    if Collision.separate(&a, &b, radius: PatrolBrain.spec.radius) > 0
                        || a.position != patrols[i].car.position {
                        patrols[i].car = a
                        patrols[j].car = b
                    }
                }
            }
        }

        // Heat.
        let inRestricted = district.zones.values.contains { $0.kind == .restricted && $0.rect.contains(player.position) }
        let inSafehouse = district.zones.values.contains { $0.kind == .safehouse && $0.rect.contains(player.position) }
        heat = HeatSystem.step(heat, dt: dt, seen: seen || dispatching, inRestricted: inRestricted,
                               inSafehouse: inSafehouse)
        if inSafehouse { dispatchTime = 0 }
        if seen && !isSeen && heat.stars > 0 { events.append(.spotted) }
        isSeen = seen

        // Bust meter: stopped right next to a chasing patrol.
        let cornered = patrols.contains {
            $0.mode == .chase && ($0.car.position - player.position).length < Self.bustDistance
        }
        if cornered && playerSpeed < Self.bustSpeed {
            bustProgress += dt
        } else {
            bustProgress = max(0, bustProgress - dt * 2)
        }
        if bustProgress >= Self.bustSeconds {
            if heat.stars <= Self.ticketMaxStars {
                // A warning and a fine: heat clears and the units go back to patrolling.
                bustProgress = 0
                heat.points = 0
                dispatchTime = 0
                for i in patrols.indices {
                    patrols[i].mode = .cruise
                    patrols[i].modeTime = 0
                    patrols[i].lastSeen = nil
                }
                events.append(.ticketed)
            } else {
                isBusted = true
                events.append(.busted)
            }
        }

        // Bring units in or send them home to match the heat.
        spawnCooldown -= dt
        if patrols.count < desiredPatrols && spawnCooldown <= 0 {
            let responding = heat.stars > 0
            spawn(awayFrom: player.position, minDistance: Self.spawnMinDistance,
                  mode: responding ? .search : .cruise, lastSeen: responding ? player.position : nil)
            spawnCooldown = 2
        } else if patrols.count > desiredPatrols,
                  let i = patrols.firstIndex(where: {
                      $0.mode == .cruise && ($0.car.position - player.position).length > Self.despawnDistance
                  }) {
            patrols.remove(at: i)
        }

        if heat.stars > starsBefore { dispatchTime = max(dispatchTime, Self.newStarDispatch) }
        if heat.stars != starsBefore {
            events.insert(.starsChanged(from: starsBefore, to: heat.stars), at: 0)
        }
        return events
    }

    private mutating func spawn(awayFrom p: Vec2, minDistance: Double, mode: PatrolMode, lastSeen: Vec2?) {
        guard let spot = PatrolBrain.randomRoadPoint(district, away: p, minDistance: minDistance, rng: &rng) else {
            return
        }
        // Face roughly toward the player so responders don't start by driving away.
        let toward = p - spot
        var patrol = Patrol(id: nextID, car: VehicleState(position: spot, heading: atan2(toward.y, toward.x)))
        patrol.mode = mode
        patrol.lastSeen = lastSeen
        patrols.append(patrol)
        nextID += 1
    }
}
