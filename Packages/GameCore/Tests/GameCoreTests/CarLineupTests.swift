import XCTest
@testable import GameCore

final class CarLineupTests: XCTestCase {
    func rich() -> PlayerProgress {
        var p = PlayerProgress()
        p.credits = 100_000
        p.reputationXP = 1_000_000
        return p
    }

    func testEveryLineupCarHasASpecAndIsDrivable() {
        for e in CarLineup.all {
            XCTAssertEqual(e.model.spec.id, e.model)
            XCTAssertTrue(VehicleID.drivable.contains(e.model), e.model.rawValue)
            XCTAssertFalse(e.blurb.isEmpty)
        }
        XCTAssertEqual(Set(CarLineup.all.map(\.model)).count, CarLineup.all.count)
    }

    func testBuyingADealerCar() {
        var p = rich()
        XCTAssertNil(CarLineup.acquire(.bruiser, progress: &p))
        XCTAssertEqual(p.garage.last?.model, .bruiser)
        XCTAssertEqual(p.selectedModel, .bruiser)
        XCTAssertEqual(p.credits, 100_000 - 7_500)
    }

    func testRepAndCreditLocks() {
        var p = PlayerProgress()
        p.credits = 50_000
        XCTAssertEqual(CarLineup.check(.razor, progress: p), .needsRep(4))
        p.reputationXP = 1_000_000
        p.credits = 100
        XCTAssertEqual(CarLineup.check(.kestrel, progress: p), .notEnoughCredits(needed: 5_400))
    }

    func testExclusivesAreOnePerPlayer() {
        var p = rich()
        XCTAssertNil(CarLineup.acquire(.razorNoir, progress: &p))
        XCTAssertEqual(CarLineup.check(.razorNoir, progress: p), .alreadyOwned)
    }

    func testLegendsAreWonWithGolds() {
        var p = rich()
        XCTAssertEqual(CarLineup.check(.stormhawk, progress: p), .needsGolds(1))
        p.challenge.golds = 3
        XCTAssertEqual(CarLineup.unclaimedLegends(p), [.stormhawk, .seabreeze])
        let before = p.credits
        XCTAssertNil(CarLineup.acquire(.seabreeze, progress: &p))
        XCTAssertEqual(p.credits, before, "legends are free")
        XCTAssertEqual(CarLineup.check(.ombra, progress: p), .needsGolds(2))
    }

    func testGarageSlotsStillLimit() {
        var p = rich()
        for _ in 0..<5 { _ = CarLineup.acquire(.kestrel, progress: &p) }
        XCTAssertEqual(p.garage.count, GarageRules.slots)
        XCTAssertEqual(CarLineup.check(.bruiser, progress: p), .garageFull)
    }

    func testRims() {
        var p = rich()
        XCTAssertNil(RimShop.fit(RimSetup(style: .deepDish, color: 3), slot: 0, progress: &p))
        XCTAssertEqual(p.garage[0].rims, RimSetup(style: .deepDish, color: 3))
        XCTAssertEqual(p.credits, 100_000 - 1_200 - 250)
        // Repainting only the colour costs the colour.
        XCTAssertEqual(RimShop.cost(from: p.garage[0].rims!, to: RimSetup(style: .deepDish, color: 1)), 250)
    }

    func testSavesKeepRimsAndWear() throws {
        var car = OwnedVehicle(model: .razor)
        car.rims = RimSetup(style: .turbofan, color: 5)
        var w = CarWear()
        w.add(driven: 50_000, knocks: 3)
        car.wear = w
        let back = try JSONDecoder().decode(OwnedVehicle.self, from: JSONEncoder().encode(car))
        XCTAssertEqual(back, car)
        // Old saves without the new fields still load.
        let old = try JSONDecoder().decode(OwnedVehicle.self, from: Data(#"{"model":"vesper"}"#.utf8))
        XCTAssertNil(old.rims)
        XCTAssertNil(old.wear)
    }
}

final class MechanicTests: XCTestCase {
    func testDrivingWearsPartsAndSlowsTheCar() {
        var w = CarWear()
        w.add(driven: 12_800 * 10, knocks: 4)   // 10 km, four knocks
        XCTAssertGreaterThan(w.wear(.oil), 0.5)
        XCTAssertGreaterThan(w.wear(.body), 0.1)
        let spec = w.apply(to: VehicleID.vesper.spec)
        XCTAssertLessThan(spec.brakeForce, VehicleID.vesper.spec.brakeForce)
        XCTAssertLessThan(spec.acceleration, VehicleID.vesper.spec.acceleration)
    }

    func testReportPutsTheWorstFirstAndFixingClearsIt() {
        var p = PlayerProgress()
        p.credits = 10_000
        var w = CarWear()
        w.add(driven: 12_800 * 12, knocks: 0)
        p.garage[0].wear = w
        let report = Mechanic.report(p.garage[0])
        XCTAssertEqual(report.first?.part, .oil)
        XCTAssertTrue(Mechanic.greeting(p.garage[0]).contains("oil"))
        let paid = Mechanic.fix(.oil, slot: 0, progress: &p)
        XCTAssertNotNil(paid)
        XCTAssertEqual(p.garage[0].wear?.wear(.oil) ?? 0, 0)
        XCTAssertEqual(p.credits, 10_000 - paid!)
    }

    func testRecommendsShopsForWhatTheCarNeeds() {
        var car = OwnedVehicle(model: .bruiser)
        var w = CarWear()
        w.add(driven: 0, knocks: 10)
        car.wear = w
        let tips = Mechanic.recommendations(car)
        XCTAssertEqual(tips.first?.kind, .collision)
        XCTAssertTrue(tips.contains { $0.kind == .paint })
    }

    func testDexAnswersAboutParts() {
        let car = OwnedVehicle(model: .vesper)
        XCTAssertTrue(Mechanic.answer("How do brakes work?", car: car).contains("pads"))
        XCTAssertTrue(Mechanic.answer("Where should I get it painted?", car: car).contains("Chrome & Candy"))
        XCTAssertTrue(Mechanic.answer("What's the weather tomorrow?", car: car).contains("only know cars"))
    }
}
