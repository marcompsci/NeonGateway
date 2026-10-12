import SwiftUI
import GameCore

/// Lay out the touch controls: drag either cluster to move it, set the size and how see-through
/// the buttons are, or swap steering to the right for left-handed play.
struct ControlLayoutView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var preview = ControlInput()
    @State private var onFoot = false

    var body: some View {
        @Bindable var model = model
        let layout = ControlLayout(model.settings)
        ZStack {
            StreetMock()
            TouchControlsView(input: preview, hud: mockHUD, layout: layout, onMove: { cluster, offset in
                let saved = LayoutOffset(x: offset.width, y: offset.height)
                switch cluster {
                case .steer: model.settings.steerOffset = saved
                case .pedals: model.settings.pedalOffset = saved
                }
            })
            VStack(alignment: .leading, spacing: 10) {
                ScreenHeader(title: "Touch controls") { router.back() }
                Text("Drag the dashed boxes to move the controls.")
                    .pixelLabel(.caption, color: Palette.cream)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Size \(Int(model.settings.controlScale * 100))%").pixelLabel(.caption)
                    Slider(value: $model.settings.controlScale, in: ControlLayout.scaleRange, step: 0.05)
                        .tint(Palette.teal)
                        .accessibilityLabel("Button size")
                    Text("Opacity \(Int(model.settings.controlOpacity * 100))%").pixelLabel(.caption)
                    Slider(value: $model.settings.controlOpacity, in: ControlLayout.opacityRange, step: 0.05)
                        .tint(Palette.teal)
                        .accessibilityLabel("Button opacity")
                }
                Toggle(isOn: $model.settings.leftHanded) {
                    Text("Steer on the right").pixelLabel(.caption)
                }
                .tint(Palette.magenta)
                HStack(spacing: 10) {
                    Button(onFoot ? "Show car buttons" : "Show on-foot buttons") { onFoot.toggle() }
                        .buttonStyle(.neon(Palette.cream))
                    Button("Reset") {
                        model.settings.controlScale = 1
                        model.settings.controlOpacity = 1
                        model.settings.leftHanded = false
                        model.settings.steerOffset = LayoutOffset()
                        model.settings.pedalOffset = LayoutOffset()
                    }
                    .buttonStyle(.neon(Palette.sunset))
                    .accessibilityIdentifier("controls.reset")
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }

    private var mockHUD: HUDState {
        var h = HUDState()
        h.onFoot = onFoot
        h.weaponCount = onFoot ? 1 : 0
        h.weaponName = onFoot ? "Pistol" : nil
        return h
    }
}

/// A plain road grid behind the controls, so the layout can be judged against the street.
private struct StreetMock: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.asphalt))
            let lane: CGFloat = 128
            var x: CGFloat = 0
            while x < size.width {
                context.fill(Path(CGRect(x: x + lane * 0.8, y: 0, width: lane * 0.2, height: size.height)),
                             with: .color(Palette.ink))
                x += lane
            }
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y + lane * 0.8, width: size.width, height: lane * 0.2)),
                             with: .color(Palette.ink))
                y += lane
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
