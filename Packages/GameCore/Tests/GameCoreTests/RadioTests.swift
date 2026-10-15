import XCTest
@testable import GameCore

final class RadioTests: XCTestCase {
    func testStationHasTheSevenSongsWithCredits() {
        let t = AuroraFM.tracks
        XCTAssertEqual(t.count, 7)
        XCTAssertEqual(Set(t.map(\.id)).count, 7)
        XCTAssertEqual(t.first { $0.id == "sevenSixers" }?.credit, "Veeze feat. Babyface Ray")
        XCTAssertEqual(t.first { $0.id == "freeJoeExotic" }?.credit, "Bfb Da Packman feat. Sada Baby")
        XCTAssertEqual(t.first { $0.id == "treehouse" }?.credit, "3200 Tre")
        XCTAssertTrue(t.allSatisfy(\.explicit))
    }

    func testCatalogMatchingIsForgivingButChecksTheArtist() {
        let seven = AuroraFM.tracks.first { $0.id == "sevenSixers" }!
        XCTAssertTrue(AuroraFM.matches(seven, title: "7sixers (feat. Babyface Ray)", artist: "Veeze"))
        XCTAssertTrue(AuroraFM.matches(seven, title: "7Sixers", artist: "Veeze & Babyface Ray"))
        XCTAssertFalse(AuroraFM.matches(seven, title: "7sixers", artist: "Somebody Else"))
        let lmao = AuroraFM.tracks.first { $0.id == "lmao" }!
        XCTAssertTrue(AuroraFM.matches(lmao, title: "Lmaoooo", artist: "Fox BD"))
        XCTAssertTrue(AuroraFM.matches(lmao, title: "LMAOOOOOOOOO", artist: "Fox Bd"))
        XCTAssertFalse(AuroraFM.matches(lmao, title: "Different Song", artist: "Fox BD"))
        let tree = AuroraFM.tracks.first { $0.id == "treehouse" }!
        XCTAssertTrue(AuroraFM.matches(tree, title: "Treehouse", artist: "3200 Tre"))
        XCTAssertFalse(AuroraFM.matches(tree, title: "Treehouse", artist: "Tre"))
    }

    func testEveryLoopPlaysEverySongOnce() {
        var q = RadioQueue(count: 7, seed: 42)
        for _ in 0..<5 {
            var heard: [Int] = [q.current!]
            for _ in 0..<6 { heard.append(q.next()!) }
            XCTAssertEqual(Set(heard), Set(0..<7))
            q.next()
        }
        XCTAssertEqual(q.loop, 5)
    }

    func testEachLoopIsANewOrderAndNeverRepeatsTheLastSong() {
        var q = RadioQueue(count: 7, seed: 9)
        var orders: [[Int]] = []
        for _ in 0..<20 {
            let order = q.order
            orders.append(order)
            for _ in 0..<6 { q.next() }
            let last = q.current
            q.next()
            XCTAssertNotEqual(q.order, order, "a fresh shuffle each loop")
            XCTAssertNotEqual(q.current, last, "no song twice in a row across the reshuffle")
        }
        XCTAssertGreaterThan(Set(orders.map { $0.description }).count, 15, "orders vary loop to loop")
    }

    func testDifferentSeedsGiveDifferentFirstLoops() {
        let a = RadioQueue(count: 7, seed: 1).order
        let b = RadioQueue(count: 7, seed: 2).order
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, Array(0..<7), "actually shuffled")
    }

    func testPickingASongPlaysItNowWithoutRepeatsThisLoop() {
        var q = RadioQueue(count: 7, seed: 5)
        let later = q.order[4]
        q.play(later)
        XCTAssertEqual(q.current, later)
        var heard = Array(q.order[0...q.position])
        while q.position < q.count - 1 { heard.append(q.next()!) }
        XCTAssertEqual(heard.count, 7)
        XCTAssertEqual(Set(heard), Set(0..<7), "nothing skipped, nothing doubled")
    }

    func testPreviousGoesBack() {
        var q = RadioQueue(count: 7, seed: 3)
        let first = q.current
        q.next()
        XCTAssertEqual(q.previous(), first)
        XCTAssertEqual(q.previous(), first, "stays on the first song")
    }

    func testRadioSettingDefaultsOnAndOldSettingsLoad() throws {
        XCTAssertTrue(GameSettings().radioOn)
        let old = try JSONDecoder().decode(GameSettings.self, from: Data(#"{"soundOn":true}"#.utf8))
        XCTAssertTrue(old.radioOn)
        var s = GameSettings()
        s.radioOn = false
        XCTAssertFalse(try JSONDecoder().decode(GameSettings.self, from: JSONEncoder().encode(s)).radioOn)
    }
}
