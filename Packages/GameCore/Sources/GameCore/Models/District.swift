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

    public var isSolid: Bool {
        switch self {
        case .building, .container, .fence, .water: true
        default: false
        }
    }
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
}

public enum ZoneKind: String, Codable, Sendable {
    case dropOff, pickup, safehouse, restricted, start
    /// A store the player walks into (on foot) to buy things.
    case shop
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
    /// All plain road tiles, where patrols spawn and cruise to.
    public let roadTiles: [TileCoord]

    public init(name: String, tileSize: Double, map: [String], zones: [Zone], neighborhoods: [Neighborhood]) {
        precondition(!map.isEmpty, "map needs at least one row")
        let width = map[0].count
        precondition(map.allSatisfy { $0.count == width }, "every map row must be the same width")
        self.name = name
        self.tileSize = tileSize
        self.cols = width
        self.rows = map.count
        let kinds: [TileKind] = map.flatMap { row in
            row.map { ch in
                guard let kind = TileKind(rawValue: ch) else {
                    preconditionFailure("unknown map character \(ch)")
                }
                return kind
            }
        }
        self.tiles = kinds
        self.zones = Dictionary(uniqueKeysWithValues: zones.map { ($0.id, $0) })
        self.neighborhoods = neighborhoods
        let cols = width
        self.roadTiles = (0..<map.count).flatMap { r in (0..<cols).map { TileCoord(col: $0, row: r) } }
            .filter { kinds[$0.row * cols + $0.col] == .road }
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
    /// so the route keeps to the middle of roads and only hugs walls where it has to.
    public func drivingRoute(from a: TileCoord, to b: TileCoord) -> [TileCoord]? {
        guard !tile(a).isSolid, !tile(b).isSolid else { return nil }
        func stepCost(_ c: TileCoord) -> Int {
            for dc in -1...1 {
                for dr in -1...1 where tile(TileCoord(col: c.col + dc, row: c.row + dr)).isSolid {
                    return 3
                }
            }
            return 1
        }
        var cost: [TileCoord: Int] = [a: 0]
        var previous: [TileCoord: TileCoord] = [:]
        var open: Set<TileCoord> = [a]
        // Ties break on (column, row) so the same trip always gets the same route.
        while let current = open.min(by: {
            (cost[$0]!, $0.col, $0.row) < (cost[$1]!, $1.col, $1.row)
        }) {
            open.remove(current)
            if current == b { break }
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let n = TileCoord(col: current.col + dc, row: current.row + dr)
                guard !tile(n).isSolid else { continue }
                let candidate = cost[current]! + stepCost(n)
                if candidate < cost[n] ?? .max {
                    cost[n] = candidate
                    previous[n] = current
                    open.insert(n)
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
