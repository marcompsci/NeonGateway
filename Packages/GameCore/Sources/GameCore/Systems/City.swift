import Foundation

/// A car or bike in the city: the player's own, or one parked at the kerb that anyone can take.
public struct CityVehicle: Sendable, Equatable, Identifiable {
    public let id: Int
    public let model: VehicleID
    /// Handling in use: stock for street cars, Garage-tuned for the player's own.
    public var spec: VehicleSpec
    public var state: VehicleState
    /// Hull points lost. At `spec.maxIntegrity` the vehicle is wrecked and stops working.
    public var damage = 0
    /// In the player's garage: taking it isn't theft, and Garage upgrades apply.
    public var owned: Bool
    /// Paint design on it (the player's own cars only).
    public var design: PaintDesign? = nil
    /// Handed back (a delivered freight rig): gone from the street, can't be entered.
    public var retired = false
    /// Aftermarket rims (the player's own car).
    public var rims: RimSetup? = nil

    public var isWrecked: Bool { damage >= spec.maxIntegrity }
    public var hull: Int { max(0, spec.maxIntegrity - damage) }
}

/// A weapon lying in the street.
public struct WeaponPickup: Sendable, Equatable, Identifiable {
    public let id: Int
    public let weapon: WeaponID
    public let ammo: Int
    public let position: Vec2
    /// Seconds until it's back after being taken; 0 = lying there now.
    public var respawn: Double = 0
    /// Dropped by someone (a cruiser, a civilian, the dealer): taken once, gone after a while.
    public var isDrop = false
    /// Seconds a drop stays on the ground.
    public var lifetime: Double = 0
    /// Dropped by another player in live play: theirs to hand out (see `DropArbiter`).
    public var networkID: String? = nil
    /// This player has asked for it and is waiting for the answer.
    public var claimed = false

    public var isAvailable: Bool { respawn <= 0 }
}

/// Another player in a live match, as this city sees them.
public struct RemoteAvatar: Sendable, Equatable, Identifiable {
    public var id: String
    public var position: Vec2
    public var heading: Double
    /// The vehicle they're in, or nil on foot.
    public var vehicle: VehicleID?
    public var health: Int

    public init(id: String, position: Vec2, heading: Double, vehicle: VehicleID?, health: Int) {
        self.id = id
        self.position = position
        self.heading = heading
        self.vehicle = vehicle
        self.health = health
    }

    public var isOnFoot: Bool { vehicle == nil }
    public var isDown: Bool { health <= 0 }
}

/// The alley dealer: sells guns cheap, or drops his case if someone knocks him down.
public struct Dealer: Sendable, Equatable {
    public var position: Vec2
    public var heading: Double
    /// Seconds until he's back after being robbed; 0 = standing there.
    public var away: Double = 0

    public var isHere: Bool { away <= 0 }
}

/// One shot, for drawing a tracer.
public struct ShotTrace: Sendable, Equatable {
    public let from: Vec2
    public let to: Vec2
    public let hit: Bool
}

public enum PlayerMode: Sendable, Equatable {
    case driving(vehicle: Int)
    case onFoot
}

/// What the player tapped this step (one-shot) or is holding.
public struct CityActions: Sendable, Equatable {
    /// Get in the nearest vehicle, or get out of the current one.
    public var enterExit = false
    /// FIRE is held.
    public var fire = false
    /// AUTO FIRE is on: shoot by itself whenever a cruiser or another player is in the sights.
    public var autoFire = false
    /// A fist tapped this step (on foot): left hook, right hook or punch.
    public var strike: Strike?

    public init(enterExit: Bool = false, fire: Bool = false, autoFire: Bool = false, strike: Strike? = nil) {
        self.enterExit = enterExit
        self.fire = fire
        self.autoFire = autoFire
        self.strike = strike
    }
}

public enum CityEvent: Sendable, Equatable {
    /// Something to feel: 0...1.
    case impact(Double)
    case wallHit
    case patrolContact
    case spotted
    case busted
    /// Health ran out (on foot). Cartoon rules: the player is knocked out, not killed.
    case knockedOut
    case entered(vehicle: Int, stolen: Bool)
    case exited(vehicle: Int)
    /// The vehicle the player was in gave out; they're on foot beside it.
    case wrecked(vehicle: Int)
    case pickedUp(WeaponID, ammo: Int)
    case shot(ShotTrace)
    case pedestrianDown(Int)
    case patrolDisabled(Int)
    case outOfAmmo
    /// A melee swing, and whether it connected.
    case swing(hit: Bool)
    /// Someone dropped a gun; it's lying in the street.
    case droppedWeapon(WeaponID)
    case dealerRobbed
    /// Someone saw a crime and is calling it in (heat lands when the call does).
    case witnessed
    /// A witness's call went through: heat is up and patrols head to the scene.
    case reported
    /// Caught with low heat: a ticket (the fine is paid by the session).
    case ticketed
    /// Live play: the player hit another player (the session tells them).
    case hitPlayer(String, damage: Int, weapon: WeaponID?)
    /// Live play: the player is standing on another player's dropped gun and asks for it.
    case claimDrop(String)
    /// A cruiser pulled over and its officers got out.
    case officersOut(Int)
    /// "Freeze!": the officers' warning has started.
    case copsWarning
    /// The warning ran out, or the player shot at cops: officers are shooting.
    case copsOpenFire
    /// An officer fired at the player.
    case copShot(ShotTrace)
    case officerDown(Int)
    /// A fist thrown on foot, and whether it landed.
    case punch(Strike, hit: Bool)
}

/// A witness on the phone to Harbor Patrol.
public struct CrimeReport: Sendable, Equatable {
    /// Seconds until the call goes through.
    public var timeLeft: Double
    public let heat: Double
    public let position: Vec2
    /// What the player was in when seen (a vehicle id), or nil on foot. Switching rides before the
    /// call lands means the description is wrong, and the heat is halved.
    public let ride: Int?
    public let witness: Int
}

/// Rain makes roads slippery; it's set per trip.
public enum Weather: String, Sendable, CaseIterable {
    case clear, rain

    /// Chance a trip starts in the rain.
    public static let rainChance = 0.3

    public static func roll(seed: UInt64) -> Weather {
        var rng = SplitMix64(seed: seed ^ 0xBADC0FFEE)
        return Double(rng.next() % 1_000) / 1_000 < rainChance ? .rain : .clear
    }

    /// Wet roads: more sideways slide, weaker brakes.
    public func adjusted(_ spec: VehicleSpec) -> VehicleSpec {
        guard self == .rain else { return spec }
        var s = spec
        s.lateralRetention = min(0.97, s.lateralRetention + (1 - s.lateralRetention) * 0.35)
        s.brakeForce *= 0.8
        return s
    }
}

/// Light in the city, from the player's own clock.
public enum TimeOfDay: String, Sendable, CaseIterable {
    case dawn, day, dusk, night

    public static func at(hour: Int) -> TimeOfDay {
        switch hour {
        case 5..<8: .dawn
        case 8..<18: .day
        case 18..<21: .dusk
        default: .night
        }
    }
}

/// Port Aurora while the player is in it: their body or vehicle, every other vehicle, the crowd,
/// weapons lying around and Harbor Patrol. Pure and steppable, so it's unit-tested; the scene
/// only draws it and feeds it input.
public struct City: Sendable {
    // Tuning. Heat numbers are in the same points as `HeatRules`.
    /// How close the player must be to a vehicle's centre to get in.
    public static let enterDistance = 72.0
    /// Can't bail out above this speed.
    public static let exitMaxSpeed = 90.0
    public static let maxHealth = 100.0
    /// Taking a car a patrol can see.
    public static let theftHeat = 15.0
    /// A shot fired where a patrol can see it.
    public static let gunfireHeat = 3.0
    public static let pedestrianHitHeat = 10.0
    public static let patrolShotHeat = 6.0
    public static let patrolDisabledHeat = 20.0
    /// Hitting someone with a vehicle faster than this knocks them down.
    public static let runOverSpeed = 70.0
    public static let pickupRadius = 44.0
    public static let pickupRespawn = 60.0
    /// A wreck throws the player clear with this much health lost.
    public static let wreckHealthLoss = 15.0
    /// A wall hit at least this fast costs a hull point.
    public static let hardHitSpeed = 260.0
    /// A patrol bump closing at least this fast costs a hull point (or health on foot).
    public static let patrolRamSpeed = 150.0
    public static let crowdSize = 28
    /// Chance a civilian who gets knocked down drops a pistol.
    public static let civilianDropChance = 0.25
    /// Seconds a dropped gun stays on the ground.
    public static let dropLifetime = 45.0
    public static let dealerAwaySeconds = 45.0
    public static let dealerRobHeat = 15.0
    /// How close to stand to trade with the dealer.
    public static let dealerTalkDistance = 64.0
    /// Live play: weapon-damage points a car does to another player on foot.
    public static let runOverDamage = 4
    /// Bystanders this close (with a clear view) see a crime.
    public static let witnessRange = 380.0
    /// Seconds a witness takes to get through to Harbor Patrol.
    public static let reportDelay = 4.0
    /// Heat kept when the witness described a ride the player has since swapped.
    public static let wrongRideShare = 0.5

    public let district: District
    public internal(set) var vehicles: [CityVehicle] = []
    public internal(set) var mode: PlayerMode
    /// The player's body; only meaningful on foot (it rides along while driving).
    public internal(set) var foot: VehicleState
    public internal(set) var health = City.maxHealth
    /// Sprint stamina on foot, 0...1. Refills whenever the player isn't sprinting.
    public internal(set) var stamina = 1.0
    public var inventory: Inventory
    public internal(set) var crowd: Crowd
    public internal(set) var pickups: [WeaponPickup] = []
    public internal(set) var dealer: Dealer?
    public var pursuit: Pursuit
    /// Knocks taken this run (walls, patrols, people), for scoring.
    public internal(set) var hits = 0
    /// Upgrades applied to vehicles the player owns.
    public let tuning: UpgradeLevels
    /// The player's skill levels.
    public let skills: SkillLevels
    /// Auto-aim cone multiplier from Settings.
    public let aimAssist: Double
    public let weather: Weather
    /// Witness calls on their way to Harbor Patrol.
    public internal(set) var reports: [CrimeReport] = []
    /// What the player did this trip, for skills.
    public internal(set) var stats = RunStats()
    /// Live play: other players, refreshed by the session every frame.
    public var remotes: [RemoteAvatar] = []
    /// Live play: who last hit the player (for who gets their gun on a knockout).
    public private(set) var lastAttacker: String?

    private var fireCooldown = 0.0
    /// Harbor Patrol officers out on foot.
    public internal(set) var officers: [Officer] = []
    public internal(set) var standoff: Standoff = .none
    var nextOfficerID = 0
    var copHullHits = 0
    var surrenderTime = 0.0
    /// Seconds since the player last fired.
    var sinceShot = 99.0
    var punchCooldown = 0.0
    /// How dazed each person is from punches (by pedestrian id).
    var daze: [Int: Double] = [:]
    /// Where AIM is locked on right now (on foot, AIM held), for the scene's reticle.
    public internal(set) var aimLock: Vec2?
    private var impactCooldown = 0.0
    private var ramCooldown = 0.0
    private var nextVehicleID = 0
    private var nextPickupID = 1000
    var rng: SplitMix64

    /// - Parameters:
    ///   - playerVehicle: the car the player starts in (their own), or nil to start on foot.
    public init(district: District, start: SpawnPoint, playerVehicle: VehicleID?, tuning: UpgradeLevels = .init(),
                inventory: Inventory = .init(), startingHeat: Double = 0, seed: UInt64 = 1,
                parked: [ParkedSpawn] = District.docksParked, pickups: [PickupSpawn] = District.docksPickups,
                dealer dealerTile: TileCoord? = District.docksDealer, playerDesign: PaintDesign? = nil,
                skills: SkillLevels = .init(), aimAssist: Double = 1, weather: Weather = .clear) {
        self.district = district
        self.tuning = tuning
        self.skills = skills
        self.aimAssist = aimAssist
        self.weather = weather
        self.inventory = inventory
        let body = VehicleState(position: start.position, heading: start.heading)
        foot = body
        if let model = playerVehicle {
            mode = .driving(vehicle: 0)
            vehicles.append(CityVehicle(id: 0, model: model, spec: UpgradeShop.spec(model.spec, levels: tuning),
                                        state: VehicleState(position: start.position, heading: start.heading),
                                        owned: true, design: playerDesign))
            nextVehicleID = 1
        } else {
            mode = .onFoot
        }
        for spot in parked {
            let position = district.center(of: spot.tile)
            // Don't park anything on top of the player.
            guard (position - start.position).length > 120 else { continue }
            vehicles.append(CityVehicle(id: nextVehicleID, model: spot.model, spec: spot.model.spec,
                                        state: VehicleState(position: position, heading: spot.heading),
                                        owned: false))
            nextVehicleID += 1
        }
        self.pickups = pickups.enumerated().map {
            WeaponPickup(id: $0.offset, weapon: $0.element.weapon, ammo: $0.element.ammo,
                         position: district.center(of: $0.element.tile))
        }
        crowd = Crowd(district: district, count: Self.crowdSize, avoid: start.position, seed: seed)
        rng = SplitMix64(seed: seed ^ 0xD00D)
        dealer = dealerTile.map { Dealer(position: district.center(of: $0), heading: -.pi / 2) }
        pursuit = Pursuit(district: district, player: body, startingHeat: startingHeat, seed: seed)
    }

    // MARK: Reading

    public var isOnFoot: Bool { mode == .onFoot }

    public var currentVehicleIndex: Int? {
        if case .driving(let i) = mode { return i }
        return nil
    }

    public var currentVehicle: CityVehicle? { currentVehicleIndex.map { vehicles[$0] } }

    /// The body that moves: the vehicle while driving, the player on foot.
    public var player: VehicleState { currentVehicle?.state ?? foot }

    public var playerPosition: Vec2 { player.position }

    /// The vehicle the player would get into now, if any.
    public var enterableVehicle: Int? {
        guard isOnFoot else { return nil }
        return vehicles.indices
            .filter { !vehicles[$0].isWrecked && !vehicles[$0].retired
                && (vehicles[$0].state.position - foot.position).length < Self.enterDistance }
            .min { (vehicles[$0].state.position - foot.position).length < (vehicles[$1].state.position - foot.position).length }
    }

    public var canExit: Bool {
        guard let v = currentVehicle else { return false }
        return v.state.speed < Self.exitMaxSpeed
    }

    /// Standing close enough to the dealer to trade.
    public var nearDealer: Bool {
        guard isOnFoot, let dealer, dealer.isHere else { return false }
        return (dealer.position - foot.position).length < Self.dealerTalkDistance
    }

    /// Drift points banked across every vehicle the player drove this run.
    public var totalDrift: Double {
        vehicles.reduce(0) { $0 + $1.state.driftScore }
    }

    /// The zone the player is standing or parked in, if any.
    public func zone(ofKind kind: ZoneKind) -> Zone? {
        district.zones.values.first { $0.kind == kind && $0.rect.contains(playerPosition) }
    }

    // MARK: Changing

    /// Marks the current vehicle as the player's own (stored at the Safehouse garage). Returns
    /// its model, or nil if it was already theirs or they're on foot.
    public mutating func keepCurrentVehicle() -> VehicleID? {
        guard let i = currentVehicleIndex, !vehicles[i].owned, VehicleID.drivable.contains(vehicles[i].model) else {
            return nil
        }
        vehicles[i].owned = true
        let damage = vehicles[i].damage
        vehicles[i].spec = UpgradeShop.spec(vehicles[i].model.spec, levels: tuning)
        vehicles[i].damage = damage
        return vehicles[i].model
    }

    // MARK: Step

    public mutating func step(input: VehicleInput, actions: CityActions, dt: Double) -> [CityEvent] {
        var events: [CityEvent] = []
        impactCooldown -= dt
        ramCooldown -= dt
        fireCooldown -= dt
        punchCooldown -= dt
        recoverDaze(dt: dt)

        if actions.enterExit { events += toggleVehicle() }

        if let i = currentVehicleIndex {
            aimLock = nil
            events += drive(i, input: input, dt: dt)
        } else {
            walk(input: input, dt: dt)
            if let s = actions.strike { events += strike(s) }
            if actions.fire || (actions.autoFire && threatInSights) { events += fire() }
        }
        settleParkedVehicles()

        // Harbor Patrol, against whichever body the player is in.
        var body = player
        let pursuitEvents = pursuit.step(player: &body, onFoot: isOnFoot, dt: dt)
        setPlayerBody(body)
        for event in pursuitEvents {
            switch event {
            case .patrolContact(let impact):
                hits += 1
                events.append(.patrolContact)
                events.append(.impact(min(1, impact / 300)))
                if impact > Self.patrolRamSpeed && ramCooldown <= 0 {
                    ramCooldown = 1
                    if let i = currentVehicleIndex {
                        vehicles[i].damage += 1
                    } else {
                        health -= min(40, impact * 0.15)
                    }
                }
            case .spotted:
                events.append(.spotted)
            case .busted:
                events.append(.busted)
                return events
            case .ticketed:
                reports.removeAll()
                stats.ticketsPaid += 1
                events.append(.ticketed)
            case .starsChanged:
                break
            }
        }
        events += stepReports(dt: dt)
        let copEvents = stepOfficers(dt: dt)
        events += copEvents
        if copEvents.contains(.busted) { return events }

        if let i = currentVehicleIndex, vehicles[i].isWrecked {
            events += bail(from: i, wrecked: true)
        }

        crowd.step(dt: dt, player: playerPosition)
        if dealer != nil, dealer!.away > 0 { dealer!.away = max(0, dealer!.away - dt) }
        collectPickups(&events, dt: dt)

        if health <= 0 {
            health = 0
            events.append(.knockedOut)
        }
        return events
    }

    private mutating func setPlayerBody(_ body: VehicleState) {
        if let i = currentVehicleIndex {
            vehicles[i].state = body
        } else {
            foot = body
        }
    }

    // MARK: Solara State: lent and parked vehicles

    /// The player's own car as the garage has it: worn parts change how it drives, rims show.
    public mutating func setPlayerCar(wear: CarWear?, rims: RimSetup?) {
        guard let i = vehicles.firstIndex(where: { $0.id == 0 && $0.owned }) else { return }
        if let wear { vehicles[i].spec = wear.apply(to: vehicles[i].spec) }
        vehicles[i].rims = rims
    }

    /// A freight rig (or any vehicle) appears at `position` and the player is put in it. A car the
    /// player was driving stays parked where it was.
    @discardableResult
    public mutating func lendVehicle(_ model: VehicleID, at position: Vec2, heading: Double) -> Int {
        if let i = currentVehicleIndex { vehicles[i].state.velocity = .zero }
        let i = vehicles.count
        vehicles.append(CityVehicle(id: nextVehicleID, model: model, spec: model.spec,
                                    state: VehicleState(position: position, heading: heading), owned: true))
        nextVehicleID += 1
        foot.position = position
        mode = .driving(vehicle: i)
        return i
    }

    /// Parks a vehicle at `position` for the player to take (the ride home after freight). It's
    /// theirs to drive, so taking it isn't theft.
    @discardableResult
    public mutating func parkVehicle(_ model: VehicleID, at position: Vec2, heading: Double) -> Int {
        vehicles.append(CityVehicle(id: nextVehicleID, model: model, spec: model.spec,
                                    state: VehicleState(position: position, heading: heading), owned: true))
        nextVehicleID += 1
        return vehicles.count - 1
    }

    /// Hands a vehicle back: it leaves the street. If the player is in it they step out beside it.
    public mutating func retireVehicle(_ i: Int) -> [CityEvent] {
        guard vehicles.indices.contains(i) else { return [] }
        var events: [CityEvent] = []
        if currentVehicleIndex == i { events = bail(from: i, wrecked: false) }
        vehicles[i].retired = true
        vehicles[i].state.velocity = .zero
        return events
    }

    /// Puts the player somewhere else on the map (fast travel), on foot or in their current car.
    public mutating func teleport(to position: Vec2, heading: Double) {
        if let i = currentVehicleIndex {
            vehicles[i].state = VehicleState(position: position, heading: heading)
        }
        foot = VehicleState(position: position, heading: heading)
    }

    // MARK: Getting in and out

    private mutating func toggleVehicle() -> [CityEvent] {
        if let i = currentVehicleIndex {
            guard canExit else { return [] }
            return bail(from: i, wrecked: false)
        }
        guard let i = enterableVehicle else { return [] }
        let stolen = !vehicles[i].owned
        mode = .driving(vehicle: i)
        vehicles[i].state.velocity = .zero
        var events: [CityEvent] = [.entered(vehicle: i, stolen: stolen)]
        if stolen { events += crime(heat: Self.theftHeat, at: vehicles[i].state.position, victim: nil) }
        return events
    }

    /// Puts the player on foot beside vehicle `i`, on the first clear side.
    private mutating func bail(from i: Int, wrecked: Bool) -> [CityEvent] {
        let car = vehicles[i].state
        vehicles[i].state.velocity = .zero
        let offsets = [car.right * -34, car.right * 34, car.forward * -46, car.forward * 46]
        var spot = car.position + offsets[0]
        for offset in offsets {
            let p = car.position + offset
            if !district.tile(at: p).isSolid
                && district.solids(near: p, radius: FootDynamics.radius).allSatisfy({ !$0.contains(p) }) {
                spot = p
                break
            }
        }
        foot = VehicleState(position: spot, heading: car.heading)
        mode = .onFoot
        if wrecked {
            health -= Self.wreckHealthLoss
            return [.wrecked(vehicle: i), .impact(0.9)]
        }
        return [.exited(vehicle: i)]
    }

    // MARK: Moving

    private mutating func drive(_ i: Int, input: VehicleInput, dt: Double) -> [CityEvent] {
        var events: [CityEvent] = []
        var v = vehicles[i]
        var spec = weather.adjusted(v.spec)
        spec.turnRate *= Skills.steeringMultiplier(skills.driving)
        v.state = VehicleDynamics.step(v.state, input: input, spec: spec, dt: dt)
        stats.driven += v.state.speed * dt
        let contact = Collision.resolve(v.state, radius: v.spec.radius,
                                        solids: district.solids(near: v.state.position, radius: v.spec.radius))
        v.state = contact.state
        if contact.impactSpeed > 90, impactCooldown <= 0 {
            hits += 1
            stats.knocks += 1
            impactCooldown = 0.3
            pursuit.add(.wallHit)
            if contact.impactSpeed > Self.hardHitSpeed { v.damage += 1 }
            events.append(.wallHit)
            events.append(.impact(min(1, contact.impactSpeed / 450)))
        }
        // Other vehicles get shoved.
        for j in vehicles.indices where j != i && !vehicles[j].retired {
            var other = vehicles[j].state
            let radius = (v.spec.radius + vehicles[j].spec.radius) / 2
            let impact = Collision.separate(&v.state, &other, radius: radius)
            vehicles[j].state = other
            if impact > 90, impactCooldown <= 0 {
                hits += 1
            stats.knocks += 1
                impactCooldown = 0.3
                if impact > Self.hardHitSpeed { v.damage += 1 }
                events.append(.impact(min(1, impact / 450)))
            }
        }
        vehicles[i] = v
        // People in the way.
        if v.state.speed > Self.runOverSpeed {
            for (k, person) in crowd.people.enumerated() where !person.isDown {
                if (person.position - v.state.position).length < v.spec.radius + Crowd.radius {
                    events += knockDownPerson(k)
                    crowd.scare(from: person.position, radius: 260)
                    hits += 1
                    events.append(.impact(0.4))
                }
            }
            if let d = dealer, d.isHere, (d.position - v.state.position).length < v.spec.radius + Crowd.radius {
                events += robDealer()
                events.append(.impact(0.4))
            }
            if ramCooldown <= 0 {
                for remote in remotes where remote.isOnFoot && !remote.isDown
                    && (remote.position - v.state.position).length < v.spec.radius + Crowd.radius {
                    ramCooldown = 1
                    events.append(.hitPlayer(remote.id, damage: Self.runOverDamage, weapon: nil))
                    events.append(.impact(0.4))
                    break
                }
            }
        }
        return events
    }

    private mutating func walk(input: VehicleInput, dt: Double) {
        var body = FootDynamics.step(foot, input: VehicleInput(throttle: input.throttle, brake: input.brake,
                                                              steer: input.steer, move: input.move,
                                                              sprint: input.sprint), dt: dt,
                                     speedScale: Skills.runMultiplier(skills.stamina), stamina: &stamina)
        stats.run += body.speed * dt
        // AIM: face the nearest target while the stick keeps moving the body.
        aimLock = nil
        if input.aim, let found = lockTarget(from: body.position) {
            aimLock = found
            let delta = found - body.position
            let wanted = atan2(delta.y, delta.x)
            let error = remainder(wanted - body.heading, 2 * .pi)
            let turn = FootDynamics.stickTurnRate * dt
            body.heading = remainder(abs(error) <= turn ? wanted : body.heading + (error > 0 ? turn : -turn), 2 * .pi)
        }
        body = Collision.resolve(body, radius: FootDynamics.radius,
                                 solids: district.solids(near: body.position, radius: FootDynamics.radius),
                                 restitution: 0).state
        // Vehicles are solid to walk into.
        for v in vehicles where !v.retired {
            let gap = body.position - v.state.position
            let minimum = v.spec.radius + FootDynamics.radius
            let d = gap.length
            if d < minimum && d > 0.001 {
                body.position = v.state.position + gap * (minimum / d)
            }
        }
        foot = body
    }

    /// Parked vehicles that got shoved slide to a stop and stay out of walls.
    private mutating func settleParkedVehicles() {
        for j in vehicles.indices where j != currentVehicleIndex && !vehicles[j].retired {
            var s = vehicles[j].state
            guard s.velocity.length > 0.5 else { continue }
            s.velocity = s.velocity * 0.9
            s.position += s.velocity * VehicleDynamics.fixedStep
            s = Collision.resolve(s, radius: vehicles[j].spec.radius,
                                  solids: district.solids(near: s.position, radius: vehicles[j].spec.radius)).state
            vehicles[j].state = s
        }
    }

    // MARK: Weapons

    private enum Target { case person(Int), patrol(Int), officer(Int), dealer, remote(String) }

    /// What a hit does to whoever it lands on.
    private mutating func apply(target: Target, damage: Int, from origin: Vec2) -> [CityEvent] {
        switch target {
        case .person(let k):
            return knockDownPerson(k)
        case .officer(let id):
            return hitOfficer(id, damage: damage, from: origin)
        case .patrol(let id):
            var provoked = provokeCops(from: origin)
            pursuit.add(.missionEvent(Self.patrolShotHeat))
            let position = pursuit.patrols.first { $0.id == id }?.car.position
            guard pursuit.damagePatrol(id: id, amount: damage, shooter: origin) else { return provoked }
            pursuit.add(.missionEvent(Self.patrolDisabledHeat))
            provoked.append(.patrolDisabled(id))
            var events = provoked
            if let position {
                // Every cruiser carries a sidearm or a shotgun.
                let weapon: WeaponID = rng.next() % 2 == 0 ? .pistol : .shotgun
                events += drop(weapon, ammo: weapon.spec.ammoPack, at: position)
            }
            return events
        case .dealer:
            return robDealer()
        case .remote(let id):
            return [.hitPlayer(id, damage: damage, weapon: inventory.equipped)]
        }
    }

    /// A bystander goes down (cartoon rules). Some of them were carrying.
    mutating func knockDownPerson(_ k: Int) -> [CityEvent] {
        let person = crowd.people[k]
        guard crowd.knockDown(k) else { return [] }
        var events: [CityEvent] = [.pedestrianDown(person.id)]
        events += crime(heat: Self.pedestrianHitHeat, at: person.position, victim: person.id)
        if Double(rng.next() % 1000) / 1000 < Self.civilianDropChance {
            events += drop(.pistol, ammo: 12, at: person.position)
        }
        return events
    }

    /// The dealer goes down and his case spills: one of his better guns.
    private mutating func robDealer() -> [CityEvent] {
        guard let d = dealer, d.isHere else { return [] }
        dealer!.away = Self.dealerAwaySeconds
        let witnessed = crime(heat: Self.dealerRobHeat, at: d.position, victim: nil)
        crowd.scare(from: d.position, radius: 300)
        let stock: [WeaponID] = [.smg, .shotgun, .rifle]
        let weapon = stock[Int(rng.next() % UInt64(stock.count))]
        return [.dealerRobbed] + witnessed + drop(weapon, ammo: weapon.spec.ammoPack * 2, at: d.position)
    }

    mutating func drop(_ weapon: WeaponID, ammo: Int, at position: Vec2) -> [CityEvent] {
        // Nudge it off walls so it can be reached.
        var spot = position
        if district.tile(at: spot).isSolid { spot = playerPosition }
        pickups.append(WeaponPickup(id: nextPickupID, weapon: weapon, ammo: ammo, position: spot,
                                    isDrop: true, lifetime: Self.dropLifetime))
        nextPickupID += 1
        return [.droppedWeapon(weapon)]
    }

    /// The nearest target within `cone` either side of `facing`, in range and in sight.
    /// `threatsOnly` leaves out bystanders and the dealer (cruisers and other players only).
    private func bestTarget(from origin: Vec2, facing: Double, cone: Double, range: Double,
                            threatsOnly: Bool) -> (Target, Vec2, Double)? {
        var best: (Target, Vec2, Double)?
        let map = district
        func consider(_ target: Target, at p: Vec2) {
            let delta = p - origin
            let distance = delta.length
            guard distance <= range, distance > 1 else { return }
            let angle = remainder(atan2(delta.y, delta.x) - facing, 2 * .pi)
            guard abs(angle) <= cone else { return }
            guard PatrolBrain.lineOfSight(from: origin, to: p, district: map) else { return }
            if best == nil || distance < best!.2 { best = (target, p, distance) }
        }
        if !threatsOnly {
            for (k, person) in crowd.people.enumerated() where !person.isDown {
                consider(.person(k), at: person.position)
            }
            if let d = dealer, d.isHere { consider(.dealer, at: d.position) }
        }
        for patrol in pursuit.patrols {
            consider(.patrol(patrol.id), at: patrol.car.position)
        }
        for officer in officers where !officer.isDown {
            consider(.officer(officer.id), at: officer.position)
        }
        for remote in remotes where !remote.isDown { consider(.remote(remote.id), at: remote.position) }
        return best
    }

    /// AIM's lock: the nearest cruiser or other player in range all round; with none about,
    /// the nearest anyone. nil with nothing loaded or nobody in range.
    func lockTarget(from origin: Vec2) -> Vec2? {
        guard let weapon = inventory.equipped, inventory.isLoaded(weapon) else { return nil }
        let range = inventory.spec(for: weapon).range
        let all = Double.pi * 1.01
        return (bestTarget(from: origin, facing: 0, cone: all, range: range, threatsOnly: true)
                ?? bestTarget(from: origin, facing: 0, cone: all, range: range, threatsOnly: false))?.1
    }

    /// A cruiser or another player sits in the sights of the loaded weapon right now (AUTO FIRE).
    public var threatInSights: Bool {
        guard isOnFoot, let weapon = inventory.equipped, inventory.isLoaded(weapon) else { return false }
        let spec = inventory.spec(for: weapon)
        let cone = spec.aimHalfAngle * aimAssist * Skills.aimMultiplier(skills.shooting)
        return bestTarget(from: foot.position, facing: foot.heading, cone: cone, range: spec.range,
                          threatsOnly: true) != nil
    }

    private mutating func fire() -> [CityEvent] {
        guard fireCooldown <= 0, let weapon = inventory.equipped else { return [] }
        guard inventory.consumeRound() else {
            fireCooldown = 0.4
            return [.outOfAmmo]
        }
        let spec = inventory.spec(for: weapon)
        fireCooldown = spec.fireInterval
        let origin = foot.position
        let facing = foot.heading
        var events: [CityEvent] = []

        // Auto-aim: the nearest person or cruiser in front, in range and in sight.
        let cone = spec.aimHalfAngle * aimAssist * Skills.aimMultiplier(skills.shooting)
        let best = bestTarget(from: origin, facing: facing, cone: cone, range: spec.range, threatsOnly: false)

        if spec.isMelee {
            // A swing: quiet, no tracer, only what's right in front.
            if let found = best {
                let (target, point, _) = found
                events.append(.swing(hit: true))
                stats.hitsLanded += 1
                crowd.scare(from: point, radius: 200)
                events += apply(target: target, damage: spec.damage, from: origin)
            } else {
                events.append(.swing(hit: false))
            }
            return events
        }

        if pursuit.isSeen { pursuit.add(.missionEvent(Self.gunfireHeat)) }
        crowd.scare(from: origin, radius: 380)
        sinceShot = 0
        // Gunfire right in front of officers: they don't wait out the warning.
        if !standoff.isFiring, officers.contains(where: { !$0.isDown && ($0.position - origin).length < 500 }) {
            events += provokeCops(from: origin)
        }

        if let found = best {
            let (target, point, _) = found
            events.append(.shot(ShotTrace(from: origin, to: point, hit: true)))
            stats.hitsLanded += 1
            events += apply(target: target, damage: spec.damage, from: origin)
        } else {
            // A miss flies straight until a wall or the end of its range.
            var end = origin
            let step = foot.forward * 16
            var travelled = 0.0
            while travelled + 16 <= spec.range {
                let next = end + step
                if district.tile(at: next).isSolid { break }
                end = next
                travelled += 16
            }
            events.append(.shot(ShotTrace(from: origin, to: end, hit: false)))
        }
        if inventory.ammo(for: weapon) == 0 {
            inventory.switchIfEmpty()
            events.append(.outOfAmmo)
        }
        return events
    }

    // MARK: Witnesses

    /// Something illegal happened at `position`. A patrol that sees it reacts at once. Otherwise
    /// the nearest bystander with a clear view calls it in after `reportDelay`; with nobody
    /// watching, nothing happens.
    mutating func crime(heat: Double, at position: Vec2, victim: Int?) -> [CityEvent] {
        if pursuit.isSeen {
            pursuit.add(.missionEvent(heat))
            return []
        }
        let map = district
        let witness = crowd.people
            .filter { !$0.isDown && $0.id != victim && ($0.position - position).length <= Self.witnessRange }
            .filter { PatrolBrain.lineOfSight(from: $0.position, to: position, district: map) }
            .min { ($0.position - position).length < ($1.position - position).length }
        guard let witness else { return [] }
        // One witness, one call: a second crime in front of the same person adds to it.
        if let i = reports.firstIndex(where: { $0.witness == witness.id }) {
            let old = reports[i]
            reports[i] = CrimeReport(timeLeft: old.timeLeft, heat: old.heat + heat, position: position,
                                     ride: currentVehicleIndex, witness: witness.id)
            return []
        }
        reports.append(CrimeReport(timeLeft: Self.reportDelay, heat: heat, position: position,
                                   ride: currentVehicleIndex, witness: witness.id))
        return [.witnessed]
    }

    private mutating func stepReports(dt: Double) -> [CityEvent] {
        guard !reports.isEmpty else { return [] }
        var events: [CityEvent] = []
        var waiting: [CrimeReport] = []
        for var report in reports {
            report.timeLeft -= dt
            guard report.timeLeft <= 0 else {
                waiting.append(report)
                continue
            }
            let share = report.ride == currentVehicleIndex ? 1 : Self.wrongRideShare
            pursuit.report(heat: report.heat * share, at: report.position)
            events.append(.reported)
        }
        reports = waiting
        return events
    }

    // MARK: Live play

    /// Another player hit this one. On foot it costs health; in a vehicle, hull.
    public mutating func takeHit(damage: Int, from attacker: String?) -> [CityEvent] {
        lastAttacker = attacker
        if let i = currentVehicleIndex {
            vehicles[i].damage += max(1, damage / 2)
            return [.impact(0.6)]
        }
        health = max(0, health - PvP.health(fromDamage: damage))
        return [.impact(0.5)]
    }

    /// Knocked out by another player: they get a gun. Removes it and returns it with its ammo.
    public mutating func surrenderGun() -> (WeaponID, Int)? {
        guard let w = inventory.droppable, let left = inventory.lose(w) else { return nil }
        return (w, max(left, w.spec.ammoPack / 2))
    }

    /// Back on your feet at a spawn point (live play doesn't end on a knockout).
    public mutating func respawn(at spawn: SpawnPoint) {
        if let i = currentVehicleIndex { vehicles[i].state.velocity = .zero }
        mode = .onFoot
        foot = VehicleState(position: spawn.position, heading: spawn.heading)
        health = Self.maxHealth
        lastAttacker = nil
        reports.removeAll()
        pursuit.calmDown()
        officers.removeAll()
        standoff = .none
        surrenderTime = 0
    }

    /// Another player's dropped gun appears in the street.
    public mutating func addNetworkDrop(_ drop: NetDrop) {
        guard !pickups.contains(where: { $0.networkID == drop.id }) else { return }
        pickups.append(WeaponPickup(id: nextPickupID, weapon: drop.weapon, ammo: drop.ammo,
                                    position: Vec2(drop.x, drop.y), isDrop: true, lifetime: Self.dropLifetime,
                                    networkID: drop.id))
        nextPickupID += 1
    }

    /// The drop's owner decided: it's gone from the street, and this player has it if `mine`.
    public mutating func resolveNetworkDrop(_ id: String, mine: Bool) -> [CityEvent] {
        guard let i = pickups.firstIndex(where: { $0.networkID == id }) else { return [] }
        let pickup = pickups.remove(at: i)
        guard mine else { return [] }
        let before = inventory.ammo(for: pickup.weapon)
        inventory.acquire(pickup.weapon, ammo: pickup.ammo)
        return [.pickedUp(pickup.weapon, ammo: inventory.ammo(for: pickup.weapon) - before)]
    }

    private mutating func collectPickups(_ events: inout [CityEvent], dt: Double) {
        var gone: Set<Int> = []
        for i in pickups.indices {
            if pickups[i].isDrop {
                pickups[i].lifetime -= dt
                if pickups[i].lifetime <= 0 { gone.insert(pickups[i].id); continue }
            } else if pickups[i].respawn > 0 {
                pickups[i].respawn = max(0, pickups[i].respawn - dt)
                continue
            }
            guard (pickups[i].position - playerPosition).length < Self.pickupRadius else { continue }
            // Another player's gun: ask its owner, don't just take it.
            if let networkID = pickups[i].networkID {
                if !pickups[i].claimed {
                    pickups[i].claimed = true
                    events.append(.claimDrop(networkID))
                }
                continue
            }
            let weapon = pickups[i].weapon
            let before = inventory.ammo(for: weapon)
            let wasOwned = inventory.owns(weapon)
            let wasCapped = inventory.isCapped(weapon)
            // A gun in hand is a new gun: any starter limit on that model comes off.
            inventory.acquire(weapon, ammo: pickups[i].ammo)
            let gained = inventory.ammo(for: weapon) - before
            // A full weapon leaves the pickup lying there.
            guard gained > 0 || !wasOwned || wasCapped else { continue }
            if pickups[i].isDrop {
                gone.insert(pickups[i].id)
            } else {
                pickups[i].respawn = Self.pickupRespawn
            }
            events.append(.pickedUp(weapon, ammo: gained))
        }
        if !gone.isEmpty { pickups.removeAll { gone.contains($0.id) } }
    }
}
