import GameController
import GameCore

/// What the on-screen controls (or a game controller) are holding right now. Written by SwiftUI
/// gestures, read by the scene every fixed step. Deliberately not observable: nothing should
/// redraw when it changes.
@MainActor
final class ControlInput {
    var steer: Double = 0      // -1...1
    var gas = false
    var brake = false
    var drift = false
    /// FIRE held (on foot).
    var fire = false
    /// One-shot taps, consumed by the scene on its next fixed step.
    var enterExitTapped = false
    var cycleWeaponTapped = false

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

    /// The taps since the last step, cleared as they're read.
    func takeActions() -> CityActions {
        defer { enterExitTapped = false }
        return CityActions(enterExit: enterExitTapped, fire: fire || pad.fire)
    }

    func releaseAll() {
        steer = 0
        gas = false
        brake = false
        drift = false
        fire = false
        enterExitTapped = false
        cycleWeaponTapped = false
    }

    var controllerConnected: Bool { GCController.current?.extendedGamepad != nil }

    /// Reads the current game controller, if there is one. Called by the scene once per frame.
    ///
    ///     Left stick: steer      Right trigger: gas / run     Left trigger: brake / back
    ///     B or left shoulder: drift      Right shoulder: fire / swing
    ///     A: get in, get out, shop, deal, keep car      Y: next weapon      Menu: pause
    func pollController() {
        guard let g = GCController.current?.extendedGamepad else {
            pad = PadState()
            return
        }
        var next = PadState()
        next.active = true
        let x = Double(g.leftThumbstick.xAxis.value)
        next.steer = abs(x) < 0.12 ? 0 : x
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
        var gas = 0.0
        var brake = 0.0
        var drift = false
        var fire = false
        var a = false
        var y = false
        var menu = false
    }
}
