import Foundation

/// A bystander on the sidewalks. Cartoon rules: a hit knocks them flat, and a few seconds later
/// they're gone and someone else walks in elsewhere. No injuries are shown.
public struct Pedestrian: Sendable, Equatable {
    public enum Mode: String, Sendable { case walk, flee, down }

    public let id: Int
    public var position: Vec2
    public var heading: Double
    public var mode: Mode = .walk
    /// Seconds left fleeing, or lying down before respawning.
    public var timer: Double = 0
    /// Where a walker is heading (a footpath tile centre) or what a runner is fleeing from.
    public var target: Vec2
    /// Picks the clothes colours when drawn.
    public var look: Int

    public var isDown: Bool { mode == .down }
}

/// Everyone on foot who isn't the player. Walkers stay on footpaths (sidewalks, plazas, alleys,
/// docks); gunfire or a crash nearby sends them running.
public struct Crowd: Sendable {
    public static let walkSpeed = 48.0
    public static let fleeSpeed = 130.0
    public static let fleeSeconds = 4.0
    public static let downSeconds = 4.0
    /// Respawns happen at least this far from the player, out of sight.
    public static let respawnDistance = 700.0
    public static let radius = 8.0

    public internal(set) var people: [Pedestrian] = []
    let district: District
    let footpaths: [TileCoord]
    let footpathBuckets: [Int: [TileCoord]]
    private var rng: SplitMix64

    public init(district: District, count: Int, avoid: Vec2, seed: UInt64) {
        self.district = district
        rng = SplitMix64(seed: seed ^ 0xC0FFEE)
        footpaths = Self.footpathTiles(district)
        var buckets: [Int: [TileCoord]] = [:]
        for c in footpaths { buckets[District.bucketKey(col: c.col, row: c.row), default: []].append(c) }
        footpathBuckets = buckets
        for id in 0..<count {
            let spot = randomFootpath(awayFrom: avoid, minDistance: 160) ?? district.bounds.center
            people.append(Pedestrian(id: id, position: spot, heading: 0, target: spot,
                                     look: Int(rng.next() % 6)))
        }
        for i in people.indices { people[i].target = nextTarget(from: people[i].position) }
    }

    static func footpathTiles(_ district: District) -> [TileCoord] {
        (0..<district.rows).flatMap { r in (0..<district.cols).map { TileCoord(col: $0, row: r) } }
            .filter { [.sidewalk, .plaza, .alley, .dock].contains(district.tile($0)) }
    }

    func isFootpath(_ c: TileCoord) -> Bool {
        [.sidewalk, .plaza, .alley, .dock].contains(district.tile(c))
    }

    mutating func randomFootpath(awayFrom p: Vec2, minDistance: Double) -> Vec2? {
        guard !footpaths.isEmpty else { return nil }
        // On a big map, walkers come back near the player (within a city block or two).
        let pool = district.isLarge ? nearbyFootpaths(p, radius: minDistance + 900) : footpaths
        guard !pool.isEmpty else { return nil }
        for _ in 0..<40 {
            let c = pool[Int(rng.next() % UInt64(pool.count))]
            let spot = district.center(of: c)
            if (spot - p).length >= minDistance { return spot }
        }
        return nil
    }

    /// Footpath tiles in the buckets around `p` (big maps only).
    private func nearbyFootpaths(_ p: Vec2, radius: Double) -> [TileCoord] {
        let c = district.coord(at: p)
        let size = District.bucketSize
        let span = Int((radius / district.tileSize / Double(size)).rounded(.up))
        var out: [TileCoord] = []
        for dr in -span...span {
            for dc in -span...span {
                if let list = footpathBuckets[(c.row / size + dr) * 10_000 + (c.col / size + dc)] { out += list }
            }
        }
        return out
    }

    /// Big maps: anyone left far behind (the player drove to another city) reappears nearby.
    public static let strayDistance = 2600.0

    /// A neighbouring footpath tile to stroll to (any direction, so walkers wander).
    mutating func nextTarget(from p: Vec2) -> Vec2 {
        let here = district.coord(at: p)
        let options = [(1, 0), (-1, 0), (0, 1), (0, -1)]
            .map { TileCoord(col: here.col + $0.0, row: here.row + $0.1) }
            .filter { isFootpath($0) }
        guard !options.isEmpty else { return district.center(of: here) }
        return district.center(of: options[Int(rng.next() % UInt64(options.count))])
    }

    public mutating func step(dt: Double, player: Vec2) {
        for i in people.indices {
            var p = people[i]
            if district.isLarge && p.mode != .down && (p.position - player).length > Self.strayDistance,
               let spot = randomFootpath(awayFrom: player, minDistance: Self.respawnDistance) {
                p.position = spot
                p.mode = .walk
                p.target = nextTarget(from: spot)
            }
            switch p.mode {
            case .walk:
                let delta = p.target - p.position
                if delta.length < 6 {
                    p.target = nextTarget(from: p.position)
                } else {
                    let dir = delta * (1 / delta.length)
                    p.heading = atan2(dir.y, dir.x)
                    p.position += dir * min(Self.walkSpeed * dt, delta.length)
                }
            case .flee:
                p.timer -= dt
                var away = p.position - p.target
                if away.length < 0.001 { away = Vec2(1, 0) }
                let dir = away * (1 / away.length)
                let next = p.position + dir * Self.fleeSpeed * dt
                // Runners don't go through walls; they just stop at them.
                if !district.tile(at: next).isSolid { p.position = next }
                p.heading = atan2(dir.y, dir.x)
                if p.timer <= 0 {
                    p.mode = .walk
                    p.target = nextTarget(from: p.position)
                }
            case .down:
                p.timer -= dt
                if p.timer <= 0 {
                    let spot = randomFootpath(awayFrom: player, minDistance: Self.respawnDistance) ?? p.position
                    p.position = spot
                    p.mode = .walk
                    p.target = nextTarget(from: spot)
                    p.look = Int(rng.next() % 6)
                }
            }
            people[i] = p
        }
    }

    /// Knocks someone flat. Returns false if they were already down.
    @discardableResult
    public mutating func knockDown(_ index: Int) -> Bool {
        guard people.indices.contains(index), !people[index].isDown else { return false }
        people[index].mode = .down
        people[index].timer = Self.downSeconds
        return true
    }

    /// Everyone standing within `radius` of `point` runs away from it.
    public mutating func scare(from point: Vec2, radius: Double) {
        for i in people.indices where !people[i].isDown && (people[i].position - point).length < radius {
            people[i].mode = .flee
            people[i].timer = Self.fleeSeconds
            people[i].target = point
        }
    }
}
