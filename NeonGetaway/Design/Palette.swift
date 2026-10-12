import SwiftUI
import UIKit

/// Neon Getaway's five-colour palette plus two support shades. Every screen and generated
/// texture draws from here so the look stays consistent.
enum Palette {
    static let asphaltHex: UInt32 = 0x14161C
    static let asphaltLightHex: UInt32 = 0x262A33
    static let tealHex: UInt32 = 0x2EE6D6
    static let magentaHex: UInt32 = 0xFF3EA5
    static let sunsetHex: UInt32 = 0xFF8A3D
    static let creamHex: UInt32 = 0xF4EBD9
    static let inkHex: UInt32 = 0x0B0C10

    static let asphalt = Color(hex: asphaltHex)
    static let asphaltLight = Color(hex: asphaltLightHex)
    static let teal = Color(hex: tealHex)
    static let magenta = Color(hex: magentaHex)
    static let sunset = Color(hex: sunsetHex)
    static let cream = Color(hex: creamHex)
    static let ink = Color(hex: inkHex)

    enum UI {
        static let asphalt = UIColor(hex: asphaltHex)
        static let asphaltLight = UIColor(hex: asphaltLightHex)
        static let teal = UIColor(hex: tealHex)
        static let magenta = UIColor(hex: magentaHex)
        static let sunset = UIColor(hex: sunsetHex)
        static let cream = UIColor(hex: creamHex)
        static let ink = UIColor(hex: inkHex)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
