import Foundation

/// The kinds of work on a Solara depot's job board.
public enum StateJobKind: String, Codable, Sendable, CaseIterable {
    /// A parcel to a landmark or park stop, in whatever you're driving. Short and timed.
    case courier
    /// A delivery to another city's depot, by car or bike. Timed.
    case intercity
    /// A long haul in a diesel rig down the highway to another city. Untimed, pays the most,
    /// and a ride home waits at the other end.
    case freight

    public var label: String {
        switch self {
        case .courier: "Courier"
        case .intercity: "City run"
        case .freight: "Freight haul"
        }
    }
}

/// Something you get on top of the pay.
public enum StateReward: Sendable, Equatable {
    case ammo(WeaponID, Int)
    case none

    public var label: String? {
        switch self {
        case .ammo(let w, let n): "\(n) rounds for the \(w.spec.name)"
        case .none: nil
        }
    }
}

public struct StateJob: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: StateJobKind
    /// What's being carried ("Solar panels", "A sealed envelope").
    public let cargo: String
    public let from: ZoneID
    public let to: ZoneID
    public let pay: Int
    public let repXP: Int
    public let reward: StateReward
    /// Seconds to get there; nil for freight.
    public let timeLimit: Double?
    /// Straight-line distance, points (the board shows it in km).
    public let distance: Double

    /// "Freight haul: Solar panels to Cinder Flats".
    public func title(in district: District) -> String {
        "\(kind.label): \(cargo) to \(destinationName(in: district))"
    }

    public func destinationName(in district: District) -> String {
        if let city = SolaraState.city(for: to) { return city.name }
        return district.zones[to]?.name ?? to.rawValue
    }

    /// Kilometres as the HUD speaks them (12.8 points per metre).
    public var kilometres: Double { distance / 12.8 / 1000 }
}

/// Builds each depot's job board. Pay grows with distance; freight pays double and comes with a
/// product crate. The board changes after every finished job.
public enum StateJobs {
    static let courierCargo = ["A sealed envelope", "Camera gear", "Trail maps", "A cake (careful)", "Film reels",
                               "Ranger radios", "Postcards"]
    static let cityCargo = ["Spare parts", "Vinyl records", "Medical kits", "Coffee beans", "Tailor-made suits",
                            "Neon tubes", "Bike frames"]
    static let freightCargo = ["Solar panels", "Redwood lumber", "Desert citrus", "Server racks", "Stage lighting",
                               "Mineral water", "Concert speakers", "Paint drums"]

    /// Pay per point travelled, by kind.
    static func rate(_ kind: StateJobKind) -> Double {
        switch kind {
        case .courier: 0.05
        case .intercity: 0.04
        case .freight: 0.075
        }
    }

    public static func board(at depot: ZoneID, seed: UInt64, district: District = SolaraState.district) -> [StateJob] {
        guard let here = district.zones[depot]?.rect.center else { return [] }
        // A stable mix of the depot's name (Swift's hashValue changes every launch).
        let salt = depot.rawValue.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        var rng = SplitMix64(seed: seed &* 0x9E37 ^ salt)
        func pick<T>(_ list: [T]) -> T { list[Int(rng.next() % UInt64(list.count))] }
        let otherDepots = ZoneID.stateDepots.filter { $0 != depot }
        // Landmarks sorted by distance: couriers go to the nearer half.
        let stops = ZoneID.stateLandmarks.sorted {
            ((district.zones[$0]?.rect.center ?? here) - here).length < ((district.zones[$1]?.rect.center ?? here) - here).length
        }
        var jobs: [StateJob] = []
        func make(_ kind: StateJobKind, to: ZoneID, cargo: String, reward: StateReward = .none) {
            let there = district.zones[to]?.rect.center ?? here
            let distance = (there - here).length
            let pay = Int((Double(kind == .freight ? 600 : 150) + distance * rate(kind)) / 10) * 10
            // Road distance is ~1.3× the straight line; allow ~250 points/s average plus slack.
            let limit: Double? = kind == .freight ? nil : (distance * 1.3 / 250 + 30).rounded()
            jobs.append(StateJob(id: "\(depot.rawValue).\(seed).\(jobs.count)", kind: kind, cargo: cargo,
                                 from: depot, to: to, pay: pay, repXP: max(20, pay / 12), reward: reward,
                                 timeLimit: limit, distance: distance))
        }
        make(.courier, to: pick(Array(stops.prefix(5))), cargo: pick(courierCargo))
        let cityRun = pick(otherDepots)
        make(.intercity, to: cityRun, cargo: pick(cityCargo))
        let haul = pick(otherDepots.filter { $0 != cityRun }.isEmpty ? otherDepots : otherDepots.filter { $0 != cityRun })
        let crate: StateReward = .ammo(pick([.pistol, .smg, .shotgun, .rifle]), 30)
        make(.freight, to: haul, cargo: pick(freightCargo), reward: crate)
        let longHaul = otherDepots.max {
            ((district.zones[$0]!.rect.center) - here).length < ((district.zones[$1]!.rect.center) - here).length
        }!
        if longHaul != haul { make(.freight, to: longHaul, cargo: pick(freightCargo), reward: .ammo(.rifle, 20)) }
        return jobs
    }
}

/// What a finished job paid.
public struct StatePayout: Sendable, Equatable {
    public var credits: Int
    public var repXP: Int
    public var reward: StateReward
    /// Knocked off for damage to the rig (freight).
    public var damageCut: Int
    /// Bonus for beating the clock with time to spare.
    public var speedBonus: Int
}

public enum StateJobEvent: Sendable, Equatable {
    case started(StateJob)
    case delivered(StateJob, StatePayout)
    case failed(StateJob, String)
    /// Freight: you left the rig; get back in to deliver.
    case needTruck
    /// Freight done: a car and a bike wait at the depot for the drive home.
    case rideHomeReady
}

/// The job in progress on Solara's roads. Pure and steppable, like `City`.
public struct StateJobRunner: Sendable {
    public private(set) var active: StateJob?
    public private(set) var elapsed = 0.0
    /// The lent rig (City vehicle index) for freight.
    public private(set) var truck: Int?
    /// Jobs finished this trip (also reshuffles the boards).
    public private(set) var finished = 0
    private var warnedTruck = false

    public init() {}

    public var timeRemaining: Double? {
        guard let job = active, let limit = job.timeLimit else { return nil }
        return max(0, limit - elapsed)
    }

    /// Takes a job from the board at the depot the player is standing in. Freight hands over a
    /// rig in the depot yard with the player already behind the wheel.
    public mutating func accept(_ job: StateJob, city: inout City) -> [StateJobEvent] {
        guard active == nil else { return [] }
        active = job
        elapsed = 0
        warnedTruck = false
        if job.kind == .freight, let yard = city.district.zones[job.from]?.rect {
            truck = city.lendVehicle(.hauler, at: yard.center, heading: .pi / 2)
        }
        return [.started(job)]
    }

    /// Gives up on the current job (the rig goes back to the yard).
    public mutating func abandon(city: inout City) -> [StateJobEvent] {
        guard let job = active else { return [] }
        let events: [StateJobEvent] = [.failed(job, "Job dropped")]
        if let truck { _ = city.retireVehicle(truck) }
        clear()
        return events
    }

    public mutating func step(city: inout City, dt: Double) -> [StateJobEvent] {
        guard let job = active else { return [] }
        elapsed += dt
        var events: [StateJobEvent] = []
        if let limit = job.timeLimit, elapsed > limit {
            events.append(.failed(job, "Out of time"))
            clear()
            return events
        }
        if let truck, city.vehicles.indices.contains(truck), city.vehicles[truck].isWrecked {
            events.append(.failed(job, "The rig is wrecked"))
            _ = city.retireVehicle(truck)
            clear()
            return events
        }
        let inTruck = truck.map { city.currentVehicleIndex == $0 } ?? true
        if !inTruck && !warnedTruck {
            warnedTruck = true
            events.append(.needTruck)
        }
        if inTruck { warnedTruck = false }
        guard let target = city.district.zones[job.to], target.rect.contains(city.playerPosition), inTruck else {
            return events
        }
        // Delivered.
        var payout = StatePayout(credits: job.pay, repXP: job.repXP, reward: job.reward, damageCut: 0, speedBonus: 0)
        if let truck, city.vehicles.indices.contains(truck) {
            payout.damageCut = min(job.pay / 2, city.vehicles[truck].damage * job.pay / 20)
            payout.credits -= payout.damageCut
        }
        if let limit = job.timeLimit, elapsed < limit * 0.6 {
            payout.speedBonus = job.pay / 5
            payout.credits += payout.speedBonus
        }
        if case .ammo(let weapon, let rounds) = job.reward {
            city.inventory.acquire(weapon, ammo: rounds)
        }
        events.append(.delivered(job, payout))
        if let truck {
            _ = city.retireVehicle(truck)
            // The ride home: a car and a bike at the yard's edge. Take either.
            let yard = target.rect
            city.parkVehicle(.dorado, at: Vec2(yard.minX + 40, yard.maxY - 40), heading: .pi / 2)
            city.parkVehicle(.flicker, at: Vec2(yard.maxX - 40, yard.maxY - 40), heading: .pi / 2)
            events.append(.rideHomeReady)
        }
        finished += 1
        clear()
        return events
    }

    private mutating func clear() {
        active = nil
        truck = nil
        elapsed = 0
        warnedTruck = false
    }
}
