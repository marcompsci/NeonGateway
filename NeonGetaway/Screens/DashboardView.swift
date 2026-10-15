import SwiftUI
import GameCore

/// The business at a glance: what you're worth, what's coming in, every till, and the latest
/// ledger lines. Compact enough for the in-game phone.
struct DashboardPanel: View {
    @Environment(AppModel.self) private var model
    /// Shows the Collect all button (menu phone only; tills can't be emptied mid-drive).
    var canCollect = false
    @State private var collected: Int?

    var body: some View {
        let p = model.progress
        let s = DashboardSummary(p)
        VStack(alignment: .leading, spacing: 12) {
            Text("Dashboard").pixelLabel(.title3, color: Palette.sunset).accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                Stat(label: "Net worth", value: s.netWorth, color: Palette.sunset)
                Stat(label: "Cash", value: p.credits, color: Palette.cream)
                Stat(label: "Saved", value: p.bank.balance, color: Palette.teal)
            }
            HStack(spacing: 8) {
                Stat(label: "Per hour", value: s.profitPerHour, color: Palette.teal, suffix: "/h")
                Stat(label: "This week", value: p.league.earnings, color: Palette.magenta)
                Stat(label: "Profit", value: p.books.profit, color: p.books.profit >= 0 ? Palette.teal : Palette.magenta)
            }
            .accessibilityIdentifier("dashboard.stats")

            worthBar(s.worth)

            Text("Businesses").pixelLabel(.caption, color: Palette.cream.opacity(0.7))
            if s.businesses.isEmpty {
                Text(s.nextBusiness.map { "None yet. The \($0.spec.name) costs \($0.spec.price.formatted()) cr." } ?? "None yet.")
                    .pixelLabel(.caption, color: Palette.cream.opacity(0.8))
            } else {
                VStack(spacing: 6) {
                    ForEach(s.businesses) { b in BusinessRow(b: b) }
                }
                if canCollect && s.tillsWaiting > 0 {
                    Button("Collect all · \(s.tillsWaiting.formatted()) cr") {
                        collected = model.collectAll().profit
                    }
                    .buttonStyle(.neon(Palette.teal))
                    .accessibilityIdentifier("dashboard.collect")
                }
                if let collected {
                    Text("Collected \(collected.formatted()) cr").pixelLabel(.caption, color: Palette.teal)
                }
            }

            HStack {
                Fact(label: "Rep level", value: "\(s.repLevel)")
                Spacer()
                Fact(label: "Jobs done", value: "\(p.completedJobs)")
                Spacer()
                Fact(label: "League", value: p.league.division.name)
            }

            if !s.recent.isEmpty {
                Text("Latest").pixelLabel(.caption, color: Palette.cream.opacity(0.7))
                VStack(spacing: 4) {
                    ForEach(s.recent) { e in
                        HStack {
                            Text(e.note).pixelLabel(.caption2, color: Palette.cream.opacity(0.8)).lineLimit(1)
                            Spacer()
                            Text((e.amount >= 0 ? "+" : "") + e.amount.formatted())
                                .pixelLabel(.caption2, color: e.amount >= 0 ? Palette.teal : Palette.magenta)
                        }
                    }
                }
            }
        }
    }

    private func worthBar(_ w: NetWorth.Breakdown) -> some View {
        let parts: [(String, Int, Color)] = [("Cash", w.cash, Palette.cream), ("Savings", w.savings, Palette.teal),
                                             ("Cars", w.vehicles, Palette.magenta), ("Business", w.businesses, Palette.sunset),
                                             ("Weapons", w.weapons, Color(hex: 0x8A8AA0))]
        let total = max(1, parts.reduce(0) { $0 + max(0, $1.1) })
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(parts, id: \.0) { part in
                        part.2.frame(width: geo.size.width * CGFloat(max(0, part.1)) / CGFloat(total))
                    }
                }
            }
            .frame(height: 10)
            .background(Palette.ink)
            HStack(spacing: 8) {
                ForEach(parts.filter { $0.1 > 0 }, id: \.0) { part in
                    HStack(spacing: 3) {
                        Rectangle().fill(part.2).frame(width: 7, height: 7)
                        Text(part.0).pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Net worth split: " + parts.filter { $0.1 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: ", "))
    }
}

private struct Stat: View {
    let label: String
    let value: Int
    let color: Color
    var suffix = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
            Text(value.formatted() + suffix).pixelLabel(.callout, color: color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Palette.ink.opacity(0.6))
        .accessibilityElement(children: .combine)
    }
}

private struct BusinessRow: View {
    let b: DashboardSummary.Business

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(b.name) · Lv \(b.level)").pixelLabel(.caption, color: Palette.cream)
                Spacer()
                Text("\(b.tillProfit.formatted()) cr").pixelLabel(.caption, color: b.tillFull ? Palette.sunset : Palette.teal)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Palette.ink
                    (b.tillFull ? Palette.sunset : Palette.teal).frame(width: geo.size.width * b.tillFill)
                }
            }
            .frame(height: 6)
            Text(b.tillFull ? "Till full: collect it" : "\(b.profitPerHour) cr an hour")
                .pixelLabel(.caption2, color: Palette.cream.opacity(0.55))
        }
        .padding(8)
        .background(Palette.ink.opacity(0.45))
        .accessibilityElement(children: .combine)
    }
}

/// The Dashboard as a full screen from the menu phone.
struct DashboardScreen: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: "Dashboard") { router.back() }
                DashboardPanel(canCollect: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
        .onAppear { model.refreshEconomy() }
    }
}
