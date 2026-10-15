import Foundation

/// A Harbor Patrol officer out of the cruiser on foot.
public struct Officer: Sendable, Equatable, Identifiable {
    public let id: Int
    /// The cruiser they came from.
    public let patrolID: Int
    public var position: Vec2
    public var heading: Double
    public var health = Officer.maxHealth
    /// Walking back to the cruiser to drive off.
    public var returning = false
    var fireCooldown: Double
    var downTime = 0.0

    public static let maxHealth = 3
    public var isDown: Bool { health <= 0 }
}

/// How a stop with officers on foot is going.
public enum Standoff: Sendable, Equatable {
    case none
    /// "Freeze!": seconds left before they open fire.
    case warning(Double)
    /// Shots fired: officers shoot on sight.
    case firing

    public var secondsLeft: Int? {
        if case .warning(let t) = self { return max(1, Int(t.rounded(.up))) }
        return nil
    }
    public var isFiring: Bool { self == .firing }
}

/// The rules for officers on foot.
public enum CopRules {
    /// A chasing cruiser this close to a slow (or walking) player pulls over and the officers get out.
    public static let dismountDistance = 300.0
    /// The player has to be slower than this (points/s) for a cruiser to pull over.
    public static let dismountPlayerSpeed = 130.0
    /// Officers only get out at this many stars (lower heat is a ticket from the car), unless shot at.
    public static let dismountStars = 2
    /// The warning before they shoot.
    public static let warningSeconds = 5.0
    public static let range = 430.0
    public static let fireInterval = 1.1
    public static let walkSpeed = 150.0
    /// Officers close in to about this far and hold.
    public static let holdDistance = 190.0
    /// Health lost per hit on foot.
    public static let footDamage = 7.0
    /// Hits on a vehicle per hull point.
    public static let hitsPerHull = 3
    /// The player this far from an officer: they head back to the cruiser.
    public static let remountDistance = 900.0
    /// Shooting at cops makes every cruiser this close pull over and fire back.
    public static let retaliationRadius = 650.0
    /// Standing still this long near an officer (not shooting) is giving up.
    public static let surrenderSeconds = 2.5
    public static let surrenderDistance = 260.0
    /// A knocked-down officer is picked up after this long.
    public static let downSeconds = 20.0
    public static let shotHeat = 6.0
    public static let downHeat = 12.0
}

extension City {
    /// Officers getting out, warning, shooting, and getting back in. Runs after the patrols move.
    mutating func stepOfficers(dt: Double) -> [CityEvent] {
        var events: [CityEvent] = []
        let player = self.player
        let stars = pursuit.heat.stars
        sinceShot += dt

        // Heat gone: nobody is after the player any more; officers walk back.
        if stars == 0 {
            standoff = .none
            for i in officers.indices where !officers[i].isDown { officers[i].returning = true }
        }

        // Pull over: chasing cruisers close to a slow player.
        let hostile = standoff.isFiring
        if stars >= CopRules.dismountStars || (hostile && stars > 0) {
            for patrol in pursuit.patrols where !patrol.parked && patrol.mode == .chase {
                let gap = (patrol.car.position - player.position).length
                guard gap < CopRules.dismountDistance, player.speed < CopRules.dismountPlayerSpeed,
                      PatrolBrain.lineOfSight(from: patrol.car.position, to: player.position, district: district) else { continue }
                events += dismount(patrol.id)
            }
        }

        // The warning runs out.
        if case .warning(let t) = standoff {
            let left = t - dt
            if left <= 0 {
                standoff = .firing
                events.append(.copsOpenFire)
            } else {
                standoff = .warning(left)
            }
        }

        // Officers move and shoot.
        var hullHits = 0
        for i in officers.indices {
            if officers[i].isDown {
                officers[i].downTime += dt
                continue
            }
            var o = officers[i]
            let toPlayer = player.position - o.position
            let gap = toPlayer.length
            if gap > CopRules.remountDistance || (currentVehicleIndex != nil && player.speed > 250 && gap > 450) {
                o.returning = true
            }
            if o.returning {
                let car = pursuit.patrols.first { $0.id == o.patrolID }?.car.position
                guard let car else {
                    o.downTime = CopRules.downSeconds + 1   // no cruiser left: gone
                    officers[i] = o
                    continue
                }
                o = walk(o, toward: car, dt: dt)
                if (car - o.position).length < 36 { o.downTime = CopRules.downSeconds + 1 }
                officers[i] = o
                continue
            }
            let sees = PatrolBrain.lineOfSight(from: o.position, to: player.position, district: district)
            o.heading = atan2(toPlayer.y, toPlayer.x)
            if gap > CopRules.holdDistance || !sees {
                o = walk(o, toward: player.position, dt: dt)
                o.heading = atan2(toPlayer.y, toPlayer.x)
            }
            o.fireCooldown -= dt
            if standoff.isFiring && sees && gap < CopRules.range && o.fireCooldown <= 0 {
                o.fireCooldown = CopRules.fireInterval * (0.85 + Double(rng.next() % 30) / 100)
                // Closer is likelier; a car on the move is hard to hit.
                var chance = min(0.7, max(0.2, 0.78 - gap / 700))
                if currentVehicleIndex != nil && player.speed > 120 { chance *= 0.5 }
                let hit = Double(rng.next() % 1000) / 1000 < chance
                var to = player.position
                if !hit {
                    let side = Vec2(-toPlayer.y, toPlayer.x) * (1 / max(1, gap))
                    to = player.position + side * (rng.next() % 2 == 0 ? 34 : -34) + toPlayer * (60 / max(1, gap))
                }
                events.append(.copShot(ShotTrace(from: o.position, to: to, hit: hit)))
                if hit {
                    hits += 1
                    if currentVehicleIndex != nil {
                        hullHits += 1
                    } else {
                        health -= CopRules.footDamage
                    }
                    events.append(.impact(0.35))
                }
            }
            officers[i] = o
        }
        if hullHits > 0, let v = currentVehicleIndex {
            copHullHits += hullHits
            while copHullHits >= CopRules.hitsPerHull {
                copHullHits -= CopRules.hitsPerHull
                vehicles[v].damage += 1
            }
        }

        // Picked up / back in the car.
        let gone = officers.filter { $0.downTime > CopRules.downSeconds }
        if !gone.isEmpty {
            officers.removeAll { $0.downTime > CopRules.downSeconds }
            for id in Set(gone.map(\.patrolID)) where !officers.contains(where: { $0.patrolID == id && !$0.isDown }) {
                officers.removeAll { $0.patrolID == id }
                pursuit.setParked(id, false)
            }
        }
        // A cruiser whose officers are all down sits there until they're picked up.
        if officers.isEmpty && !standoff.isFiring { standoff = .none }

        // Giving up: standing still near an officer without shooting.
        let nearOfficer = officers.contains { !$0.isDown && !$0.returning && ($0.position - player.position).length < CopRules.surrenderDistance }
        if nearOfficer && player.speed < 25 && sinceShot > 1 && stars > 0 {
            surrenderTime += dt
        } else {
            surrenderTime = max(0, surrenderTime - dt * 2)
        }
        if surrenderTime >= CopRules.surrenderSeconds {
            surrenderTime = 0
            switch pursuit.caught() {
            case .ticketed:
                reports.removeAll()
                stats.ticketsPaid += 1
                standoff = .none
                for i in officers.indices where !officers[i].isDown { officers[i].returning = true }
                events.append(.ticketed)
            default:
                events.append(.busted)
            }
        }
        return events
    }

    /// Fraction of the surrender (0...1), for the HUD.
    public var surrenderFraction: Double { min(1, surrenderTime / CopRules.surrenderSeconds) }

    /// A cruiser pulls over and two officers step out either side.
    private mutating func dismount(_ patrolID: Int) -> [CityEvent] {
        guard let patrol = pursuit.patrols.first(where: { $0.id == patrolID }), !patrol.parked else { return [] }
        pursuit.setParked(patrolID, true)
        let car = patrol.car
        let side = Vec2(-sin(car.heading), cos(car.heading))
        for sign in [1.0, -1.0] {
            var spot = car.position + side * (sign * 42)
            if district.tile(at: spot).isSolid { spot = car.position - car.forward * 50 }
            officers.append(Officer(id: nextOfficerID, patrolID: patrolID, position: spot, heading: car.heading,
                                    fireCooldown: standoff.isFiring ? 0.25 + Double(nextOfficerID % 3) * 0.2 : CopRules.fireInterval))
            nextOfficerID += 1
        }
        var events: [CityEvent] = [.officersOut(patrolID)]
        if standoff == .none {
            standoff = .warning(CopRules.warningSeconds)
            events.append(.copsWarning)
        }
        return events
    }

    private func walk(_ officer: Officer, toward target: Vec2, dt: Double) -> Officer {
        var o = officer
        let delta = target - o.position
        let d = delta.length
        guard d > 1 else { return o }
        var body = VehicleState(position: o.position + delta * (min(d, CopRules.walkSpeed * dt) / d), heading: o.heading)
        body = Collision.resolve(body, radius: FootDynamics.radius,
                                 solids: district.solids(near: body.position, radius: FootDynamics.radius),
                                 restitution: 0).state
        o.position = body.position
        o.heading = atan2(delta.y, delta.x)
        return o
    }

    /// The player shot at Harbor Patrol: no more warnings. Nearby cruisers pull over and every
    /// officer fires back at once.
    mutating func provokeCops(from origin: Vec2) -> [CityEvent] {
        var events: [CityEvent] = []
        let wasFiring = standoff.isFiring
        standoff = .firing
        // Shooting at Harbor Patrol is at least "Wanted" (two stars).
        let wanted = HeatRules.starThresholds[CopRules.dismountStars - 1]
        if pursuit.heat.points < wanted { pursuit.add(.missionEvent(wanted - pursuit.heat.points + 1)) }
        for i in officers.indices where !officers[i].isDown {
            officers[i].returning = false
            officers[i].fireCooldown = min(officers[i].fireCooldown, 0.2)
        }
        for patrol in pursuit.patrols where !patrol.parked
            && (patrol.car.position - origin).length < CopRules.retaliationRadius {
            events += dismount(patrol.id)
        }
        if !wasFiring { events.append(.copsOpenFire) }
        return events
    }

    /// A shot lands on an officer.
    mutating func hitOfficer(_ id: Int, damage: Int, from origin: Vec2) -> [CityEvent] {
        guard let i = officers.firstIndex(where: { $0.id == id }), !officers[i].isDown else { return [] }
        pursuit.add(.missionEvent(CopRules.shotHeat))
        var events = provokeCops(from: origin)
        officers[i].health -= max(1, damage)
        if officers[i].isDown {
            pursuit.add(.missionEvent(CopRules.downHeat))
            events.append(.officerDown(id))
            // Every officer carries a sidearm; it lands in the street.
            events += drop(.pistol, ammo: WeaponID.pistol.spec.ammoPack, at: officers[i].position)
        }
        return events
    }
}
