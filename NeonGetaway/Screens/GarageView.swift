import SwiftUI
import GameCore

/// Your cars and their upgrades: pick which one you start in, sell extras, and spend credits on
/// three upgrade tracks (four levels each, gated by reputation) that apply to every car you own.
struct GarageView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var lastMessage: String?

    var body: some View {
        let spec = model.playerSpec
        ScrollView {
            VStack(spacing: 18) {
                ScreenHeader(title: "Garage") { router.back() }
                Image(uiImage: PixelArt.vehicleImage(model.progress.selectedModel, design: model.selectedDesign, scale: 7,
                                                     rims: model.selectedCar?.rims))
                    .interpolation(.none)
                    .accessibilityHidden(true)
                Text(spec.displayName).pixelLabel(.title2)
                    .accessibilityLabel("Driving: \(spec.displayName)")
                OwnedCarsStrip(lastMessage: $lastMessage)
                if !CarLineup.unclaimedLegends(model.progress).isEmpty {
                    Button("A legend is waiting for you: claim it") { router.go(.dealership) }
                        .buttonStyle(.neon(Color(hex: 0xE2B13C)))
                        .padding(.horizontal, 40)
                        .accessibilityIdentifier("garage.claimLegend")
                }
                HStack(spacing: 10) {
                    garageTile("Dealership", icon: "car.2.fill", color: Palette.teal, id: "garage.dealership") { router.go(.dealership) }
                    garageTile("Wheels", icon: "circle.hexagongrid.circle", color: Palette.sunset, id: "garage.rims") { router.go(.rims) }
                    garageTile(mechanicNeedsWork ? "Mechanic !" : "Mechanic", icon: "wrench.and.screwdriver.fill",
                               color: mechanicNeedsWork ? Palette.magenta : Palette.cream, id: "garage.mechanic") { router.go(.mechanic) }
                }
                .padding(.horizontal, 20)
                Button("Body shop: paint & designs") { router.go(.bodyShop) }
                    .buttonStyle(.neon(Palette.magenta))
                    .padding(.horizontal, 40)
                    .accessibilityIdentifier("garage.bodyShop")
                HStack(spacing: 22) {
                    Fact(label: "Credits", value: "\(model.progress.credits)")
                    Fact(label: "Rep", value: "Level \(model.repLevel)")
                    Fact(label: "Top speed", value: "\(Int((spec.maxSpeed * 0.3).rounded()))")
                    Fact(label: "Hull", value: "\(spec.maxIntegrity)")
                }
                VStack(spacing: 14) {
                    ForEach(UpgradeTrack.allCases, id: \.self) { track in
                        UpgradeRow(track: track, progress: model.progress) {
                            lastMessage = message(for: track, result: model.buy(track))
                        }
                    }
                }
                .padding(.horizontal, 20)
                if let lastMessage {
                    Text(lastMessage)
                        .pixelLabel(.footnote, color: Palette.sunset)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Text("Upgrades apply to every car you own. Street cars you take are stock until you park them in the Safehouse bay and tap Keep car.")
                    .font(.pixel(.footnote, weight: .medium))
                    .foregroundStyle(Palette.cream.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }

    private var mechanicNeedsWork: Bool {
        model.selectedCar.map { Mechanic.report($0).contains { $0.needsWork } } ?? false
    }

    private func garageTile(_ title: String, icon: String, color: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(color)
                Text(title).pixelLabel(.caption, color: Palette.cream)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(Palette.ink.opacity(0.6))
            .overlay(Rectangle().strokeBorder(color.opacity(0.7), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func message(for track: UpgradeTrack, result: Result<UpgradeTier, UpgradeShop.Refusal>) -> String {
        switch result {
        case .success(let tier): "\(UpgradeRow.name(track)) is now level \(tier.level)."
        case .failure(.maxed): "\(UpgradeRow.name(track)) is maxed out."
        case .failure(.needsRep(let level)): "Reach rep level \(level) to buy this."
        case .failure(.needsCredits(let short)): "You need \(short) more credits."
        }
    }
}

struct UpgradeRow: View {
    let track: UpgradeTrack
    let progress: PlayerProgress
    let onBuy: () -> Void

    static func name(_ track: UpgradeTrack) -> String {
        switch track {
        case .speed: "Speed"
        case .handling: "Handling"
        case .durability: "Durability"
        }
    }

    var body: some View {
        let level = UpgradeShop.level(track, in: progress.upgrades)
        let check = UpgradeShop.check(track, progress: progress)
        let tier = UpgradeShop.nextTier(track, levels: progress.upgrades)
        VStack(alignment: .leading, spacing: 8) {
            StatRow(name: Self.name(track), level: level)
            Text(UpgradeShop.effectText(track) + " per level")
                .font(.pixel(.caption, weight: .medium))
                .foregroundStyle(Palette.cream.opacity(0.65))
            Button(action: onBuy) {
                Text(buttonTitle(check: check, tier: tier))
            }
            .buttonStyle(.neon(isAvailable(check) ? Palette.magenta : Palette.cream.opacity(0.35)))
            .disabled(tier == nil)
            .accessibilityHint(hint(check: check))
        }
        .padding(14)
        .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.5), lineWidth: 2))
    }

    private func isAvailable(_ check: Result<UpgradeTier, UpgradeShop.Refusal>) -> Bool {
        if case .success = check { return true }
        return false
    }

    private func buttonTitle(check: Result<UpgradeTier, UpgradeShop.Refusal>, tier: UpgradeTier?) -> String {
        switch check {
        case .success(let t): "Buy level \(t.level) · \(t.cost) cr"
        case .failure(.maxed): "Maxed"
        case .failure(.needsRep(let rep)): "Level \(tier?.level ?? 0) · needs rep \(rep)"
        case .failure(.needsCredits): "Level \(tier?.level ?? 0) · \(tier?.cost ?? 0) cr"
        }
    }

    private func hint(check: Result<UpgradeTier, UpgradeShop.Refusal>) -> String {
        switch check {
        case .success: "Spends credits on the next level"
        case .failure(.maxed): "Already at the top level"
        case .failure(.needsRep(let rep)): "Locked until reputation level \(rep)"
        case .failure(.needsCredits(let short)): "\(short) more credits needed"
        }
    }
}

/// Four blocks per stat. The filled count is also spoken, so colour never carries the meaning alone.
struct StatRow: View {
    let name: String
    let level: Int
    let maxLevel = UpgradeShop.maxLevel

    var body: some View {
        HStack {
            Text(name).pixelLabel(.callout)
            Spacer()
            HStack(spacing: 4) {
                ForEach(0..<maxLevel, id: \.self) { i in
                    Rectangle()
                        .fill(i < level ? Palette.teal : Palette.asphaltLight)
                        .overlay(Rectangle().strokeBorder(Palette.teal, lineWidth: 1))
                        .frame(width: 22, height: 14)
                }
            }
            Text("\(level)/\(maxLevel)").pixelLabel(.caption, color: Palette.cream.opacity(0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), level \(level) of \(maxLevel)")
    }
}

/// Every car the player owns. Tap one to start runs in it; sell any but the starter.
struct OwnedCarsStrip: View {
    @Environment(AppModel.self) private var model
    @Binding var lastMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your cars (\(model.progress.garage.count)/\(GarageRules.slots))")
                .pixelLabel(.headline, color: Palette.teal)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(model.progress.garage.enumerated()), id: \.offset) { slot, car in
                        card(slot: slot, car: car)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func card(slot: Int, car: OwnedVehicle) -> some View {
        let selected = slot == model.progress.selectedVehicle
        return VStack(spacing: 6) {
            Button { model.selectVehicle(slot: slot) } label: {
                VStack(spacing: 4) {
                    Image(uiImage: PixelArt.vehicleImage(car.model,
                                                         design: car.design.flatMap { BodyShop.design($0, progress: model.progress) },
                                                         scale: 3, rims: car.rims))
                        .interpolation(.none)
                        .frame(height: 90)
                    Text(car.model.spec.displayName.components(separatedBy: " ").first ?? "")
                        .pixelLabel(.caption, color: Palette.cream)
                    Text(selected ? "Driving" : "Tap to drive")
                        .pixelLabel(.caption2, color: selected ? Palette.teal : Palette.cream.opacity(0.6))
                }
                .frame(width: 104)
                .padding(.vertical, 8)
                .background(selected ? Palette.asphaltLight : Palette.ink.opacity(0.5))
                .overlay(Rectangle().strokeBorder(selected ? Palette.teal : Palette.cream.opacity(0.3),
                                                  lineWidth: selected ? 3 : 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(car.model.spec.displayName)
            .accessibilityValue(selected ? "Selected" : "")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("garage.car.\(slot)")
            if slot > 0 {
                Button("Sell \(GarageRules.resaleValue(car.model))") {
                    if let paid = model.sellVehicle(slot: slot) {
                        lastMessage = "Sold for \(paid) credits. It was worth \(car.model.marketValue) new: used cars sell for less."
                    }
                }
                .font(.pixel(.caption))
                .foregroundStyle(Palette.sunset)
                .frame(minHeight: 44)
                .accessibilityHint("Sells this car for credits")
            } else {
                Text("Starter").pixelLabel(.caption2, color: Palette.cream.opacity(0.5)).frame(minHeight: 44)
            }
        }
    }
}
