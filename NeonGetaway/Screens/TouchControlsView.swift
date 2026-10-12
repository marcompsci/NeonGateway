import SwiftUI
import GameCore

/// How the player set up the on-screen controls in Settings.
struct ControlLayout: Equatable {
    var scale = 1.0
    var opacity = 1.0
    var leftHanded = false
    var steerOffset = CGSize.zero
    var pedalOffset = CGSize.zero

    static let scaleRange = 0.8...1.4
    static let opacityRange = 0.35...1.0
    /// How far a cluster can be dragged from its default spot.
    static let xRange: ClosedRange<CGFloat> = -220...220
    static let yRange: ClosedRange<CGFloat> = -420...30

    init() {}

    init(_ s: GameSettings) {
        scale = min(max(s.controlScale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        opacity = min(max(s.controlOpacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        leftHanded = s.leftHanded
        steerOffset = Self.clamp(CGSize(width: s.steerOffset.x, height: s.steerOffset.y))
        pedalOffset = Self.clamp(CGSize(width: s.pedalOffset.x, height: s.pedalOffset.y))
    }

    static func clamp(_ size: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, xRange.lowerBound), xRange.upperBound),
               height: min(max(size.height, yRange.lowerBound), yRange.upperBound))
    }
}

/// Portrait thumb controls in the bottom of the screen: a steering strip on one side, GAS,
/// BRAKE/REV and DRIFT on the other. Each control tracks its own finger, so steering and
/// pedals can be held at the same time. Size, see-through-ness, side and position all come
/// from Settings; in the layout editor (`onMove` set) drags move the clusters instead.
struct TouchControlsView: View {
    enum Cluster { case steer, pedals }

    let input: ControlInput
    var hud = HUDState()
    var layout = ControlLayout()
    var onContext: () -> Void = {}
    var onMove: ((Cluster, CGSize) -> Void)? = nil

    var body: some View {
        VStack {
            Spacer()
            if let context = hud.context {
                HStack {
                    if !layout.leftHanded { Spacer() }
                    ContextButton(action: context, onTap: onContext)
                    if layout.leftHanded { Spacer() }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            HStack(alignment: .bottom, spacing: 10) {
                if layout.leftHanded {
                    pedals
                    Spacer(minLength: 4)
                    steer
                } else {
                    steer
                    Spacer(minLength: 4)
                    pedals
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
        }
        // Switching between car and feet swaps buttons; let go of anything held.
        .onChange(of: hud.onFoot) { _, _ in
            input.drift = false
            input.fire = false
        }
    }

    private func mover(_ cluster: Cluster) -> ((CGSize) -> Void)? {
        guard let onMove else { return nil }
        return { onMove(cluster, $0) }
    }

    private var steer: some View {
        SteerPad { input.steer = $0 }
            .opacity(layout.opacity)
            .scaleEffect(layout.scale, anchor: layout.leftHanded ? .bottomTrailing : .bottomLeading)
            .modifier(Movable(offset: layout.steerOffset, label: "Steering",
                              onMove: mover(.steer)))
    }

    private var pedals: some View {
        VStack(alignment: layout.leftHanded ? .leading : .trailing, spacing: 10) {
            if hud.onFoot {
                if hud.weaponCount > 0 {
                    HoldButton(title: hud.isMelee ? "Swing" : "Fire", color: Palette.magenta,
                               size: CGSize(width: 92, height: 52),
                               hint: hud.isMelee ? "Hold to swing at whatever's right in front of you."
                                                 : "Hold to shoot whatever you're facing.") {
                        input.fire = $0
                    }
                    .accessibilityIdentifier("controls.fire")
                }
            } else {
                HoldButton(title: "Drift", color: Palette.sunset, size: CGSize(width: 92, height: 52)) {
                    input.drift = $0
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                let brake = HoldButton(title: hud.onFoot ? "Back" : "Brake", color: Palette.cream,
                                       size: CGSize(width: 74, height: 74),
                                       hint: hud.onFoot ? "Hold to step backwards."
                                                        : "Hold to brake. Hold when stopped to reverse.") {
                    input.brake = $0
                }
                let gas = HoldButton(title: hud.onFoot ? "Run" : "Gas", color: Palette.teal,
                                     size: CGSize(width: 98, height: 98)) {
                    input.gas = $0
                }
                // The big GAS button stays nearest the edge of the screen, under the thumb.
                if layout.leftHanded {
                    gas
                    brake
                } else {
                    brake
                    gas
                }
            }
        }
        .opacity(layout.opacity)
        .scaleEffect(layout.scale, anchor: layout.leftHanded ? .bottomLeading : .bottomTrailing)
        .modifier(Movable(offset: layout.pedalOffset, label: "Pedals",
                          onMove: mover(.pedals)))
    }
}

/// Moves a control cluster by the player's saved offset. In the layout editor it also shows a
/// dashed frame and can be dragged; the new offset is reported when the finger lifts.
private struct Movable: ViewModifier {
    let offset: CGSize
    let label: String
    let onMove: ((CGSize) -> Void)?
    @State private var drag = CGSize.zero

    func body(content: Content) -> some View {
        content
            .overlay {
                if let onMove {
                    Rectangle()
                        .fill(Palette.sunset.opacity(0.12))
                        .overlay(Rectangle().strokeBorder(Palette.sunset, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { drag = $0.translation }
                                .onEnded { value in
                                    onMove(ControlLayout.clamp(CGSize(width: offset.width + value.translation.width,
                                                                      height: offset.height + value.translation.height)))
                                    drag = .zero
                                }
                        )
                        .accessibilityElement()
                        .accessibilityLabel("\(label) position")
                        .accessibilityHint("Drag to move")
                }
            }
            .offset(ControlLayout.clamp(CGSize(width: offset.width + drag.width, height: offset.height + drag.height)))
    }
}

/// One tap: get in, get out, shop or keep the car, whichever applies where the player is.
struct ContextButton: View {
    let action: HUDState.ContextAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(action.title)
                .pixelLabel(.callout, color: Palette.ink)
                .padding(.horizontal, 16)
                .frame(minWidth: 120, minHeight: 48)
                .background(Palette.cream)
                .overlay(Rectangle().strokeBorder(Palette.ink, lineWidth: 3))
        }
        .accessibilityHint(action.hint)
        .accessibilityIdentifier("controls.context")
    }
}

/// Horizontal strip: finger left of centre steers left, right steers right; lifting re-centres.
/// It takes whatever width is left beside the pedals (up to 190 pt) so the row fits any iPhone.
struct SteerPad: View {
    let onSteer: (Double) -> Void
    @State private var value: Double = 0
    @State private var width: CGFloat = 160
    private let height: CGFloat = 96
    private let knob: CGFloat = 30

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Palette.ink.opacity(0.55))
                .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.8), lineWidth: 3))
            HStack {
                Image(systemName: "arrowtriangle.left.fill")
                Spacer()
                Image(systemName: "arrowtriangle.right.fill")
            }
            .font(.title3)
            .foregroundStyle(Palette.teal.opacity(0.5))
            .padding(.horizontal, 12)
            Rectangle()
                .fill(Palette.teal)
                .frame(width: knob, height: height - 20)
                .offset(x: CGFloat(value) * max(0, width / 2 - knob))
        }
        .frame(minWidth: 120, maxWidth: 190)
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let half = width / 2
                    // Full lock is reached at 80% of the way to the edge.
                    let raw = Double((drag.location.x - half) / (half * 0.8))
                    set(min(max(raw, -1), 1))
                }
                .onEnded { _ in set(0) }
        )
        .accessibilityElement()
        .accessibilityLabel("Steering")
        .accessibilityValue(value == 0 ? "Centred" : (value < 0 ? "Left" : "Right"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(min(value + 0.5, 1))
            case .decrement: set(max(value - 0.5, -1))
            @unknown default: break
            }
        }
    }

    private func set(_ newValue: Double) {
        value = newValue
        onSteer(newValue)
    }
}

/// A pedal-style button that is "down" for as long as a finger is on it. With VoiceOver, a
/// double-tap toggles it held or released instead.
struct HoldButton: View {
    let title: String
    let color: Color
    let size: CGSize
    var hint: String? = nil
    let onChange: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Text(title)
            .pixelLabel(size.width > 90 ? .title3 : .callout, color: pressed ? Palette.ink : color)
            .frame(width: size.width, height: size.height)
            .background(Rectangle().fill(pressed ? color : Palette.ink.opacity(0.55)))
            .overlay(Rectangle().strokeBorder(color, lineWidth: 3))
            .scaleEffect(pressed ? 0.94 : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed { set(true) }
                    }
                    .onEnded { _ in set(false) }
            )
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(pressed ? "Held" : "Released")
            .accessibilityHint(hint ?? "Double-tap to hold or release")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { set(!pressed) }
    }

    private func set(_ down: Bool) {
        pressed = down
        onChange(down)
    }
}
