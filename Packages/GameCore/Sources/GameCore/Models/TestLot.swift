import Foundation

/// Phase 2's empty practice lot: a walled square with a few blocks to slide around.
/// Replaced by the Port Aurora Docks district in Phase 3.
public struct TestLot: Sendable, Equatable {
    public let bounds: Rect
    public let blocks: [Rect]
    public let spawn: Vec2

    /// 2048 × 2432 points = 16 × 19 ground tiles of 128 points. Blocks sit in a ring around the
    /// centre so there is room to slide around them.
    public static let standard = TestLot(
        bounds: Rect(x: 0, y: 0, width: 2048, height: 2432),
        blocks: [
            Rect(x: 400, y: 620, width: 260, height: 140),
            Rect(x: 1388, y: 620, width: 260, height: 140),
            Rect(x: 894, y: 1086, width: 260, height: 260),
            Rect(x: 400, y: 1672, width: 260, height: 140),
            Rect(x: 1388, y: 1672, width: 260, height: 140)
        ],
        spawn: Vec2(1024, 300)
    )

    public var solids: [Rect] { Collision.walls(around: bounds) + blocks }
}
