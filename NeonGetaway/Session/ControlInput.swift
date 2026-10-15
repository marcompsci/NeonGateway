import GameController
import GameCore

/// What the on-screen controls (or a game controller) are holding right now. Written by SwiftUI
/// gestures, read by the scene every fixed step. Deliberately not observable: nothing should
/// redraw when it changes.
@MainActor
final class ControlInput {
    /// Stick or the classic strip and pedals (from Settings).
    var style: ControlStyle = .racer
    /// The touch stick: x right, y up (screen and world agree; the camera never turns), length 0...1.
    var stick = Vec2.zero
    /// SPRINT held (on foot, stick style).
    var sprint = false
    var steer: Double = 0      // -1...1
    var gas = false
    var brake = false
    var drift = false
    /// FIRE held (on foot).
    var fire = false
    /// AIM held (on foot): lock on to the nearest target.
    var aim = false
    /// AUTO FIRE switched on (from Settings, toggled on the weapon bar).
    var autoFire = false
    /// One-shot taps, consumed by the scene on its next fixed step.
    var enterExitTapped = false
    var cycleWeaponTapped = false
    /// A fist button tapped (left hook, right hook, punch).
    var strikeTapped: Strike?

    /// Controller buttons that act outside the street sim (set by the session).
    var onControllerContext: (() -> Void)?
    var onControllerCycle: (() -> Void)?
    var onControllerPause: (() -> Void)?

    private var pad = PadState()

    var vehicleInput: VehicleInput {
        let p = pad
        guard p.active else {
            return VehicleInput(throttle: gas ? 1 : 0, brake: brake ? 1 : 0, steer: steer, drift: drift)
        }
        // A controller and the touch controls both work; whichever is pushed harder wins.
        let s = abs(p.steer) > abs(steer) ? p.steer : steer
        return VehicleInput(throttle: max(p.gas, gas ? 1 : 0), brake: max(p.brake, brake ? 1 : 0),
                            steer: s, drift: drift || p.drift)
    }

    /// Stick style: whichever stick is pushed harder, the touch one or a controller's left stick.
    var stickVector: Vec2 {
        let p = pad
        guard p.active else { return stick }
        let padStick = Vec2(p.stickX, p.stickY)
        return padStick.length > stick.length ? padStick : stick
    }

    var brakeHeld: Bool { brake || pad.brake > 0.3 }
    var driftHeld: Bool { drift || pad.drift }
    /// On foot the drift button doubles as SPRINT on a controller.
    var sprintHeld: Bool { sprint || pad.drift }
    /// On foot the left trigger aims on a controller.
    var aimHeld: Bool { aim || pad.brake > 0.3 }

    /// The taps since the last step, cleared as they're read.
    func takeActions() -> CityActions {
        defer {
            enterExitTapped = false
            strikeTapped = nil
        }
        return CityActions(enterExit: enterExitTapped, fire: fire || pad.fire, autoFire: autoFire, strike: strikeTapped)
    }

    func releaseAll() {
        stick = .zero
        sprint = false
        steer = 0
        gas = false
        brake = false
        drift = false
        fire = false
        aim = false
        enterExitTapped = false
        cycleWeaponTapped = false
        strikeTapped = nil
    }

    var controllerConnected: Bool { GCController.current?.extendedGamepad != nil }

    /// Reads the current game controller, if there is one. Called by the scene once per frame.
    ///
    ///     Left stick: steer (Classic) or point where to go (Stick)
    ///     Right trigger: gas / run     Left trigger: brake / back (aim on foot)
    ///     B or left shoulder: drift (sprint on foot)      Right shoulder: fire / swing
    ///     A: get in, get out, shop, deal, keep car      Y: next weapon      Menu: pause
    func pollController() {
        guard let g = GCController.current?.extendedGamepad else {
            pad = PadState()
            return
        }
        var next = PadState()
        next.active = true
        let x = Double(g.leftThumbstick.xAxis.value)
        let y = Double(g.leftThumbstick.yAxis.value)
        next.steer = abs(x) < 0.12 ? 0 : x
        next.stickX = x
        next.stickY = y
        next.gas = Double(g.rightTrigger.value)
        next.brake = Double(g.leftTrigger.value)
        next.drift = g.buttonB.isPressed || g.leftShoulder.isPressed
        next.fire = g.rightShoulder.isPressed
        next.a = g.buttonA.isPressed
        next.y = g.buttonY.isPressed
        next.menu = g.buttonMenu.isPressed
        // Buttons act once per press.
        if next.a && !pad.a { onControllerContext?() }
        if next.y && !pad.y { onControllerCycle?() }
        if next.menu && !pad.menu { onControllerPause?() }
        pad = next
    }

    private struct PadState {
        var active = false
        var steer = 0.0
        var stickX = 0.0
        var stickY = 0.0
        var gas = 0.0
        var brake = 0.0
        var drift = false
        var fire = false
        var a = false
        var y = false
        var menu = false
    }
}
