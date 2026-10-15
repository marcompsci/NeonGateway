import Foundation

/// Weapons in Port Aurora. Names and models are invented; the art is chunky pixel cartoon.
public enum WeaponID: String, Codable, Sendable, CaseIterable {
    case bat
    case pistol
    case smg
    case shotgun
    case rifle

    public var spec: WeaponSpec {
        switch self {
        case .bat:
            WeaponSpec(id: self, name: "Slugger bat", damage: 1, fireInterval: 0.5, range: 52,
                       aimHalfAngle: .pi / 3, maxAmmo: 0, price: 120, ammoPack: 0, ammoPrice: 0, isMelee: true)
        case .pistol:
            WeaponSpec(id: self, name: "Ember 9 pistol", damage: 1, fireInterval: 0.35, range: 420,
                       aimHalfAngle: .pi / 6, maxAmmo: 120, price: 300, ammoPack: 24, ammoPrice: 40)
        case .smg:
            WeaponSpec(id: self, name: "Rattler SMG", damage: 1, fireInterval: 0.11, range: 360,
                       aimHalfAngle: .pi / 7, maxAmmo: 300, price: 900, ammoPack: 60, ammoPrice: 90)
        case .shotgun:
            WeaponSpec(id: self, name: "Breaker shotgun", damage: 4, fireInterval: 0.85, range: 230,
                       aimHalfAngle: .pi / 4, maxAmmo: 40, price: 1200, ammoPack: 8, ammoPrice: 80)
        case .rifle:
            WeaponSpec(id: self, name: "Longshot rifle", damage: 3, fireInterval: 1.2, range: 620,
                       aimHalfAngle: .pi / 10, maxAmmo: 60, price: 1600, ammoPack: 10, ammoPrice: 100)
        }
    }

    /// One-line description for the onboarding picker and the store.
    public var pitch: String {
        switch self {
        case .bat: "Close up and quiet. Never runs out."
        case .pistol: "Reliable all-rounder. Easy to find ammo for."
        case .smg: "Sprays fast at mid range. Eats ammo."
        case .shotgun: "Huge hit up close. Slow to fire again."
        case .rifle: "Reaches across a whole block. Slow and steady."
        }
    }
}

public struct WeaponSpec: Sendable, Equatable {
    public let id: WeaponID
    public let name: String
    /// Damage per hit. A bystander drops at 1; a patrol cruiser takes `Patrol.maxHealth`.
    public let damage: Int
    /// Seconds between shots (or swings) while FIRE is held.
    public let fireInterval: Double
    /// How far a shot reaches, points (a swing for melee).
    public let range: Double
    /// Auto-aim: the nearest target within this angle either side of facing is hit.
    public let aimHalfAngle: Double
    /// Most ammo a full (non-starter) gun can carry. 0 for melee.
    public let maxAmmo: Int
    /// Gun store prices, credits.
    public let price: Int
    public let ammoPack: Int
    public let ammoPrice: Int
    /// Melee weapons never use ammo and never leave tracers.
    public var isMelee = false
}

/// What the player carries. Saved with progress. A weapon is owned while it has an entry,
/// even at 0 ammo (the store sells ammo for it).
///
/// A starter gun (chosen when the player is created) is capped at `starterAmmoCap` rounds.
/// The cap comes off when the gun is modded (Extended Mag at Bolt & Barrel) or when the
/// player gets a new one of the same gun: buying it, or taking one from a cruiser, a
/// dealer or a civilian.
public struct Inventory: Codable, Sendable, Equatable {
    public static let starterAmmoCap = 35

    /// Ammo per owned weapon, keyed by `WeaponID.rawValue`.
    public var ammo: [String: Int] = [:]
    public var equipped: WeaponID?
    /// Starter guns still held to `starterAmmoCap`.
    public var capped: Set<String> = []
    /// Workbench builds per weapon (parts and finish), keyed by `WeaponID.rawValue`.
    public var builds: [String: GunBuild] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey { case ammo, equipped, capped, builds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ammo = try c.decodeIfPresent([String: Int].self, forKey: .ammo) ?? [:]
        // An unknown weapon id (from a newer build) just isn't equipped.
        equipped = (try? c.decodeIfPresent(WeaponID.self, forKey: .equipped)) ?? nil
        capped = try c.decodeIfPresent(Set<String>.self, forKey: .capped) ?? []
        builds = (try? c.decodeIfPresent([String: GunBuild].self, forKey: .builds)) ?? [:]
    }

    /// The weapon as built: base stats changed by its installed parts.
    public func spec(for w: WeaponID) -> WeaponSpec { build(for: w).apply(to: w.spec) }

    public func build(for w: WeaponID) -> GunBuild { builds[w.rawValue] ?? GunBuild() }

    public var owned: [WeaponID] { WeaponID.allCases.filter { ammo[$0.rawValue] != nil } }

    public func owns(_ w: WeaponID) -> Bool { ammo[w.rawValue] != nil }

    public func ammo(for w: WeaponID) -> Int { ammo[w.rawValue] ?? 0 }

    public func isCapped(_ w: WeaponID) -> Bool { capped.contains(w.rawValue) }

    /// Most rounds this weapon can carry right now.
    public func ammoCap(for w: WeaponID) -> Int {
        if w.spec.isMelee { return 0 }
        let max = spec(for: w).maxAmmo
        return isCapped(w) ? min(Self.starterAmmoCap, max) : max
    }

    /// Can this weapon be used right now (melee always; guns with ammo)?
    public func isLoaded(_ w: WeaponID) -> Bool { owns(w) && (w.spec.isMelee || ammo(for: w) > 0) }

    /// The player's first weapon. Guns start full but capped at 35 rounds.
    public mutating func addStarter(_ w: WeaponID) {
        if w.spec.isMelee {
            ammo[w.rawValue] = 0
        } else {
            capped.insert(w.rawValue)
            ammo[w.rawValue] = ammoCap(for: w)
        }
        equipped = w
    }

    /// Adds ammo (and the weapon, if new) within the current cap. Equips it if nothing usable is.
    public mutating func add(_ w: WeaponID, ammo amount: Int) {
        ammo[w.rawValue] = min(ammoCap(for: w), ammo(for: w) + max(0, amount))
        if equipped == nil || !isLoaded(equipped!) { equipped = w }
    }

    /// A new gun in hand (bought, found or taken): any starter cap on that gun comes off.
    public mutating func acquire(_ w: WeaponID, ammo amount: Int) {
        capped.remove(w.rawValue)
        add(w, ammo: amount)
    }

    /// Hands a weapon over (knocked out by another player): it's gone, with its ammo. Returns
    /// the ammo it had, or nil if the player didn't own it.
    @discardableResult
    public mutating func lose(_ w: WeaponID) -> Int? {
        guard owns(w) else { return nil }
        let left = ammo(for: w)
        ammo.removeValue(forKey: w.rawValue)
        capped.remove(w.rawValue)
        if equipped == w {
            equipped = owned.first { isLoaded($0) && !$0.spec.isMelee } ?? owned.first
        }
        return left
    }

    /// The gun a knocked-out player drops: the one in hand if it's a gun, else their best loaded
    /// gun. Melee weapons are never dropped.
    public var droppable: WeaponID? {
        if let w = equipped, !w.spec.isMelee { return w }
        return owned.filter { !$0.spec.isMelee }.max { $0.spec.price < $1.spec.price }
    }

    /// The Extended Mag mod: lifts the starter cap.
    public mutating func uncap(_ w: WeaponID) { capped.remove(w.rawValue) }

    /// Uses one round of the equipped weapon (melee never runs out). False if it can't fire.
    public mutating func consumeRound() -> Bool {
        guard let w = equipped, owns(w) else { return false }
        if w.spec.isMelee { return true }
        guard ammo(for: w) > 0 else { return false }
        ammo[w.rawValue] = ammo(for: w) - 1
        return true
    }

    /// Puts a particular weapon in hand (the weapon bar). False if it isn't owned or is empty.
    @discardableResult
    public mutating func equip(_ w: WeaponID) -> Bool {
        guard isLoaded(w) else { return false }
        equipped = w
        return true
    }

    /// Next usable weapon after the equipped one; stays put if there's none.
    public mutating func cycle() {
        let loaded = owned.filter { isLoaded($0) }
        guard !loaded.isEmpty else { return }
        if let current = equipped, let i = loaded.firstIndex(of: current) {
            equipped = loaded[(i + 1) % loaded.count]
        } else {
            equipped = loaded[0]
        }
    }

    /// After running dry, switch to another loaded gun, else to a melee weapon.
    mutating func switchIfEmpty() {
        guard let w = equipped, !isLoaded(w) else { return }
        if let gun = owned.first(where: { !$0.spec.isMelee && isLoaded($0) }) {
            equipped = gun
        } else if let melee = owned.first(where: { $0.spec.isMelee }) {
            equipped = melee
        }
    }

    public var canFire: Bool { equipped.map { isLoaded($0) } ?? false }
}

/// One part on the Workbench. Each slot holds one part (or the stock part, nil).
public enum GunPart: String, Codable, Sendable, CaseIterable {
    case longBarrel, shortBarrel
    case extendedMag
    case steadyGrip, quickGrip

    public enum Slot: String, Sendable, CaseIterable { case barrel, magazine, grip }

    public var slot: Slot {
        switch self {
        case .longBarrel, .shortBarrel: .barrel
        case .extendedMag: .magazine
        case .steadyGrip, .quickGrip: .grip
        }
    }

    public var name: String {
        switch self {
        case .longBarrel: "Long barrel"
        case .shortBarrel: "Snub barrel"
        case .extendedMag: "Extended mag"
        case .steadyGrip: "Steady grip"
        case .quickGrip: "Quick grip"
        }
    }

    /// What it does, in plain words.
    public var effect: String {
        switch self {
        case .longBarrel: "+30% reach, a little slower to fire"
        case .shortBarrel: "15% faster to fire, −20% reach"
        case .extendedMag: "No starter limit, +50% ammo you can carry"
        case .steadyGrip: "Auto-aim catches targets 40% wider"
        case .quickGrip: "15% faster to fire, slightly narrower aim"
        }
    }

    public var price: Int {
        switch self {
        case .longBarrel, .shortBarrel: 200
        case .extendedMag: 250
        case .steadyGrip, .quickGrip: 180
        }
    }

    /// Melee weapons only take a finish.
    public func fits(_ w: WeaponID) -> Bool { !w.spec.isMelee }
}

/// A gun as built at the Workbench: one part per slot plus a paint finish.
public struct GunBuild: Codable, Sendable, Equatable {
    /// Finish colours offered (index into the app's finish palette); 0 = factory.
    public static let finishCount = 8
    public static let finishPrice = 60

    public var barrel: GunPart?
    public var magazine: GunPart?
    public var grip: GunPart?
    public var finish = 0
    /// Parts bought for this gun; swapping between them is free.
    public var owned: Set<GunPart> = []

    public init() {}

    public func installed(_ slot: GunPart.Slot) -> GunPart? {
        switch slot {
        case .barrel: barrel
        case .magazine: magazine
        case .grip: grip
        }
    }

    public mutating func install(_ part: GunPart?, in slot: GunPart.Slot) {
        switch slot {
        case .barrel: barrel = part
        case .magazine: magazine = part
        case .grip: grip = part
        }
    }

    /// Base stats changed by the installed parts.
    public func apply(to base: WeaponSpec) -> WeaponSpec {
        guard !base.isMelee else { return base }
        var range = base.range
        var interval = base.fireInterval
        var aim = base.aimHalfAngle
        var maxAmmo = base.maxAmmo
        switch barrel {
        case .longBarrel?: range *= 1.3; interval *= 1.1
        case .shortBarrel?: range *= 0.8; interval *= 0.85
        default: break
        }
        if magazine == .extendedMag { maxAmmo = Int((Double(maxAmmo) * 1.5).rounded()) }
        switch grip {
        case .steadyGrip?: aim *= 1.4
        case .quickGrip?: interval *= 0.85; aim *= 0.9
        default: break
        }
        return WeaponSpec(id: base.id, name: base.name, damage: base.damage, fireInterval: interval, range: range,
                          aimHalfAngle: aim, maxAmmo: maxAmmo, price: base.price, ammoPack: base.ammoPack,
                          ammoPrice: base.ammoPrice, isMelee: base.isMelee)
    }
}
