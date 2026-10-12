import XCTest
@testable import GameCore

/// The online layer: name filter, the design market's money and safety rules, the live-play
/// protocol, and players hitting, knocking out and taking guns from each other.
final class OnlineTests: XCTestCase {
    let district = District.portAuroraDocks
    let dt = VehicleDynamics.fixedStep
    let now = Date(timeIntervalSince1970: 1_791_763_200)

    func at(_ col: Int, _ row: Int) -> Vec2 { district.center(of: TileCoord(col: col, row: row)) }

    // MARK: Filter

    func testFilterCatchesRudeNamesButNotInnocentOnes() {
        for bad in ["Sh1t Racer", "f.u.c.k", "BIG ASS", "www.mysite.com", "add me @snap", "SHIIIT"] {
            XCTAssertFalse(ContentFilter.isAllowedPublicName(bad), bad)
        }
        for fine in ["Cassidy", "Grasshopper", "Peacock Flames", "Raccoon", "Midnight Racer", "Torpedo",
                     "Grape Soda", "Nova"] {
            XCTAssertTrue(ContentFilter.isAllowedPublicName(fine), fine)
        }
        XCTAssertNil(PlayerProfile.cleanName("B1tch"))
        XCTAssertEqual(PlayerProfile.cleanName("Nova"), "Nova")
        var p = PlayerProgress()
        if case .failure(let r) = BodyShop.create(name: "Shit Storm", cells: PaintDesign.cells(.flames, a: 1, b: 2),
                                                  progress: &p) {
            XCTAssertEqual(r, .badName)
        } else {
            XCTFail("rude design name saved")
        }
    }

    // MARK: Market

    func design(_ id: String = "rec1", by creator: String = "G:creator", price: Int = 400,
                reports: Int = 0, name: String = "Neon Wave") -> MarketDesign {
        MarketDesign(id: id, name: name, creatorID: creator, creatorName: "Lula", cells: PaintDesign.cells(.flames, a: 2, b: 3),
                     price: price, created: now, reports: reports)
    }

    func testBuyingADesignOnline() {
        var p = PlayerProgress()
        p.credits = 1_000
        XCTAssertEqual(OnlineMarket.buy(design(), myID: "G:creator", progress: &p), .ownDesign)
        XCTAssertNil(OnlineMarket.buy(design(), myID: "G:me", progress: &p, now: now))
        XCTAssertEqual(p.credits, 600)
        XCTAssertTrue(p.designs.contains { $0.id == "cloud.rec1" && $0.creator == "Lula" })
        XCTAssertEqual(p.books.total(.paint), -400)
        XCTAssertEqual(OnlineMarket.buy(design(), myID: "G:me", progress: &p), .alreadyOwned)
        XCTAssertEqual(OnlineMarket.buy(design("rec2", price: 5_000), myID: "G:me", progress: &p),
                       .notEnoughCredits(needed: 4_400))
        XCTAssertEqual(OnlineMarket.buy(design("rec3", reports: 3), myID: "G:me", progress: &p), .hidden)
        // A bought online design paints a car like any other.
        XCTAssertNil(BodyShop.apply("cloud.rec1", toSlot: 0, progress: &p))
    }

    func testBlockedReportedAndRudeDesignsAreHidden() {
        var p = PlayerProgress()
        OnlineMarket.block("G:troll", progress: &p)
        OnlineMarket.block("G:troll", progress: &p)
        XCTAssertEqual(p.online.blocked, ["G:troll"])
        let shown = OnlineMarket.visible([design("a"), design("b", by: "G:troll"), design("c", reports: 5),
                                          design("d", name: "Sh1t Wagon")], for: p)
        XCTAssertEqual(shown.map(\.id), ["a"])
        OnlineMarket.unblock("G:troll", progress: &p)
        XCTAssertTrue(p.online.blocked.isEmpty)
        XCTAssertTrue(OnlineMarket.markReported("a", progress: &p))
        XCTAssertFalse(OnlineMarket.markReported("a", progress: &p), "one report per player")
    }

    func testCreatorsArePaidOncePerSaleAfterTheFee() {
        var p = PlayerProgress()
        let sales = [
            MarketPurchase(id: "p1", designID: "rec1", designName: "Neon Wave", creatorID: "G:me", buyerID: "G:a",
                           price: 400, created: now),
            MarketPurchase(id: "p2", designID: "rec1", designName: "Neon Wave", creatorID: "G:me", buyerID: "G:b",
                           price: 400, created: now.addingTimeInterval(60)),
            // Not mine, and a "purchase" of my own design: neither pays.
            MarketPurchase(id: "p3", designID: "rec9", designName: "Other", creatorID: "G:x", buyerID: "G:a",
                           price: 400, created: now),
            MarketPurchase(id: "p4", designID: "rec1", designName: "Neon Wave", creatorID: "G:me", buyerID: "G:me",
                           price: 400, created: now)
        ]
        let payout = OnlineMarket.collectSales(sales, myID: "G:me", progress: &p, now: now)
        XCTAssertEqual(payout.sales, 2)
        XCTAssertEqual(payout.net, 560)
        XCTAssertEqual(p.credits, 560)
        XCTAssertEqual(p.books.total(.designSales), 560)
        XCTAssertEqual(p.online.onlineEarnings, 560)
        // The same records again (a refresh) pay nothing.
        XCTAssertEqual(OnlineMarket.collectSales(sales, myID: "G:me", progress: &p, now: now).sales, 0)
        XCTAssertEqual(p.credits, 560)
    }

    func testPublishingNeedsLegendaryAndACleanDesign() {
        var p = PlayerProgress()
        guard case .success(let mine) = BodyShop.create(name: "Neon Wave", cells: PaintDesign.cells(.flames, a: 2, b: 3),
                                                        progress: &p) else { return XCTFail("saved") }
        XCTAssertEqual(OnlineMarket.checkPublish(mine.id, price: 300, progress: p), .notLegendary)
        p.reputationXP = 99_999
        XCTAssertNil(OnlineMarket.checkPublish(mine.id, price: 300, progress: p))
        XCTAssertEqual(OnlineMarket.checkPublish(mine.id, price: 1, progress: p), .badPrice)
        XCTAssertEqual(OnlineMarket.checkPublish("house.dusk", price: 300, progress: p), .badDesign)
        OnlineMarket.markPublished(mine.id, record: "rec7", progress: &p)
        XCTAssertEqual(OnlineMarket.checkPublish(mine.id, price: 300, progress: p), .alreadyPublished)
    }

    // MARK: Protocol

    func testMessagesRoundTrip() {
        let messages: [NetMessage] = [
            .hello(name: "Nova", profile: PlayerProfile(name: "Nova", starter: .pistol), paint: [1, 2, 3]),
            .state(PlayerSnapshot(x: 1, y: 2, heading: 0.5, speed: 30, vehicle: .dorado, weapon: .smg, health: 80, time: 3)),
            .hit(target: "G:b", damage: 3, weapon: .rifle),
            .hit(target: "G:b", damage: 4, weapon: nil),
            .knockedOut(by: "G:a"),
            .drop(NetDrop(id: "G:a#1", owner: "G:a", weapon: .shotgun, ammo: 8, x: 10, y: 20)),
            .claim(dropID: "G:a#1"),
            .granted(dropID: "G:a#1", to: "G:b")
        ]
        for m in messages {
            XCTAssertEqual(NetCodec.decode(NetCodec.encode(m)!), m)
        }
        XCTAssertNil(NetCodec.decode(Data("junk".utf8)))
    }

    func testHitsMustBePlausible() {
        XCTAssertTrue(PvP.plausible(shooter: .zero, target: Vec2(300, 0), weapon: .pistol, damage: 1))
        XCTAssertFalse(PvP.plausible(shooter: .zero, target: Vec2(2_000, 0), weapon: .pistol, damage: 1))
        XCTAssertFalse(PvP.plausible(shooter: .zero, target: Vec2(10, 0), weapon: .pistol, damage: 50))
        XCTAssertTrue(PvP.plausible(shooter: .zero, target: Vec2(40, 0), weapon: nil, damage: City.runOverDamage))
    }

    func testRemoteMovementIsSmoothedAndOldPacketsIgnored() {
        var track = RemoteTrack()
        XCTAssertNil(track.pose(at: 0))
        func snap(_ x: Double, _ t: Double) -> PlayerSnapshot {
            PlayerSnapshot(x: x, y: 0, heading: 0, speed: 0, vehicle: nil, weapon: nil, health: 100, time: t)
        }
        track.receive(snap(0, 1.0), at: 10)
        track.receive(snap(100, 1.1), at: 10.1)
        track.receive(snap(50, 1.05), at: 10.12)
        XCTAssertEqual(track.latest?.x, 100, "an older packet doesn't overwrite a newer one")
        let mid = track.pose(at: 10.1 + PvP.interpolationDelay - 0.05)!
        XCTAssertEqual(mid.position.x, 50, accuracy: 1)
        XCTAssertFalse(track.isStale(at: 12))
        XCTAssertTrue(track.isStale(at: 10.1 + PvP.timeout + 1))
    }

    func testTheFirstClaimGetsTheGun() {
        var arbiter = DropArbiter(owner: "G:a")
        let drop = arbiter.makeDrop(weapon: .smg, ammo: 30, at: .zero)
        XCTAssertEqual(arbiter.claim(drop.id, by: "G:b"), "G:b")
        XCTAssertNil(arbiter.claim(drop.id, by: "G:c"), "already gone")
        XCTAssertNil(arbiter.claim("G:z#9", by: "G:c"))
        let second = arbiter.makeDrop(weapon: .pistol, ammo: 5, at: .zero)
        XCTAssertNotEqual(second.id, drop.id)
    }

    // MARK: Live play in the city

    func armedCity(_ weapon: WeaponID = .pistol) -> City {
        var inv = Inventory()
        inv.addStarter(weapon)
        var city = City(district: district, start: SpawnPoint(position: at(12, 4), heading: 0), playerVehicle: nil,
                        inventory: inv, seed: 3, parked: [], pickups: [])
        city.crowd.people = []
        city.pursuit.patrols = []
        return city
    }

    func testShootingAnotherPlayerReportsAHit() {
        var city = armedCity()
        city.remotes = [RemoteAvatar(id: "G:b", position: at(12, 4) + Vec2(200, 0), heading: 0, vehicle: nil, health: 100)]
        let events = city.step(input: .idle, actions: CityActions(fire: true), dt: dt)
        XCTAssertTrue(events.contains(.hitPlayer("G:b", damage: 1, weapon: .pistol)))
        // A player who's down can't be hit again.
        city.remotes[0].health = 0
        var later: [CityEvent] = []
        for _ in 0..<60 { later += city.step(input: .idle, actions: CityActions(fire: true), dt: dt) }
        XCTAssertFalse(later.contains { if case .hitPlayer = $0 { return true } else { return false } })
    }

    func testGettingKnockedOutByAPlayerHandsOverAGun() {
        var victim = armedCity(.shotgun)
        XCTAssertEqual(victim.inventory.droppable, .shotgun)
        _ = victim.takeHit(damage: 4, from: "G:a")
        XCTAssertEqual(victim.health, City.maxHealth - 48)
        _ = victim.takeHit(damage: 5, from: "G:a")
        let events = victim.step(input: .idle, actions: .init(), dt: dt)
        XCTAssertTrue(events.contains(.knockedOut))
        XCTAssertEqual(victim.lastAttacker, "G:a")
        let gun = victim.surrenderGun()
        XCTAssertEqual(gun?.0, .shotgun)
        XCTAssertFalse(victim.inventory.owns(.shotgun))
        victim.respawn(at: SpawnPoint(position: at(6, 4), heading: 0))
        XCTAssertEqual(victim.health, City.maxHealth)
        XCTAssertNil(victim.lastAttacker)
        XCTAssertEqual(victim.pursuit.heat.points, 0)

        // The attacker's side: the drop appears, they ask for it, the owner says yes.
        var taker = armedCity(.bat)
        var arbiter = DropArbiter(owner: "G:b")
        let drop = arbiter.makeDrop(weapon: gun!.0, ammo: gun!.1, at: taker.playerPosition)
        taker.addNetworkDrop(drop)
        taker.addNetworkDrop(drop)
        XCTAssertEqual(taker.pickups.filter { $0.networkID != nil }.count, 1, "added once")
        let claim = taker.step(input: .idle, actions: .init(), dt: dt)
        XCTAssertTrue(claim.contains(.claimDrop(drop.id)))
        XCTAssertFalse(taker.inventory.owns(.shotgun), "not until the owner agrees")
        XCTAssertFalse(taker.step(input: .idle, actions: .init(), dt: dt).contains(.claimDrop(drop.id)), "asks once")
        XCTAssertEqual(arbiter.claim(drop.id, by: "G:a"), "G:a")
        let got = taker.resolveNetworkDrop(drop.id, mine: true)
        XCTAssertTrue(got.contains { if case .pickedUp(.shotgun, _) = $0 { return true } else { return false } })
        XCTAssertTrue(taker.inventory.owns(.shotgun))
        XCTAssertFalse(taker.inventory.isCapped(.shotgun), "a taken gun has no starter limit")
        XCTAssertTrue(taker.pickups.allSatisfy { $0.networkID == nil })
    }

    func testHitsInACarCostHullAndBikesRunPlayersOver() {
        var city = City(district: district, start: SpawnPoint(position: at(5, 4), heading: 0), playerVehicle: .vesper,
                        seed: 3, parked: [], pickups: [])
        city.crowd.people = []
        city.pursuit.patrols = []
        _ = city.takeHit(damage: 4, from: "G:a")
        XCTAssertEqual(city.currentVehicle?.damage, 2)
        XCTAssertEqual(city.health, City.maxHealth)
        city.remotes = [RemoteAvatar(id: "G:w", position: at(9, 4), heading: 0, vehicle: nil, health: 100)]
        var events: [CityEvent] = []
        for _ in 0..<Int(2 / dt) { events += city.step(input: VehicleInput(throttle: 1), actions: .init(), dt: dt) }
        XCTAssertTrue(events.contains(.hitPlayer("G:w", damage: City.runOverDamage, weapon: nil)))
    }

    func testOldSavesGetEmptyOnlineState() throws {
        var p = PlayerProgress()
        p.credits = 50
        OnlineMarket.block("G:x", progress: &p)
        let round = SaveCodec.loadProgress(from: SaveCodec.encode(p))
        XCTAssertEqual(round, p)
        var json = try JSONSerialization.jsonObject(with: SaveCodec.encode(p)!) as! [String: Any]
        json.removeValue(forKey: "online")
        let old = SaveCodec.loadProgress(from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.online, OnlineState())
        XCTAssertEqual(old.credits, 50)
    }

    func testBoardsPostTheRightScores() {
        var p = PlayerProgress()
        p.reputationXP = 300
        p.league.earnings = 1_234
        let scores = OnlineBoards.scores(p)
        XCTAssertEqual(scores[OnlineBoards.weekly], 1_234)
        XCTAssertEqual(scores[OnlineBoards.allTime], Ranking.score(p))
        XCTAssertEqual(scores[OnlineBoards.netWorth], NetWorth.total(p))
    }
}
