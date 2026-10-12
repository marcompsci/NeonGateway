import Foundation

/// A car or bike waiting at the kerb when a run starts. Anyone can get in.
public struct ParkedSpawn: Sendable, Equatable {
    public let model: VehicleID
    public let tile: TileCoord
    /// Radians, 0 = east, π/2 = north.
    public let heading: Double

    public init(model: VehicleID, tile: TileCoord, heading: Double) {
        self.model = model
        self.tile = tile
        self.heading = heading
    }
}

/// A weapon lying somewhere in the district. It comes back a while after it's taken.
public struct PickupSpawn: Sendable, Equatable {
    public let weapon: WeaponID
    public let ammo: Int
    public let tile: TileCoord

    public init(weapon: WeaponID, ammo: Int, tile: TileCoord) {
        self.weapon = weapon
        self.ammo = ammo
        self.tile = tile
    }
}

extension District {
    /// Vehicles parked on the sidewalks of Port Aurora Docks, all off the roads.
    public static let docksParked: [ParkedSpawn] = [
        ParkedSpawn(model: .dorado, tile: TileCoord(col: 1, row: 8), heading: .pi / 2),
        ParkedSpawn(model: .ridgeback, tile: TileCoord(col: 12, row: 9), heading: .pi / 2),
        ParkedSpawn(model: .flicker, tile: TileCoord(col: 17, row: 8), heading: .pi / 2),
        ParkedSpawn(model: .dorado, tile: TileCoord(col: 20, row: 9), heading: -.pi / 2),
        ParkedSpawn(model: .flicker, tile: TileCoord(col: 6, row: 14), heading: 0),
        ParkedSpawn(model: .dorado, tile: TileCoord(col: 12, row: 16), heading: .pi / 2),
        ParkedSpawn(model: .ridgeback, tile: TileCoord(col: 2, row: 25), heading: .pi / 2),
        ParkedSpawn(model: .flicker, tile: TileCoord(col: 17, row: 27), heading: .pi),
        ParkedSpawn(model: .dorado, tile: TileCoord(col: 21, row: 18), heading: 0),
        ParkedSpawn(model: .dorado, tile: TileCoord(col: 9, row: 21), heading: 0)
    ]

    /// Where the alley dealer stands: the back end of the night-market lane.
    public static let docksDealer = TileCoord(col: 8, row: 2)

    /// Weapons lying around the district.
    public static let docksPickups: [PickupSpawn] = [
        PickupSpawn(weapon: .pistol, ammo: 24, tile: TileCoord(col: 7, row: 9)),
        PickupSpawn(weapon: .pistol, ammo: 24, tile: TileCoord(col: 13, row: 15)),
        PickupSpawn(weapon: .smg, ammo: 60, tile: TileCoord(col: 10, row: 25)),
        PickupSpawn(weapon: .shotgun, ammo: 8, tile: TileCoord(col: 22, row: 27))
    ]
}
