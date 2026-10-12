import XCTest
@testable import GameCore

/// The Workbench, paint designs, the body shop, the rankings and the design market.
final class CreativeTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_900_000_000)

    func player(credits: Int = 10_000, starter: WeaponID = .pistol) -> PlayerProgress {
        var p = PlayerProgress()
        p.credits = credits
        Onboarding.complete(PlayerProfile(name: "Nova", starter: starter), progress: &p)
        return p
    }

    // MARK: Workbench

    func testPartsChangeTheGunsRealStats() {
        var p = player()
        let base = WeaponID.pistol.spec
        XCTAssertNil(Workbench.fit(.longBarrel, slot: .barrel, on: .pistol, progress: &p, now: now))
        XCTAssertEqual(p.inventory.spec(for: .pistol).range, base.range * 1.3, accuracy: 0.001)
        XCTAssertGreaterThan(p.inventory.spec(for: .pistol).fireInterval, base.fireInterval)
        XCTAssertNil(Workbench.fit(.quickGrip, slot: .grip, on: .pistol, progress: &p))
        XCTAssertLessThan(p.inventory.spec(for: .pistol).aimHalfAngle, base.aimHalfAngle)
        XCTAssertEqual(p.books.total(.mods), -(GunPart.longBarrel.price + GunPart.quickGrip.price))
    }

    func testSwappingBetweenOwnedPartsIsFree() {
        var p = player()
        Workbench.fit(.shortBarrel, slot: .barrel, on: .pistol, progress: &p)
        let credits = p.credits
        XCTAssertNil(Workbench.fit(nil, slot: .barrel, on: .pistol, progress: &p))
        XCTAssertNil(p.inventory.build(for: .pistol).barrel)
        XCTAssertNil(Workbench.fit(.shortBarrel, slot: .barrel, on: .pistol, progress: &p))
        XCTAssertEqual(p.credits, credits, "already bought")
    }

    func testTheWorkbenchExtendedMagLiftsTheStarterLimitAndAddsCapacity() {
        var p = player()
        XCTAssertNil(Workbench.fit(.extendedMag, slot: .magazine, on: .pistol, progress: &p))
        XCTAssertFalse(p.inventory.isCapped(.pistol))
        XCTAssertEqual(p.inventory.ammoCap(for: .pistol), 180, "120 × 1.5")
        // The store's Extended Mag button fits the same part.
        var q = player()
        GunStore.buyExtendedMag(.pistol, progress: &q)
        XCTAssertEqual(q.inventory.build(for: .pistol).magazine, .extendedMag)
    }

    func testPartsOnlyFitTheirSlotAndGuns() {
        var p = player(starter: .bat)
        XCTAssertEqual(Workbench.fit(.longBarrel, slot: .barrel, on: .bat, progress: &p), .doesNotFit)
        XCTAssertEqual(Workbench.fit(.longBarrel, slot: .grip, on: .bat, progress: &p), .doesNotFit)
        XCTAssertEqual(Workbench.fit(.longBarrel, slot: .barrel, on: .rifle, progress: &p), .notOwned)
        XCTAssertNil(Workbench.paint(.bat, finish: 3, progress: &p), "the bat takes a finish")
        XCTAssertEqual(p.inventory.build(for: .bat).finish, 3)
        XCTAssertEqual(Workbench.paint(.bat, finish: 99, progress: &p), .badFinish)
    }

    func testBrokeCantBuyParts() {
        var p = player(credits: 10)
        XCTAssertEqual(Workbench.fit(.steadyGrip, slot: .grip, on: .pistol, progress: &p),
                       .notEnoughCredits(needed: GunPart.steadyGrip.price - 10))
        XCTAssertNil(p.inventory.build(for: .pistol).grip)
    }

    func testBuiltStatsReachTheStreet() {
        var p = player()
        Workbench.fit(.longBarrel, slot: .barrel, on: .pistol, progress: &p)
        // A target just past stock range but inside the long barrel's reach.
        let district = District.portAuroraDocks
        let origin = district.center(of: TileCoord(col: 6, row: 4))
        var city = City(district: district, start: SpawnPoint(position: origin, heading: 0), playerVehicle: nil,
                        inventory: p.inventory, seed: 3, parked: [], pickups: [], dealer: nil)
        city.crowd.people = [Pedestrian(id: 9, position: origin + Vec2(500, 0), heading: 0,
                                        target: origin + Vec2(500, 0), look: 0)]
        let events = city.step(input: .idle, actions: CityActions(fire: true), dt: VehicleDynamics.fixedStep)
        XCTAssertTrue(events.contains(.pedestrianDown(9)), "500 pt is out of a stock pistol's 420")
    }

    // MARK: Designs

    func testTemplatesAreValidAndDifferent() {
        var seen: Set<[UInt8]> = []
        for t in PaintDesign.Template.allCases {
            let cells = PaintDesign.cells(t, a: 1, b: 2)
            XCTAssertEqual(cells.count, PaintDesign.width * PaintDesign.height)
            XCTAssertTrue(cells.contains { $0 != 0 }, t.name)
            seen.insert(cells)
        }
        XCTAssertEqual(seen.count, PaintDesign.Template.allCases.count)
        XCTAssertTrue(BodyShop.houseDesigns.allSatisfy(\.isValid))
    }

    func testSamplingMapsTheGridOntoAnyCar() {
        let d = PaintDesign(id: "t", name: "Split", creator: "x", cells: PaintDesign.cells(.splitTone, a: 1, b: 2), price: 0)
        XCTAssertEqual(d.sample(u: 0.1, v: 0.5), 1)
        XCTAssertEqual(d.sample(u: 0.9, v: 0.5), 2)
        XCTAssertEqual(d.sample(u: 1.5, v: -1), 2, "clamped to the edge")
    }

    func testBolderDesignsScoreHigher() {
        let thin = PaintDesign(id: "a", name: "a", creator: "x", cells: PaintDesign.cells(.racingStripe, a: 1, b: 1), price: 0)
        let loud = PaintDesign(id: "b", name: "b", creator: "x", cells: PaintDesign.cells(.checker, a: 1, b: 2), price: 0)
        XCTAssertGreaterThan(loud.boldness, thin.boldness)
        XCTAssertLessThanOrEqual(loud.boldness, 1)
    }

    // MARK: Body shop

    func testBuyingAndApplyingADesign() {
        var p = player()
        let id = BodyShop.houseDesigns[0].id
        XCTAssertEqual(BodyShop.apply(id, toSlot: 0, progress: &p), .unknownDesign, "buy it first")
        XCTAssertNil(BodyShop.buy(id, progress: &p, now: now))
        XCTAssertEqual(BodyShop.buy(id, progress: &p), .alreadyOwned)
        XCTAssertEqual(p.books.total(.paint), -BodyShop.houseDesigns[0].price)
        XCTAssertNil(BodyShop.apply(id, toSlot: 0, progress: &p))
        XCTAssertEqual(p.garage[0].design, id)
        XCTAssertNil(BodyShop.apply(nil, toSlot: 0, progress: &p))
        XCTAssertNil(p.garage[0].design)
        XCTAssertEqual(BodyShop.apply(id, toSlot: 9, progress: &p), .noSuchCar)
    }

    func testAnyoneCanDrawButOnlyLegendsSell() {
        var p = player()
        let cells = PaintDesign.cells(.flames, a: 3, b: 4)
        guard case .success(let mine) = BodyShop.create(name: "  Night   Fire ", cells: cells, progress: &p) else {
            return XCTFail("design saved")
        }
        XCTAssertEqual(mine.name, "Night Fire")
        XCTAssertEqual(mine.creator, "Nova")
        XCTAssertTrue(BodyShop.isMine(mine.id))
        XCTAssertNil(BodyShop.apply(mine.id, toSlot: 0, progress: &p), "paint your own car any time")
        XCTAssertEqual(BodyShop.list(mine.id, price: 300, progress: &p), .notLegendary)
        XCTAssertEqual(BodyShop.create(name: "x", cells: cells, progress: &p), .failure(.badName))
        XCTAssertEqual(BodyShop.create(name: "Empty", cells: PaintDesign.blank, progress: &p), .failure(.badDesign))
        XCTAssertEqual(BodyShop.list(BodyShop.houseDesigns[0].id, price: 300, progress: &p), .notLegendary)
    }

    // MARK: Rankings

    func testTheLadderAndLegendaryRank() {
        var p = player()
        XCTAssertEqual(Ranking.tier(p), .street)
        XCTAssertEqual(Ranking.board(p).count, Ranking.rivals.count + 1)
        XCTAssertGreaterThan(Ranking.pointsToLegendary(p), 0)
        p.reputationXP = Ranking.pointsToLegendary(p) + Ranking.score(p)
        XCTAssertTrue(Ranking.isLegendary(p))
        XCTAssertEqual(Ranking.rank(p), Ranking.legendaryCutoff)
        XCTAssertEqual(Ranking.pointsToLegendary(p), 0)
        XCTAssertEqual(Ranking.tier(forRank: 7), .elite)
        XCTAssertEqual(Ranking.tier(forRank: 12), .pro)
        XCTAssertTrue(Set(Ranking.rivals.map(\.0)).count == Ranking.rivals.count)
    }

    func testProfitCountsTowardTheRanking() {
        var p = player()
        let before = Ranking.score(p)
        p.books.record(1000, .jobPay, "gig", on: now)
        XCTAssertEqual(Ranking.score(p), before + 200)
    }

    // MARK: Market

    func legend() -> (PlayerProgress, String) {
        var p = player()
        p.reputationXP = 5000
        guard case .success(let d) = BodyShop.create(name: "Grid Lock", cells: PaintDesign.cells(.checker, a: 2, b: 5),
                                                     progress: &p) else { fatalError() }
        return (p, d.id)
    }

    func testListingAndSellingPaysTheCreatorMinusTheFee() {
        var (p, id) = legend()
        XCTAssertNil(BodyShop.list(id, price: 200, progress: &p))
        XCTAssertEqual(BodyShop.list(id, price: 1, progress: &p), .badPrice)
        let credits = p.credits
        var total = BodyShop.Report()
        for _ in 0..<10 { total.lines += BodyShop.marketDay(&p, now: now).lines }
        let sold = total.lines.reduce(0) { $0 + $1.sold }
        XCTAssertGreaterThan(sold, 5, "a bold design at 200 sells")
        let gross = sold * 200
        let fee = total.lines.reduce(0) { $0 + $1.fee }
        XCTAssertEqual(fee, total.lines.reduce(0) { $0 + Int((Double($1.gross) * BodyShop.platformFee).rounded()) })
        XCTAssertEqual(p.credits - credits, gross - fee)
        XCTAssertEqual(p.books.total(.designSales), gross - fee)
        XCTAssertEqual(p.listings[0].sold, sold)
        XCTAssertEqual(p.marketDay, 10)
    }

    func testHigherPricesSellFewerButCanEarnMore() {
        XCTAssertGreaterThan(BodyShop.expectedSales(boldness: 0.8, price: 100),
                             BodyShop.expectedSales(boldness: 0.8, price: 800))
        let revenue = { (price: Int) in BodyShop.expectedSales(boldness: 0.8, price: price) * Double(price) }
        XCTAssertGreaterThan(revenue(400), revenue(50), "too cheap leaves money on the table")
        XCTAssertGreaterThan(revenue(400), revenue(2000), "too dear and nobody buys")
    }

    func testUnlistedDesignsDontSell() {
        var (p, id) = legend()
        BodyShop.list(id, price: 200, progress: &p)
        BodyShop.unlist(id, progress: &p)
        XCTAssertTrue(BodyShop.marketDay(&p).isEmpty)
    }

    func testTheMarketIsRepeatable() {
        var (a, id) = legend()
        var b = a
        BodyShop.list(id, price: 350, progress: &a)
        BodyShop.list(id, price: 350, progress: &b)
        for _ in 0..<5 {
            XCTAssertEqual(BodyShop.marketDay(&a, now: now), BodyShop.marketDay(&b, now: now))
        }
    }

    func testNewLessonsUnlock() {
        var (p, id) = legend()
        func unlocked(_ lesson: String) -> Bool { Lesson.all.first { $0.id == lesson }!.isUnlocked(p) }
        XCTAssertTrue(unlocked("creator"))
        XCTAssertFalse(unlocked("pricing"))
        BodyShop.list(id, price: 150, progress: &p)
        XCTAssertTrue(unlocked("pricing"))
        for _ in 0..<5 { BodyShop.marketDay(&p) }
        XCTAssertTrue(unlocked("platformFee"))
    }

    func testCreativeDataSurvivesASave() {
        var (p, id) = legend()
        BodyShop.list(id, price: 250, progress: &p)
        BodyShop.buy(BodyShop.houseDesigns[1].id, progress: &p, now: now)
        BodyShop.apply(id, toSlot: 0, progress: &p)
        Workbench.fit(.steadyGrip, slot: .grip, on: .pistol, progress: &p, now: now)
        Workbench.paint(.pistol, finish: 2, progress: &p, now: now)
        BodyShop.marketDay(&p, now: now)
        XCTAssertEqual(SaveCodec.loadProgress(from: SaveCodec.encode(p)), p)
    }
}
