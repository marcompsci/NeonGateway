import Foundation

/// What one map tile is. Solid tiles stop the car; everything else can be driven on.
public enum TileKind: Character, Sendable, CaseIterable {
    case road = "."
    case sidewalk = ","
    case alley = "a"
    case dock = "d"
    case plaza = "p"
    case safehouse = "S"
    case building = "B"
    case container = "C"
    case fence = "#"
    case water = "~"
    // Solara State (open country between cities).
    /// A divided highway: drives like a road, painted with lanes and a shoulder.
    case highway = "h"
    /// Highway deck over water (the Crimson Span and causeways).
    case bridge = "="
    /// Open grassland. Drivable off-road.
    case grass = "g"
    /// Desert sand and scrub. Drivable off-road.
    case sand = "s"
    /// Dense forest: the trees block cars.
    case forest = "f"
    /// Mountain rock and canyon walls.
    case rock = "r"
    /// A landmark's footprint (domes, towers, arches): solid, drawn by the landmark art.
    case landmark = "L"

    public var isSolid: Bool {
        switch self {
        case .building, .container, .fence, .water, .forest, .rock, .landmark: true
        default: false
        }
    }

    /// Paved roads traffic and patrols use.
    public var isRoad: Bool { self == .road || self == .highway || self == .bridge }

    /// Off-road ground: drivable but rough.
    public var isOffRoad: Bool { self == .grass || self == .sand }
}

/// A grid cell. `row` counts from the top (north) like the map strings; `col` from the left.
public struct TileCoord: Sendable, Hashable {
    public var col: Int
    public var row: Int

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }
}

public enum ZoneID: String, Codable, Sendable, CaseIterable {
    case pier4
    case pier9
    case lanternAlleyDrop
    case safehouse
    case customsYard
    case parkLantern
    case containerLantern
    case alleyLantern
    case neonRowBay
    case marketLane
    case signalLantern
    case tideLantern
    case gunStore
    case printShop
    case flyerHarbor
    case flyerNeonRow
    case flyerTideRoad
    case flyerAlleys
    // Solara State depots (one per city).
    case depotAurora, depotStarline, depotRedwood, depotCinder, depotMesa, depotSteamvale
    // Solara State landmark stops.
    case spanVista, graniteCrown, titanGrove, glowTower, sunstoneArches, oldSteady, starlineObservatory,
         sunsetPier, auroraNeedle, mirrorLake

    /// Zones that belong to Solara State rather than Port Aurora Docks.
    public var isState: Bool { ZoneID.stateZones.contains(self) }
    public static let stateDepots: [ZoneID] = [.depotAurora, .depotStarline, .depotRedwood, .depotCinder,
                                                .depotMesa, .depotSteamvale]
    public static let stateLandmarks: [ZoneID] = [.spanVista, .graniteCrown, .titanGrove, .glowTower,
                                                   .sunstoneArches, .oldSteady, .starlineObservatory,
                                                   .sunsetPier, .auroraNeedle, .mirrorLake]
    static let stateZones = Set(stateDepots + stateLandmarks)
}

public enum ZoneKind: String, Codable, Sendable {
    case dropOff, pickup, safehouse, restricted, start
    /// A store the player walks into (on foot) to buy things.
    case shop
    /// Solara State: a freight depot with a job board.
    case depot
    /// Solara State: a landmark or national park visitor stop.
    case landmark
}

public struct Zone: Sendable, Equatable, Identifiable {
    public let id: ZoneID
    public let name: String
    public let kind: ZoneKind
    public let rect: Rect

    public init(id: ZoneID, name: String, kind: ZoneKind, rect: Rect) {
        self.id = id
        self.name = name
        self.kind = kind
        self.rect = rect
    }
}

/// A named area of the district, used for HUD labels ("Downtown", "The Alleys").
public struct Neighborhood: Sendable, Equatable {
    public let name: String
    public let rect: Rect
}

/// One district of Port Aurora: a tile grid plus named zones. World origin is the lower-left
/// corner (SpriteKit's convention); map strings are written top row first.
public struct District: Sendable {
    public let name: String
    public let tileSize: Double
    public let cols: Int
    public let rows: Int
    /// Row-major, row 0 = top (north).
    public let tiles: [TileKind]
    public let zones: [ZoneID: Zone]
    public let neighborhoods: [Neighborhood]
    /// All road tiles (streets, highways, bridges), where patrols spawn and cruise to.
    public let roadTiles: [TileCoord]
    /// Road tiles grouped into 16 × 16-tile buckets, so a big map can find roads near a point fast.
    let roadBuckets: [Int: [TileCoord]]

    /// Bucket size (tiles) for the spatial lookups.
    static let bucketSize = 16

    /// Maps bigger than this many tiles keep traffic, walkers and patrols near the player.
    public var isLarge: Bool { cols * rows > 4000 }

    public init(name: String, tileSize: Double, map: [String], zones: [Zone], neighborhoods: [Neighborhood]) {
        precondition(!map.isEmpty, "map needs at least one row")
        let width = map[0].count
        precondition(map.allSatisfy { $0.count == width }, "every map row must be the same width")
        let kinds: [TileKind] = map.flatMap { row in
            row.map { ch in
                guard let kind = TileKind(rawValue: ch) else {
                    preconditionFailure("unknown map character \(ch)")
                }
                return kind
            }
        }
        self.init(name: name, tileSize: tileSize, cols: width, rows: map.count, tiles: kinds, zones: zones,
                  neighborhoods: neighborhoods)
    }

    /// A district from a ready-made tile array (row-major, row 0 = north). Used by generated maps.
    public init(name: String, tileSize: Double, cols: Int, rows: Int, tiles kinds: [TileKind], zones: [Zone],
                neighborhoods: [Neighborhood]) {
        precondition(kinds.count == cols * rows, "tile count must be cols × rows")
        self.name = name
        self.tileSize = tileSize
        self.cols = cols
        self.rows = rows
        self.tiles = kinds
        self.zones = Dictionary(uniqueKeysWithValues: zones.map { ($0.id, $0) })
        self.neighborhoods = neighborhoods
        var roads: [TileCoord] = []
        var buckets: [Int: [TileCoord]] = [:]
        for r in 0..<rows {
            for c in 0..<cols where kinds[r * cols + c].isRoad {
                let coord = TileCoord(col: c, row: r)
                roads.append(coord)
                buckets[Self.bucketKey(col: c, row: r), default: []].append(coord)
            }
        }
        self.roadTiles = roads
        self.roadBuckets = buckets
    }

    static func bucketKey(col: Int, row: Int) -> Int {
        (row / bucketSize) * 10_000 + (col / bucketSize)
    }

    /// Road tiles in the buckets within `radius` points of `p`.
    public func roadTiles(near p: Vec2, radius: Double) -> [TileCoord] {
        let c = coord(at: p)
        let span = Int((radius / tileSize / Double(Self.bucketSize)).rounded(.up))
        let bc = c.col / Self.bucketSize, br = c.row / Self.bucketSize
        var out: [TileCoord] = []
        for dr in -span...span {
            for dc in -span...span where br + dr >= 0 && bc + dc >= 0 {
                if let list = roadBuckets[(br + dr) * 10_000 + (bc + dc)] { out += list }
            }
        }
        return out
    }

    public var bounds: Rect {
        Rect(x: 0, y: 0, width: Double(cols) * tileSize, height: Double(rows) * tileSize)
    }

    public func tile(_ c: TileCoord) -> TileKind {
        guard c.col >= 0, c.col < cols, c.row >= 0, c.row < rows else { return .building }
        return tiles[c.row * cols + c.col]
    }

    public func coord(at p: Vec2) -> TileCoord {
        TileCoord(col: Int((p.x / tileSize).rounded(.down)),
                  row: rows - 1 - Int((p.y / tileSize).rounded(.down)))
    }

    public func tile(at p: Vec2) -> TileKind { tile(coord(at: p)) }

    /// World rectangle covered by a tile.
    public func rect(of c: TileCoord) -> Rect {
        Rect(x: Double(c.col) * tileSize, y: Double(rows - 1 - c.row) * tileSize,
             width: tileSize, height: tileSize)
    }

    /// Centre of a tile in world points.
    public func center(of c: TileCoord) -> Vec2 { rect(of: c).center }

    /// World rectangle covering tiles from `top`-left to `bottom`-right corner, inclusive.
    public func rect(cols c0: Int, _ c1: Int, rows r0: Int, _ r1: Int) -> Rect {
        Rect(x: Double(c0) * tileSize, y: Double(rows - 1 - r1) * tileSize,
             width: Double(c1 - c0 + 1) * tileSize, height: Double(r1 - r0 + 1) * tileSize)
    }

    /// Solid tile rects that a circle at `p` with `radius` could touch, plus the map edge.
    /// Only nearby tiles are returned, so collision cost stays flat however big the map gets.
    public func solids(near p: Vec2, radius: Double) -> [Rect] {
        let minCol = Int(((p.x - radius) / tileSize).rounded(.down))
        let maxCol = Int(((p.x + radius) / tileSize).rounded(.down))
        let minYIndex = Int(((p.y - radius) / tileSize).rounded(.down))
        let maxYIndex = Int(((p.y + radius) / tileSize).rounded(.down))
        var result: [Rect] = []
        for col in minCol...maxCol {
            for yIndex in minYIndex...maxYIndex {
                let c = TileCoord(col: col, row: rows - 1 - yIndex)
                // Off-map tiles count as solid, which walls the district in.
                if tile(c).isSolid {
                    result.append(Rect(x: Double(col) * tileSize, y: Double(yIndex) * tileSize,
                                       width: tileSize, height: tileSize))
                }
            }
        }
        return result
    }

    public func neighborhood(at p: Vec2) -> String {
        neighborhoods.first { $0.rect.contains(p) }?.name ?? name
    }

    /// Every drivable tile reachable from `start` by 4-way moves. Used to validate content.
    public func reachable(from start: TileCoord) -> Set<TileCoord> {
        guard !tile(start).isSolid else { return [] }
        var seen: Set<TileCoord> = [start]
        var queue = [start]
        var index = 0
        while index < queue.count {
            let c = queue[index]
            index += 1
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let n = TileCoord(col: c.col + dc, row: c.row + dr)
                if !seen.contains(n), !tile(n).isSolid {
                    seen.insert(n)
                    queue.append(n)
                }
            }
        }
        return seen
    }

    /// Shortest drivable path between two tiles (both ends included), or nil if none.
    public func path(from a: TileCoord, to b: TileCoord) -> [TileCoord]? {
        guard !tile(a).isSolid, !tile(b).isSolid else { return nil }
        var previous: [TileCoord: TileCoord] = [:]
        var seen: Set<TileCoord> = [a]
        var queue = [a]
        var index = 0
        while index < queue.count {
            let c = queue[index]
            index += 1
            if c == b {
                var route = [b]
                var step = b
                while let p = previous[step] {
                    route.append(p)
                    step = p
                }
                return route.reversed()
            }
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let n = TileCoord(col: c.col + dc, row: c.row + dr)
                if !seen.contains(n), !tile(n).isSolid {
                    seen.insert(n)
                    previous[n] = c
                    queue.append(n)
                }
            }
        }
        return nil
    }

    /// A comfortable driving route: like `path`, but each step next to a wall costs 3 instead of 1,
    /// so the route keeps to the middle of roads and only hugs walls where it has to. Off-road
    /// ground costs 2, so routes prefer roads and highways. Dijkstra on a binary heap, so it stays
    /// quick on Solara State's big map; ties break on (cost, column, row) so the same trip always
    /// gets the same route.
    public func drivingRoute(from a: TileCoord, to b: TileCoord) -> [TileCoord]? {
        guard !tile(a).isSolid, !tile(b).isSolid else { return nil }
        func stepCost(_ c: TileCoord) -> Int {
            for dc in -1...1 {
                for dr in -1...1 where tile(TileCoord(col: c.col + dc, row: c.row + dr)).isSolid {
                    return 3
                }
            }
            return tile(c).isOffRoad ? 2 : 1
        }
        var cost: [TileCoord: Int] = [a: 0]
        var previous: [TileCoord: TileCoord] = [:]
        var done: Set<TileCoord> = []
        var heap = RouteHeap()
        heap.push(RouteHeap.Entry(cost: 0, col: a.col, row: a.row))
        while let top = heap.pop() {
            let current = TileCoord(col: top.col, row: top.row)
            if done.contains(current) || top.cost != cost[current] { continue }
            done.insert(current)
            if current == b { break }
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let n = TileCoord(col: current.col + dc, row: current.row + dr)
                guard !tile(n).isSolid, !done.contains(n) else { continue }
                let candidate = top.cost + stepCost(n)
                if candidate < cost[n] ?? .max {
                    cost[n] = candidate
                    previous[n] = current
                    heap.push(RouteHeap.Entry(cost: candidate, col: n.col, row: n.row))
                }
            }
        }
        guard cost[b] != nil else { return nil }
        var route = [b]
        var step = b
        while let p = previous[step] {
            route.append(p)
            step = p
        }
        return route.reversed()
    }

    /// Shortest drivable path length in tile steps, or nil if none.
    public func pathLength(from a: TileCoord, to b: TileCoord) -> Int? {
        path(from: a, to: b).map { $0.count - 1 }
    }
}

/// Min-heap ordered by (cost, column, row) for `drivingRoute`.
struct RouteHeap {
    struct Entry {
        let cost: Int
        let col: Int
        let row: Int
        func less(_ o: Entry) -> Bool { (cost, col, row) < (o.cost, o.col, o.row) }
    }
    private var items: [Entry] = []

    mutating func push(_ e: Entry) {
        items.append(e)
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard items[i].less(items[parent]) else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> Entry? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count && items[l].less(items[m]) { m = l }
                if r < items.count && items[r].less(items[m]) { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
        }
        return top
    }
}
