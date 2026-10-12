import SwiftUI
import GameCore

/// Top-of-screen readouts: speed, clock, pause, the current objective and a minimap.
/// Every value is also written in words, so nothing depends on colour alone.
struct HUDView: View {
    let hud: HUDState
    let district: District
    let onPause: () -> Void
    var onCycleWeapon: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                speedBox
                Spacer(minLength: 4)
                if let time = hud.timeRemaining { TimerBox(seconds: time) }
                Spacer(minLength: 4)
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .font(.title2.weight(.black))
                        .foregroundStyle(Palette.cream)
                        .frame(width: 48, height: 48)
                        .background(Palette.ink.opacity(0.7))
                        .overlay(Rectangle().strokeBorder(Palette.magenta, lineWidth: 2))
                }
                .accessibilityLabel("Pause")
                .accessibilityIdentifier("hud.pause")
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    objectiveBanner
                    if hud.isDrifting || hud.driftScore > 0 { driftBadge }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    MinimapView(hud: hud, district: district)
                    HeatMeterView(stars: hud.heatStars, label: hud.heatLabel, points: hud.heatPoints)
                    if hud.witnessCalls > 0 { WitnessChip(count: hud.witnessCalls) }
                    if hud.onFoot {
                        HealthView(health: hud.health)
                    } else {
                        HullView(hull: hud.hull, max: hud.hullMax)
                    }
                    if hud.weaponCount > 0 {
                        WeaponChip(name: hud.weaponName, ammo: hud.ammo, cap: hud.ammoCap, melee: hud.isMelee,
                                   canCycle: hud.weaponCount > 1, onTap: onCycleWeapon)
                    }
                }
            }
            if let notice = hud.notice {
                NoticeBanner(text: notice, urgency: hud.bustFraction)
                    .frame(maxWidth: .infinity)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var speedBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(hud.speed)")
                .font(.system(size: 30, weight: .black, design: .monospaced))
                .foregroundStyle(Palette.cream)
                .monospacedDigit()
            Text(hud.onFoot ? "ON FOOT" : "SPD").pixelLabel(.caption2, color: Palette.teal)
        }
        .frame(minWidth: 64, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Palette.ink.opacity(0.7))
        .overlay(Rectangle().strokeBorder(Palette.teal, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hud.onFoot ? "On foot, speed \(hud.speed)"
                                       : "\(hud.vehicleName ?? "Car"), speed \(hud.speed)")
    }

    private var objectiveBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hud.objective)
                .font(.pixel(.footnote))
                .foregroundStyle(Palette.cream)
                .fixedSize(horizontal: false, vertical: true)
            if let metres = hud.targetMetres, let bearing = hud.targetBearing {
                Text("\(metres) m \(bearing)")
                    .font(.pixel(.footnote))
                    .foregroundStyle(Palette.teal)
            }
            Text(hud.areaName).pixelLabel(.caption2, color: Palette.cream.opacity(0.55))
        }
        .padding(8)
        .background(Palette.ink.opacity(0.75))
        .overlay(alignment: .leading) { Rectangle().fill(Palette.teal).frame(width: 3) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(objectiveSpoken)
    }

    private var objectiveSpoken: String {
        var words = hud.objective
        if let metres = hud.targetMetres, let bearing = hud.targetBearing, let name = hud.targetName {
            words += ". \(name) is \(metres) metres \(Self.bearingWords[bearing] ?? bearing)."
        }
        words += " You are in \(hud.areaName)."
        return words
    }

    static let bearingWords = ["N": "north", "NE": "north-east", "E": "east", "SE": "south-east",
                               "S": "south", "SW": "south-west", "W": "west", "NW": "north-west"]

    private var driftBadge: some View {
        Text(hud.isDrifting ? "DRIFT \(hud.driftScore)" : "DRIFT TOTAL \(hud.driftScore)")
            .pixelLabel(.caption, color: hud.isDrifting ? Palette.ink : Palette.magenta)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(hud.isDrifting ? Palette.magenta : Palette.ink.opacity(0.7))
            .accessibilityLabel(hud.isDrifting ? "Drifting, \(hud.driftScore) points"
                                               : "Drift total \(hud.driftScore) points")
    }
}

/// Countdown. Under 10 s it turns sunset AND says HURRY, so it never relies on colour alone.
struct TimerBox: View {
    let seconds: Double

    var body: some View {
        let low = seconds < 10
        let whole = Int(seconds.rounded(.up))
        VStack(spacing: 0) {
            Text(String(format: "%d:%02d", whole / 60, whole % 60))
                .font(.system(size: 30, weight: .black, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(low ? Palette.ink : Palette.cream)
            Text(low ? "HURRY" : "CLOCK").pixelLabel(.caption2, color: low ? Palette.ink : Palette.sunset)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(low ? Palette.sunset : Palette.ink.opacity(0.7))
        .overlay(Rectangle().strokeBorder(Palette.sunset, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(whole) seconds left")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The district in flat colour: the car as a cream arrow, objectives as teal squares, and
/// patrols that are after you as magenta dots.
struct MinimapView: View {
    let hud: HUDState
    let district: District
    private let width: CGFloat = 84

    var body: some View {
        let height = width * CGFloat(district.rows) / CGFloat(district.cols)
        Image(uiImage: DistrictArt.mapImage(for: district, scale: 4))
            .resizable()
            .interpolation(.none)
            .frame(width: width, height: height)
            .overlay {
                Canvas { context, size in
                    for patrol in hud.mapPatrols {
                        let p = CGPoint(x: patrol.x * size.width, y: (1 - patrol.y) * size.height)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                                     with: .color(Palette.magenta))
                    }
                    for target in hud.mapTargets {
                        let p = CGPoint(x: target.x * size.width, y: (1 - target.y) * size.height)
                        context.fill(Path(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                                     with: .color(Palette.teal))
                        context.stroke(Path(CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                                       with: .color(Palette.ink), lineWidth: 1)
                    }
                    let c = CGPoint(x: hud.mapCar.x * size.width, y: (1 - hud.mapCar.y) * size.height)
                    // Screen y is down, so flip the heading's sine.
                    let a = hud.mapHeading
                    func pt(_ angle: Double, _ r: Double) -> CGPoint {
                        CGPoint(x: c.x + cos(angle) * r, y: c.y - sin(angle) * r)
                    }
                    var arrow = Path()
                    arrow.move(to: pt(a, 6))
                    arrow.addLine(to: pt(a + 2.4, 5))
                    arrow.addLine(to: pt(a - 2.4, 5))
                    arrow.closeSubpath()
                    context.fill(arrow, with: .color(Palette.cream))
                    context.stroke(arrow, with: .color(Palette.ink), lineWidth: 1)
                }
            }
            .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.8), lineWidth: 2))
            .accessibilityHidden(true)  // the objective banner speaks the same information
    }
}

/// Five boxes plus the label and points in words, so heat never depends on colour alone.
struct HeatMeterView: View {
    let stars: Int
    let label: String
    let points: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < stars ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(i < stars ? Palette.magenta : Palette.cream.opacity(0.35))
                }
            }
            Text("\(label) \(points)").pixelLabel(.caption2, color: stars > 0 ? Palette.magenta : Palette.cream.opacity(0.7))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Palette.ink.opacity(0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heat: \(stars) of 5 stars, \(label)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Hull points as blocks plus "HULL 3/5" in words.
struct HullView: View {
    let hull: Int
    let max: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("Hull \(hull)/\(max)").pixelLabel(.caption2, color: hull <= 1 ? Palette.sunset : Palette.cream)
            HStack(spacing: 2) {
                ForEach(0..<max, id: \.self) { i in
                    Rectangle()
                        .fill(i < hull ? (hull <= 1 ? Palette.sunset : Palette.teal) : Palette.asphaltLight)
                        .frame(width: 5, height: 9)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Palette.ink.opacity(0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hull \(hull) of \(max)")
    }
}

/// Short urgent message in the middle of the HUD. VoiceOver announces it when it appears.
struct NoticeBanner: View {
    let text: String
    /// 0...1 fills a bar under the text (used for the bust meter).
    let urgency: Double

    var body: some View {
        VStack(spacing: 4) {
            Text(text).pixelLabel(.headline, color: Palette.ink)
            if urgency > 0.05 {
                GeometryReader { geo in
                    Rectangle().fill(Palette.ink.opacity(0.25))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Palette.ink).frame(width: geo.size.width * min(1, urgency))
                        }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.sunset)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

/// Health on foot as a bar plus "HP 80" in words.
struct HealthView: View {
    let health: Int

    var body: some View {
        let low = health <= 25
        HStack(spacing: 4) {
            Text("HP \(health)").pixelLabel(.caption2, color: low ? Palette.sunset : Palette.cream)
            Rectangle().fill(Palette.asphaltLight)
                .frame(width: 40, height: 7)
                .overlay(alignment: .leading) {
                    Rectangle().fill(low ? Palette.sunset : Palette.teal)
                        .frame(width: 40 * CGFloat(max(0, min(100, health))) / 100)
                }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Palette.ink.opacity(0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health \(health) of 100")
    }
}

/// The equipped weapon and its ammo. Tap to switch weapons when you carry more than one.
struct WeaponChip: View {
    let name: String?
    let ammo: Int
    var cap: Int? = nil
    var melee = false
    let canCycle: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if canCycle { Image(systemName: "arrow.triangle.2.circlepath").font(.caption2.weight(.bold)) }
                Text("\(shortName) \(rounds)").pixelLabel(.caption2, color: !melee && ammo == 0 ? Palette.sunset : Palette.cream)
            }
            .foregroundStyle(Palette.sunset)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
            .background(Palette.ink.opacity(0.75))
            .overlay(Rectangle().strokeBorder(Palette.sunset.opacity(0.7), lineWidth: 1))
        }
        .disabled(!canCycle)
        .accessibilityLabel(melee ? "\(name ?? "Melee weapon"), never runs out"
                                  : "\(name ?? "No weapon"), \(ammo) rounds\(cap.map { " of a \($0)-round starter limit" } ?? "")")
        .accessibilityHint(canCycle ? "Switches to your next weapon" : "")
        .accessibilityIdentifier("hud.weapon")
    }

    private var rounds: String {
        if melee { return "∞" }
        return cap.map { "\(ammo)/\($0)" } ?? "\(ammo)"
    }

    private var shortName: String {
        (name ?? "Unarmed").components(separatedBy: " ").first?.uppercased() ?? "GUN"
    }
}

/// Someone is on the phone to Harbor Patrol about the player.
struct WitnessChip: View {
    let count: Int

    var body: some View {
        Label(count == 1 ? "Witness" : "\(count) witnesses", systemImage: "phone.fill")
            .font(.pixel(.caption2))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Palette.sunset)
            .accessibilityLabel(count == 1 ? "A witness is calling Harbor Patrol"
                                           : "\(count) witnesses are calling Harbor Patrol")
    }
}
