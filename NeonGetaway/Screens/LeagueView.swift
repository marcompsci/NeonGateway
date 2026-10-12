import SwiftUI
import GameCore

/// The weekly money league: 15 drivers, ranked on what they earned by working this week.
/// Top 3 go up a division, bottom 3 go down, and the top 10 split a prize purse on Monday.
/// A second tab ranks net worth, because earning and keeping aren't the same thing.
struct LeagueView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.week

    enum Tab: String, CaseIterable { case week = "This week", worth = "Net worth" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "League") { router.back() }
                Picker("Board", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch tab {
                case .week: WeekBoard()
                case .worth: WorthBoard()
                }
                Button("All-time rankings (Legendary)") { router.go(.rankings) }
                    .buttonStyle(.neon(Palette.magenta))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
        .onAppear { model.refreshEconomy() }
    }
}

private struct WeekBoard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.progress
        let now = Date()
        let board = League.board(p, now: now)
        let rank = League.rank(p, now: now)
        let division = p.league.division
        let projected = League.prize(rank: rank, division: division)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(division.name) league · #\(rank) of \(League.size)")
                    .pixelLabel(.title3, color: Palette.sunset)
                Text(statusLine(rank: rank, division: division))
                    .pixelLabel(.caption, color: Palette.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Fact(label: "Earned", value: "\(p.league.earnings)")
                    Spacer()
                    Fact(label: "Prize now", value: projected > 0 ? "\(projected)" : "—")
                    Spacer()
                    Fact(label: "Ends in", value: Self.timeLeft(GameClock.secondsLeftInWeek(now)))
                }
                let gap = League.gapToNext(p, now: now)
                if gap > 0 {
                    Text("\(gap) cr more passes the next driver.")
                        .pixelLabel(.caption2, color: Palette.teal)
                }
            }
            .padding(14)
            .background(Palette.ink.opacity(0.6))
            .overlay(Rectangle().strokeBorder(Palette.sunset, lineWidth: 2))

            VStack(spacing: 0) {
                ForEach(Array(board.enumerated()), id: \.offset) { index, entry in
                    row(rank: index + 1, entry: entry, division: division)
                }
            }
            .overlay(Rectangle().strokeBorder(Palette.cream.opacity(0.2), lineWidth: 1))

            prizeTable(division)

            Text("What counts: job pay, design sales, business profit and daily bonuses. Selling things you own, savings interest and prizes don't: the league ranks money you earned by working. Rivals are Port Aurora drivers; online leagues come later.")
                .font(.pixel(.footnote, weight: .medium))
                .foregroundStyle(Palette.cream.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusLine(rank: Int, division: Division) -> String {
        switch League.zone(forRank: rank, division: division) {
        case 1: "In the promotion zone: finish top 3 to move up to \(division.next?.name ?? "")."
        case -1: "In the drop zone: climb out of the bottom 3 or fall to \(division.previous?.name ?? "")."
        default: rank <= League.prizeMultipliers.count ? "In the prize places. Keep earning." : "Top 10 win prize money on Monday."
        }
    }

    private func row(rank: Int, entry: League.Entry, division: Division) -> some View {
        let zone = League.zone(forRank: rank, division: division)
        let prize = League.prize(rank: rank, division: division)
        return HStack(spacing: 10) {
            Text("\(rank)").pixelLabel(.callout, color: zone > 0 ? Palette.teal : (zone < 0 ? Palette.sunset : Palette.cream))
                .frame(width: 28, alignment: .trailing)
            Image(systemName: zone > 0 ? "arrow.up" : (zone < 0 ? "arrow.down" : "minus"))
                .font(.caption.weight(.black))
                .foregroundStyle(zone > 0 ? Palette.teal : (zone < 0 ? Palette.sunset : Palette.cream.opacity(0.2)))
                .frame(width: 14)
            Text(entry.name).pixelLabel(.callout, color: entry.isPlayer ? Palette.ink : Palette.cream)
                .lineLimit(1)
            Spacer()
            if prize > 0 {
                Text("+\(prize)").pixelLabel(.caption2, color: entry.isPlayer ? Palette.ink : Palette.sunset)
            }
            Text("\(entry.earnings)").pixelLabel(.callout, color: entry.isPlayer ? Palette.ink : Palette.cream)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(entry.isPlayer ? Palette.teal : (rank % 2 == 0 ? Palette.ink.opacity(0.4) : Color.clear))
        .overlay(alignment: .bottom) {
            if rank == League.promoted || rank == League.size - League.relegated {
                Rectangle().fill(Palette.cream.opacity(0.35)).frame(height: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(rank: rank, entry: entry, prize: prize, zone: zone))
    }

    private func prizeTable(_ division: Division) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prize purse").pixelLabel(.headline, color: Palette.magenta)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { r in
                    VStack(spacing: 2) {
                        Text("#\(r)").pixelLabel(.caption2, color: Palette.cream.opacity(0.7))
                        Text("\(League.prize(rank: r, division: division))").pixelLabel(.caption, color: Palette.sunset)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("6th–10th: \(League.prize(rank: 6, division: division)) each.")
                .pixelLabel(.caption2, color: Palette.cream.opacity(0.7))
        }
        .padding(12)
        .background(Palette.ink.opacity(0.5))
    }

    static func spoken(rank: Int, entry: League.Entry, prize: Int, zone: Int) -> String {
        var text = "\(rank). \(entry.isPlayer ? "You" : entry.name), \(entry.earnings) credits"
        if prize > 0 { text += ", wins \(prize)" }
        if zone > 0 { text += ", promotion zone" }
        if zone < 0 { text += ", drop zone" }
        return text
    }

    static func timeLeft(_ seconds: Double) -> String {
        let hours = Int(seconds / 3_600)
        return hours >= 24 ? "\(hours / 24)d \(hours % 24)h" : "\(hours)h \(Int(seconds / 60) % 60)m"
    }
}

private struct WorthBoard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.progress
        let worth = NetWorth.breakdown(p)
        let board = NetWorth.board(p)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Net worth \(worth.total) · #\(NetWorth.rank(p))").pixelLabel(.title3, color: Palette.teal)
                WorthLine(label: "Cash", value: worth.cash)
                WorthLine(label: "Savings", value: worth.savings)
                WorthLine(label: "Vehicles (resale)", value: worth.vehicles)
                WorthLine(label: "Businesses (resale)", value: worth.businesses)
                WorthLine(label: "Weapons (resale)", value: worth.weapons)
                Text("Things are counted at what they'd sell for, not what you paid.")
                    .pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
            }
            .padding(14)
            .background(Palette.ink.opacity(0.6))
            .overlay(Rectangle().strokeBorder(Palette.teal, lineWidth: 2))
            VStack(spacing: 0) {
                ForEach(Array(board.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        Text("\(index + 1)").pixelLabel(.callout).frame(width: 28, alignment: .trailing)
                        Text(entry.name).pixelLabel(.callout, color: entry.isPlayer ? Palette.ink : Palette.cream)
                            .lineLimit(1)
                        Spacer()
                        Text("\(entry.worth)").pixelLabel(.callout, color: entry.isPlayer ? Palette.ink : Palette.cream)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(entry.isPlayer ? Palette.teal : (index % 2 == 1 ? Palette.ink.opacity(0.4) : Color.clear))
                    .accessibilityElement(children: .combine)
                }
            }
            .overlay(Rectangle().strokeBorder(Palette.cream.opacity(0.2), lineWidth: 1))
        }
    }
}

private struct WorthLine: View {
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Text(label).pixelLabel(.caption, color: Palette.cream.opacity(0.8))
            Spacer()
            Text("\(value)").pixelLabel(.caption, color: Palette.cream)
        }
        .accessibilityElement(children: .combine)
    }
}
