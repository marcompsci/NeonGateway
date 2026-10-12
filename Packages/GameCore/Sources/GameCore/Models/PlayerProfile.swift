import Foundation

/// The player's character, made in onboarding: a name, a look and a first weapon.
public struct PlayerProfile: Codable, Sendable, Equatable {
    public static let skinCount = 5
    public static let hairCount = 5
    public static let jacketCount = 8
    public static let nameLength = 2...16

    public var name: String
    public var skin: Int
    public var hair: Int
    public var jacket: Int
    public var starter: WeaponID

    public init(name: String, skin: Int = 0, hair: Int = 0, jacket: Int = 0, starter: WeaponID = .pistol) {
        self.name = name
        self.skin = skin
        self.hair = hair
        self.jacket = jacket
        self.starter = starter
    }

    /// A tidy name, or nil if it can't be used: 2–16 characters of letters, numbers,
    /// spaces, hyphens, apostrophes or dots, with spaces trimmed and runs of spaces squeezed.
    public static func cleanName(_ raw: String) -> String? {
        let squeezed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard nameLength.contains(squeezed.count) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -'."))
        guard squeezed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard squeezed.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        // Other players see this name online.
        guard ContentFilter.isAllowedPublicName(squeezed) else { return nil }
        return squeezed
    }

    /// Indices kept in range, whatever was saved.
    public var normalized: PlayerProfile {
        var p = self
        p.skin = ((skin % Self.skinCount) + Self.skinCount) % Self.skinCount
        p.hair = ((hair % Self.hairCount) + Self.hairCount) % Self.hairCount
        p.jacket = ((jacket % Self.jacketCount) + Self.jacketCount) % Self.jacketCount
        return p
    }

    /// A random look for the dice button. The name is left to the player.
    public static func random<G: RandomNumberGenerator>(name: String, using rng: inout G) -> PlayerProfile {
        PlayerProfile(name: name,
                      skin: Int.random(in: 0..<skinCount, using: &rng),
                      hair: Int.random(in: 0..<hairCount, using: &rng),
                      jacket: Int.random(in: 0..<jacketCount, using: &rng),
                      starter: WeaponID.allCases.randomElement(using: &rng) ?? .pistol)
    }
}

public enum Onboarding {
    public enum Problem: Error, Equatable {
        case badName
        case alreadyDone
    }

    /// Creates the player and hands over their first weapon. Existing weapons are kept.
    @discardableResult
    public static func complete(_ draft: PlayerProfile, progress: inout PlayerProgress) -> Problem? {
        guard progress.profile == nil else { return .alreadyDone }
        guard let name = PlayerProfile.cleanName(draft.name) else { return .badName }
        var profile = draft.normalized
        profile.name = name
        progress.profile = profile
        if progress.inventory.owns(draft.starter) {
            // Already carrying this gun from an earlier build: it stays a full gun.
            progress.inventory.equipped = draft.starter
        } else {
            let others = progress.inventory.owned
            progress.inventory.addStarter(draft.starter)
            if !others.isEmpty { progress.inventory.equipped = draft.starter }
        }
        return nil
    }

    /// Changing the look later keeps the name, the starter and everything owned.
    public static func updateLook(skin: Int, hair: Int, jacket: Int, progress: inout PlayerProgress) {
        guard var profile = progress.profile else { return }
        profile.skin = skin
        profile.hair = hair
        profile.jacket = jacket
        progress.profile = profile.normalized
    }
}
