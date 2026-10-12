import Foundation

/// Circle-vs-rectangle contact for the car against walls and blocks.
public enum Collision {
    public struct Result: Sendable, Equatable {
        public var state: VehicleState
        /// Speed lost into the wall this step (points/s). 0 = no contact.
        public var impactSpeed: Double
        public var hit: Bool { impactSpeed > 0 }
    }

    /// Pushes the car out of every overlapping rect and reflects the velocity part that went
    /// into the wall, scaled by `restitution` (0 = stop dead, 1 = perfect bounce).
    public static func resolve(_ state: VehicleState, radius: Double, solids: [Rect],
                               restitution: Double = 0.35) -> Result {
        var s = state
        var impact: Double = 0
        for rect in solids {
            let closest = Vec2(min(max(s.position.x, rect.minX), rect.maxX),
                               min(max(s.position.y, rect.minY), rect.maxY))
            var delta = s.position - closest
            let distance = delta.length
            guard distance < radius else { continue }

            if distance == 0 {
                // Centre is inside the rect: push out along the shortest side.
                let pushes: [(Double, Vec2)] = [
                    (s.position.x - rect.minX, Vec2(-1, 0)),
                    (rect.maxX - s.position.x, Vec2(1, 0)),
                    (s.position.y - rect.minY, Vec2(0, -1)),
                    (rect.maxY - s.position.y, Vec2(0, 1))
                ]
                let best = pushes.min { $0.0 < $1.0 }!
                delta = best.1
                s.position = s.position + best.1 * (best.0 + radius)
            } else {
                delta = delta * (1 / distance)
                s.position = closest + delta * radius
            }

            let into = s.velocity.dot(delta)
            if into < 0 {
                s.velocity = s.velocity - delta * (into * (1 + restitution))
                impact = max(impact, -into)
            }
        }
        return Result(state: s, impactSpeed: impact)
    }

    /// Pushes two cars apart if they overlap and trades the speed along the line between them.
    /// Returns the closing speed at contact (0 = they weren't touching or were moving apart).
    @discardableResult
    public static func separate(_ a: inout VehicleState, _ b: inout VehicleState, radius: Double) -> Double {
        var delta = a.position - b.position
        var distance = delta.length
        let minDistance = radius * 2
        guard distance < minDistance else { return 0 }
        if distance < 0.001 {
            delta = Vec2(1, 0)
            distance = 0.001
        }
        let normal = delta * (1 / distance)
        let push = (minDistance - distance) / 2
        a.position = a.position + normal * push
        b.position = b.position - normal * push
        let closing = (b.velocity - a.velocity).dot(normal)
        guard closing > 0 else { return 0 }
        // Equal-mass bump with a little energy lost.
        let impulse = closing * 0.8
        a.velocity = a.velocity + normal * impulse
        b.velocity = b.velocity - normal * impulse
        return closing
    }

    /// The four walls around a rectangular arena, `thickness` points thick, outside `bounds`.
    public static func walls(around bounds: Rect, thickness: Double = 200) -> [Rect] {
        [
            Rect(x: bounds.minX - thickness, y: bounds.minY - thickness,
                 width: bounds.width + 2 * thickness, height: thickness),
            Rect(x: bounds.minX - thickness, y: bounds.maxY,
                 width: bounds.width + 2 * thickness, height: thickness),
            Rect(x: bounds.minX - thickness, y: bounds.minY, width: thickness, height: bounds.height),
            Rect(x: bounds.maxX, y: bounds.minY, width: thickness, height: bounds.height)
        ]
    }
}
