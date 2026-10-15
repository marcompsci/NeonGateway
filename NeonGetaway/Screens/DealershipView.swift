import SwiftUI
import GameCore

/// Buy cars, claim exclusive builds, and drive off with legends won from races.
struct DealershipView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var tier: CarTier = .dealer
    @State private var message: String?

    private let tiers: [CarTier] = [.dealer, .exclusive, .legendary]

    var body: some View {
        let p = model.progress
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Dealership") { router.back() }
                Picker("Showroom", selection: $tier) {
                    ForEach(tiers, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("dealer.tier")
                Text(intro).pixelLabel(.caption, color: Palette.cream.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Fact(label: "Cash", value: "\(p.credits)")
                    Spacer()
                    Fact(label: "Garage", value: "\(p.garage.count)/\(GarageRules.slots)")
                    Spacer()
                    Fact(label: "Golds", value: "\(p.challenge.golds)")
                }
                if let message {
                    Text(message).pixelLabel(.footnote, color: Palette.sunset)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("dealer.message")
                }
                ForEach(CarLineup.all.filter { $0.tier == tier }) { entry in
                    CarCard(entry: entry) { act(entry) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }

    private var intro: String {
        switch tier {
        case .dealer: "New cars from every maker in Solara. Pay once and they're yours, with your garage upgrades on top."
        case .exclusive: "Limited builds with special trim. One each, and only for drivers with the reputation."
        case .legendary: "Never for sale. Beat Nova's ghost in the weekly Street Challenge for golds and these classics are yours."
        default: ""
        }
    }

    private func act(_ entry: CarEntry) {
        switch model.acquireCar(entry.model) {
        case nil:
            message = entry.tier == .legendary ? "The \(entry.model.spec.displayName) is in your garage. Drive it with pride."
                                                : "Bought the \(entry.model.spec.displayName). It's in your garage and ready to drive."
        case .needsRep(let level): message = "Reach rep level \(level) first."
        case .needsGolds(let n): message = "Win \(n) more Street Challenge gold\(n == 1 ? "" : "s")."
        case .notEnoughCredits(let short): message = "You need \(short) more credits."
        case .garageFull: message = "Your garage is full. Sell a car in the garage first."
        case .alreadyOwned: message = "You already own this one."
        case .notForSale: message = "Not for sale."
        }
    }
}

private struct CarCard: View {
    @Environment(AppModel.self) private var model
    let entry: CarEntry
    let onAct: () -> Void

    var body: some View {
        let p = model.progress
        let refusal = CarLineup.check(entry.model, progress: p)
        let spec = entry.model.spec
        let colour: Color = switch entry.tier {
        case .exclusive: Palette.magenta
        case .legendary: Color(hex: 0xE2B13C)
        default: Palette.teal
        }
        HStack(alignment: .top, spacing: 12) {
            Image(uiImage: HDArt.vehiclePreview(entry.model, design: nil, height: 110))
                .frame(width: 72, height: 116)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.brand.rawValue.uppercased()).pixelLabel(.caption2, color: colour)
                Text(spec.displayName).pixelLabel(.headline, color: Palette.cream)
                Text(entry.blurb).pixelLabel(.caption, color: Palette.cream.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                StatBars(spec: spec)
                HStack {
                    Text(priceText).pixelLabel(.callout, color: colour)
                    Spacer()
                    Button(buttonTitle(refusal), action: onAct)
                        .buttonStyle(.neon(refusal == nil ? colour : Palette.cream.opacity(0.35)))
                        .frame(maxWidth: 150)
                        .disabled(refusal == .alreadyOwned)
                        .accessibilityIdentifier("dealer.buy.\(entry.model.rawValue)")
                }
            }
        }
        .padding(12)
        .background(Palette.ink.opacity(0.55))
        .overlay(Rectangle().strokeBorder(colour.opacity(0.6), lineWidth: 2))
        .accessibilityElement(children: .contain)
    }

    private var priceText: String {
        entry.tier == .legendary ? "\(entry.golds) gold\(entry.golds == 1 ? "" : "s")" : "\(entry.price.formatted()) cr"
    }

    private func buttonTitle(_ refusal: CarLineup.Refusal?) -> String {
        switch refusal {
        case nil: entry.tier == .legendary ? "Claim" : "Buy"
        case .alreadyOwned: "Owned"
        case .needsRep(let l): "Rep \(l)"
        case .needsGolds: "Locked"
        case .garageFull: "Garage full"
        default: "Buy"
        }
    }
}

/// Top speed, acceleration, handling and toughness as bars (and words for VoiceOver).
struct StatBars: View {
    let spec: VehicleSpec

    var body: some View {
        let rows: [(String, Double)] = [
            ("Speed", (spec.maxSpeed - 380) / 360),
            ("Accel", (spec.acceleration - 200) / 340),
            ("Handling", (spec.turnRate - 2.2) / 1.5),
            ("Tough", Double(spec.maxIntegrity) / 12)
        ]
        VStack(spacing: 3) {
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 6) {
                    Text(row.0).font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.cream.opacity(0.7))
                        .frame(width: 56, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Palette.ink
                            Palette.teal.frame(width: geo.size.width * min(1, max(0.06, row.1)))
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rows.map { "\($0.0) \(Int(min(1, max(0, $0.1)) * 10)) of 10" }.joined(separator: ", "))
    }
}
