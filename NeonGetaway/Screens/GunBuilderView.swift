import SwiftUI
import GameCore

/// Bolt & Barrel's Workbench for one gun: a part in each slot (buy once, swap free) and a
/// finish colour. The stat bars show stock against built, so every choice is a trade-off.
struct GunBuilderView: View {
    @Environment(AppModel.self) private var model
    let weapon: WeaponID
    let onDone: () -> Void
    @State private var message: String?

    var body: some View {
        let inv = model.progress.inventory
        let build = inv.build(for: weapon)
        let built = inv.spec(for: weapon)
        let stock = weapon.spec
        OverlayBackdrop {
            VStack(alignment: .leading, spacing: 16) {
                Text("Workbench").pixelLabel(.caption, color: Palette.teal)
                Text(stock.name).pixelLabel(.largeTitle, color: Palette.sunset)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer()
                    Image(uiImage: PixelArt.weaponImage(weapon, finish: build.finish, scale: 9))
                        .interpolation(.high)
                        .accessibilityLabel("\(stock.name) in \(PixelArt.finishNames[build.finish]) finish")
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(Palette.ink.opacity(0.7))
                .overlay(Rectangle().strokeBorder(Palette.sunset.opacity(0.6), lineWidth: 2))
                HStack { Fact(label: "Credits", value: "\(model.progress.credits)"); Spacer() }

                if !stock.isMelee {
                    VStack(spacing: 6) {
                        CompareBar(label: "Reach", stock: stock.range / 820, built: built.range / 820)
                        CompareBar(label: "Speed", stock: min(1, (1 / stock.fireInterval) / 11),
                                   built: min(1, (1 / built.fireInterval) / 11))
                        CompareBar(label: "Aim", stock: stock.aimHalfAngle / 1.2, built: built.aimHalfAngle / 1.2)
                        CompareBar(label: "Ammo", stock: Double(inv.isCapped(weapon) ? Inventory.starterAmmoCap : stock.maxAmmo) / 450,
                                   built: Double(inv.ammoCap(for: weapon)) / 450)
                    }
                    ForEach(GunPart.Slot.allCases, id: \.self) { slot in
                        slotRow(slot, build: build)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Finish · \(GunBuild.finishPrice) cr").pixelLabel(.caption, color: Palette.teal)
                    HStack(spacing: 8) {
                        ForEach(0..<GunBuild.finishCount, id: \.self) { i in
                            Button {
                                message = text(model.paint(weapon, finish: i))
                            } label: {
                                Rectangle().fill(Color(uiColor: PixelArt.finishColors[i]))
                                    .frame(width: 30, height: 30)
                                    .overlay(Rectangle().strokeBorder(i == build.finish ? Palette.cream : Palette.ink,
                                                                      lineWidth: i == build.finish ? 4 : 2))
                                    .frame(minWidth: 36, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(PixelArt.finishNames[i]) finish")
                            .accessibilityAddTraits(i == build.finish ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }

                if let message {
                    Text(message).pixelLabel(.footnote, color: Palette.sunset)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Parts are bought once per gun; swap between owned parts for free. Mods are a business cost in your ledger.")
                    .font(.pixel(.footnote, weight: .medium))
                    .foregroundStyle(Palette.cream.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Done", action: onDone)
                    .buttonStyle(.neon(Palette.teal))
                    .accessibilityIdentifier("workbench.done")
            }
        }
    }

    private func slotRow(_ slot: GunPart.Slot, build: GunBuild) -> some View {
        let options = GunPart.allCases.filter { $0.slot == slot }
        return VStack(alignment: .leading, spacing: 6) {
            Text(slot.rawValue.capitalized).pixelLabel(.caption, color: Palette.teal)
            HStack(spacing: 8) {
                partButton(nil, slot: slot, build: build)
                ForEach(options, id: \.self) { part in
                    partButton(part, slot: slot, build: build)
                }
            }
            if let current = build.installed(slot) {
                Text(current.effect).pixelLabel(.caption2, color: Palette.cream.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func partButton(_ part: GunPart?, slot: GunPart.Slot, build: GunBuild) -> some View {
        let installed = build.installed(slot) == part
        let owned = part.map { build.owned.contains($0) } ?? true
        let title = part?.name ?? "Stock"
        return Button {
            message = text(model.fit(part, slot: slot, on: weapon))
        } label: {
            VStack(spacing: 2) {
                Text(title).pixelLabel(.caption, color: installed ? Palette.ink : Palette.cream)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(owned ? (installed ? "Fitted" : "Owned") : "\(part!.price) cr")
                    .pixelLabel(.caption2, color: installed ? Palette.ink.opacity(0.7) : Palette.sunset)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 4)
            .background(installed ? Palette.teal : Palette.ink.opacity(0.6))
            .overlay(Rectangle().strokeBorder(installed ? Palette.teal : Palette.cream.opacity(0.3), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(part.map { "\($0.name): \($0.effect)" } ?? "Stock \(slot.rawValue)")
        .accessibilityValue(installed ? "Fitted" : (owned ? "Owned" : "\(part!.price) credits"))
        .accessibilityIdentifier("workbench.\(slot.rawValue).\(part?.rawValue ?? "stock")")
    }

    private func text(_ refusal: Workbench.Refusal?) -> String? {
        switch refusal {
        case nil: nil
        case .notEnoughCredits(let needed): "You need \(needed) more credits."
        case .notOwned: "You don't own that gun."
        case .doesNotFit: "That part doesn't fit."
        case .badFinish: "Pick a finish from the row."
        }
    }
}

/// Stock (outline) against built (filled), so a trade-off reads at a glance.
private struct CompareBar: View {
    let label: String
    let stock: Double
    let built: Double

    var body: some View {
        let s = max(0.05, min(1, stock)), b = max(0.05, min(1, built))
        HStack(spacing: 8) {
            Text(label).pixelLabel(.caption, color: Palette.cream.opacity(0.7))
                .frame(width: 56, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.cream.opacity(0.1))
                    Rectangle().fill(b >= s ? Palette.teal : Palette.sunset).frame(width: geo.size.width * b)
                    Rectangle().strokeBorder(Palette.cream.opacity(0.7), lineWidth: 1).frame(width: geo.size.width * s)
                }
            }
            .frame(height: 12)
            Text(b > s + 0.005 ? "▲" : (b < s - 0.005 ? "▼" : "="))
                .pixelLabel(.caption2, color: b >= s ? Palette.teal : Palette.sunset)
                .frame(width: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(b > s + 0.005 ? "better than stock" : (b < s - 0.005 ? "worse than stock" : "same as stock"))")
    }
}
