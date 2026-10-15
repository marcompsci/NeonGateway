import SwiftUI
import GameCore

/// How the player set up the on-screen controls in Settings.
struct ControlLayout: Equatable {
    var style: ControlStyle = .racer
    var scale = 1.0
    /// On-foot buttons.
    var opacity = 1.0
    /// Car buttons: see-through by default so the road shows under them.
    var driveOpacity = 0.65
    var leftHanded = false
    var autoFire = false
    var steerOffset = CGSize.zero
    var pedalOffset = CGSize.zero

    static let scaleRange = 0.8...1.4
    static let opacityRange = 0.35...1.0
    /// How far a cluster can be dragged from its default spot (landscape).
    static let xRange: ClosedRange<CGFloat> = -300...300
    static let yRange: ClosedRange<CGFloat> = -170...20

    init() {}

    init(_ s: GameSettings) {
        style = s.controlStyle
        scale = min(max(s.controlScale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        opacity = min(max(s.controlOpacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        driveOpacity = min(max(s.driveOpacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        leftHanded = s.leftHanded
        autoFire = s.autoFire
        steerOffset = Self.clamp(CGSize(width: s.steerOffset.x, height: s.steerOffset.y))
        pedalOffset = Self.clamp(CGSize(width: s.pedalOffset.x, height: s.pedalOffset.y))
    }

    static func clamp(_ size: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, xRange.lowerBound), xRange.upperBound),
               height: min(max(size.height, yRange.lowerBound), yRange.upperBound))
    }

    /// The shooter layout on foot (Racer and Stick); Classic keeps its tank-style pads.
    var shooterOnFoot: Bool { style != .classic }
}

/// Landscape thumb controls.
///
/// - In a car (Racer): the joystick under the left thumb (push where you want to go); DRIFT,
///   BRAKE and GAS pedals under the right. Stick style keeps just DRIFT and BRAKE. All car
///   buttons are see-through (`driveOpacity`) so the street shows under them.
/// - On foot (Racer and Stick): the shooter layout. Move stick with a second FIRE above it on
///   the left; big FIRE, AIM, SWAP and SPRINT on the right; the weapon bar and AUTO FIRE along
///   the bottom middle.
///
/// Each control tracks its own finger, so steering and pedals can be held together. In the
/// layout editor (`onMove` set) the dashed clusters can be dragged instead.
struct TouchControlsView: View {
    enum Cluster { case steer, pedals }

    let input: ControlInput
    var hud = HUDState()
    var layout = ControlLayout()
    var onContext: () -> Void = {}
    var onCycle: () -> Void = {}
    var onEquip: (WeaponID) -> Void = { _ in }
    var onAutoFire: (Bool) -> Void = { _ in }
    var onMove: ((Cluster, CGSize) -> Void)? = nil

    private var shooter: Bool { hud.onFoot && layout.shooterOnFoot }
    /// The whole screen, for the driving stick's touch zone.
    @State private var screen = CGSize(width: 874, height: 402)

    /// Driving: the stick appears wherever the thumb lands in the lower-left of the screen,
    /// below the map and objective, up to about the middle.
    private var driveZone: CGSize {
        let w = max(220, min(screen.width * 0.46, screen.width - 300) - 18)
        let h = max(190, screen.height - 128)
        return CGSize(width: w, height: h)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 8) {
                if layout.leftHanded {
                    rightCluster
                    Spacer(minLength: 4)
                    leftCluster
                } else {
                    leftCluster
                    Spacer(minLength: 4)
                    rightCluster
                }
            }
            if shooter && hud.weaponCount > 0 {
                WeaponBar(slots: hud.weapons, autoFire: layout.autoFire, onEquip: onEquip, onAutoFire: onAutoFire)
                    .opacity(max(layout.opacity, 0.8))
                    .padding(.bottom, 2)
                    // Sit left of centre so the fist buttons beside FIRE stay clear.
                    .offset(x: layout.leftHanded ? 70 : -70)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        // Fill the screen so the clusters sit right down at the bottom edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
        // Switching between car and feet swaps buttons; let go of anything held.
        .onChange(of: hud.onFoot) { _, _ in
            input.drift = false
            input.fire = false
            input.sprint = false
            input.brake = false
            input.gas = false
            input.aim = false
            input.steer = 0
            input.stick = .zero
        }
    }

    private func mover(_ cluster: Cluster) -> ((CGSize) -> Void)? {
        guard let onMove else { return nil }
        return { onMove(cluster, $0) }
    }

    // MARK: Clusters

    /// Under the left thumb (right thumb when left-handed): how you move.
    @ViewBuilder
    private var leftCluster: some View {
        Group {
            if shooter {
                VStack(alignment: layout.leftHanded ? .trailing : .leading, spacing: 4) {
                    if hud.weaponCount > 0 {
                        RoundHold(icon: hud.isMelee ? "bolt.fill" : "scope", caption: hud.isMelee ? "Swing" : "Fire",
                                  color: Palette.magenta, diameter: 62,
                                  hint: "A second fire button for the left thumb.") { input.fire = $0 }
                            .padding(.horizontal, 20)
                            .accessibilityIdentifier("controls.fire2")
                    }
                    StickPad(width: 200, height: 176) { input.stick = $0 }
                }
                .opacity(layout.opacity)
            } else if hud.onFoot {
                classicSteer.opacity(layout.opacity)
            } else {
                if layout.style == .classic {
                    classicSteer
                } else {
                    // The same joystick as on foot, but it appears wherever the thumb lands in
                    // the lower-left; at rest it's a faint ring in the corner so the road shows.
                    StickPad(width: driveZone.width, height: driveZone.height, idleOpacity: 0.45,
                             rest: { area in
                                 CGPoint(x: layout.leftHanded ? area.width - 62 - 34 : 62 + 34, y: area.height - 62 - 14)
                             }) { input.stick = $0 }
                }
            }
        }
        .opacity(hud.onFoot ? 1 : layout.driveOpacity)
        .scaleEffect(layout.scale, anchor: layout.leftHanded ? .bottomTrailing : .bottomLeading)
        .modifier(Movable(offset: layout.steerOffset, label: hud.onFoot ? "Move" : "Steering", onMove: mover(.steer)))
    }

    /// Under the right thumb: gas and brake in a car, fire and friends on foot.
    private var rightCluster: some View {
        VStack(alignment: layout.leftHanded ? .leading : .trailing, spacing: 8) {
            if let context = hud.context {
                ContextButton(action: context, onTap: onContext)
            }
            Group {
                if shooter {
                    HStack(alignment: .bottom, spacing: 6) {
                        if layout.leftHanded {
                            shooterButtons
                            fistButtons
                        } else {
                            fistButtons
                            shooterButtons
                        }
                    }
                    .opacity(layout.opacity)
                } else if hud.onFoot {
                    classicPedals.opacity(layout.opacity)
                } else {
                    Group {
                        switch layout.style {
                        case .racer: racerPedals
                        case .stick: stickCarButtons
                        case .classic: classicPedals
                        }
                    }
                    .opacity(layout.driveOpacity)
                }
            }
            .scaleEffect(layout.scale, anchor: layout.leftHanded ? .bottomLeading : .bottomTrailing)
            .modifier(Movable(offset: layout.pedalOffset, label: hud.onFoot ? "Action buttons" : "Pedals",
                              onMove: mover(.pedals)))
        }
    }

    // MARK: Car

    private var racerPedals: some View {
        HStack(alignment: .bottom, spacing: 14) {
            let brakeStack = VStack(spacing: 10) {
                RoundHold(icon: "tornado", caption: "Drift", color: Palette.sunset, diameter: 58,
                          hint: "Hold in a turn to slide the back out.") { input.drift = $0 }
                    .accessibilityIdentifier("controls.drift")
                PedalButton(kind: .brake) { input.brake = $0 }
            }
            let gas = PedalButton(kind: .gas) { input.gas = $0 }
            if layout.leftHanded {
                gas
                brakeStack
            } else {
                brakeStack
                gas
            }
        }
    }

    /// Stick style in a car: the stick steers and drives, so only DRIFT and BRAKE.
    private var stickCarButtons: some View {
        HStack(alignment: .bottom, spacing: 14) {
            RoundHold(icon: "tornado", caption: "Drift", color: Palette.sunset, diameter: 66,
                      hint: "Hold in a turn to slide the back out.") { input.drift = $0 }
                .accessibilityIdentifier("controls.drift")
            RoundHold(icon: "stop.fill", caption: "Brake", color: Palette.cream, diameter: 92,
                      hint: "Hold to brake. The stick also brakes and reverses when you pull it back.") {
                input.brake = $0
            }
        }
    }

    private var classicSteer: some View {
        SteerPad { input.steer = $0 }
            .frame(width: 210)
    }

    private var classicPedals: some View {
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
                if layout.leftHanded {
                    gas
                    brake
                } else {
                    brake
                    gas
                }
            }
        }
    }

    // MARK: On foot

    /// Fists: right hook on top, a straight punch, left hook at the bottom, in a little arc.
    private var fistButtons: some View {
        VStack(spacing: 6) {
            TapRound(icon: "hand.raised.fill", caption: "R hook", color: Palette.sunset, diameter: 56,
                     hint: "Swing a right hook at whoever's to your front right.") { input.strikeTapped = .right }
                .accessibilityIdentifier("controls.hookRight")
                .offset(x: layout.leftHanded ? -8 : 8)
            TapRound(icon: "hand.point.up.fill", caption: "Punch", color: Palette.cream, diameter: 62,
                     hint: "A quick straight punch at whoever's right in front.") { input.strikeTapped = .jab }
                .accessibilityIdentifier("controls.punch")
            TapRound(icon: "hand.raised.fill", caption: "L hook", color: Palette.teal, diameter: 56,
                     hint: "Swing a left hook at whoever's to your front left.") { input.strikeTapped = .left }
                .accessibilityIdentifier("controls.hookLeft")
                .offset(x: layout.leftHanded ? -8 : 8)
        }
        .padding(.bottom, 4)
    }

    /// Big FIRE in the thumb's resting spot, AIM above it, SWAP inside, SPRINT in the corner.
    private var shooterButtons: some View {
        let w: CGFloat = 236, h: CGFloat = 206
        // Mirror the cluster for left-handed play.
        func x(_ v: CGFloat) -> CGFloat { layout.leftHanded ? w - v : v }
        return ZStack {
            if hud.weaponCount > 0 {
                RoundHold(icon: hud.isMelee ? "bolt.fill" : "scope", caption: hud.isMelee ? "Swing" : "Fire",
                          color: Palette.magenta, diameter: 104, big: true,
                          hint: hud.isMelee ? "Hold to swing at whatever's right in front of you."
                                            : "Hold to shoot whatever you're facing.") { input.fire = $0 }
                    .accessibilityIdentifier("controls.fire")
                    .position(x: x(118), y: 142)
                RoundHold(icon: "target", caption: hud.aimLocked ? "Locked" : "Aim",
                          color: hud.aimLocked ? Palette.magenta : Palette.cream, diameter: 64,
                          hint: "Hold to turn and face the nearest target while you keep moving.") { input.aim = $0 }
                    .accessibilityIdentifier("controls.aim")
                    .position(x: x(200), y: 52)
                if hud.weaponCount > 1 {
                    TapRound(icon: "arrow.triangle.2.circlepath", caption: "Swap", color: Palette.sunset,
                             diameter: 54, hint: "Switches to your next weapon", action: onCycle)
                        .accessibilityIdentifier("controls.swap")
                        .position(x: x(34), y: 176)
                }
            }
            SprintRound(stamina: hud.stamina) { input.sprint = $0 }
                .accessibilityIdentifier("controls.sprint")
                .position(x: x(206), y: 172)
        }
        .frame(width: w, height: h)
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

/// A round glass button that is "down" while a finger is on it (fire, aim, arrows, drift).
/// With VoiceOver, a double-tap toggles it held or released instead.
struct RoundHold: View {
    let icon: String
    let caption: String?
    let color: Color
    let diameter: CGFloat
    var big = false
    var label: String? = nil
    var hint: String? = nil
    let onChange: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        RoundFace(icon: icon, caption: caption, color: color, diameter: diameter, big: big, pressed: pressed)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { set(true) } }
                    .onEnded { _ in set(false) }
            )
            .accessibilityElement()
            .accessibilityLabel(label ?? caption ?? "Button")
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

/// A round button for a single tap (weapon swap).
struct TapRound: View {
    let icon: String
    let caption: String?
    let color: Color
    let diameter: CGFloat
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundFace(icon: icon, caption: caption, color: color, diameter: diameter, big: false, pressed: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption ?? "Button")
        .accessibilityHint(hint ?? "")
    }
}

/// The look shared by the round buttons: dark glass, a neon rim, an icon and a small caption.
private struct RoundFace: View {
    let icon: String
    let caption: String?
    let color: Color
    let diameter: CGFloat
    let big: Bool
    let pressed: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Palette.ink.opacity(0.35), Palette.ink.opacity(0.75)],
                                     center: .center, startRadius: 0, endRadius: diameter / 2))
            if pressed { Circle().fill(color.opacity(0.85)) }
            Circle().strokeBorder(color.opacity(pressed ? 1 : 0.9), lineWidth: big ? 4 : 3)
            if big {
                Circle().strokeBorder(color.opacity(0.35), lineWidth: 2).padding(9)
            }
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: diameter * (caption == nil ? 0.36 : 0.32), weight: .heavy))
                if let caption {
                    Text(caption.uppercased())
                        .font(.system(size: max(8, diameter * 0.13), weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(pressed ? Palette.ink : color)
            .padding(.horizontal, 6)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: color.opacity(pressed ? 0.7 : 0.25), radius: pressed ? 12 : 5)
        .scaleEffect(pressed ? 0.93 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// GAS and BRAKE as foot pedals: a tall ribbed GAS on the outside, a wide grid BRAKE inside.
struct PedalButton: View {
    enum Kind { case gas, brake }
    let kind: Kind
    let onChange: (Bool) -> Void
    @State private var pressed = false

    private var size: CGSize { kind == .gas ? CGSize(width: 78, height: 124) : CGSize(width: 78, height: 70) }
    private var color: Color { kind == .gas ? Palette.teal : Palette.cream }
    private var title: String { kind == .gas ? "Gas" : "Brake" }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: kind == .gas ? 22 : 16, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Palette.ink.opacity(0.45), Palette.ink.opacity(0.8)],
                                      startPoint: .top, endPoint: .bottom))
            if pressed { shape.fill(color.opacity(0.85)) }
            // Ridges (gas) or a grid (brake), like real pedal rubber.
            Canvas { context, s in
                let ink = (pressed ? Palette.ink : color).opacity(0.55)
                if kind == .gas {
                    var y: CGFloat = 26
                    while y < s.height - 28 {
                        context.fill(Path(roundedRect: CGRect(x: 18, y: y, width: s.width - 36, height: 5), cornerRadius: 2.5),
                                     with: .color(ink))
                        y += 13
                    }
                } else {
                    for row in 0..<3 {
                        for col in 0..<4 {
                            let r = CGRect(x: 14 + CGFloat(col) * 13, y: 14 + CGFloat(row) * 11, width: 9, height: 7)
                            context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(ink))
                        }
                    }
                }
            }
            shape.strokeBorder(color, lineWidth: 3)
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(pressed ? Palette.ink : color)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 6)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: color.opacity(pressed ? 0.7 : 0.25), radius: pressed ? 12 : 5)
        .rotation3DEffect(.degrees(pressed ? 14 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { set(true) } }
                .onEnded { _ in set(false) }
        )
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(pressed ? "Held" : "Released")
        .accessibilityHint(kind == .gas ? "Hold to drive forward" : "Hold to brake. Hold when stopped to reverse.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { set(!pressed) }
        .accessibilityIdentifier(kind == .gas ? "controls.gas" : "controls.brake")
    }

    private func set(_ down: Bool) {
        pressed = down
        onChange(down)
    }
}

/// SPRINT: a round button with the stamina left drawn as a ring around it.
struct SprintRound: View {
    let stamina: Double
    let onChange: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        let left = max(0, min(1, stamina))
        let colour = left > 0.02 ? Palette.sunset : Palette.cream.opacity(0.5)
        ZStack {
            RoundFace(icon: "figure.run", caption: left > 0.02 ? "Sprint" : "Winded", color: colour,
                      diameter: 64, big: false, pressed: pressed)
            Circle()
                .trim(from: 0, to: left)
                .stroke(colour, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 74, height: 74)
        }
        .frame(width: 76, height: 76)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { set(true) } }
                .onEnded { _ in set(false) }
        )
        .accessibilityElement()
        .accessibilityLabel("Sprint")
        .accessibilityValue("\(Int(left * 100)) percent stamina")
        .accessibilityHint("Hold to sprint while you have stamina")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { set(!pressed) }
    }

    private func set(_ down: Bool) {
        pressed = down
        onChange(down)
    }
}

/// The weapon bar along the bottom: one slot per weapon carried with its rounds left; tap a slot
/// to put that weapon in hand. AUTO FIRE sits on top of it.
struct WeaponBar: View {
    let slots: [HUDState.WeaponSlot]
    let autoFire: Bool
    let onEquip: (WeaponID) -> Void
    let onAutoFire: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { onAutoFire(!autoFire) } label: {
                HStack(spacing: 5) {
                    Text("Auto fire").font(.system(size: 11, weight: .heavy, design: .rounded))
                    Image(systemName: autoFire ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(autoFire ? Palette.sunset : Palette.cream)
                .padding(.horizontal, 8)
                .frame(minHeight: 26)
                .background(Palette.ink.opacity(0.6), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Auto fire")
            .accessibilityValue(autoFire ? "On" : "Off")
            .accessibilityHint("Shoots by itself when a cruiser or another player is in your sights")
            .accessibilityIdentifier("controls.autofire")
            HStack(spacing: 4) {
                ForEach(slots) { slot in
                    Button { onEquip(slot.id) } label: { WeaponSlotView(slot: slot) }
                        .buttonStyle(.plain)
                        .disabled(!slot.loaded)
                        .accessibilityLabel(slot.id.spec.name)
                        .accessibilityValue(slot.id.spec.isMelee ? "Never runs out"
                                            : "\(slot.ammo) rounds\(slot.equipped ? ", in hand" : "")")
                        .accessibilityIdentifier("weapon.\(slot.id.rawValue)")
                }
            }
        }
    }
}

private struct WeaponSlotView: View {
    let slot: HUDState.WeaponSlot

    var body: some View {
        let edge = slot.equipped ? Palette.sunset : Palette.cream.opacity(0.35)
        VStack(spacing: 1) {
            Image(uiImage: WeaponIcons.image(slot.id))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 18)
                .opacity(slot.loaded ? 1 : 0.35)
            Text(slot.id.spec.isMelee ? "∞" : "\(slot.ammo)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(!slot.id.spec.isMelee && slot.ammo == 0 ? Palette.sunset : Palette.cream)
        }
        .frame(width: 54, height: 42)
        .background(slot.equipped ? Palette.sunset.opacity(0.22) : Palette.ink.opacity(0.65))
        .overlay(Rectangle().strokeBorder(edge, lineWidth: slot.equipped ? 2.5 : 1))
        .overlay(alignment: .bottom) {
            if slot.equipped { Rectangle().fill(Palette.sunset).frame(height: 3) }
        }
    }
}

/// Weapon pictures for the bar, drawn once.
@MainActor
enum WeaponIcons {
    private static var cache: [WeaponID: UIImage] = [:]

    static func image(_ w: WeaponID) -> UIImage {
        if let hit = cache[w] { return hit }
        let image = PixelArt.weaponImage(w, scale: 3)
        cache[w] = image
        return image
    }
}

/// Horizontal strip: finger left of centre steers left, right steers right; lifting re-centres.
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
        .frame(minWidth: 120, maxWidth: 210)
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

/// A pedal-style button that is "down" for as long as a finger is on it (Classic). With
/// VoiceOver, a double-tap toggles it held or released instead.
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

/// A floating thumbstick. Put a thumb down anywhere in the pad and the stick centres there;
/// push toward where you want to go. Reports x right / y up, length 0...1 (full at the rim).
struct StickPad: View {
    var width: CGFloat = 210
    var height: CGFloat = 220
    /// How visible the stick is while nobody's touching it.
    var idleOpacity: Double = 1
    /// Where the stick sits at rest in the pad (default: bottom middle).
    var rest: ((CGSize) -> CGPoint)? = nil
    let onChange: (Vec2) -> Void
    @State private var base: CGPoint?
    @State private var knob = CGSize.zero
    @State private var area = CGSize(width: 200, height: 200)
    private let radius: CGFloat = 62

    var body: some View {
        ZStack {
            // The touch area: generous, mostly invisible.
            Rectangle().fill(Color.white.opacity(0.001))
            let centre = base ?? rest?(area) ?? CGPoint(x: area.width / 2, y: area.height - radius - 10)
            ZStack {
                Circle()
                    .fill(Palette.ink.opacity(base == nil ? 0.35 : 0.5))
                    .overlay(Circle().strokeBorder(Palette.teal.opacity(base == nil ? 0.45 : 0.9), lineWidth: 3))
                    .frame(width: radius * 2, height: radius * 2)
                ForEach(0..<4) { i in
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Palette.teal.opacity(0.55))
                        .offset(y: -radius + 13)
                        .rotationEffect(.degrees(Double(i) * 90))
                }
                Circle()
                    .fill(RadialGradient(colors: [Palette.teal, Palette.teal.opacity(0.75)],
                                         center: .topLeading, startRadius: 2, endRadius: 40))
                    .overlay(Circle().strokeBorder(Palette.cream.opacity(0.85), lineWidth: 2))
                    .frame(width: 54, height: 54)
                    .shadow(color: Palette.teal.opacity(0.6), radius: base == nil ? 0 : 10)
                    .offset(knob)
            }
            .opacity(base == nil ? idleOpacity : 1)
            .animation(.easeOut(duration: 0.12), value: base == nil)
            .position(centre)
            .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { area = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if base == nil {
                        // Keep the whole ring on the pad.
                        let x = min(max(drag.startLocation.x, radius), area.width - radius)
                        let y = min(max(drag.startLocation.y, radius), area.height - radius)
                        base = CGPoint(x: x, y: y)
                    }
                    guard let base else { return }
                    var dx = drag.location.x - base.x
                    var dy = drag.location.y - base.y
                    let length = (dx * dx + dy * dy).squareRoot()
                    if length > radius {
                        dx *= radius / length
                        dy *= radius / length
                    }
                    knob = CGSize(width: dx, height: dy)
                    // Screen y grows downward; the world's grows up.
                    onChange(Vec2(Double(dx / radius), Double(-dy / radius)))
                }
                .onEnded { _ in
                    base = nil
                    knob = .zero
                    onChange(.zero)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Movement stick")
        .accessibilityHint("Push the way you want to go")
        .accessibilityIdentifier("controls.stick")
    }
}
