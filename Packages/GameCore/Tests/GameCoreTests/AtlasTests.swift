import XCTest
@testable import GameCore

final class AtlasTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func richPlayer() -> PlayerProgress {
        var p = PlayerProgress()
        p.credits = 9_000
        p.reputationXP = 100_000
        var truck = OwnedProperty(kind: .tacoTruck, lastCollected: now.addingTimeInterval(-20 * 3_600), invested: 1_500)
        truck.level = 1
        p.properties = [truck]
        return p
    }

    func testFactIDsAreUniqueAndTextIsFilledIn() {
        let facts = AtlasKnowledge.all
        XCTAssertEqual(Set(facts.map(\.id)).count, facts.count)
        for f in facts {
            XCTAssertFalse(f.text.isEmpty, f.id)
            XCTAssertFalse(f.keywords.isEmpty, f.id)
            XCTAssertEqual(f.keywords, f.keywords.map { $0.lowercased() }, f.id)
        }
    }

    func testRelevantFindsFreightForTruckQuestions() {
        XCTAssertEqual(Atlas.relevant(to: "How do I drive the big diesel truck?").first?.id, "rule.freight")
        XCTAssertEqual(Atlas.relevant(to: "What does the bank pay in interest?").first?.id, "rule.bank")
    }

    func testBusinessAnswerUsesTheTill() {
        let reply = Atlas.answer("How is my business doing?", progress: richPlayer(), now: now)
        XCTAssertTrue(reply.contains("1 business"), reply)
        XCTAssertTrue(reply.contains("Taco truck"), reply)   // its till is full after 20 hours
    }

    func testWhereAmIHeadedUsesTheContext() {
        let ctx = AtlasContext(activity: "Freight haul: Solar panels to Cinder Flats", target: "12.4 km E", place: "Solara State")
        let reply = Atlas.answer("Where am I headed?", progress: PlayerProgress(), context: ctx, now: now)
        XCTAssertTrue(reply.contains("Cinder Flats") && reply.contains("12.4 km E"), reply)
    }

    func testOffTopicIsDeclined() {
        let reply = Atlas.answer("What's the weather in Chicago tomorrow?", progress: PlayerProgress(), now: now)
        XCTAssertTrue(reply.contains("only help with Neon Getaway"), reply)
    }

    func testNextStepCollectsFullTillsFirst() {
        let reply = Atlas.answer("What should I do next?", progress: richPlayer(), now: now)
        XCTAssertTrue(reply.contains("Collect"), reply)
    }

    func testPromptCarriesFactsAndState() {
        let prompt = Atlas.prompt("How do freight hauls work?", progress: richPlayer(), context: nil, now: now)
        XCTAssertTrue(prompt.contains("Freight hauls:"))
        XCTAssertTrue(prompt.contains("Cash: 9000 cr"))
        XCTAssertTrue(prompt.hasSuffix("QUESTION: How do freight hauls work?"))
    }

    func testDashboardSummary() {
        let s = DashboardSummary(richPlayer(), now: now)
        XCTAssertEqual(s.businesses.count, 1)
        XCTAssertTrue(s.businesses[0].tillFull)
        XCTAssertEqual(s.businesses[0].tillFill, 1)
        XCTAssertGreaterThan(s.tillsWaiting, 0)
        XCTAssertEqual(s.nextBusiness, .carWash)
        XCTAssertEqual(s.netWorth, NetWorth.total(richPlayer()))
    }
}
