import SwiftUI
import GameCore

/// Buying weapons. Bolt & Barrel (on Signal Street) sells everything plus ammo and the Extended
/// Mag mod; the alley dealer sells guns only, cheaper. Every purchase lands in the ledger.
struct GunStoreView: View {
    @Environment(AppModel.self) private var model
    var seller: GunSeller = .store
    let onLeave: () -> Void
    @State private var message: String?
    @State private var workbench: WeaponID?

    var body: some View {
        if let workbench {
            GunBuilderView(weapon: workbench) { self.workbench = nil }
        } else {
            storefront
        }
    }

    private var storefront: some View {
        OverlayBackdrop {
            VStack(alignment: .leading, spacing: 16) {
                Text(seller.name).pixelLabel(.largeTitle, color: Palette.sunset)
                    .accessibilityAddTraits(.isHeader)
                Text(seller == .store ? "Gun store · Signal Street" : "Back of the night-market lane · cash, no questions")
                    .pixelLabel(.caption, color: Palette.cream.opacity(0.6))
                HStack {
                    Fact(label: "Credits", value: "\(model.progress.credits)")
                    Spacer()
                }
                ForEach(stock, id: \.self) { weapon in
                    row(weapon)
                }
                if let message {
                    Text(message)
                        .pixelLabel(.footnote, color: Palette.sunset)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Text(seller == .store
                     ? "Starter guns hold 35 rounds until you fit an Extended Mag or buy a new one. Every purchase is a business cost in your ledger."
                     : "The dealer undercuts the store by 20%. No ammo, no mods: just guns.")
                    .font(.pixel(.footnote, weight: .medium))
                    .foregroundStyle(Palette.cream.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Back to the street", action: onLeave)
                    .buttonStyle(.neon(Palette.teal))
                    .accessibilityIdentifier("store.leave")
            }
        }
    }

    private var stock: [WeaponID] {
        seller == .store ? WeaponID.allCases : WeaponID.allCases.filter { !$0.spec.isMelee }
    }

    private func row(_ weapon: WeaponID) -> some View {
        let spec = weapon.spec
        let inv = model.progress.inventory
        let owned = inv.owns(weapon)
        let capped = inv.isCapped(weapon)
        let ammo = inv.ammo(for: weapon)
        let cap = inv.ammoCap(for: weapon)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(uiImage: PixelArt.weaponImage(weapon, finish: inv.build(for: weapon).finish, scale: 4))
                    .interpolation(.high)
                    .frame(width: 64, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.name).pixelLabel(.callout)
                    Text(statusLine(weapon, owned: owned, capped: capped, ammo: ammo, cap: cap))
                        .pixelLabel(.caption2, color: owned ? (capped ? Palette.sunset : Palette.teal) : Palette.cream.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !owned || capped {
                Button(capped ? "Buy a new one · \(seller.price(weapon)) cr" : "Buy · \(seller.price(weapon)) cr") {
                    message = text(model.buyWeapon(weapon, from: seller),
                                   success: capped ? "A fresh \(spec.name): no more 35-round limit."
                                                   : "\(spec.name) is yours. Hold FIRE on foot.")
                }
                .buttonStyle(.neon(Palette.sunset))
                .accessibilityIdentifier("store.buy.\(weapon.rawValue)")
            }
            if seller.sellsAmmoAndMods && owned {
                Button("Workbench: parts & finish") { workbench = weapon }
                    .buttonStyle(.neon(Palette.magenta))
                    .accessibilityHint("Fit barrels, magazines and grips, or paint the \(spec.name)")
                    .accessibilityIdentifier("store.workbench.\(weapon.rawValue)")
                if capped {
                    Button("Extended mag · \(GunStore.extendedMagPrice) cr") {
                        message = text(model.buyExtendedMag(weapon), success: "Extended mag fitted. Carry up to \(spec.maxAmmo) now.")
                    }
                    .buttonStyle(.neon(Palette.teal))
                    .accessibilityHint("Removes the 35-round starter limit")
                    .accessibilityIdentifier("store.mag.\(weapon.rawValue)")
                }
                if !spec.isMelee {
                    Button("Ammo +\(spec.ammoPack) · \(spec.ammoPrice) cr") {
                        message = text(model.buyAmmo(weapon), success: "Topped up.")
                    }
                    .buttonStyle(.neon(Palette.cream))
                    .disabled(ammo >= cap)
                    .accessibilityIdentifier("store.ammo.\(weapon.rawValue)")
                }
            }
        }
        .padding(12)
        .background(Palette.ink.opacity(0.5))
        .overlay(Rectangle().strokeBorder(Palette.sunset.opacity(0.5), lineWidth: 2))
    }

    private func statusLine(_ weapon: WeaponID, owned: Bool, capped: Bool, ammo: Int, cap: Int) -> String {
        let spec = weapon.spec
        if spec.isMelee { return owned ? "Owned · never runs out" : "Melee · never runs out" }
        if !owned {
            let rate = (1 / spec.fireInterval).rounded()
            return "Range \(Int(spec.range / 12.8)) m · \(Int(rate))/s · comes with \(spec.ammoPack)"
        }
        return capped ? "Starter · \(ammo)/\(cap) rounds (limit)" : "Owned · \(ammo)/\(cap) rounds"
    }

    private func text(_ refusal: GunStore.Refusal?, success: String) -> String {
        switch refusal {
        case nil: success
        case .notEnoughCredits(let needed): "You need \(needed) more credits. Jobs pay."
        case .alreadyOwned: "You already own that."
        case .notOwned: "Buy the weapon first."
        case .full: "You can't carry more of that ammo."
        case .notCapped: "That gun has no limit to lift."
        case .notSoldHere: "Not sold here."
        }
    }
}
