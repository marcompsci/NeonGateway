import Foundation

/// Everything the game saves. Field names stay stable so a CloudKit record can mirror them later.
/// Decoding tolerates missing fields, so saves from older builds load instead of resetting.
public struct PlayerProgress: Codable, Sendable, Equatable {
    public var schemaVersion: Int = PlayerProgress.currentSchema
    public var credits: Int = 0
    public var reputationXP: Int = 0
    public var completedJobs: Int = 0
    public var bestEscapeStreak: Int = 0
    public var currentEscapeStreak: Int = 0
    public var upgrades: UpgradeLevels = .init()
    /// Keyed by `MissionID.rawValue` so the JSON stays a plain object.
    public var missionBests: [String: MissionBest] = [:]
    public var lastUpdated: Date = .distantPast
    /// Weapons and ammo (schema 2).
    public var inventory = Inventory()
    /// Vehicles the player owns; slot 0 is always the starter Vesper (schema 2).
    public var garage: [OwnedVehicle] = [OwnedVehicle(model: .vesper)]
    /// Garage slot the player starts runs in.
    public var selectedVehicle = 0
    /// Every credit in and out (schema 2).
    public var books = Books()
    /// The player's character; nil until onboarding is finished.
    public var profile: PlayerProfile?
    /// Paint designs the player owns: bought in the body shop or drawn in the studio.
    public var designs: [PaintDesign] = []
    /// The player's own designs on sale in the body shop.
    public var listings: [DesignListing] = []
    /// Market days so far (one per finished job).
    public var marketDay = 0
    /// Numbers the player's designs ("mine.0", "mine.1", ...).
    public var designSerial = 0
    /// The weekly money league (schema 3).
    public var league = LeagueState()
    /// Daily streak and Job of the day (schema 3).
    public var daily = DailyState()
    /// Harbor Savings (schema 3).
    public var bank = BankAccount()
    /// Businesses the player owns (schema 3).
    public var properties: [OwnedProperty] = []
    /// Driving, shooting, stamina and hustle XP (schema 3).
    public var skills = SkillBook()
    /// Lifetime totals (schema 3).
    public var career = CareerStats()
    /// Trophies whose reward has been collected (schema 3).
    public var claimedAchievements: [String] = []
    /// Online market, blocks, reports and live-play record (schema 4).
    public var online = OnlineState()

    /// 2: weapons, garage and the business ledger. 3: league, dailies, bank, businesses, skills.
    /// 4: online state.
    public static let currentSchema = 4

    /// The car the player starts runs in.
    public var selectedModel: VehicleID {
        garage.indices.contains(selectedVehicle) ? garage[selectedVehicle].model : .vesper
    }

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, credits, reputationXP, completedJobs, bestEscapeStreak,
             currentEscapeStreak, upgrades, missionBests, lastUpdated,
             inventory, garage, selectedVehicle, books, profile,
             designs, listings, marketDay, designSerial,
             league, daily, bank, properties, skills, career, claimedAchievements, online
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlayerProgress()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        credits = try c.decodeIfPresent(Int.self, forKey: .credits) ?? d.credits
        reputationXP = try c.decodeIfPresent(Int.self, forKey: .reputationXP) ?? d.reputationXP
        completedJobs = try c.decodeIfPresent(Int.self, forKey: .completedJobs) ?? d.completedJobs
        bestEscapeStreak = try c.decodeIfPresent(Int.self, forKey: .bestEscapeStreak) ?? d.bestEscapeStreak
        currentEscapeStreak = try c.decodeIfPresent(Int.self, forKey: .currentEscapeStreak) ?? d.currentEscapeStreak
        upgrades = try c.decodeIfPresent(UpgradeLevels.self, forKey: .upgrades) ?? d.upgrades
        missionBests = try c.decodeIfPresent([String: MissionBest].self, forKey: .missionBests) ?? d.missionBests
        lastUpdated = try c.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? d.lastUpdated
        inventory = (try? c.decodeIfPresent(Inventory.self, forKey: .inventory)) ?? d.inventory
        let savedGarage = (try? c.decodeIfPresent([OwnedVehicle].self, forKey: .garage)) ?? d.garage
        garage = savedGarage.isEmpty ? d.garage : savedGarage
        selectedVehicle = try c.decodeIfPresent(Int.self, forKey: .selectedVehicle) ?? d.selectedVehicle
        books = (try? c.decodeIfPresent(Books.self, forKey: .books)) ?? d.books
        profile = (try? c.decodeIfPresent(PlayerProfile.self, forKey: .profile)) ?? nil
        designs = (try? c.decodeIfPresent([PaintDesign].self, forKey: .designs)) ?? []
        listings = (try? c.decodeIfPresent([DesignListing].self, forKey: .listings)) ?? []
        marketDay = try c.decodeIfPresent(Int.self, forKey: .marketDay) ?? 0
        designSerial = try c.decodeIfPresent(Int.self, forKey: .designSerial) ?? 0
        league = (try? c.decodeIfPresent(LeagueState.self, forKey: .league)) ?? LeagueState()
        daily = (try? c.decodeIfPresent(DailyState.self, forKey: .daily)) ?? DailyState()
        bank = (try? c.decodeIfPresent(BankAccount.self, forKey: .bank)) ?? BankAccount()
        properties = ((try? c.decodeIfPresent([Lossy<OwnedProperty>].self, forKey: .properties)) ?? [])
            .compactMap(\.value)
        skills = (try? c.decodeIfPresent(SkillBook.self, forKey: .skills)) ?? SkillBook()
        career = (try? c.decodeIfPresent(CareerStats.self, forKey: .career)) ?? CareerStats()
        claimedAchievements = (try? c.decodeIfPresent([String].self, forKey: .claimedAchievements)) ?? []
        online = (try? c.decodeIfPresent(OnlineState.self, forKey: .online)) ?? OnlineState()
        // An old save is upgraded in place, not thrown away.
        schemaVersion = max(schemaVersion, PlayerProgress.currentSchema)
    }
}

public struct MissionBest: Codable, Sendable, Equatable {
    public var bestScore: Int
    public var bestTime: Double?
    public var timesCompleted: Int

    public init(bestScore: Int, bestTime: Double?, timesCompleted: Int) {
        self.bestScore = bestScore
        self.bestTime = bestTime
        self.timesCompleted = timesCompleted
    }
}

public enum UpgradeTrack: String, Codable, Sendable, CaseIterable {
    case speed, handling, durability
}

public struct UpgradeLevels: Codable, Sendable, Equatable {
    public var speed = 0
    public var handling = 0
    public var durability = 0

    public init() {}
}

/// Player-facing options. `reduceMotionOverride == nil` follows the iOS setting.
public struct GameSettings: Codable, Sendable, Equatable {
    public var soundOn = true
    public var hapticsOn = true
    public var crtOn = false
    public var reduceMotionOverride: Bool? = nil
    /// How generously shots snap to targets.
    public var aimAssist: AimAssist = .standard
    /// Frame rate: 60 normally, 30 to save battery, 120 on ProMotion screens.
    public var frameRate = 60
    /// Size of the on-screen buttons, 0.8...1.4.
    public var controlScale = 1.0
    /// How see-through the on-screen buttons are, 0.35...1.
    public var controlOpacity = 1.0
    /// Steering on the right, pedals on the left.
    public var leftHanded = false
    /// Where the player dragged the two button clusters, in points from their default spots.
    public var steerOffset = LayoutOffset()
    public var pedalOffset = LayoutOffset()
    /// Weather and time of day follow the real clock.
    public var liveWeather = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case soundOn, hapticsOn, crtOn, reduceMotionOverride, aimAssist, frameRate, controlScale,
             controlOpacity, leftHanded, steerOffset, pedalOffset, liveWeather
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameSettings()
        soundOn = (try? c.decodeIfPresent(Bool.self, forKey: .soundOn)) ?? d.soundOn
        hapticsOn = (try? c.decodeIfPresent(Bool.self, forKey: .hapticsOn)) ?? d.hapticsOn
        crtOn = (try? c.decodeIfPresent(Bool.self, forKey: .crtOn)) ?? d.crtOn
        reduceMotionOverride = try? c.decodeIfPresent(Bool.self, forKey: .reduceMotionOverride)
        aimAssist = (try? c.decodeIfPresent(AimAssist.self, forKey: .aimAssist)) ?? d.aimAssist
        frameRate = (try? c.decodeIfPresent(Int.self, forKey: .frameRate)) ?? d.frameRate
        controlScale = (try? c.decodeIfPresent(Double.self, forKey: .controlScale)) ?? d.controlScale
        controlOpacity = (try? c.decodeIfPresent(Double.self, forKey: .controlOpacity)) ?? d.controlOpacity
        leftHanded = (try? c.decodeIfPresent(Bool.self, forKey: .leftHanded)) ?? d.leftHanded
        steerOffset = (try? c.decodeIfPresent(LayoutOffset.self, forKey: .steerOffset)) ?? d.steerOffset
        pedalOffset = (try? c.decodeIfPresent(LayoutOffset.self, forKey: .pedalOffset)) ?? d.pedalOffset
        liveWeather = (try? c.decodeIfPresent(Bool.self, forKey: .liveWeather)) ?? d.liveWeather
    }
}

public struct LayoutOffset: Codable, Sendable, Equatable {
    public var x = 0.0
    public var y = 0.0
    public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
}

/// How much auto-aim helps. Off still fires straight ahead.
public enum AimAssist: String, Codable, Sendable, CaseIterable {
    case off, low, standard, high

    public var label: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .standard: "Standard"
        case .high: "High"
        }
    }

    /// Multiplies a weapon's auto-aim cone.
    public var coneMultiplier: Double {
        switch self {
        case .off: 0.12
        case .low: 0.6
        case .standard: 1
        case .high: 1.4
        }
    }
}
