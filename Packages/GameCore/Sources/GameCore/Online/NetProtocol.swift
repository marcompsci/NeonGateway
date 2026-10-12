import Foundation

/// Live play: up to four players share Port Aurora. Each phone runs its own city (its own crowd
/// and patrols) and sends where its player is ten times a second; the others draw that player.
/// Damage is decided by the player who gets hit, so nobody can cheat someone else's health,
/// and a dropped gun belongs to whoever dropped it until they hand it to the first claimant.
public struct PlayerSnapshot: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var heading: Double
    public var speed: Double
    /// The vehicle they're in, or nil on foot.
    public var vehicle: VehicleID?
    public var weapon: WeaponID?
    public var health: Int
    /// The sender's clock (seconds since their match started), for ordering.
    public var time: Double

    public init(x: Double, y: Double, heading: Double, speed: Double, vehicle: VehicleID?, weapon: WeaponID?,
                health: Int, time: Double) {
        self.x = x
        self.y = y
        self.heading = heading
        self.speed = speed
        self.vehicle = vehicle
        self.weapon = weapon
        self.health = health
        self.time = time
    }

    public var position: Vec2 { Vec2(x, y) }
}

/// A gun lying in the street that came from another player.
public struct NetDrop: Codable, Sendable, Equatable {
    public var id: String
    /// Who dropped it (and decides who gets it).
    public var owner: String
    public var weapon: WeaponID
    public var ammo: Int
    public var x: Double
    public var y: Double

    public init(id: String, owner: String, weapon: WeaponID, ammo: Int, x: Double, y: Double) {
        self.id = id
        self.owner = owner
        self.weapon = weapon
        self.ammo = ammo
        self.x = x
        self.y = y
    }
}

public enum NetMessage: Codable, Sendable, Equatable {
    /// Sent once on joining: who you are and what you look like.
    case hello(name: String, profile: PlayerProfile, paint: [UInt8]?)
    case state(PlayerSnapshot)
    /// "I hit you": the target applies it (or ignores it if it's out of range or they're gone).
    /// `weapon` is nil when they were hit by a car.
    case hit(target: String, damage: Int, weapon: WeaponID?)
    /// The sender was knocked out, by `by` if another player did it.
    case knockedOut(by: String?)
    case drop(NetDrop)
    case claim(dropID: String)
    /// The drop's owner decided who gets it; everyone removes it.
    case granted(dropID: String, to: String)
}

public enum NetCodec {
    public static func encode(_ m: NetMessage) -> Data? { try? JSONEncoder().encode(m) }
    public static func decode(_ d: Data) -> NetMessage? { try? JSONDecoder().decode(NetMessage.self, from: d) }
}

/// PvP tuning.
public enum PvP {
    public static let maxPlayers = 4
    /// Health lost per point of weapon damage (pistol 1, rifle 3, shotgun 4 on a 100-health body).
    public static let healthPerDamage = 12
    /// A hit is ignored if the shooter was further than this from where the target is now
    /// (weapon range plus slack for lag).
    public static let rangeSlack = 160.0
    public static let snapshotsPerSecond = 10.0
    /// Seconds a remote player is drawn behind real time, so there are two snapshots to blend.
    public static let interpolationDelay = 0.15
    /// A player not heard from for this long is treated as gone.
    public static let timeout = 6.0

    /// Whether a reported hit is believable from where the shooter and target are.
    public static func plausible(shooter: Vec2, target: Vec2, weapon: WeaponID?, damage: Int) -> Bool {
        let reach = weapon?.spec.range ?? 80
        let strongest = weapon.map { $0.spec.damage * 2 } ?? City.runOverDamage
        return (shooter - target).length <= reach + rangeSlack && damage > 0 && damage <= strongest
    }

    public static func health(fromDamage damage: Int) -> Double {
        Double(max(0, damage) * healthPerDamage)
    }
}

/// Smooths a remote player's movement between snapshots.
public struct RemoteTrack: Sendable, Equatable {
    public private(set) var previous: PlayerSnapshot?
    public private(set) var latest: PlayerSnapshot?
    /// Local clock when `latest` arrived.
    public private(set) var receivedAt: Double = 0

    public init() {}

    public mutating func receive(_ s: PlayerSnapshot, at now: Double) {
        // Out-of-order packets are dropped.
        if let latest, s.time <= latest.time { return }
        previous = latest
        latest = s
        receivedAt = now
    }

    public func isStale(at now: Double) -> Bool { latest == nil || now - receivedAt > PvP.timeout }

    /// Where to draw the player at local time `now`: blended between the last two snapshots.
    public func pose(at now: Double) -> (position: Vec2, heading: Double)? {
        guard let latest else { return nil }
        guard let previous else { return (latest.position, latest.heading) }
        let span = max(0.001, latest.time - previous.time)
        let t = min(1.5, max(0, (now - receivedAt + span - PvP.interpolationDelay) / span))
        let p = previous.position + (latest.position - previous.position) * t
        var dh = remainder(latest.heading - previous.heading, 2 * .pi)
        if !dh.isFinite { dh = 0 }
        return (p, previous.heading + dh * min(1, t))
    }
}

/// The owner's side of dropped guns: the first claim wins, later ones are refused.
public struct DropArbiter: Sendable, Equatable {
    public let owner: String
    public private(set) var open: [String: NetDrop] = [:]
    private var serial = 0

    public init(owner: String) { self.owner = owner }

    /// A new drop at the owner's feet.
    public mutating func makeDrop(weapon: WeaponID, ammo: Int, at p: Vec2) -> NetDrop {
        serial += 1
        let drop = NetDrop(id: "\(owner)#\(serial)", owner: owner, weapon: weapon, ammo: ammo, x: p.x, y: p.y)
        open[drop.id] = drop
        return drop
    }

    /// Returns who gets it if this claim wins; nil if it's gone or not ours.
    public mutating func claim(_ id: String, by player: String) -> String? {
        guard open.removeValue(forKey: id) != nil else { return nil }
        return player
    }

    /// Drops that expired on the ground.
    public mutating func expire(_ id: String) { open.removeValue(forKey: id) }
}
