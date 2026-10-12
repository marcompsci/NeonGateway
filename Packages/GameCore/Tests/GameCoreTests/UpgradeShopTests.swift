import XCTest
@testable import GameCore

final class UpgradeShopTests: XCTestCase {
    func progress(credits: Int, xp: Int = 0) -> PlayerProgress {
        var p = PlayerProgress()
        p.credits = credits
        p.reputationXP = xp
        return p
    }

    func testFirstLevelCostsOneFiftyAndNeedsNoRep() {
        var p = progress(credits: 200)
        let result = UpgradeShop.buy(.speed, progress: &p)
        XCTAssertEqual(try result.get().level, 1)
        XCTAssertEqual(p.credits, 50)
        XCTAssertEqual(p.upgrades.speed, 1)
    }

    func testNotEnoughCreditsChangesNothing() {
        var p = progress(credits: 100)
        XCTAssertEqual(UpgradeShop.buy(.handling, progress: &p), .failure(.needsCredits(short: 50)))
        XCTAssertEqual(p, progress(credits: 100))
    }

    func testRepGateBlocksLevelTwoUntilRepLevelOne() {
        var p = progress(credits: 5000)
        _ = UpgradeShop.buy(.durability, progress: &p)
        XCTAssertEqual(UpgradeShop.buy(.durability, progress: &p), .failure(.needsRep(1)))
        p.reputationXP = 100
        XCTAssertEqual(try UpgradeShop.buy(.durability, progress: &p).get().level, 2)
        XCTAssertEqual(p.credits, 5000 - 150 - 400)
    }

    func testMaxLevelIsFour() {
        var p = progress(credits: 10_000, xp: 1500)
        for _ in 0..<4 { _ = UpgradeShop.buy(.speed, progress: &p) }
        XCTAssertEqual(p.upgrades.speed, 4)
        XCTAssertEqual(p.credits, 10_000 - (150 + 400 + 900 + 1800))
        XCTAssertEqual(UpgradeShop.buy(.speed, progress: &p), .failure(.maxed))
        XCTAssertNil(UpgradeShop.nextTier(.speed, levels: p.upgrades))
    }

    func testTracksAreIndependent() {
        var p = progress(credits: 1000)
        _ = UpgradeShop.buy(.speed, progress: &p)
        XCTAssertEqual(UpgradeShop.nextTier(.handling, levels: p.upgrades)?.cost, 150)
        XCTAssertEqual(UpgradeShop.nextTier(.speed, levels: p.upgrades)?.cost, 400)
    }

    func testUpgradeEffectsStackOnTheSpec() {
        let base = VehicleSpec.vesper
        var levels = UpgradeLevels()
        levels.speed = 2
        levels.handling = 3
        levels.durability = 4
        let s = UpgradeShop.spec(base, levels: levels)
        XCTAssertEqual(s.maxSpeed, base.maxSpeed * 1.16, accuracy: 0.001)
        XCTAssertEqual(s.acceleration, base.acceleration * 1.12, accuracy: 0.001)
        XCTAssertEqual(s.turnRate, base.turnRate * 1.3, accuracy: 0.001)
        XCTAssertLessThan(s.lateralRetention, base.lateralRetention)
        XCTAssertEqual(s.maxIntegrity, base.maxIntegrity + 4)
        XCTAssertEqual(UpgradeShop.spec(base, levels: UpgradeLevels()), base)
    }

    func testFasterCarActuallyGoesFaster() {
        var levels = UpgradeLevels()
        levels.speed = 4
        let fast = UpgradeShop.spec(.vesper, levels: levels)
        var a = VehicleState(), b = VehicleState()
        for _ in 0..<(60 * 5) {
            a = VehicleDynamics.step(a, input: VehicleInput(throttle: 1), spec: .vesper, dt: 1.0 / 60)
            b = VehicleDynamics.step(b, input: VehicleInput(throttle: 1), spec: fast, dt: 1.0 / 60)
        }
        XCTAssertGreaterThan(b.speed, a.speed * 1.25)
        XCTAssertGreaterThan(b.speed, VehicleSpec.harborPatrol.maxSpeed, "fully upgraded cars outrun patrols")
    }

    func testUpgradesSurviveASave() {
        var p = progress(credits: 500)
        _ = UpgradeShop.buy(.handling, progress: &p)
        XCTAssertEqual(SaveCodec.loadProgress(from: SaveCodec.encode(p)).upgrades.handling, 1)
    }
}
