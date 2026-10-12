import SwiftUI

extension Font {
    /// The game's chunky monospaced type. Built on a text style so Dynamic Type still scales it.
    static func pixel(_ style: Font.TextStyle, weight: Font.Weight = .black) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

extension View {
    /// Uppercase, wide-tracked label in the game's type.
    func pixelLabel(_ style: Font.TextStyle = .headline, color: Color = Palette.cream) -> some View {
        self.font(.pixel(style))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
