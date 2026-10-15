import Foundation

extension MissionDef {
    /// Job 1: a refrigerated crate from Pier 9 to a back door in Lantern Alley.
    public static let coldCrate = MissionDef(
        id: .coldCrate,
        title: "Cold Crate",
        brief: "A sealed cooler crate is waiting on Pier 9. Get it to the back door in Lantern Alley before the ice melts. No questions asked.",
        kind: .timedDelivery,
        requiredRepLevel: 0,
        start: SpawnPoint(
            position: District.portAuroraDocks.center(of: TileCoord(col: 16, row: 29)),
            heading: .pi / 2
        ),
        objectives: [.reach(.lanternAlleyDrop)],
        timeLimit: 35,
        baseReward: 200,
        baseRepXP: 60,
        objectiveLines: ["Deliver the crate to Lantern Alley"]
    )

    /// Job 2: start inside the Customs Yard with heat, shake the patrols, slip away from Pier 4.
    public static let tideLineRun = MissionDef(
        id: .tideLineRun,
        title: "Tide Line Run",
        brief: "Customs flagged your plates mid-pickup. Get out of the yard, lose every patrol, then roll onto Pier 4 when nobody's watching. The boat won't wait for a tail.",
        kind: .escape,
        requiredRepLevel: 0,
        start: SpawnPoint(
            position: District.portAuroraDocks.center(of: TileCoord(col: 21, row: 25)),
            heading: .pi / 2
        ),
        objectives: [.reachCalm(.pier4)],
        timeLimit: nil,
        baseReward: 260,
        baseRepXP: 80,
        objectiveLines: ["Lose the heat, then reach Pier 4"],
        startingHeat: 35
    )

    /// Job 3: three lanterns hide envelopes. Grab them all, then get home to the Safehouse.
    public static let lanternSweep = MissionDef(
        id: .lanternSweep,
        title: "Lantern Sweep",
        brief: "Three paper lanterns around the district hide envelopes for the night-market crew. Grab all three in any order and bring them home to the Safehouse. Every grab turns heads.",
        kind: .pickupRun,
        requiredRepLevel: 0,
        start: GameCoreSpawns.safehouseRoad,
        objectives: [.collect([.parkLantern, .containerLantern, .alleyLantern]), .returnTo(.safehouse)],
        timeLimit: 60,
        baseReward: 320,
        baseRepXP: 90,
        objectiveLines: ["Grab the three lanterns", "Bring the envelopes to the Safehouse"],
        pickupHeat: 12
    )

    // MARK: Harder jobs, one per reputation level

    /// Rep 1, harder delivery: across the whole district on a tighter clock, already noticed.
    public static let deepFreeze = MissionDef(
        id: .deepFreeze,
        title: "Deep Freeze",
        brief: "A dockhand saw you load the freezer case on Pier 4 and made a call. Get it up to the Neon Row bay before it thaws, with Harbor Patrol already looking.",
        kind: .timedDelivery,
        requiredRepLevel: 1,
        start: SpawnPoint(
            position: District.portAuroraDocks.center(of: TileCoord(col: 5, row: 29)),
            heading: .pi / 2
        ),
        objectives: [.reach(.neonRowBay)],
        timeLimit: 25,
        baseReward: 340,
        baseRepXP: 110,
        objectiveLines: ["Deliver the case to the Neon Row bay"],
        startingHeat: 12
    )

    /// Rep 2, harder escape: three stars at the top of Downtown, and the boat is down at Pier 9.
    public static let ghostTide = MissionDef(
        id: .ghostTide,
        title: "Ghost Tide",
        brief: "The meet on Harbor Avenue was a trap and every unit in Port Aurora heard about it. Lose them all, then slip onto Pier 9 before the tide turns.",
        kind: .escape,
        requiredRepLevel: 2,
        start: SpawnPoint(
            position: District.portAuroraDocks.center(of: TileCoord(col: 8, row: 5)),
            heading: 0
        ),
        objectives: [.reachCalm(.pier9)],
        timeLimit: nil,
        baseReward: 420,
        baseRepXP: 150,
        objectiveLines: ["Lose the heat, then reach Pier 9"],
        startingHeat: 55
    )

    /// Rep 3, harder pickup run: five lanterns, each one hotter, then home.
    public static let lanternFestival = MissionDef(
        id: .lanternFestival,
        title: "Lantern Festival",
        brief: "Festival night: five lanterns, five envelopes, from the back alleys to the container rows. Every grab turns more heads than the last. Bring it all home to the Safehouse.",
        kind: .pickupRun,
        requiredRepLevel: 3,
        start: SpawnPoint(
            position: District.portAuroraDocks.center(of: TileCoord(col: 14, row: 4)),
            heading: 0
        ),
        objectives: [.collect([.parkLantern, .containerLantern, .alleyLantern, .signalLantern, .tideLantern]),
                     .returnTo(.safehouse)],
        timeLimit: 80,
        baseReward: 520,
        baseRepXP: 180,
        objectiveLines: ["Grab the five lanterns", "Bring the envelopes to the Safehouse"],
        pickupHeat: 14
    )

    /// Rep 4, the double: a timed drop at Pier 9 that turns out to be a setup, then a getaway.
    public static let doubleCross = MissionDef(
        id: .doubleCross,
        title: "Double Cross",
        brief: "A buyer on Pier 9 wants the case fast. Something about it feels wrong. If it goes bad, lose the heat and disappear into the night-market lane.",
        kind: .double,
        requiredRepLevel: 4,
        start: SpawnPoint(
            position: District.portAuroraDocks.center(of: TileCoord(col: 19, row: 6)),
            heading: -.pi / 2
        ),
        objectives: [.reach(.pier9), .reachCalm(.marketLane)],
        timeLimit: 20,
        baseReward: 650,
        baseRepXP: 220,
        objectiveLines: ["Deliver the case to Pier 9", "Lose the heat, reach the night-market lane"],
        clockedObjectives: 1,
        alarm: MissionAlarm(afterObjective: 0, heat: 55, notice: "It's a setup! Get out of there")
    )

    /// On foot: a side hustle for the print shop. Paid per job, no car needed (but allowed).
    public static let streetFlyers = MissionDef(
        id: .streetFlyers,
        title: "Street Flyers",
        brief: "The print shop on Signal Street pays cash to get its flyers into four storefronts before the lunch rush. It's a side hustle: small pay, no boss, no car needed. Run them out and come back for your money.",
        kind: .pickupRun,
        requiredRepLevel: 0,
        start: SpawnPoint(
            position: District.portAuroraDocks.center(of: TileCoord(col: 13, row: 11)),
            heading: .pi / 2
        ),
        objectives: [.collect([.flyerHarbor, .flyerNeonRow, .flyerTideRoad, .flyerAlleys]),
                     .returnTo(.printShop)],
        timeLimit: 90,
        baseReward: 180,
        baseRepXP: 50,
        objectiveLines: ["Drop flyers at four storefronts", "Collect your pay at the print shop"],
        startsOnFoot: true,
        collectLabel: "FLYERS"
    )

    /// Jobs in map order: the starters, then one harder job per reputation level, then the
    /// on-foot side hustle.
    public static let all: [MissionDef] = [.coldCrate, .tideLineRun, .lanternSweep,
                                           .deepFreeze, .ghostTide, .lanternFestival, .doubleCross,
                                           .streetFlyers]

    public static func with(_ id: MissionID) -> MissionDef? {
        if id == .streetChallenge { return StreetChallenge.current() }
        return all.first { $0.id == id }
    }
}

/// Shared spawn points.
public enum GameCoreSpawns {
    /// The road in front of the Safehouse garage, facing south toward the city.
    public static let safehouseRoad = SpawnPoint(
        position: District.portAuroraDocks.center(of: TileCoord(col: 19, row: 2)),
        heading: -.pi / 2
    )
}
