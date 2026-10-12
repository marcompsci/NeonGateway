import Foundation

/// A small 2D vector in scene points. Kept here so GameCore never imports CoreGraphics or SpriteKit.
public struct Vec2: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public var length: Double { (x * x + y * y).squareRoot() }

    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }

    /// Unit vector pointing along `angle` (radians, 0 = +x, counter-clockwise).
    public static func unit(_ angle: Double) -> Vec2 { Vec2(cos(angle), sin(angle)) }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
}

/// An axis-aligned rectangle in scene points (origin = lower-left, like SpriteKit).
public struct Rect: Codable, Sendable, Equatable, Hashable {
    public var minX: Double
    public var minY: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.minX = x
        self.minY = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { minX + width }
    public var maxY: Double { minY + height }
    public var center: Vec2 { Vec2(minX + width / 2, minY + height / 2) }

    public func contains(_ p: Vec2) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }
}
