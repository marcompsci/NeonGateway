import Foundation

extension District {
    /// Port Aurora Docks: the first district. 24 × 32 tiles of 128 points.
    ///
    /// North: the Alleys (west) and the Safehouse garage (east). Middle: a Downtown grid with
    /// Harbor Park. South: container rows on the Docks, the fenced Customs Yard, two piers.
    ///
    ///  `.` road  `,` sidewalk  `a` alley  `d` dock  `p` plaza  `S` safehouse
    ///  `B` building  `C` containers  `#` fence  `~` water
    public static let portAuroraDocks: District = {
        let map = [
            "BBBBBBBBBBBBBBBBBBBBBBBB", //  0
            "B,..BBaBBB..BBBBBB..BBBB", //  1
            "B,..aaaaaa..BBBBBB..SSSB", //  2
            "B,..BBaBBB..BBBBBB..SSSB", //  3
            "B......................B", //  4  Harbor Avenue
            "B......................B", //  5
            "B,..BBBaBB..,,,,,,..,,,B", //  6
            "B,..BBBaBB..,BBBB,..,BBB", //  7
            "B,..aaaaaa..,BBBB,..,BBB", //  8
            "B,..BaBaBB..,BBBB,..,BBB", //  9
            "B,..BaBaBB..,BBBB,..,BBB", // 10
            "B,..BBBaBB..,,,,,,..,,,B", // 11
            "B......................B", // 12  Signal Street
            "B......................B", // 13
            "B,..,,,,,,..,,,,,,..,,,B", // 14
            "B,..,BBBB,..,pppp,..,BBB", // 15
            "B,..,BBBB,..,pBBp,..,BBB", // 16
            "B,..,BBBB,..,pppp,..,BBB", // 17
            "B,..,,,,,,..,,,,,,..,,,B", // 18
            "B......................B", // 19  Tide Road
            "B......................B", // 20
            "B,..,,,,,,..,,,,,,..,,,B", // 21
            "BddddddddddddddddddddddB", // 22
            "BdddCCCCddddCCCCddd#dddB", // 23
            "BdddCCCCddddCCCCddd#dddB", // 24
            "Bdddddddddddddddddd#dddB", // 25
            "BdddCCCCddddCCCCddd####B", // 26
            "BddddddddddddddddddddddB", // 27
            "~~~~ddd~~~~~~~ddd~~~~~~~", // 28  Pier 4 (west), Pier 9 (east)
            "~~~~ddd~~~~~~~ddd~~~~~~~", // 29
            "~~~~~~~~~~~~~~~~~~~~~~~~", // 30
            "~~~~~~~~~~~~~~~~~~~~~~~~"  // 31
        ]
        // Zones are built against a bare grid first so tile → world maths is shared.
        let grid = District(name: "Port Aurora Docks", tileSize: 128, map: map, zones: [], neighborhoods: [])
        let zones = [
            Zone(id: .pier4, name: "Pier 4", kind: .start,
                 rect: grid.rect(cols: 4, 6, rows: 28, 29)),
            Zone(id: .pier9, name: "Pier 9", kind: .start,
                 rect: grid.rect(cols: 14, 16, rows: 28, 29)),
            Zone(id: .lanternAlleyDrop, name: "Lantern Alley drop", kind: .dropOff,
                 rect: grid.rect(cols: 5, 5, rows: 9, 10)),
            Zone(id: .safehouse, name: "Safehouse", kind: .safehouse,
                 rect: grid.rect(cols: 20, 22, rows: 2, 3)),
            Zone(id: .customsYard, name: "Customs Yard", kind: .restricted,
                 rect: grid.rect(cols: 20, 22, rows: 22, 25)),
            Zone(id: .parkLantern, name: "Harbor Park lantern", kind: .pickup,
                 rect: grid.rect(cols: 13, 16, rows: 17, 17)),
            Zone(id: .containerLantern, name: "Container-row lantern", kind: .pickup,
                 rect: grid.rect(cols: 9, 10, rows: 23, 24)),
            Zone(id: .alleyLantern, name: "Back-alley lantern", kind: .pickup,
                 rect: grid.rect(cols: 8, 9, rows: 8, 8)),
            Zone(id: .neonRowBay, name: "Neon Row bay", kind: .dropOff,
                 rect: grid.rect(cols: 20, 22, rows: 6, 6)),
            Zone(id: .marketLane, name: "Night-market lane", kind: .dropOff,
                 rect: grid.rect(cols: 4, 5, rows: 2, 2)),
            Zone(id: .signalLantern, name: "Signal Street lantern", kind: .pickup,
                 rect: grid.rect(cols: 20, 22, rows: 11, 11)),
            Zone(id: .tideLantern, name: "Tide Road lantern", kind: .pickup,
                 rect: grid.rect(cols: 5, 8, rows: 21, 21)),
            Zone(id: .gunStore, name: "Bolt & Barrel", kind: .shop,
                 rect: grid.rect(cols: 14, 15, rows: 14, 14)),
            Zone(id: .printShop, name: "Signal Street print shop", kind: .dropOff,
                 rect: grid.rect(cols: 12, 13, rows: 11, 11)),
            Zone(id: .flyerHarbor, name: "Harbor Avenue storefront", kind: .pickup,
                 rect: grid.rect(cols: 13, 13, rows: 6, 6)),
            Zone(id: .flyerNeonRow, name: "Neon Row storefront", kind: .pickup,
                 rect: grid.rect(cols: 21, 21, rows: 14, 14)),
            Zone(id: .flyerTideRoad, name: "Tide Road storefront", kind: .pickup,
                 rect: grid.rect(cols: 5, 5, rows: 18, 18)),
            Zone(id: .flyerAlleys, name: "Alleys storefront", kind: .pickup,
                 rect: grid.rect(cols: 1, 1, rows: 10, 10))
        ]
        let neighborhoods = [
            Neighborhood(name: "The Alleys", rect: grid.rect(cols: 1, 9, rows: 1, 11)),
            Neighborhood(name: "Safehouse Row", rect: grid.rect(cols: 12, 22, rows: 1, 3)),
            Neighborhood(name: "Customs Yard", rect: grid.rect(cols: 20, 22, rows: 22, 25)),
            Neighborhood(name: "The Docks", rect: grid.rect(cols: 0, 23, rows: 22, 31)),
            Neighborhood(name: "Downtown", rect: grid.rect(cols: 0, 23, rows: 4, 21))
        ]
        return District(name: "Port Aurora Docks", tileSize: 128, map: map, zones: zones,
                        neighborhoods: neighborhoods)
    }()
}
