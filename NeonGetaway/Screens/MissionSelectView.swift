import SwiftUI
import GameCore

struct MissionSelectView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @AppStorage("neon.lastJob") private var selected: MissionID = .coldCrate

    private let district = District.portAuroraDocks

    private func isUnlocked(_ def: MissionDef) -> Bool {
        DebugLaunch.unlockAll || ProgressionRules.isUnlocked(def, progress: model.progress)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(title: "Port Aurora") { router.back() }
                statusRow
                SolaraCard { router.go(.drive(.state)) }
                    .padding(.horizontal, 20)
                ChallengeCard { router.go(.drive(.mission(.streetChallenge))) }
                    .padding(.horizontal, 20)
                CityMapView(district: district, selected: $selected, isUnlocked: isUnlocked)
                    .padding(.horizontal, 20)
                JobStrip(selected: $selected, isUnlocked: isUnlocked,
                         bests: model.progress.missionBests)
                if let def = MissionDef.with(selected) {
                    JobCard(def: def, best: model.progress.missionBests[def.id.rawValue],
                            unlocked: isUnlocked(def)) {
                        router.go(.drive(.mission(def.id)))
                    }
                    .padding(.horizontal, 20)
                }
                Button("Free roam") { router.go(.drive(.freeDrive)) }
                    .buttonStyle(.neon(Palette.sunset))
                    .accessibilityHint("Drive or walk around the district with no job or timer")
                    .accessibilityIdentifier("map.freeDrive")
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
            }
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }

    private var statusRow: some View {
        let xp = model.progress.reputationXP
        let next = ProgressionRules.xpToNextLevel(xp)
        let nextJob = MissionDef.all.first { $0.requiredRepLevel == model.repLevel + 1 }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Credits").pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
                Text("\(model.progress.credits)").pixelLabel(.title3, color: Palette.sunset)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.progress.credits) credits")
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Rep level \(model.repLevel)").pixelLabel(.callout, color: Palette.teal)
                Text(next.map { xp in nextJob.map { "\(xp) XP to \($0.title)" } ?? "\(xp) XP to next" } ?? "Top level")
                    .pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 24)
    }
}

/// The weekly Street Challenge: this week's route, Nova's time, your best and medal, and how long
/// until the route changes.
struct ChallengeCard: View {
    @Environment(AppModel.self) private var model
    let onRace: () -> Void

    var body: some View {
        let state = model.challengeState
        let rival = model.challengeRival().duration
        let def = StreetChallenge.def(week: model.challengeWeek)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Street Challenge", systemImage: "flag.checkered")
                    .pixelLabel(.headline, color: Palette.magenta)
                Spacer()
                Text(resetsIn).pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
            }
            Text("\(def.objectives.count) checkpoints in order. New route every Monday.")
                .pixelLabel(.caption, color: Palette.cream.opacity(0.8))
            HStack(spacing: 18) {
                Fact(label: StreetChallenge.rivalName, value: String(format: "%.1f s", rival))
                Fact(label: "Your best", value: state.bestTime.map { String(format: "%.1f s", $0) } ?? "—")
                Fact(label: "Medal", value: state.medal?.label ?? "—")
            }
            Button("Race the ghosts", action: onRace)
                .buttonStyle(.neon(Palette.magenta))
                .accessibilityHint("A time trial against Nova's ghost and your own best run")
                .accessibilityIdentifier("map.challenge")
        }
        .padding(14)
        .background(Palette.ink.opacity(0.6))
        .overlay(Rectangle().strokeBorder(Palette.magenta.opacity(0.7), lineWidth: 2))
    }

    private var resetsIn: String {
        let left = max(0, StreetChallenge.ends(week: model.challengeWeek).timeIntervalSinceNow)
        let days = Int(left / 86_400), hours = Int(left.truncatingRemainder(dividingBy: 86_400) / 3600)
        return days > 0 ? "New route in \(days)d \(hours)h" : "New route in \(hours)h"
    }
}

/// One chip per job, in map order, scrolling sideways. Locked jobs show the rep they need.
struct JobStrip: View {
    @Binding var selected: MissionID
    let isUnlocked: (MissionDef) -> Bool
    let bests: [String: MissionBest]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(MissionDef.all.enumerated()), id: \.element.id) { index, def in
                        chip(def, number: index + 1)
                            .id(def.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, id in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func chip(_ def: MissionDef, number: Int) -> some View {
        let unlocked = isUnlocked(def)
        let isSelected = def.id == selected
        let done = bests[def.id.rawValue] != nil
        return Button { selected = def.id } label: {
            HStack(spacing: 8) {
                MapPin(label: "\(number)", color: CityMapView.pinColor(def.kind), selected: false,
                       locked: !unlocked, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(def.title).pixelLabel(.callout, color: unlocked ? Palette.cream : Palette.cream.opacity(0.55))
                        .lineLimit(1)
                    Text(unlocked ? (done ? "Done ✓" : def.kind.label) : "Rep \(def.requiredRepLevel)")
                        .pixelLabel(.caption2, color: unlocked ? Palette.teal : Palette.sunset)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(minHeight: 48)
            .background(isSelected ? Palette.asphaltLight : Palette.ink.opacity(0.5))
            .overlay(Rectangle().strokeBorder(isSelected ? Palette.cream : CityMapView.pinColor(def.kind).opacity(0.5),
                                              lineWidth: isSelected ? 3 : 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Job \(number), \(def.title), \(def.kind.label)")
        .accessibilityValue(unlocked ? (done ? "Completed" : "Open") : "Locked, needs rep level \(def.requiredRepLevel)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("job.\(def.id.rawValue)")
    }
}

/// The district map with job pins. Tapping a playable pin selects it.
struct CityMapView: View {
    let district: District
    @Binding var selected: MissionID
    var isUnlocked: (MissionDef) -> Bool = { _ in true }

    var body: some View {
        let image = DistrictArt.mapImage(for: district, scale: 8)
        let bounds = district.bounds
        Image(uiImage: image)
            .resizable()
            .interpolation(.none)
            .aspectRatio(CGFloat(district.cols) / CGFloat(district.rows), contentMode: .fit)
            .frame(maxHeight: 420)
            .overlay {
                GeometryReader { geo in
                    let place = { (p: Vec2) -> CGPoint in
                        CGPoint(x: p.x / bounds.width * geo.size.width,
                                y: (1 - p.y / bounds.height) * geo.size.height)
                    }
                    ForEach(Array(MissionDef.all.enumerated()), id: \.element.id) { index, def in
                        let isSelected = def.id == selected
                        let unlocked = isUnlocked(def)
                        if isSelected, let drop = def.objectives.first?.zones.first,
                           let zone = district.zones[drop] {
                            Image(systemName: "flag.fill")
                                .font(.title3)
                                .foregroundStyle(Palette.teal)
                                .shadow(color: .black, radius: 2)
                                .position(place(zone.rect.center))
                                .accessibilityHidden(true)
                        }
                        Button { selected = def.id } label: {
                            MapPin(label: "\(index + 1)", color: Self.pinColor(def.kind), selected: isSelected,
                                   locked: !unlocked)
                        }
                        .position(place(def.start.position))
                        .zIndex(isSelected ? 1 : 0)
                        .accessibilityLabel("Job \(index + 1), \(def.title)")
                        .accessibilityValue(unlocked ? def.kind.label : "Locked")
                        .accessibilityIdentifier("pin.\(def.id.rawValue)")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                    // Map labels are part of the picture: a fixed size, like the pins.
                    Text("SAFEHOUSE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 3)
                        .background(Palette.sunset)
                        .fixedSize()
                        .position(place(district.zones[.safehouse]!.rect.center + Vec2(-150, 250)))
                        .accessibilityHidden(true)
                }
            }
            .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.7), lineWidth: 2))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Map of Port Aurora Docks")
    }
}

extension CityMapView {
    /// Pin colour by job type; the number on the pin is the job's place on the map list.
    static func pinColor(_ kind: MissionKind) -> Color {
        switch kind {
        case .timedDelivery: Palette.magenta
        case .escape: Palette.sunset
        case .pickupRun: Palette.teal
        case .double: Palette.cream
        }
    }
}

/// A square job pin. Locked jobs are dimmed with a padlock in place of the number, so the
/// state reads without relying on colour.
struct MapPin: View {
    let label: String
    let color: Color
    let selected: Bool
    var locked = false
    var size: CGFloat = 30

    var body: some View {
        Group {
            if locked {
                Image(systemName: "lock.fill").font(.system(size: size * 0.45, weight: .black))
            } else {
                Text(label).font(.system(size: size * 0.53, weight: .black, design: .monospaced))
            }
        }
        .foregroundStyle(Palette.ink)
        .frame(width: size, height: size)
        .background(locked ? color.opacity(0.45) : color)
        .overlay(Rectangle().strokeBorder(selected ? Palette.cream : Palette.ink, lineWidth: selected ? 3 : 2))
        .scaleEffect(selected ? 1.15 : 1)
        .frame(width: max(44, size), height: max(44, size))
        .contentShape(Rectangle())
    }
}

struct JobCard: View {
    let def: MissionDef
    let best: MissionBest?
    let unlocked: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(def.title).pixelLabel(.title2, color: Palette.magenta)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(def.kind.label).pixelLabel(.caption, color: Palette.teal)
            }
            Text(def.brief)
                .font(.pixel(.callout, weight: .medium))
                .foregroundStyle(Palette.cream)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                if let limit = def.timeLimit {
                    Fact(label: def.clockedObjectives == nil ? "Time" : "Drop clock", value: "\(Int(limit)) s")
                } else {
                    Fact(label: "Starts", value: "\(HeatRules.stars(for: def.startingHeat))★ heat")
                }
                Fact(label: "Pay", value: "\(def.baseReward) cr +")
                Fact(label: "Best", value: best.flatMap { $0.bestTime }.map { String(format: "%.1f s", $0) } ?? "—")
            }
            if def.startingHeat > 0 && def.kind != .escape {
                Label("Starts with \(HeatRules.stars(for: def.startingHeat))★ heat", systemImage: "exclamationmark.triangle.fill")
                    .font(.pixel(.footnote, weight: .medium))
                    .foregroundStyle(Palette.sunset)
            }
            Button(unlocked ? "Start job" : "Locked: rep \(def.requiredRepLevel)", action: onStart)
                .buttonStyle(.neon(Palette.magenta))
                .disabled(!unlocked)
                .accessibilityIdentifier("map.startJob")
        }
        .padding(16)
        .background(Palette.ink.opacity(0.6))
        .overlay(Rectangle().strokeBorder(Palette.magenta.opacity(0.7), lineWidth: 2))
    }
}

struct Fact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
            Text(value).pixelLabel(.callout, color: Palette.cream)
        }
        .accessibilityElement(children: .combine)
    }
}
