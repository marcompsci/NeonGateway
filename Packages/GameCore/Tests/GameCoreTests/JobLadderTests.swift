import XCTest
@testable import GameCore

/// The reputation ladder: three starter jobs, then one harder job per level, ending in a
/// delivery that turns into an escape.
final class JobLadderTests: XCTestCase {
    let district = District.portAuroraDocks
    let dt = VehicleDynamics.fixedStep

    // MARK: Structure

    func testStartersAreOpenAndEachLevelAddsOneJob() {
        let starters = MissionDef.all.filter { $0.requiredRepLevel == 0 }
        XCTAssertEqual(Set(starters.map(\.kind)), [.timedDelivery, .escape, .pickupRun])
        for level in 1...4 {
            XCTAssertEqual(ProgressionRules.jobsUnlocked(atLevel: level).count, 1, "rep \(level)")
        }
        XCTAssertEqual(ProgressionRules.jobsUnlocked(atLevel: 4).first?.id, .doubleCross)
        // Every level a player can reach before the top has something new on the map.
        XCTAssertGreaterThanOrEqual(ProgressionRules.levelThresholds.count, 5)
    }

    func testUnlocksFollowReputation() {
        var p = PlayerProgress()
        XCTAssertFalse(ProgressionRules.isUnlocked(.deepFreeze, progress: p))
        p.reputationXP = ProgressionRules.levelThresholds[1]
        XCTAssertTrue(ProgressionRules.isUnlocked(.deepFreeze, progress: p))
        XCTAssertFalse(ProgressionRules.isUnlocked(.ghostTide, progress: p))
        p.reputationXP = ProgressionRules.levelThresholds[4]
        XCTAssertTrue(MissionDef.all.allSatisfy { ProgressionRules.isUnlocked($0, progress: p) })
    }

    func testLevelUpReportsTheJobsItOpened() {
        var p = PlayerProgress()
        p.reputationXP = ProgressionRules.levelThresholds[1] - 10
        let win = MissionResult(missionID: .coldCrate, kind: .timedDelivery, outcome: .success,
                                elapsed: 20, timeLimit: 35, hits: 0, driftScore: 0)
        let update = ProgressionRules.apply(win, def: .coldCrate, to: &p)
        XCTAssertEqual(update.leveledUpTo, 1)
        XCTAssertEqual(update.unlockedJobs, [.deepFreeze])
        // Skipping a level (a big payout just under a threshold) opens both levels' jobs.
        var q = PlayerProgress()
        q.reputationXP = ProgressionRules.levelThresholds[1] - 1
        let big = MissionResult(missionID: .doubleCross, kind: .double, outcome: .success,
                                elapsed: 60, timeLimit: 20, hits: 0, driftScore: 0, clockElapsed: 10)
        let jump = ProgressionRules.apply(big, def: .doubleCross, to: &q)
        XCTAssertEqual(jump.leveledUpTo, 2)
        XCTAssertEqual(jump.unlockedJobs, [.deepFreeze, .ghostTide])
        // No level-up, nothing new.
        XCTAssertEqual(ProgressionRules.apply(win, def: .coldCrate, to: &p).unlockedJobs, [])
    }

    func testHarderJobsPayAndTeachMore() {
        let pairs: [(MissionDef, MissionDef)] = [(.coldCrate, .deepFreeze), (.tideLineRun, .ghostTide),
                                                 (.lanternSweep, .lanternFestival)]
        for (easy, hard) in pairs {
            XCTAssertEqual(easy.kind, hard.kind)
            XCTAssertGreaterThan(hard.requiredRepLevel, easy.requiredRepLevel)
            XCTAssertGreaterThan(hard.baseReward, easy.baseReward, hard.title)
            XCTAssertGreaterThan(hard.baseRepXP, easy.baseRepXP, hard.title)
        }
        let top = MissionDef.all.map(\.baseReward).max()
        XCTAssertEqual(MissionDef.doubleCross.baseReward, top)
    }

    func testHarderVariantsAreActuallyHarder() {
        // Deep Freeze: a tighter clock than Cold Crate, and it starts with a star of heat.
        XCTAssertLessThan(MissionDef.deepFreeze.timeLimit!, MissionDef.coldCrate.timeLimit!)
        XCTAssertEqual(HeatRules.stars(for: MissionDef.deepFreeze.startingHeat), 1)
        // Ghost Tide starts a star hotter than Tide Line Run.
        XCTAssertGreaterThan(HeatRules.stars(for: MissionDef.ghostTide.startingHeat),
                             HeatRules.stars(for: MissionDef.tideLineRun.startingHeat))
        // Lantern Festival: more lanterns, each hotter.
        XCTAssertGreaterThan(MissionDef.lanternFestival.objectives[0].zones.count,
                             MissionDef.lanternSweep.objectives[0].zones.count)
        XCTAssertGreaterThan(MissionDef.lanternFestival.pickupHeat, MissionDef.lanternSweep.pickupHeat)
    }

    func testNoTwoJobsShareAStartSpot() {
        let starts = MissionDef.all.map { district.coord(at: $0.start.position) }
        XCTAssertEqual(Set(starts).count, starts.count, "map pins would sit on top of each other")
    }

    // MARK: The double

    func testDoubleCrossIsATimedDropThenAnUntimedEscape() {
        let def = MissionDef.doubleCross
        XCTAssertEqual(def.clockedObjectives, 1)
        XCTAssertTrue(def.isClocked(objectiveIndex: 0))
        XCTAssertFalse(def.isClocked(objectiveIndex: 1))
        XCTAssertEqual(def.alarm?.afterObjective, 0)
        guard case .reachCalm = def.objectives[1] else { return XCTFail("the second half is an escape") }
        XCTAssertTrue(def.kind.endsInEscape)
        // The alarm is enough to bring three stars on its own.
        XCTAssertGreaterThanOrEqual(HeatRules.stars(for: def.alarm!.heat), 3)
    }

    func testClockStopsAfterTheDropAndTheEscapeHasNoTimeLimit() {
        let def = MissionDef.doubleCross
        let drop = district.zones[.pier9]!.rect.center
        let away = def.start.position
        var s = MissionRunState()
        var events: [MissionRunner.Event]
        (s, _) = MissionRunner.step(s, def: def, district: district, carPosition: away, dt: 5)
        XCTAssertEqual(MissionRunner.timeRemaining(s, def: def), def.timeLimit! - 5)
        (s, events) = MissionRunner.step(s, def: def, district: district, carPosition: drop, dt: 1)
        XCTAssertEqual(events, [.objectiveComplete(index: 0)])
        XCTAssertEqual(s.clockElapsed, 6)
        XCTAssertNil(MissionRunner.timeRemaining(s, def: def), "no clock on the getaway")
        // Long after the limit, the escape is still on.
        for _ in 0..<120 {
            (s, _) = MissionRunner.step(s, def: def, district: district, carPosition: away, heatStars: 3, dt: 1)
        }
        XCTAssertNil(s.outcome)
        XCTAssertEqual(s.clockElapsed, 6)
        XCTAssertEqual(s.elapsed, 126)
        // Reaching the lane with heat doesn't count; without it, it does.
        let lane = district.zones[.marketLane]!.rect.center
        (s, _) = MissionRunner.step(s, def: def, district: district, carPosition: lane, heatStars: 1, dt: 1)
        XCTAssertNil(s.outcome)
        (s, _) = MissionRunner.step(s, def: def, district: district, carPosition: lane, heatStars: 0, dt: 1)
        XCTAssertEqual(s.outcome, .success)
    }

    func testMissingTheDropClockIsTimeUp() {
        let def = MissionDef.doubleCross
        var s = MissionRunState()
        for _ in 0..<40 where !s.isFinished {
            (s, _) = MissionRunner.step(s, def: def, district: district, carPosition: def.start.position, dt: 1)
        }
        XCTAssertEqual(s.outcome, .timeUp)
        XCTAssertEqual(s.clockElapsed, def.timeLimit!)
        XCTAssertEqual(s.elapsed, def.timeLimit!)
    }

    func testDoubleTimeBonusUsesOnlyTheClockedPart() {
        let def = MissionDef.doubleCross
        let quickDrop = MissionResult(missionID: def.id, kind: def.kind, outcome: .success, elapsed: 90,
                                      timeLimit: def.timeLimit, hits: 0, driftScore: 0, clockElapsed: 8)
        let p = RewardCalculator.payout(for: quickDrop, def: def)
        XCTAssertEqual(p.timeBonus, Int((Double(def.baseReward) * RewardCalculator.maxTimeBonusShare).rounded()),
                       "an 8 s drop on a 20 s clock earns the full bonus, however long the getaway took")
    }

    func testDoubleCountsTowardTheEscapeStreak() {
        let def = MissionDef.doubleCross
        var progress = PlayerProgress()
        let win = MissionResult(missionID: def.id, kind: def.kind, outcome: .success, elapsed: 60,
                                timeLimit: def.timeLimit, hits: 0, driftScore: 0, clockElapsed: 10)
        _ = ProgressionRules.apply(win, def: def, to: &progress)
        XCTAssertEqual(progress.currentEscapeStreak, 1)
        var lose = win
        lose.outcome = .busted
        _ = ProgressionRules.apply(lose, def: def, to: &progress)
        XCTAssertEqual(progress.currentEscapeStreak, 0)
        XCTAssertEqual(progress.bestEscapeStreak, 1)
    }

    // MARK: Alarm

    func testAlarmBringsHeatDispatchAndNearbyUnits() {
        let spot = district.zones[.pier9]!.rect.center
        var player = VehicleState(position: spot)
        var pursuit = Pursuit(district: district, player: player, seed: 3)
        XCTAssertEqual(pursuit.heat.stars, 0)
        let events = pursuit.raiseAlarm(heat: MissionDef.doubleCross.alarm!.heat, at: spot)
        XCTAssertEqual(events, [.starsChanged(from: 0, to: pursuit.heat.stars)])
        XCTAssertGreaterThanOrEqual(pursuit.heat.stars, 3)
        XCTAssertEqual(pursuit.dispatchTime, Pursuit.hotStartDispatch)
        XCTAssertEqual(pursuit.patrols.count, pursuit.desiredPatrols)
        XCTAssertTrue(pursuit.patrols.allSatisfy { $0.mode != .cruise && $0.lastSeen == spot })
        // During the radio fix every unit chases the live position and the heat holds.
        let points = pursuit.heat.points
        for _ in 0..<(60 * 2) { _ = pursuit.step(player: &player, dt: dt) }
        XCTAssertTrue(pursuit.patrols.allSatisfy { $0.mode == .chase })
        XCTAssertGreaterThanOrEqual(pursuit.heat.points, points)
    }

    // MARK: Fairness of the clocks

    /// The hotter starts can't be won by a quick dash: the fastest possible cool-down from
    /// Ghost Tide's start takes longer than Tide Line Run's.
    func testGhostTideCoolsSlowerThanTideLineRun() {
        func coolDown(_ points: Double) -> Double {
            var heat = HeatState(points: points)
            var t = 0.0
            while heat.stars > 0 {
                heat = HeatSystem.step(heat, dt: dt, seen: t < Pursuit.hotStartDispatch,
                                       inRestricted: false, inSafehouse: false)
                t += dt
            }
            return t
        }
        XCTAssertGreaterThan(coolDown(MissionDef.ghostTide.startingHeat),
                             coolDown(MissionDef.tideLineRun.startingHeat) + 2)
    }
}
