import Foundation

public enum MissionID: String, Codable, Sendable, CaseIterable {
    case coldCrate
    case tideLineRun
    case lanternSweep
    case deepFreeze
    case ghostTide
    case lanternFestival
    case doubleCross
    case streetFlyers
    /// The weekly time trial (not on the job ladder; its route changes every week).
    case streetChallenge

    /// Jobs on the map (everything but the Street Challenge).
    public static var jobs: [MissionID] { allCases.filter { $0 != .streetChallenge } }
}

public enum MissionKind: String, Codable, Sendable {
    case timedDelivery, escape, pickupRun
    /// A timed delivery that turns into an escape when the drop goes wrong.
    case double

    public var label: String {
        switch self {
        case .timedDelivery: "Timed delivery"
        case .escape: "Escape"
        case .pickupRun: "Pickup run"
        case .double: "Delivery + escape"
        }
    }

    /// Jobs that finish with a getaway count toward the escape streak.
    public var endsInEscape: Bool { self == .escape || self == .double }
}

/// A job event that brings Harbor Patrol in hard: heat added at once, units sent to the spot.
public struct MissionAlarm: Sendable, Equatable {
    /// The alarm goes off when this objective (0-based) is completed.
    public let afterObjective: Int
    /// Heat points added.
    public let heat: Double
    /// One line for the HUD while it happens.
    public let notice: String

    public init(afterObjective: Int, heat: Double, notice: String) {
        self.afterObjective = afterObjective
        self.heat = heat
        self.notice = notice
    }
}

public enum Objective: Sendable, Equatable {
    /// Drive into a zone.
    case reach(ZoneID)
    /// Drive through every listed zone, in any order.
    case collect([ZoneID])
    /// Bring the car back to a zone (the Safehouse).
    case returnTo(ZoneID)
    /// Drive into a zone with no heat (0 stars); it doesn't count while patrols are after you.
    case reachCalm(ZoneID)

    public var zones: [ZoneID] {
        switch self {
        case .reach(let z), .returnTo(let z), .reachCalm(let z): [z]
        case .collect(let zs): zs
        }
    }
}

public struct SpawnPoint: Sendable, Equatable {
    public let position: Vec2
    /// Radians, 0 = +x, π/2 = north.
    public let heading: Double

    public init(position: Vec2, heading: Double) {
        self.position = position
        self.heading = heading
    }
}

public struct MissionDef: Sendable, Equatable, Identifiable {
    public let id: MissionID
    public let title: String
    public let brief: String
    public let kind: MissionKind
    public let requiredRepLevel: Int
    public let start: SpawnPoint
    public let objectives: [Objective]
    /// Seconds; nil = no clock.
    public let timeLimit: Double?
    public let baseReward: Int
    public let baseRepXP: Int
    /// Objective text shown in the HUD, one per objective.
    public let objectiveLines: [String]
    /// Heat points the job starts with (escape jobs start hot).
    public let startingHeat: Double
    /// Heat added each time a pickup is grabbed.
    public let pickupHeat: Double
    /// How many objectives the clock covers, from the first; nil = the whole job. After that the
    /// clock stops and the rest is untimed (the escape half of a double job).
    public let clockedObjectives: Int?
    /// Optional mid-job alarm (a delivery that turns out to be a setup).
    public let alarm: MissionAlarm?
    /// The job starts on foot (no car at the spawn); the player can still take one.
    public let startsOnFoot: Bool
    /// Word painted on this job's collect spots ("LANTERN", "FLYERS").
    public let collectLabel: String

    public init(id: MissionID, title: String, brief: String, kind: MissionKind, requiredRepLevel: Int,
                start: SpawnPoint, objectives: [Objective], timeLimit: Double?, baseReward: Int,
                baseRepXP: Int, objectiveLines: [String], startingHeat: Double = 0, pickupHeat: Double = 0,
                clockedObjectives: Int? = nil, alarm: MissionAlarm? = nil, startsOnFoot: Bool = false,
                collectLabel: String = "LANTERN") {
        precondition(objectives.count == objectiveLines.count, "one HUD line per objective")
        precondition(clockedObjectives.map { $0 >= 1 && $0 <= objectives.count } ?? true, "clock covers 1...count")
        precondition(alarm.map { $0.afterObjective < objectives.count } ?? true, "alarm after a real objective")
        self.id = id
        self.title = title
        self.brief = brief
        self.kind = kind
        self.requiredRepLevel = requiredRepLevel
        self.start = start
        self.objectives = objectives
        self.timeLimit = timeLimit
        self.baseReward = baseReward
        self.baseRepXP = baseRepXP
        self.objectiveLines = objectiveLines
        self.startingHeat = startingHeat
        self.pickupHeat = pickupHeat
        self.clockedObjectives = clockedObjectives
        self.alarm = alarm
        self.startsOnFoot = startsOnFoot
        self.collectLabel = collectLabel
    }

    /// True while the clock is still running for this objective index.
    public func isClocked(objectiveIndex: Int) -> Bool {
        guard timeLimit != nil else { return false }
        return objectiveIndex < (clockedObjectives ?? objectives.count)
    }
}

public enum MissionOutcome: String, Codable, Sendable {
    case success, timeUp, busted, wrecked, quit
    /// Health ran out on foot. Cartoon rules: knocked out, not killed.
    case knockedOut

    public var isSuccess: Bool { self == .success }
}

/// Per-run state, advanced by `MissionRunner`.
public struct MissionRunState: Sendable, Equatable {
    public var elapsed: Double = 0
    /// Seconds the job clock has run. Equals `elapsed` unless the clock stopped part-way.
    public var clockElapsed: Double = 0
    public var objectiveIndex = 0
    public var collected: Set<ZoneID> = []
    public var collisions = 0
    public var outcome: MissionOutcome?

    public init() {}

    public var isFinished: Bool { outcome != nil }
}
