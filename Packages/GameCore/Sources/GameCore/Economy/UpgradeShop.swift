import Foundation

public struct UpgradeTier: Sendable, Equatable {
    public let track: UpgradeTrack
    /// The level this purchase reaches (1...4).
    public let level: Int
    public let cost: Int
    public let requiredRepLevel: Int
}

public enum UpgradeShop {
    public static let maxLevel = 4
    /// Cost and reputation gate of levels 1...4, the same for every track.
    public static let costs = [150, 400, 900, 1800]
    public static let repGates = [0, 1, 2, 3]

    public enum Refusal: Error, Equatable {
        case maxed
        case needsRep(Int)
        case needsCredits(short: Int)
    }

    public static func level(_ track: UpgradeTrack, in levels: UpgradeLevels) -> Int {
        switch track {
        case .speed: levels.speed
        case .handling: levels.handling
        case .durability: levels.durability
        }
    }

    public static func nextTier(_ track: UpgradeTrack, levels: UpgradeLevels) -> UpgradeTier? {
        let current = level(track, in: levels)
        guard current < maxLevel else { return nil }
        return UpgradeTier(track: track, level: current + 1, cost: costs[current],
                           requiredRepLevel: repGates[current])
    }

    /// Whether the next level of `track` can be bought now, and if not, why.
    public static func check(_ track: UpgradeTrack, progress: PlayerProgress) -> Result<UpgradeTier, Refusal> {
        guard let tier = nextTier(track, levels: progress.upgrades) else { return .failure(.maxed) }
        let rep = ProgressionRules.level(forXP: progress.reputationXP)
        if rep < tier.requiredRepLevel { return .failure(.needsRep(tier.requiredRepLevel)) }
        if progress.credits < tier.cost { return .failure(.needsCredits(short: tier.cost - progress.credits)) }
        return .success(tier)
    }

    /// Buys the next level: takes the credits and raises the track. Changes nothing if refused.
    @discardableResult
    public static func buy(_ track: UpgradeTrack, progress: inout PlayerProgress,
                           now: Date = Date()) -> Result<UpgradeTier, Refusal> {
        let result = check(track, progress: progress)
        if case .success(let tier) = result {
            progress.credits -= tier.cost
            switch track {
            case .speed: progress.upgrades.speed = tier.level
            case .handling: progress.upgrades.handling = tier.level
            case .durability: progress.upgrades.durability = tier.level
            }
            progress.books.record(-tier.cost, .upgrades, "\(track.rawValue.capitalized) level \(tier.level)", on: now)
            progress.lastUpdated = now
        }
        return result
    }

    /// The car with upgrades applied.
    /// Speed: +8% top speed and +6% acceleration per level.
    /// Handling: +10% turn rate per level and firmer grip (less sideways slip).
    /// Durability: +1 hull point per level.
    public static func spec(_ base: VehicleSpec, levels: UpgradeLevels) -> VehicleSpec {
        var s = base
        let speed = Double(min(max(levels.speed, 0), maxLevel))
        let handling = Double(min(max(levels.handling, 0), maxLevel))
        let durability = min(max(levels.durability, 0), maxLevel)
        s.maxSpeed *= 1 + 0.08 * speed
        s.acceleration *= 1 + 0.06 * speed
        s.turnRate *= 1 + 0.10 * handling
        s.lateralRetention = max(0.3, s.lateralRetention - 0.04 * handling)
        s.maxIntegrity += durability
        return s
    }

    /// Plain-words effect of one level, for the Garage.
    public static func effectText(_ track: UpgradeTrack) -> String {
        switch track {
        case .speed: "+8% top speed, +6% acceleration"
        case .handling: "+10% steering, firmer grip"
        case .durability: "+1 hull point"
        }
    }
}
