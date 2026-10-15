import Foundation

/// A bare-handed hit: left hook, right hook or a straight punch (jab).
public enum Strike: String, Sendable, CaseIterable {
    case left, right, jab

    public var label: String {
        switch self {
        case .left: "Left hook"
        case .right: "Right hook"
        case .jab: "Punch"
        }
    }
}

/// Fist-fight rules (cartoon: people get knocked down, never hurt).
public enum FistRules {
    /// Reach in points and how wide the hit sweeps either side of its centre line.
    public static func reach(_ s: Strike) -> Double { s == .jab ? 56 : 48 }
    public static func halfArc(_ s: Strike) -> Double { s == .jab ? .pi / 7 : .pi / 4 }
    /// Hooks swing round from the side they're thrown with (left is anticlockwise).
    public static func offset(_ s: Strike) -> Double {
        switch s {
        case .left: .pi / 6
        case .right: -.pi / 6
        case .jab: 0
        }
    }
    /// Seconds before the next strike.
    public static func recovery(_ s: Strike) -> Double { s == .jab ? 0.22 : 0.36 }
    /// Daze points per hit; a person goes down at `knockdown`.
    public static func power(_ s: Strike) -> Double { s == .jab ? 1.2 : 1.75 }
    public static let knockdown = 3.0
    /// Daze wears off at this many points a second.
    public static let recoverPerSecond = 0.4
    /// Throwing hands where someone can see it.
    public static let assaultHeat = 4.0
}

extension City {
    /// Throws a punch on foot. Hits the nearest person, officer or player in the arc in front.
    mutating func strike(_ s: Strike) -> [CityEvent] {
        guard isOnFoot, punchCooldown <= 0 else { return [] }
        punchCooldown = FistRules.recovery(s)
        let origin = foot.position
        let centre = foot.heading + FistRules.offset(s)
        let reach = FistRules.reach(s) + FootDynamics.radius
        let arc = FistRules.halfArc(s)
        func inArc(_ p: Vec2) -> Double? {
            let d = p - origin
            let dist = d.length
            guard dist <= reach, dist > 0.5 else { return nil }
            guard abs(remainder(atan2(d.y, d.x) - centre, 2 * .pi)) <= arc else { return nil }
            return dist
        }
        enum Hit { case person(Int), officer(Int), remote(String) }
        var best: (Hit, Vec2, Double)?
        func consider(_ h: Hit, _ p: Vec2) {
            if let d = inArc(p), best == nil || d < best!.2 { best = (h, p, d) }
        }
        for (k, person) in crowd.people.enumerated() where !person.isDown { consider(.person(k), person.position) }
        for o in officers where !o.isDown { consider(.officer(o.id), o.position) }
        for r in remotes where r.isOnFoot && !r.isDown { consider(.remote(r.id), r.position) }

        guard let (hit, point, _) = best else { return [.punch(s, hit: false)] }
        stats.hitsLanded += 1
        var events: [CityEvent] = [.punch(s, hit: true)]
        switch hit {
        case .person(let k):
            let id = crowd.people[k].id
            let first = daze[id] == nil
            daze[id, default: 0] += FistRules.power(s)
            // Knocked back a step.
            let push = (point - origin) * (10 / max(1, (point - origin).length))
            crowd.people[k].position += push
            if daze[id]! >= FistRules.knockdown {
                daze[id] = nil
                crowd.scare(from: point, radius: 220)
                events += knockDownPerson(k)
            } else {
                crowd.scare(from: point, radius: 140)
                if first { events += crime(heat: FistRules.assaultHeat, at: point, victim: id) }
            }
        case .officer(let id):
            events += hitOfficer(id, damage: 1, from: origin)
        case .remote(let id):
            events.append(.hitPlayer(id, damage: 1, weapon: nil))
        }
        return events
    }

    /// Daze wears off.
    mutating func recoverDaze(dt: Double) {
        guard !daze.isEmpty else { return }
        for (id, v) in daze {
            let left = v - FistRules.recoverPerSecond * dt
            daze[id] = left > 0 ? left : nil
        }
    }
}
