import Foundation

/// Advances a mission one step. Pure: give it the car's position, get the next state back.
public enum MissionRunner {
    public enum Event: Sendable, Equatable {
        case objectiveComplete(index: Int)
        case collected(ZoneID)
        case finished(MissionOutcome)
    }

    public static func step(_ state: MissionRunState, def: MissionDef, district: District,
                            carPosition: Vec2, heatStars: Int = 0, dt: Double) -> (MissionRunState, [Event]) {
        guard !state.isFinished else { return (state, []) }
        var s = state
        var events: [Event] = []
        let clocked = def.isClocked(objectiveIndex: s.objectiveIndex)
        s.elapsed += dt
        if clocked { s.clockElapsed += dt }

        if s.objectiveIndex < def.objectives.count {
            let objective = def.objectives[s.objectiveIndex]
            var done = false
            switch objective {
            case .reach(let id), .returnTo(let id):
                done = district.zones[id]?.rect.contains(carPosition) ?? false
            case .reachCalm(let id):
                done = heatStars == 0 && (district.zones[id]?.rect.contains(carPosition) ?? false)
            case .collect(let ids):
                for id in ids where !s.collected.contains(id) {
                    if district.zones[id]?.rect.contains(carPosition) ?? false {
                        s.collected.insert(id)
                        events.append(.collected(id))
                    }
                }
                done = ids.allSatisfy { s.collected.contains($0) }
            }
            if done {
                events.append(.objectiveComplete(index: s.objectiveIndex))
                s.objectiveIndex += 1
            }
        }

        if s.objectiveIndex >= def.objectives.count {
            s.outcome = .success
            events.append(.finished(.success))
        } else if clocked, let limit = def.timeLimit, s.clockElapsed >= limit,
                  def.isClocked(objectiveIndex: s.objectiveIndex) {
            // Time up only if the objective that was on the clock didn't finish this step.
            s.elapsed -= s.clockElapsed - limit
            s.clockElapsed = limit
            s.outcome = .timeUp
            events.append(.finished(.timeUp))
        }
        return (s, events)
    }

    /// Ends a run early (pause → quit, bust, wreck). Does nothing if already finished.
    public static func end(_ state: MissionRunState, with outcome: MissionOutcome) -> MissionRunState {
        guard !state.isFinished else { return state }
        var s = state
        s.outcome = outcome
        return s
    }

    /// Seconds left, or nil for untimed jobs and once the clocked part is done.
    public static func timeRemaining(_ state: MissionRunState, def: MissionDef) -> Double? {
        guard def.isClocked(objectiveIndex: state.objectiveIndex) || (state.outcome == .timeUp) else { return nil }
        return def.timeLimit.map { max(0, $0 - state.clockElapsed) }
    }

    /// True when the player is in the target zone of a calm-only objective but still has heat.
    public static func isWaitingForCalm(_ state: MissionRunState, def: MissionDef, district: District,
                                        carPosition: Vec2, heatStars: Int) -> Bool {
        guard heatStars > 0, state.objectiveIndex < def.objectives.count,
              case .reachCalm(let id) = def.objectives[state.objectiveIndex] else { return false }
        return district.zones[id]?.rect.contains(carPosition) ?? false
    }

    /// Zones the HUD should point at now: the current objective's unfinished zones.
    public static func activeZones(_ state: MissionRunState, def: MissionDef) -> [ZoneID] {
        guard state.objectiveIndex < def.objectives.count else { return [] }
        return def.objectives[state.objectiveIndex].zones.filter { !state.collected.contains($0) }
    }
}
