import SwiftUI
import GameCore

/// Landscape readouts around the edge of the street: minimap, health and the speed dial on the
/// left; the objective beside the map; the clock in the middle; pause and heat on the right.
/// Every value is also written in words, so nothing depends on colour alone.
struct HUDView: View {
    let hud: HUDState
    let district: District
    let onPause: () -> Void
    var onCycleWeapon: () -> Void = {}
    /// Classic controls have no weapon bar, so the HUD shows the weapon chip instead.
    var showWeaponChip = false
    /// Pull out the phone (Aurora FM).
    var onPhone: () -> Void = {}
    /// On foot: switch between 2nd, 1st and 3rd person.
    var onView: () -> Void = {}
    /// Street-level 3D on or off.
    var onToggle3D: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                MinimapView(hud: hud, district: district)
                if hud.onFoot {
                    HealthView(health: hud.health)
                } else {
                    HullView(hull: hud.hull, max: hud.hullMax)
                    SpeedDial(speed: hud.speed, fraction: hud.speedFraction)
                        .accessibilityLabel("\(hud.vehicleName ?? "Car"), speed \(hud.speed)")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                objectiveBanner
                if hud.isDrifting || hud.driftScore > 0 { driftBadge }
                // Notices sit up here, beside the map, so they never cover the player.
                if let seconds = hud.copWarning {
                    CopWarningBanner(seconds: seconds, surrender: hud.surrenderFraction)
                } else if hud.copsFiring {
                    CopWarningBanner(seconds: nil, surrender: hud.surrenderFraction)
                }
                if let notice = hud.notice {
                    NoticeBanner(text: notice, urgency: hud.bustFraction)
                }
            }
            .frame(maxWidth: 270, alignment: .leading)
            Spacer(minLength: 4)
            if let time = hud.timeRemaining { TimerBox(seconds: time) }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                Button(action: onPause) {
                    Image(systemName: "line.3.horizontal")
                        .font(.title2.weight(.black))
                        .foregroundStyle(Palette.cream)
                        .frame(width: 48, height: 44)
                        .background(Palette.ink.opacity(0.6))
                        .overlay(Rectangle().strokeBorder(Palette.magenta, lineWidth: 2))
                }
                .accessibilityLabel("Pause")
                .accessibilityIdentifier("hud.pause")
                HeatMeterView(stars: hud.heatStars, label: hud.heatLabel, points: hud.heatPoints)
                NowPlayingChip(onTap: onPhone)
                HStack(spacing: 6) {
                    Button(action: onToggle3D) {
                        Text(hud.is3D ? "3D" : "2D")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 44, height: 30)
                            .background(hud.is3D ? Palette.sunset : Palette.cream, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hud.is3D ? "Street view, 3D. Switch to top-down" : "Top-down view. Switch to 3D street view")
                    .accessibilityIdentifier("hud.3d")
                    if hud.onFoot {
                        Button(action: onView) {
                            HStack(spacing: 4) {
                                Image(systemName: hud.footView == .overhead ? "map" : hud.footView == .eyes ? "eye" : "person.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("VIEW \(hud.footView.short)").font(.system(size: 11, weight: .heavy, design: .rounded))
                            }
                            .foregroundStyle(Palette.cream)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(Palette.ink.opacity(0.65), in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.teal.opacity(0.8), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Camera: \(hud.footView.label). Switch view")
                        .accessibilityIdentifier("hud.view")
                    }
                }
                if hud.witnessCalls > 0 { WitnessChip(count: hud.witnessCalls) }
                if showWeaponChip && hud.weaponCount > 0 {
                    WeaponChip(name: hud.weaponName, ammo: hud.ammo, cap: hud.ammoCap, melee: hud.isMelee,
                               canCycle: hud.weaponCount > 1, onTap: onCycleWeapon)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var objectiveBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hud.objective)
                .font(.pixel(.footnote))
                .foregroundStyle(Palette.cream)
                .fixedSize(horizontal: false, vertical: true)
            if let km = hud.jobDistance, km >= 1, let bearing = hud.targetBearing {
                Text(String(format: "%.1f km %@", km, bearing))
                    .font(.pixel(.footnote))
                    .foregroundStyle(Palette.teal)
            } else if let metres = hud.targetMetres, let bearing = hud.targetBearing {
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

/// The car's speed as a racing dial: a sweep of segments that light up as you go faster
/// (teal, then sunset near the top end) around the number.
struct SpeedDial: View {
    let speed: Int
    let fraction: Double
    private let segments = 24
    private let size: CGFloat = 92

    var body: some View {
        let lit = Int((max(0, min(1, fraction)) * Double(segments)).rounded())
        ZStack {
            Circle().fill(Palette.ink.opacity(0.55))
            ForEach(0..<segments, id: \.self) { i in
                let hot = i >= segments * 3 / 4
                Capsule()
                    .fill(i < lit ? (hot ? Palette.sunset : Palette.teal) : Palette.cream.opacity(0.18))
                    .frame(width: 3.5, height: hot ? 11 : 8)
                    .offset(y: -size / 2 + 9)
                    .rotationEffect(.degrees(-135 + Double(i) * 270 / Double(segments - 1)))
            }
            VStack(spacing: -2) {
                Text("\(speed)")
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Palette.cream)
                    .minimumScaleFactor(0.6)
                Text("SPD").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(Palette.teal)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Palette.teal.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.updatesFrequently)
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
/// patrols that are after you as magenta dots. On Solara's big map it shows the area around
/// you (about 40 tiles across) and pins off-screen targets to the edge.
struct MinimapView: View {
    let hud: HUDState
    let district: District
    private let side: CGFloat = 92

    var body: some View {
        if district.isLarge { localMap } else { wholeMap }
    }

    private var wholeMap: some View {
        // Fit inside a square so a tall district doesn't push the HUD down.
        let ratio = CGFloat(district.rows) / CGFloat(district.cols)
        let width = ratio > 1 ? side / ratio : side
        let height = ratio > 1 ? side : side * ratio
        return Image(uiImage: DistrictArt.mapImage(for: district, scale: 4))
            .resizable()
            .interpolation(.none)
            .frame(width: width, height: height)
            .overlay {
                Canvas { context, size in
                    draw(context, size: size) { p in CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height) }
                }
            }
            .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.8), lineWidth: 2))
            .accessibilityHidden(true)  // the objective banner speaks the same information
    }

    /// Points per tile on the local map.
    private var tilePoints: CGFloat { side / 40 }

    private var localMap: some View {
        let fullW = CGFloat(district.cols) * tilePoints, fullH = CGFloat(district.rows) * tilePoints
        let car = hud.mapCar
        let ox = side / 2 - car.x * fullW, oy = side / 2 - (1 - car.y) * fullH
        return ZStack(alignment: .topLeading) {
            Image(uiImage: DistrictArt.mapImage(for: district, scale: 2))
                .resizable()
                .interpolation(.none)
                .frame(width: fullW, height: fullH)
                .offset(x: ox, y: oy)
            Canvas { context, size in
                draw(context, size: size, clampTargets: true) { p in
                    CGPoint(x: size.width / 2 + (p.x - car.x) * fullW, y: size.height / 2 + (car.y - p.y) * fullH)
                }
            }
            .frame(width: side, height: side)
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .clipped()
        .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.8), lineWidth: 2))
        .accessibilityHidden(true)
    }

    private func draw(_ context: GraphicsContext, size: CGSize, clampTargets: Bool = false,
                      _ place: (CGPoint) -> CGPoint) {
        for patrol in hud.mapPatrols {
            let p = place(patrol)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                         with: .color(Palette.magenta))
        }
        for target in hud.mapTargets {
            var p = place(target)
            if clampTargets {
                p.x = min(max(p.x, 6), size.width - 6)
                p.y = min(max(p.y, 6), size.height - 6)
            }
            context.fill(Path(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(Palette.teal))
            context.stroke(Path(CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                           with: .color(Palette.ink), lineWidth: 1)
        }
        let c = place(hud.mapCar)
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
            Text(text).pixelLabel(.footnote, color: Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.sunset.opacity(0.94))
        .fixedSize(horizontal: false, vertical: true)
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

/// Harbor Patrol on foot: the "Freeze!" countdown, then "shots fired". Standing still gives up.
struct CopWarningBanner: View {
    let seconds: Int?
    let surrender: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(seconds == nil ? Palette.magenta : Palette.sunset)
                if let seconds {
                    Text("FREEZE! \(seconds)").font(.pixel(.headline)).foregroundStyle(Palette.cream)
                        .contentTransition(.numericText())
                } else {
                    Text("SHOTS FIRED").font(.pixel(.headline)).foregroundStyle(Palette.magenta)
                }
            }
            Text(seconds == nil ? "Run, take cover, or stand still to give up"
                                : "Stand still to give up. Run or shoot and they fire")
                .font(.pixel(.caption2))
                .foregroundStyle(Palette.cream.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            if surrender > 0.02 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Palette.ink
                        Palette.teal.frame(width: geo.size.width * surrender)
                    }
                }
                .frame(height: 5)
                .accessibilityLabel("Giving up, \(Int(surrender * 100)) percent")
            }
        }
        .padding(8)
        .background(Palette.ink.opacity(0.82))
        .overlay(Rectangle().strokeBorder(seconds == nil ? Palette.magenta : Palette.sunset, lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hud.copWarning")
    }
}
