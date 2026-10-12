import XCTest
@testable import GameCore

final class SaveCodecTests: XCTestCase {
    func testProgressRoundTrips() {
        var p = PlayerProgress()
        p.credits = 1250
        p.reputationXP = 340
        p.upgrades.handling = 2
        p.lastUpdated = Date(timeIntervalSince1970: 1_800_000_000)
        let loaded = SaveCodec.loadProgress(from: SaveCodec.encode(p))
        XCTAssertEqual(loaded, p)
    }

    func testDamagedBlobFallsBackToFreshSave() {
        let loaded = SaveCodec.loadProgress(from: Data("{not json".utf8))
        XCTAssertEqual(loaded, PlayerProgress())
    }

    func testMissingBlobIsFreshSave() {
        XCTAssertEqual(SaveCodec.loadProgress(from: nil), PlayerProgress())
    }

    func testNewerSchemaIsIgnored() {
        var p = PlayerProgress()
        p.schemaVersion = PlayerProgress.currentSchema + 1
        p.credits = 99
        XCTAssertEqual(SaveCodec.loadProgress(from: SaveCodec.encode(p)), PlayerProgress())
    }

    func testPhase2SaveWithoutMissionBestsStillLoads() {
        let old = """
        {"schemaVersion":1,"credits":420,"reputationXP":15,"completedJobs":2,"bestEscapeStreak":0,
         "currentEscapeStreak":0,"upgrades":{"speed":1,"handling":0,"durability":0},
         "lastUpdated":"2026-10-09T12:00:00Z"}
        """
        let loaded = SaveCodec.loadProgress(from: Data(old.utf8))
        XCTAssertEqual(loaded.credits, 420)
        XCTAssertEqual(loaded.upgrades.speed, 1)
        XCTAssertEqual(loaded.missionBests, [:])
    }

    func testMissionBestsRoundTrip() {
        var p = PlayerProgress()
        p.missionBests["coldCrate"] = MissionBest(bestScore: 1300, bestTime: 18.4, timesCompleted: 3)
        XCTAssertEqual(SaveCodec.loadProgress(from: SaveCodec.encode(p)), p)
    }

    func testSettingsRoundTripAndDefaults() {
        var s = GameSettings()
        s.crtOn = true
        s.hapticsOn = false
        XCTAssertEqual(SaveCodec.loadSettings(from: SaveCodec.encode(s)), s)
        XCTAssertEqual(SaveCodec.loadSettings(from: nil), GameSettings())
    }
}
