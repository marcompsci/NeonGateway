import Foundation

/// One pose of a recorded run, every `Ghost.interval` seconds.
public struct GhostFrame: Codable, Sendable, Equatable {
    public var t: Double
    public var x: Double
    public var y: Double
    public var heading: Double

    public init(t: Double, x: Double, y: Double, heading: Double) {
        self.t = t
        self.x = x
        self.y = y
        self.heading = heading
    }
}

/// A recorded drive that can be replayed as a see-through car: your best run, or Nova's.
public struct Ghost: Codable, Sendable, Equatable {
    public static let interval = 0.1
    public var frames: [GhostFrame]
    public var vehicle: VehicleID

    public init(frames: [GhostFrame] = [], vehicle: VehicleID = .vesper) {
        self.frames = frames
        self.vehicle = vehicle
    }

    public var duration: Double { frames.last?.t ?? 0 }

    /// Where the ghost is `t` seconds in, smoothly between frames; parked at the end once done.
    public func pose(at t: Double) -> (position: Vec2, heading: Double)? {
        guard let first = frames.first, let last = frames.last else { return nil }
        if t <= first.t { return (Vec2(first.x, first.y), first.heading) }
        if t >= last.t { return (Vec2(last.x, last.y), last.heading) }
        // Frames are evenly spaced, so jump straight to the right pair.
        var i = min(frames.count - 2, max(0, Int((t - first.t) / Ghost.interval)))
        while i > 0 && frames[i].t > t { i -= 1 }
        while i < frames.count - 2 && frames[i + 1].t < t { i += 1 }
        let a = frames[i], b = frames[i + 1]
        let f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
        let turn = remainder(b.heading - a.heading, 2 * .pi)
        return (Vec2(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f), a.heading + turn * f)
    }
}

/// Samples a run into a ghost as it's driven.
public struct GhostRecorder: Sendable {
    public private(set) var ghost: Ghost
    private var nextSample = 0.0

    public init(vehicle: VehicleID = .vesper) { ghost = Ghost(vehicle: vehicle) }

    public mutating func record(t: Double, position: Vec2, heading: Double) {
        guard t >= nextSample else { return }
        ghost.frames.append(GhostFrame(t: t, x: position.x, y: position.y, heading: heading))
        nextSample = t + Ghost.interval
    }

    /// The last pose, always kept (the finish line), whatever the sample timing.
    public mutating func finish(t: Double, position: Vec2, heading: Double) {
        if let last = ghost.frames.last, last.t >= t { ghost.frames.removeLast() }
        ghost.frames.append(GhostFrame(t: t, x: position.x, y: position.y, heading: heading))
    }

    public mutating func setVehicle(_ v: VehicleID) { ghost.vehicle = v }
}

public enum Medal: String, Codable, Sendable, Comparable, CaseIterable {
    case bronze, silver, gold

    public var label: String { rawValue.capitalized }

    /// Paid the first time each medal is reached in a week.
    public var bonus: Int {
        switch self {
        case .bronze: 40
        case .silver: 90
        case .gold: 180
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (a: Medal, b: Medal) -> Bool { a.rank < b.rank }
}

/// This week's Street Challenge on the player's save: best time, its ghost and the medal.
public struct ChallengeState: Codable, Sendable, Equatable {
    public var week = -1
    public var bestTime: Double?
    public var ghost: Ghost?
    public var medal: Medal?
    public var attempts = 0
    /// Lifetime golds, for bragging.
    public var golds = 0

    public init() {}
}

/// The weekly Street Challenge: five checkpoints across Port Aurora in order, a fresh route every
/// Monday (UTC). Race Nova's ghost (the game's own driver, run through the real physics) and your
/// own best. Solo players always have someone to race, even with nobody online.
public enum StreetChallenge {
    /// Monday 5 January 2026, 00:00 UTC: week 0.
    public static let epoch = Date(timeIntervalSince1970: 1_767_571_200)
    public static let checkpointCount = 5
    public static let timeLimit = 150.0
    public static let rivalName = "Nova"
    /// Silver is within this much of Nova's time; gold beats it.
    public static let silverMargin = 1.2

    /// Checkpoints a car can reach (no shops, no Safehouse, no Customs Yard).
    public static let pool: [ZoneID] = [
        .pier4, .pier9, .lanternAlleyDrop, .parkLantern, .containerLantern, .alleyLantern,
        .neonRowBay, .marketLane, .signalLantern, .tideLantern, .printShop,
        .flyerHarbor, .flyerNeonRow, .flyerTideRoad, .flyerAlleys
    ]

    public static func week(of date: Date) -> Int {
        Int((date.timeIntervalSince(epoch) / (7 * 86_400)).rounded(.down))
    }

    /// When this week's route is replaced.
    public static func ends(week: Int) -> Date {
        epoch.addingTimeInterval(Double(week + 1) * 7 * 86_400)
    }

    /// The route for a week: five different checkpoints, each a decent drive from the last.
    public static func route(week: Int, district: District = .portAuroraDocks) -> [ZoneID] {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(week)) &* 0x2545F4914F6CDD1D &+ 77)
        let start = GameCoreSpawns.safehouseRoad.position
        var left = pool.filter { district.zones[$0] != nil }
        var route: [ZoneID] = []
        var from = start
        while route.count < checkpointCount && !left.isEmpty {
            // Prefer spots 900+ points away so every leg is a real drive.
            let far = left.filter { (district.zones[$0]!.rect.center - from).length > 900 }
            let choices = far.isEmpty ? left : far
            let pick = choices[Int(rng.next() % UInt64(choices.count))]
            route.append(pick)
            left.removeAll { $0 == pick }
            from = district.zones[pick]!.rect.center
        }
        return route
    }

    public static func def(week: Int, district: District = .portAuroraDocks) -> MissionDef {
        let route = route(week: week, district: district)
        let lines = route.enumerated().map { i, id in
            "Checkpoint \(i + 1) of \(route.count): \(district.zones[id]?.name ?? id.rawValue)"
        }
        return MissionDef(
            id: .streetChallenge,
            title: "Street Challenge",
            brief: "This week's route: \(route.count) checkpoints across Port Aurora, in order. "
                + "Race \(rivalName)'s ghost (magenta) and your own best (teal). Beat \(rivalName) for gold. "
                + "A new route every Monday.",
            kind: .timedDelivery,
            requiredRepLevel: 1,
            start: GameCoreSpawns.safehouseRoad,
            objectives: route.map { .reach($0) },
            timeLimit: timeLimit,
            baseReward: 120,
            baseRepXP: 30,
            objectiveLines: lines,
            collectLabel: "CHECK")
    }

    public static func current(now: Date = Date()) -> MissionDef { def(week: week(of: now)) }

    /// Nova's run: the game's autopilot drives the route through the real physics and walls
    /// (no traffic, no patrols) in the starter car. Deterministic for a given week.
    public static func rival(for def: MissionDef, district: District = .portAuroraDocks) -> Ghost {
        let spec = VehicleSpec.vesper
        var car = VehicleState(position: def.start.position, heading: def.start.heading)
        var run = MissionRunState()
        var pilot: Autopilot?
        var pilotIndex = -1
        var recorder = GhostRecorder(vehicle: .vesper)
        let dt = VehicleDynamics.fixedStep
        for _ in 0..<Int(def.timeLimit ?? timeLimit) * 60 where !run.isFinished {
            if run.objectiveIndex != pilotIndex, let id = MissionRunner.activeZones(run, def: def).first,
               let zone = district.zones[id] {
                pilot = Autopilot(district: district, from: car.position, to: zone.rect.center)
                pilotIndex = run.objectiveIndex
            }
            recorder.record(t: run.elapsed, position: car.position, heading: car.heading)
            let input = pilot?.input(for: car) ?? .idle
            car = VehicleDynamics.step(car, input: input, spec: spec, dt: dt)
            car = Collision.resolve(car, radius: spec.radius,
                                    solids: district.solids(near: car.position, radius: spec.radius)).state
            run = MissionRunner.step(run, def: def, district: district, carPosition: car.position, dt: dt).0
        }
        recorder.finish(t: run.elapsed, position: car.position, heading: car.heading)
        return recorder.ghost
    }

    public static func medal(time: Double, rival: Double) -> Medal {
        if time <= rival { return .gold }
        if time <= rival * silverMargin { return .silver }
        return .bronze
    }

    /// What a finished challenge run changed.
    public struct Outcome: Sendable, Equatable {
        public var medal: Medal
        public var newBest: Bool
        /// Medal bonus paid this time (only when the week's medal goes up).
        public var bonus: Int
        /// Your time minus Nova's (negative = you beat Nova).
        public var gapToRival: Double
        public var previousBest: Double?
    }

    /// Files a successful run on the save: weekly best + ghost, medal, and the medal bonus.
    @discardableResult
    public static func record(time: Double, ghost: Ghost, rivalTime: Double, week: Int,
                              progress p: inout PlayerProgress, now: Date = Date()) -> Outcome {
        if p.challenge.week != week {
            let golds = p.challenge.golds
            p.challenge = ChallengeState()
            p.challenge.week = week
            p.challenge.golds = golds
        }
        p.challenge.attempts += 1
        let previous = p.challenge.bestTime
        let newBest = previous.map { time < $0 } ?? true
        if newBest {
            p.challenge.bestTime = time
            p.challenge.ghost = ghost
        }
        let medal = Self.medal(time: time, rival: rivalTime)
        var bonus = 0
        if p.challenge.medal.map({ medal > $0 }) ?? true {
            // Pay the difference so bronze → gold over a week adds up to the gold bonus.
            bonus = medal.bonus - (p.challenge.medal?.bonus ?? 0)
            if medal == .gold { p.challenge.golds += 1 }
            p.challenge.medal = medal
            p.earn(bonus, .jobPay, "Street Challenge \(medal.label.lowercased())", on: now)
        }
        return Outcome(medal: medal, newBest: newBest, bonus: bonus, gapToRival: time - rivalTime,
                       previousBest: previous)
    }

    /// Counts a run that didn't finish (so attempts show), resetting for a new week.
    public static func recordAttempt(week: Int, progress p: inout PlayerProgress) {
        if p.challenge.week != week {
            let golds = p.challenge.golds
            p.challenge = ChallengeState()
            p.challenge.week = week
            p.challenge.golds = golds
        }
        p.challenge.attempts += 1
    }

    /// This week's state on the save (empty if it's from an older week).
    public static func state(week: Int, progress: PlayerProgress) -> ChallengeState {
        if progress.challenge.week == week { return progress.challenge }
        var fresh = ChallengeState()
        fresh.week = week
        fresh.golds = progress.challenge.golds
        return fresh
    }
}
