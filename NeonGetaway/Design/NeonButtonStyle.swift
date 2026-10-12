import SwiftUI

/// Hard-edged menu button: cream text on asphalt, a neon border, and a solid offset "shadow"
/// block that the button presses into.
struct NeonButtonStyle: ButtonStyle {
    var accent: Color = Palette.teal

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .pixelLabel(.title3)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Palette.asphaltLight)
            .overlay(Rectangle().strokeBorder(accent, lineWidth: 3))
            .background(
                Rectangle()
                    .fill(accent.opacity(0.35))
                    .offset(x: pressed ? 0 : 6, y: pressed ? 0 : 6)
            )
            .offset(x: pressed ? 6 : 0, y: pressed ? 6 : 0)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == NeonButtonStyle {
    static var neon: NeonButtonStyle { NeonButtonStyle() }
    static func neon(_ accent: Color) -> NeonButtonStyle { NeonButtonStyle(accent: accent) }
}

/// Screen header with a back arrow, used by the stub and settings screens.
struct ScreenHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.black))
                    .foregroundStyle(Palette.teal)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("nav.back")
            Spacer()
            Text(title).pixelLabel(.title2)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
    }
}
