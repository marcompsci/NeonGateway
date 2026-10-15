import Foundation

/// What a landmark is, so the app knows how to draw it. Every landmark is an original design
/// with an invented name; they're meant to *feel* like the kind of place a road trip stops at.
public enum LandmarkKind: String, Sendable, CaseIterable {
    /// A long red suspension bridge over the bay (drawn over the bridge deck tiles).
    case suspensionBridge
    /// A tall needle tower with a saucer top.
    case needleTower
    /// A big pier Ferris wheel.
    case ferrisWheel
    /// A domed hilltop observatory.
    case observatory
    /// A stand of giant redwood-like trees.
    case giantTrees
    /// A huge granite dome rising out of the forest.
    case graniteDome
    /// A still mountain lake.
    case lake
    /// The neon tower on the desert strip.
    case glowTower
    /// Red sandstone arches.
    case arches
    /// A geyser that blows on a timer.
    case geyser
}

public struct Landmark: Sendable, Equatable, Identifiable {
    /// Unique per piece of art (a grove has several trees).
    public let id: String
    /// The stop zone players drive to.
    public let zone: ZoneID
    public let name: String
    public let kind: LandmarkKind
    /// The landmark's own footprint in world points (the art fills it).
    public let footprint: Rect
    /// One line for the phone and the job board.
    public let blurb: String
}

public struct StateCity: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// One line for the job board ("Bay city · the Crimson Span").
    public let tagline: String
    public let depot: ZoneID
    /// The city's footprint in world points.
    public let rect: Rect
}

/// Solara State: the big open map under Play. Port Aurora and five more cities, joined by
/// highways across coast, redwood forest, granite mountains and desert, with national parks and
/// landmarks to stop at. Generated in code (300 × 220 tiles, about 38 × 28 thousand points), so
/// it's the same on every phone.
public enum SolaraState {
    public static let cols = 300
    public static let rows = 220
    public static let tileSize = 128.0

    public static let district: District = build().district
    public static let landmarks: [Landmark] = build().landmarks
    public static let cities: [StateCity] = build().cities
    public static let parked: [ParkedSpawn] = build().parked
    public static let pickups: [PickupSpawn] = build().pickups

    /// Where a Solara run starts: Port Aurora's freight depot.
    public static var start: SpawnPoint {
        let depot = district.zones[.depotAurora]!.rect
        return SpawnPoint(position: depot.center, heading: .pi / 2)
    }

    public static func city(for depot: ZoneID) -> StateCity? { cities.first { $0.depot == depot } }

    /// The city the point is in (or nearest to), for "drive back to the city of your choosing".
    public static func nearestCity(to p: Vec2) -> StateCity {
        cities.min { ($0.rect.center - p).length < ($1.rect.center - p).length }!
    }

    // MARK: Building

    struct Built: Sendable {
        let district: District
        let landmarks: [Landmark]
        let cities: [StateCity]
        let parked: [ParkedSpawn]
        let pickups: [PickupSpawn]
    }

    /// The whole state, built once.
    nonisolated(unsafe) private static var cache: Built?
    private static let lock = NSLock()

    static func build() -> Built {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        var builder = Builder()
        let built = builder.make()
        cache = built
        return built
    }
}

/// Lays the state out tile by tile. Row 0 is the north edge, like the district map strings.
private struct Builder {
    let cols = SolaraState.cols
    let rows = SolaraState.rows
    var t: [TileKind]
    var zones: [Zone] = []
    var hoods: [Neighborhood] = []
    var landmarks: [Landmark] = []
    var cities: [StateCity] = []
    var parked: [ParkedSpawn] = []
    var pickups: [PickupSpawn] = []
    /// Tiles a highway runs on (kept clear of forest and rock).
    var highwayMask: Set<Int> = []

    init() { t = Array(repeating: .grass, count: SolaraState.cols * SolaraState.rows) }

    // MARK: Helpers

    func inside(_ c: Int, _ r: Int) -> Bool { c >= 0 && c < cols && r >= 0 && r < rows }
    func get(_ c: Int, _ r: Int) -> TileKind { inside(c, r) ? t[r * cols + c] : .rock }
    mutating func set(_ c: Int, _ r: Int, _ k: TileKind) { if inside(c, r) { t[r * cols + c] = k } }
    mutating func fill(_ c0: Int, _ r0: Int, _ w: Int, _ h: Int, _ k: TileKind) {
        for r in r0..<(r0 + h) { for c in c0..<(c0 + w) { set(c, r, k) } }
    }

    /// World rect (y up) of a tile block.
    func rect(_ c0: Int, _ r0: Int, _ w: Int, _ h: Int) -> Rect {
        let ts = SolaraState.tileSize
        return Rect(x: Double(c0) * ts, y: Double(rows - r0 - h) * ts, width: Double(w) * ts, height: Double(h) * ts)
    }

    /// Smooth 0...1 noise on a coarse grid, for forests, rock and dunes.
    func noise(_ c: Int, _ r: Int, cell: Int, salt: UInt64) -> Double {
        func h(_ x: Int, _ y: Int) -> Double {
            var g = SplitMix64(seed: UInt64(bitPattern: Int64(x &* 73_856_093 ^ y &* 19_349_663)) ^ salt)
            return Double(g.next() % 10_000) / 10_000
        }
        let fx = Double(c) / Double(cell), fy = Double(r) / Double(cell)
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        let tx = fx - Double(x0), ty = fy - Double(y0)
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        let a = h(x0, y0) + (h(x0 + 1, y0) - h(x0, y0)) * sx
        let b = h(x0, y0 + 1) + (h(x0 + 1, y0 + 1) - h(x0, y0 + 1)) * sx
        return a + (b - a) * sy
    }

    // MARK: Make

    mutating func make() -> SolaraState.Built {
        terrain()
        water()
        cityGrids()
        highways()
        landmarkSites()
        depots()
        hoods += [
            Neighborhood(name: "Coast Highway", rect: rect(14, 0, 10, rows)),
            Neighborhood(name: "Titan Grove National Park", rect: rect(100, 4, 44, 40)),
            Neighborhood(name: "Granite Range", rect: rect(140, 40, 36, 130)),
            Neighborhood(name: "Sunstone Arches National Park", rect: rect(158, 156, 40, 30)),
            Neighborhood(name: "Steamvale Geyser Basin", rect: rect(214, 6, 34, 36)),
            Neighborhood(name: "Ember Desert", rect: rect(176, 40, 124, 180)),
            Neighborhood(name: "Solara Interstate", rect: rect(0, 98, cols, 6)),
            Neighborhood(name: "Mirror Lake", rect: rect(86, 56, 26, 22))
        ]
        let district = District(name: "Solara State", tileSize: SolaraState.tileSize, cols: cols, rows: rows,
                                tiles: t, zones: zones, neighborhoods: hoods)
        return SolaraState.Built(district: district, landmarks: landmarks, cities: cities, parked: parked,
                                 pickups: pickups)
    }

    // MARK: Terrain

    mutating func terrain() {
        for r in 0..<rows {
            for c in 0..<cols {
                // Desert to the east and south-east.
                let desert = c > 176 || (c > 150 && r > 150)
                var k: TileKind = desert ? .sand : .grass
                // Redwood forest across the north.
                if r < 62 && c > 36 && c < 214 && !desert {
                    let n = noise(c, r, cell: 5, salt: 11)
                    let parkBoost = (c > 100 && c < 144 && r < 44) ? 0.16 : 0
                    if n + parkBoost > 0.5 { k = .forest }
                }
                // Granite range down the middle.
                if c > 140 && c < 176 && r > 40 && r < 172 {
                    if noise(c, r, cell: 6, salt: 23) > 0.46 { k = .rock }
                }
                // Canyon fins in the desert.
                if desert && noise(c, r, cell: 4, salt: 37) > 0.78 { k = .rock }
                // Scattered groves in the coastal grassland.
                if !desert && r >= 62 && c > 30 && noise(c, r, cell: 3, salt: 41) > 0.83 { k = .forest }
                t[r * cols + c] = k
            }
        }
    }

    mutating func water() {
        // Ocean along the west coast, with a gently wandering shore.
        for r in 0..<rows {
            let shore = 9 + Int((3 * sin(Double(r) / 9) + 2 * sin(Double(r) / 23)).rounded())
            for c in 0..<max(0, shore) { set(c, r, .water) }
        }
        // The bay north of Port Aurora: open to the ocean, crossed by the Crimson Span.
        for r in 72...85 {
            let reach = 54 - abs(r - 78) * 2
            for c in 0..<reach { set(c, r, .water) }
        }
        // Mirror Lake.
        for r in 60...72 {
            for c in 90...108 {
                let dx = Double(c - 99) / 9.5, dy = Double(r - 66) / 6.5
                if dx * dx + dy * dy <= 1 { set(c, r, .water) }
            }
        }
    }

    // MARK: Cities

    struct CitySpec {
        let id: String
        let name: String
        let tagline: String
        let col: Int, row: Int, w: Int, h: Int
        let depot: ZoneID
        /// Depot yard top-left (tiles).
        let depotCol: Int, depotRow: Int
        let seed: UInt64
    }

    static let citySpecs: [CitySpec] = [
        CitySpec(id: "aurora", name: "Port Aurora", tagline: "Bay city · the Crimson Span and Sunset Pier",
                 col: 26, row: 88, w: 34, h: 26, depot: .depotAurora, depotCol: 54, depotRow: 104, seed: 1),
        CitySpec(id: "starline", name: "Starline Hills", tagline: "Hillside lights · the Observatory",
                 col: 24, row: 176, w: 30, h: 24, depot: .depotStarline, depotCol: 48, depotRow: 192, seed: 2),
        CitySpec(id: "redwood", name: "Redwood Hollow", tagline: "Timber town · Titan Grove next door",
                 col: 66, row: 12, w: 28, h: 22, depot: .depotRedwood, depotCol: 88, depotRow: 26, seed: 3),
        CitySpec(id: "cinder", name: "Cinder Flats", tagline: "Desert neon · the Glow Tower",
                 col: 228, row: 96, w: 36, h: 28, depot: .depotCinder, depotCol: 229, depotRow: 104, seed: 4),
        CitySpec(id: "mesa", name: "Mesa Rojo", tagline: "Canyon town · Sunstone Arches",
                 col: 202, row: 178, w: 28, h: 22, depot: .depotMesa, depotCol: 203, depotRow: 192, seed: 5),
        CitySpec(id: "steamvale", name: "Steamvale", tagline: "Hot-spring town · Old Steady geyser",
                 col: 250, row: 14, w: 24, h: 20, depot: .depotSteamvale, depotCol: 251, depotRow: 26, seed: 6)
    ]

    /// A street grid: two-lane streets every 8 tiles (and round the edge), sidewalks round each
    /// block, buildings inside, and the odd park.
    mutating func cityGrids() {
        for spec in Self.citySpecs {
            var rng = SplitMix64(seed: spec.seed &* 977)
            fill(spec.col, spec.row, spec.w, spec.h, .sidewalk)
            for r in spec.row..<(spec.row + spec.h) {
                for c in spec.col..<(spec.col + spec.w) {
                    let lc = c - spec.col, lr = r - spec.row
                    let street = lc % 8 < 2 || lr % 8 < 2 || lc >= spec.w - 2 || lr >= spec.h - 2
                    if street { set(c, r, .road) }
                }
            }
            // Blocks: sidewalk ring, then buildings, a plaza park, or an alley through.
            var bc = spec.col + 2
            while bc + 6 <= spec.col + spec.w - 2 {
                var br = spec.row + 2
                while br + 6 <= spec.row + spec.h - 2 {
                    let roll = rng.next() % 10
                    if roll < 2 {
                        fill(bc + 1, br + 1, 4, 4, .plaza)
                    } else {
                        fill(bc + 1, br + 1, 4, 4, .building)
                        if roll == 9 { for r in (br + 1)..<(br + 5) { set(bc + 2, r, .alley) } }
                    }
                    br += 8
                }
                bc += 8
            }
            let world = rect(spec.col, spec.row, spec.w, spec.h)
            cities.append(StateCity(id: spec.id, name: spec.name, tagline: spec.tagline, depot: spec.depot, rect: world))
            hoods.append(Neighborhood(name: spec.name, rect: world))
            // A few cars at the kerb and a weapon or two.
            var placed = 0
            var tries = 0
            while placed < 4 && tries < 200 {
                tries += 1
                let c = spec.col + 2 + Int(rng.next() % UInt64(spec.w - 4))
                let r = spec.row + 2 + Int(rng.next() % UInt64(spec.h - 4))
                guard get(c, r) == .sidewalk, get(c + 1, r) == .road || get(c - 1, r) == .road else { continue }
                let model: VehicleID = [.dorado, .flicker, .ridgeback, .dorado][placed]
                parked.append(ParkedSpawn(model: model, tile: TileCoord(col: c, row: r), heading: .pi / 2))
                placed += 1
            }
            for _ in 0..<40 {
                let c = spec.col + 2 + Int(rng.next() % UInt64(spec.w - 4))
                let r = spec.row + 2 + Int(rng.next() % UInt64(spec.h - 4))
                if get(c, r) == .plaza || get(c, r) == .sidewalk {
                    pickups.append(PickupSpawn(weapon: pickups.count % 3 == 0 ? .smg : .pistol, ammo: 30,
                                               tile: TileCoord(col: c, row: r)))
                    break
                }
            }
        }
    }

    // MARK: Highways

    /// Two-tile-wide highway along a straight line, with a two-tile clear shoulder.
    mutating func highway(from a: (Int, Int), to b: (Int, Int)) {
        let horizontal = a.1 == b.1
        let (c0, c1) = (min(a.0, b.0), max(a.0, b.0))
        let (r0, r1) = (min(a.1, b.1), max(a.1, b.1))
        for r in r0...(horizontal ? r0 + 1 : r1) {
            for c in c0...(horizontal ? c1 : c0 + 1) {
                pave(c, r)
            }
        }
        // Shoulders: clear trees and rock so the road isn't a tunnel.
        let pad = 2
        for r in (r0 - pad)...((horizontal ? r0 + 1 : r1) + pad) {
            for c in (c0 - pad)...((horizontal ? c1 : c0 + 1) + pad) where inside(c, r) {
                let k = get(c, r)
                if k == .forest || k == .rock { set(c, r, c > 176 || (c > 150 && r > 150) ? .sand : .grass) }
            }
        }
    }

    mutating func pave(_ c: Int, _ r: Int) {
        guard inside(c, r) else { return }
        let k = get(c, r)
        switch k {
        case .road: return                       // through a city: its streets carry on
        case .water, .bridge: set(c, r, .bridge)
        case .sidewalk, .building, .plaza, .alley: set(c, r, .road)
        default: set(c, r, .highway)
        }
        highwayMask.insert(r * cols + c)
    }

    mutating func highways() {
        // Coast Highway: north–south down the coast, over the bay on the Crimson Span.
        highway(from: (16, 20), to: (16, 204))
        // Solara Interstate: Port Aurora east across the range to Cinder Flats.
        highway(from: (16, 100), to: (264, 100))
        // Redline Road: across the north, Coast Highway → Redwood Hollow → Steamvale.
        highway(from: (16, 24), to: (274, 24))
        // Grove Road: Redwood Hollow south past Mirror Lake to the Interstate.
        highway(from: (84, 24), to: (84, 100))
        // Sunrise Route: along the south, Coast Highway → Starline Hills → Mesa Rojo.
        highway(from: (16, 190), to: (246, 190))
        // Canyon Pass: Cinder Flats south to the Sunrise Route.
        highway(from: (246, 100), to: (246, 191))
        // Vale Road: Steamvale south to Cinder Flats.
        highway(from: (262, 24), to: (262, 100))
    }

    // MARK: Landmarks and depots

    /// A 3 × 3 visitor stop (plaza) at `col,row`, as a landmark zone.
    mutating func stop(_ id: ZoneID, _ name: String, _ c: Int, _ r: Int, w: Int = 3, h: Int = 3) {
        fill(c, r, w, h, .plaza)
        zones.append(Zone(id: id, name: name, kind: .landmark, rect: rect(c, r, w, h)))
    }

    mutating func site(_ id: ZoneID, _ name: String, _ kind: LandmarkKind, footprint: (Int, Int, Int, Int),
                       solid: Bool = true, blurb: String) {
        let (c, r, w, h) = footprint
        if solid { fill(c, r, w, h, .landmark) }
        landmarks.append(Landmark(id: "\(id.rawValue).\(landmarks.count)", zone: id, name: name, kind: kind,
                                  footprint: rect(c, r, w, h), blurb: blurb))
    }

    mutating func landmarkSites() {
        // Crimson Span: the bridge deck is the Coast Highway over the bay (rows 72–85).
        landmarks.append(Landmark(id: "spanVista", zone: .spanVista, name: "Crimson Span", kind: .suspensionBridge,
                                  footprint: rect(14, 70, 6, 18),
                                  blurb: "The red suspension bridge over Aurora Bay. Best at sunset."))
        stop(.spanVista, "Span Vista Point", 19, 66)

        // Port Aurora: the Needle downtown, Sunset Pier on the ocean.
        site(.auroraNeedle, "Aurora Needle", .needleTower, footprint: (37, 93, 3, 3),
             blurb: "A saucer-topped tower over downtown Port Aurora.")
        stop(.auroraNeedle, "Needle Plaza", 36, 97, w: 5)
        for c in 9...24 where c != 16 && c != 17 { for r in 108...109 { set(c, r, .dock) } }
        site(.sunsetPier, "Sunset Pier Wheel", .ferrisWheel, footprint: (9, 106, 4, 4),
             blurb: "The big wheel at the end of Sunset Pier.")
        stop(.sunsetPier, "Sunset Pier", 22, 110)

        // Starline Hills: the observatory on the hill above town.
        site(.starlineObservatory, "Starline Observatory", .observatory, footprint: (33, 168, 5, 5),
             blurb: "A white-domed observatory with the whole state below it.")
        stop(.starlineObservatory, "Observatory Lot", 34, 173)
        for r in 168...176 { set(31, r, .road); set(32, r, .road) }

        // Titan Grove National Park: giant trees east of Redwood Hollow.
        for (i, spot) in [(112, 14), (120, 20), (128, 12), (134, 30), (116, 34)].enumerated() {
            site(.titanGrove, "Titan Grove", .giantTrees, footprint: (spot.0, spot.1, 3, 3),
                 blurb: i == 0 ? "Redwood-like giants, some older than any city in Solara." : "")
        }
        stop(.titanGrove, "Titan Grove Visitor Center", 122, 26, w: 4)
        for c in 96...122 { if get(c, 27) != .highway { set(c, 27, .road); set(c, 28, .road) } }

        // Granite Crown: a huge dome east of Grove Road.
        site(.graniteCrown, "Granite Crown", .graniteDome, footprint: (90, 40, 9, 8),
             blurb: "A sheer granite dome climbers come from everywhere to see.")
        stop(.graniteCrown, "Crown Meadow", 87, 46)

        // Mirror Lake (the water is already there).
        landmarks.append(Landmark(id: "mirrorLake", zone: .mirrorLake, name: "Mirror Lake", kind: .lake, footprint: rect(90, 60, 19, 13),
                                  blurb: "Still enough to see the Granite Crown twice."))
        stop(.mirrorLake, "Mirror Lake Shore", 87, 64)

        // Cinder Flats: the Glow Tower on the strip.
        site(.glowTower, "Glow Tower", .glowTower, footprint: (237, 108, 3, 3),
             blurb: "The neon needle of Cinder Flats, visible from the desert at night.")
        stop(.glowTower, "Glow Mile", 236, 112, w: 5)

        // Sunstone Arches National Park.
        for spot in [(170, 166), (178, 172), (186, 164), (176, 180)] {
            site(.sunstoneArches, "Sunstone Arches", .arches, footprint: (spot.0, spot.1, 4, 2),
                 blurb: "Red sandstone arches carved by wind.")
        }
        for c in 170...202 { if get(c, 186) != .highway { set(c, 186, .road); set(c, 187, .road) } }
        stop(.sunstoneArches, "Arches Overlook", 180, 183)

        // Steamvale Geyser Basin: Old Steady.
        site(.oldSteady, "Old Steady", .geyser, footprint: (232, 18, 3, 3),
             blurb: "Blows like clockwork, roughly every half minute.")
        stop(.oldSteady, "Geyser Boardwalk", 231, 22)
        // Clear the basin around it.
        for r in 14...26 { for c in 226...242 where get(c, r) == .forest || get(c, r) == .rock { set(c, r, .sand) } }
    }

    /// A freight yard (garage-floor tiles) next to the highway in each city.
    mutating func depots() {
        for spec in Self.citySpecs {
            fill(spec.depotCol, spec.depotRow, 5, 4, .safehouse)
            zones.append(Zone(id: spec.depot, name: "\(spec.name) Freight Depot", kind: .depot,
                              rect: rect(spec.depotCol, spec.depotRow, 5, 4)))
        }
    }
}
