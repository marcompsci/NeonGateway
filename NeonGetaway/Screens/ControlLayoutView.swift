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
            TouchControlsView(input: preview, hud: mockHUD, layout: layout,
                              onAutoFire: { model.settings.autoFire = $0 },
                              onMove: { cluster, offset in
                let saved = LayoutOffset(x: offset.width, y: offset.height)
                switch cluster {
                case .steer: model.settings.steerOffset = saved
                case .pedals: model.settings.pedalOffset = saved
                }
            })
            // Settings sit in the middle at the top, between the two button clusters.
            VStack(spacing: 6) {
                ScreenHeader(title: "Touch controls") { router.back() }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Control style", selection: $model.settings.controlStyle) {
                            ForEach(ControlStyle.allCases, id: \.self) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("controls.style")
                        Text(model.settings.controlStyle.blurb)
                            .pixelLabel(.caption2, color: Palette.cream.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Drag the dashed boxes to move the controls.")
                            .pixelLabel(.caption, color: Palette.cream)
                        Text("Size \(Int(model.settings.controlScale * 100))%").pixelLabel(.caption)
                        Slider(value: $model.settings.controlScale, in: ControlLayout.scaleRange, step: 0.05)
                            .tint(Palette.teal)
                            .accessibilityLabel("Button size")
                        Text("Car buttons \(Int(model.settings.driveOpacity * 100))% solid").pixelLabel(.caption)
                        Slider(value: $model.settings.driveOpacity, in: ControlLayout.opacityRange, step: 0.05)
                            .tint(Palette.teal)
                            .accessibilityLabel("Car button opacity")
                            .accessibilityIdentifier("controls.driveOpacity")
                        Text("On-foot buttons \(Int(model.settings.controlOpacity * 100))% solid").pixelLabel(.caption)
                        Slider(value: $model.settings.controlOpacity, in: ControlLayout.opacityRange, step: 0.05)
                            .tint(Palette.teal)
                            .accessibilityLabel("On-foot button opacity")
                        Toggle(isOn: $model.settings.leftHanded) {
                            Text("Swap sides (left-handed)").pixelLabel(.caption)
                        }
                        .tint(Palette.magenta)
                        HStack(spacing: 10) {
                            Button(onFoot ? "Show car buttons" : "Show on-foot buttons") { onFoot.toggle() }
                                .buttonStyle(.neon(Palette.cream))
                            Button("Reset") {
                                let fresh = GameSettings()
                                model.settings.controlStyle = fresh.controlStyle
                                model.settings.controlScale = fresh.controlScale
                                model.settings.controlOpacity = fresh.controlOpacity
                                model.settings.driveOpacity = fresh.driveOpacity
                                model.settings.leftHanded = false
                                model.settings.steerOffset = LayoutOffset()
                                model.settings.pedalOffset = LayoutOffset()
                            }
                            .buttonStyle(.neon(Palette.sunset))
                            .accessibilityIdentifier("controls.reset")
                        }
                    }
                    .padding(12)
                }
                .scrollBounceBehavior(.basedOnSize)
                .background(Palette.ink.opacity(0.85))
                .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.5), lineWidth: 1))
                .frame(maxHeight: 250)
                Spacer()
            }
            .frame(maxWidth: 400)
            .padding(.top, 6)
        }
        .background(Palette.asphalt.ignoresSafeArea())
        .landscapeWhileVisible()
    }

    private var mockHUD: HUDState {
        var h = HUDState()
        h.onFoot = onFoot
        h.weaponCount = onFoot ? 2 : 0
        h.weaponName = onFoot ? "Pistol" : nil
        h.stamina = 0.7
        h.speed = 64
        h.speedFraction = 0.4
        if onFoot {
            h.weapons = [
                .init(id: .pistol, ammo: 35, loaded: true, equipped: true),
                .init(id: .bat, ammo: 0, loaded: true, equipped: false)
            ]
        }
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
