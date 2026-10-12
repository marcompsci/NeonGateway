import XCTest
@testable import GameCore

/// The money side: the ledger, the gun store, the garage and the lessons.
final class BusinessTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_900_000_000)

    func rich(_ credits: Int = 5000) -> PlayerProgress {
        var p = PlayerProgress()
        p.credits = credits
        return p
    }

    // MARK: Books

    func testJobPayAndUpgradesLandInTheBooks() {
        var p = PlayerProgress()
        let result = MissionResult(missionID: .coldCrate, kind: .timedDelivery, outcome: .success,
                                   elapsed: 20, timeLimit: 35, hits: 0, driftScore: 0)
        let update = ProgressionRules.apply(result, def: .coldCrate, to: &p, now: now)
        XCTAssertEqual(p.books.income, update.payout.credits)
        XCTAssertEqual(p.books.entries.last?.category, .jobPay)
        XCTAssertEqual(p.books.entries.last?.note, "Cold Crate")

        p.credits = 1000
        UpgradeShop.buy(.speed, progress: &p, now: now)
        XCTAssertEqual(p.books.expenses, UpgradeShop.costs[0])
        XCTAssertEqual(p.books.profit, update.payout.credits - UpgradeShop.costs[0])
        XCTAssertEqual(p.books.margin!, Double(p.books.profit) / Double(p.books.income), accuracy: 1e-9)
    }

    func testFailedJobsWriteNothing() {
        var p = PlayerProgress()
        let fail = MissionResult(missionID: .coldCrate, kind: .timedDelivery, outcome: .busted,
                                 elapsed: 20, timeLimit: 35, hits: 0, driftScore: 0)
        _ = ProgressionRules.apply(fail, def: .coldCrate, to: &p, now: now)
        XCTAssertTrue(p.books.entries.isEmpty)
        XCTAssertNil(p.books.margin)
    }

    func testOldEntriesAreTrimmedButTotalsStay() {
        var books = Books()
        for _ in 0..<(Books.keepEntries + 50) { books.record(10, .jobPay, "gig", on: now) }
        XCTAssertEqual(books.entries.count, Books.keepEntries)
        XCTAssertEqual(books.income, 10 * (Books.keepEntries + 50))
        XCTAssertEqual(books.entryCount, Books.keepEntries + 50)
    }

    // MARK: Gun store

    func testBuyingAWeaponAndAmmo() {
        var p = rich(1000)
        XCTAssertNil(GunStore.buy(.pistol, progress: &p, now: now))
        XCTAssertEqual(p.credits, 1000 - WeaponID.pistol.spec.price)
        XCTAssertEqual(p.inventory.ammo(for: .pistol), WeaponID.pistol.spec.ammoPack)
        XCTAssertEqual(p.inventory.equipped, .pistol)
        XCTAssertEqual(GunStore.buy(.pistol, progress: &p), .alreadyOwned)

        XCTAssertNil(GunStore.buyAmmo(.pistol, progress: &p, now: now))
        XCTAssertEqual(p.inventory.ammo(for: .pistol), 2 * WeaponID.pistol.spec.ammoPack)
        XCTAssertEqual(p.books.total(.weapons), -WeaponID.pistol.spec.price)
        XCTAssertEqual(p.books.total(.ammo), -WeaponID.pistol.spec.ammoPrice)
    }

    func testGunStoreRefusals() {
        var broke = rich(10)
        XCTAssertEqual(GunStore.buy(.shotgun, progress: &broke),
                       .notEnoughCredits(needed: WeaponID.shotgun.spec.price - 10))
        XCTAssertEqual(broke.credits, 10, "nothing taken")
        XCTAssertEqual(GunStore.buyAmmo(.smg, progress: &broke), .notOwned)
        var full = rich()
        full.inventory.add(.shotgun, ammo: 999)
        XCTAssertEqual(GunStore.buyAmmo(.shotgun, progress: &full), .full)
    }

    // MARK: Garage

    func testANewSaveOwnsTheVesper() {
        let p = PlayerProgress()
        XCTAssertEqual(p.garage, [OwnedVehicle(model: .vesper)])
        XCTAssertEqual(p.selectedModel, .vesper)
    }

    func testKeepingAndSellingCars() {
        var p = PlayerProgress()
        XCTAssertTrue(GarageRules.keep(.flicker, progress: &p))
        XCTAssertTrue(GarageRules.keep(.ridgeback, progress: &p))
        XCTAssertFalse(GarageRules.keep(.harborPatrol, progress: &p), "patrol cars can't be kept")
        p.selectedVehicle = 2
        XCTAssertEqual(p.selectedModel, .ridgeback)
        XCTAssertEqual(GarageRules.assetValue(p),
                       VehicleID.vesper.marketValue + VehicleID.flicker.marketValue + VehicleID.ridgeback.marketValue)

        XCTAssertNil(GarageRules.sell(slot: 0, progress: &p), "the starter car stays")
        let paid = GarageRules.sell(slot: 2, progress: &p, now: now)
        XCTAssertEqual(paid, GarageRules.resaleValue(.ridgeback))
        XCTAssertLessThan(paid!, VehicleID.ridgeback.marketValue, "second-hand sells for less")
        XCTAssertEqual(p.credits, paid)
        XCTAssertEqual(p.selectedVehicle, 0, "selection falls back to a car you still have")
        XCTAssertEqual(p.books.total(.vehicleSale), paid)
    }

    func testGarageHasLimitedSlots() {
        var p = PlayerProgress()
        for _ in 1..<GarageRules.slots { XCTAssertTrue(GarageRules.keep(.dorado, progress: &p)) }
        XCTAssertFalse(GarageRules.keep(.dorado, progress: &p))
        XCTAssertEqual(p.garage.count, GarageRules.slots)
    }

    // MARK: Lessons

    func testLessonsUnlockFromWhatThePlayerDid() {
        var p = PlayerProgress()
        XCTAssertTrue(Lesson.all.allSatisfy { !$0.isUnlocked(p) }, "a new save has nothing unlocked")
        p.books.record(200, .jobPay, "Cold Crate", on: now)
        XCTAssertTrue(Lesson.all.first { $0.id == "revenue" }!.isUnlocked(p))
        GarageRules.keep(.flicker, progress: &p)
        XCTAssertTrue(Lesson.all.first { $0.id == "assets" }!.isUnlocked(p))
        XCTAssertEqual(Set(Lesson.all.map(\.id)).count, Lesson.all.count)
    }

    // MARK: Saves

    func testAVersion1SaveUpgradesWithAGarageAndEmptyBooks() {
        let old = """
        {"schemaVersion":1,"credits":420,"reputationXP":15,"completedJobs":2,"bestEscapeStreak":0,
         "currentEscapeStreak":0,"upgrades":{"speed":1,"handling":0,"durability":0},
         "missionBests":{},"lastUpdated":"2026-10-09T12:00:00Z"}
        """
        let loaded = SaveCodec.loadProgress(from: Data(old.utf8))
        XCTAssertEqual(loaded.credits, 420)
        XCTAssertEqual(loaded.garage, [OwnedVehicle(model: .vesper)])
        XCTAssertEqual(loaded.inventory, Inventory())
        XCTAssertEqual(loaded.books, Books())
        XCTAssertEqual(loaded.schemaVersion, PlayerProgress.currentSchema)
    }

    func testEverythingNewRoundTrips() {
        var p = rich(3000)
        _ = GunStore.buy(.smg, progress: &p, now: now)
        GarageRules.keep(.flicker, progress: &p)
        p.selectedVehicle = 1
        XCTAssertEqual(SaveCodec.loadProgress(from: SaveCodec.encode(p)), p)
    }
}
