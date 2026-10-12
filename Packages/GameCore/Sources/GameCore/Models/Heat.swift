import Foundation

/// How hot the player is with Harbor Patrol: 0...100 points, shown as 0–5 stars.
public struct HeatState: Sendable, Equatable {
    public var points: Double = 0
    /// Seconds since any patrol last saw the player.
    public var timeUnseen: Double = 0

    public init(points: Double = 0) {
        self.points = min(max(points, 0), HeatRules.maxPoints)
    }

    public var stars: Int { HeatRules.stars(for: points) }
    public var label: String { HeatRules.labels[stars] }
}

public enum HeatEvent: Sendable, Equatable {
    case wallHit
    case patrolHit
    /// Set per job, e.g. grabbing a pickup.
    case missionEvent(Double)
}

public enum HeatRules {
    public static let maxPoints = 100.0
    /// Points needed for 1...5 stars.
    public static let starThresholds = [10.0, 30.0, 50.0, 70.0, 90.0]
    public static let labels = ["Calm", "Noticed", "Wanted", "Hunted", "Pursuit", "Manhunt"]

    public static let wallHit = 4.0
    public static let patrolHit = 15.0
    public static let restrictedPerSecond = 4.0
    public static let decayPerSecond = 8.0
    /// Heat only starts falling after this long out of every patrol's sight.
    public static let graceSeconds = 4.0

    public static func stars(for points: Double) -> Int {
        starThresholds.filter { points >= $0 }.count
    }
}

public enum HeatSystem {
    public static func apply(_ event: HeatEvent, to state: HeatState) -> HeatState {
        var s = state
        switch event {
        case .wallHit: s.points += HeatRules.wallHit
        case .patrolHit: s.points += HeatRules.patrolHit
        case .missionEvent(let points): s.points += points
        }
        s.points = min(max(s.points, 0), HeatRules.maxPoints)
        return s
    }

    /// One time step. `seen`: a patrol can see the player right now.
    public static func step(_ state: HeatState, dt: Double, seen: Bool, inRestricted: Bool,
                            inSafehouse: Bool) -> HeatState {
        var s = state
        if inSafehouse {
            s.points = 0
            s.timeUnseen = 0
            return s
        }
        s.timeUnseen = seen ? 0 : s.timeUnseen + dt
        if inRestricted { s.points += HeatRules.restrictedPerSecond * dt }
        if s.timeUnseen > HeatRules.graceSeconds { s.points -= HeatRules.decayPerSecond * dt }
        s.points = min(max(s.points, 0), HeatRules.maxPoints)
        return s
    }
}
