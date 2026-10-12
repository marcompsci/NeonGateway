import SwiftUI
import GameCore

/// Businesses for sale in Port Aurora. Each one earns every hour, even with the game closed,
/// and keeps its takings in the till until you collect. Every number a real owner would look
/// at is on the card: price, profit per hour, running costs and payback time.
struct PropertiesView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var message: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let p = model.progress
            let hustle = p.skills.level(.hustle)
            let tills = p.properties.map { Properties.till($0, hustle: hustle, now: context.date) }
            let waiting = tills.reduce(0) { $0 + $1.profit }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "Businesses") { router.back() }
                    HStack {
                        Fact(label: "Cash", value: "\(p.credits)")
                        Spacer()
                        Fact(label: "In the tills", value: "\(waiting)")
                        Spacer()
                        Fact(label: "Invested", value: "\(p.books.invested)")
                    }
                    if waiting > 0 {
                        Button("Collect everything (+\(waiting))") {
                            let till = model.collectAll()
                            message = "Took \(till.revenue) in, paid \(till.costs) in running costs: \(till.profit) profit."
                        }
                        .buttonStyle(.neon(Palette.teal))
                        .accessibilityIdentifier("biz.collectAll")
                    }
                    if let message {
                        Text(message).pixelLabel(.footnote, color: Palette.sunset)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(PropertyID.allCases) { id in
                        card(id, progress: p, hustle: hustle, now: context.date)
                    }
                    Text("Tills fill for \(Int(Properties.tillHours[0])) hours (more after upgrades), then stop until you collect. Hustle skill adds 5% a level. Buying a business is an investment, not a cost: your ledger keeps it apart from spending.")
                        .font(.pixel(.footnote, weight: .medium))
                        .foregroundStyle(Palette.cream.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }

    @ViewBuilder
    private func card(_ id: PropertyID, progress p: PlayerProgress, hustle: Int, now: Date) -> some View {
        let spec = id.spec
        let owned = Properties.owned(id, in: p)
        let level = owned?.level ?? 1
        let perHour = Int(Properties.profitPerHour(id, level: level, hustle: hustle).rounded())
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(spec.name).pixelLabel(.headline, color: owned == nil ? Palette.cream : Palette.teal)
                Spacer()
                if let owned {
                    Text("Level \(owned.level)").pixelLabel(.caption, color: Palette.sunset)
                }
            }
            Text(spec.blurb).pixelLabel(.caption2, color: Palette.cream.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Fact(label: "Profit/hour", value: "\(perHour)")
                Spacer()
                Fact(label: "Costs", value: "\(Int(spec.costShare * 100))% of sales")
                Spacer()
                Fact(label: "Pays back in", value: "\(Int(Properties.paybackHours(id).rounded())) h")
            }
            if let owned {
                let till = Properties.till(owned, hustle: hustle, now: now)
                HStack {
                    Text(till.isFull ? "Till full: \(till.profit) profit" : "Till: \(till.profit) profit so far")
                        .pixelLabel(.caption, color: till.isFull ? Palette.sunset : Palette.cream)
                    Spacer()
                    Text("Made \(owned.lifetimeProfit) total").pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
                }
                HStack(spacing: 8) {
                    Button("Collect") {
                        if let t = model.collect(id) {
                            message = "\(spec.name): \(t.revenue) sales − \(t.costs) costs = \(t.profit) profit."
                        } else {
                            message = "Nothing in the till yet."
                        }
                    }
                    .buttonStyle(.neon(Palette.teal))
                    .accessibilityIdentifier("biz.collect.\(id.rawValue)")
                    if let price = Properties.upgradePrice(owned) {
                        Button("Upgrade · \(price)") {
                            message = text(model.upgradeProperty(id), done: "\(spec.name) is level \(owned.level + 1): more customers, bigger till.")
                        }
                        .buttonStyle(.neon(Palette.sunset))
                    }
                }
                Button("Sell for \(Properties.resaleValue(owned))") {
                    if let paid = model.sellProperty(id) {
                        message = "Sold the \(spec.name) for \(paid)."
                    }
                }
                .buttonStyle(.neon(Palette.cream))
            } else {
                Button("Buy · \(spec.price)") {
                    message = text(model.buyProperty(id), done: "The \(spec.name) is yours. It starts earning now.")
                }
                .buttonStyle(.neon(Palette.magenta))
                .disabled(model.repLevel < spec.requiredRepLevel)
                .accessibilityIdentifier("biz.buy.\(id.rawValue)")
                if model.repLevel < spec.requiredRepLevel {
                    Label("Needs rep level \(spec.requiredRepLevel)", systemImage: "lock.fill")
                        .font(.pixel(.caption))
                        .foregroundStyle(Palette.sunset)
                }
            }
        }
        .padding(12)
        .background(Palette.ink.opacity(0.55))
        .overlay(Rectangle().strokeBorder((owned == nil ? Palette.cream : Palette.teal).opacity(0.5), lineWidth: 2))
    }

    private func text(_ refusal: Properties.Refusal?, done: String) -> String {
        switch refusal {
        case nil: done
        case .notEnoughCredits(let needed): "You need \(needed) more credits."
        case .alreadyOwned: "You already own it."
        case .notOwned: "Buy it first."
        case .maxLevel: "It's fully upgraded."
        case .locked(let level): "Reach rep level \(level) first."
        case .nothingToCollect: "Nothing in the till yet."
        }
    }
}
