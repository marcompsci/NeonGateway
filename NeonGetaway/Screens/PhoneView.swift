import SwiftUI
import GameCore

/// The player's phone: today's streak and Job of the day up top, then an app for every part of
/// the money game. Everything here is offline; online play comes later.
struct PhoneView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var result: LeagueResult?

    var body: some View {
        let p = model.progress
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Phone") { router.back() }
                if let result {
                    LeagueResultCard(result: result) { self.result = nil }
                }
                DailyCard()
                // A plain grid (not lazy) so every app exists on screen for VoiceOver and UI tests.
                let tiles = apps(p)
                VStack(spacing: 12) {
                    ForEach(Array(stride(from: 0, to: tiles.count, by: 3)), id: \.self) { start in
                        HStack(spacing: 12) {
                            ForEach(start..<min(start + 3, tiles.count), id: \.self) { i in
                                let t = tiles[i]
                                AppTile(title: t.title, detail: t.detail, icon: t.icon, color: t.color, id: t.id,
                                        badge: t.badge) { router.go(t.screen) }
                            }
                            ForEach(0..<(3 - min(3, tiles.count - start)), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                HStack {
                    Fact(label: "Cash", value: "\(p.credits)")
                    Spacer()
                    Fact(label: "Net worth", value: "\(NetWorth.total(p))")
                    Spacer()
                    Fact(label: "This week", value: "\(p.league.earnings)")
                }
                .padding(12)
                .background(Palette.ink.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
        .onAppear {
            model.refreshEconomy()
            if let unseen = model.takeLeagueResult() { result = unseen }
        }
    }

    private struct Tile {
        let title: String
        let detail: String
        let icon: String
        let color: Color
        let id: String
        var badge = 0
        let screen: Screen
    }

    private func apps(_ p: PlayerProgress) -> [Tile] {
        [
            Tile(title: "Dashboard", detail: "\(DashboardSummary(p).profitPerHour) cr/h", icon: "chart.bar.xaxis",
                 color: Palette.sunset, id: "phone.dashboard", badge: tillsReady(p), screen: .dashboard),
            Tile(title: "Atlas", detail: "Ask anything", icon: "sparkles",
                 color: Palette.teal, id: "phone.atlas", screen: .atlas),
            Tile(title: "League", detail: "#\(League.rank(p)) · \(p.league.division.name)", icon: "trophy.fill",
                 color: Palette.sunset, id: "phone.league", screen: .league),
            Tile(title: "Biz", detail: bizDetail(p), icon: "storefront.fill", color: Palette.teal,
                 id: "phone.properties", badge: tillsReady(p), screen: .properties),
            Tile(title: "Bank", detail: "\(p.bank.balance) saved", icon: "building.columns.fill",
                 color: Palette.cream, id: "phone.bank", screen: .bank),
            Tile(title: "Ledger", detail: "Profit \(p.books.profit)", icon: "book.closed.fill",
                 color: Palette.teal, id: "phone.business", screen: .business),
            Tile(title: "Rankings", detail: Ranking.tier(p).rawValue, icon: "list.number",
                 color: Palette.magenta, id: "phone.rankings", screen: .rankings),
            Tile(title: "Trophies", detail: "\(Int(Achievements.completion(p) * 100))% done", icon: "rosette",
                 color: Palette.sunset, id: "phone.trophies", badge: Achievements.claimable(p).count, screen: .trophies),
            Tile(title: "Skills", detail: skillsDetail(p), icon: "figure.run",
                 color: Palette.magenta, id: "phone.skills", screen: .skills),
            Tile(title: "Style", detail: "Your look", icon: "person.crop.circle.fill",
                 color: Palette.teal, id: "phone.style", screen: .style),
            Tile(title: "Radio", detail: AuroraFM.name, icon: "radio.fill",
                 color: Palette.magenta, id: "phone.radio", screen: .radio)
        ]
    }

    private func bizDetail(_ p: PlayerProgress) -> String {
        p.properties.isEmpty ? "Buy a business" : "\(p.properties.count) owned"
    }

    private func tillsReady(_ p: PlayerProgress) -> Int {
        p.properties.filter { Properties.till($0, hustle: p.skills.level(.hustle)).isFull }.count
    }

    private func skillsDetail(_ p: PlayerProgress) -> String {
        "Lv " + Skill.allCases.map { "\(p.skills.level($0))" }.joined(separator: "·")
    }
}

/// One app on the phone's home screen.
struct AppTile: View {
    let title: String
    let detail: String
    let icon: String
    let color: Color
    let id: String
    var badge = 0
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 58, height: 58)
                    .background(color)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.pixel(.caption2))
                                .foregroundStyle(Palette.cream)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Palette.magenta)
                                .offset(x: 8, y: -8)
                        }
                    }
                Text(title).pixelLabel(.callout)
                Text(detail).pixelLabel(.caption2, color: Palette.cream.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(.vertical, 8)
            .background(Palette.ink.opacity(0.55))
            .overlay(Rectangle().strokeBorder(color.opacity(0.6), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(detail)" + (badge > 0 ? ", \(badge) waiting" : ""))
        .accessibilityIdentifier(id)
    }
}

/// Today's streak, the next bonus, and the double-pay Job of the day.
struct DailyCard: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.progress
        let today = GameClock.day(Date())
        let streak = Daily.liveStreak(p, today: today)
        let doneToday = p.daily.lastDay == today
        let nextBonus = Daily.bonus(forStreak: streak + 1)
        let featured = Daily.featured(day: today, progress: p)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(streak > 0 ? "\(streak)-day streak" : "No streak yet", systemImage: "flame.fill")
                    .font(.pixel(.headline))
                    .foregroundStyle(streak > 0 ? Palette.sunset : Palette.cream.opacity(0.7))
                Spacer()
                if p.daily.shields > 0 {
                    Label("\(p.daily.shields)", systemImage: "shield.fill")
                        .font(.pixel(.callout))
                        .foregroundStyle(Palette.teal)
                        .accessibilityLabel("\(p.daily.shields) streak shields")
                }
            }
            Text(doneToday
                 ? "Today's streak bonus is banked. Tomorrow's first job pays \(nextBonus) cr."
                 : "Finish any job today for +\(nextBonus) cr. Miss a day and the streak starts over.")
                .pixelLabel(.caption, color: Palette.cream.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(1...Daily.streakBonuses.count, id: \.self) { day in
                    let reached = day <= streak
                    VStack(spacing: 2) {
                        Text("D\(day)").pixelLabel(.caption2, color: reached ? Palette.ink : Palette.cream.opacity(0.6))
                        Text("\(Daily.streakBonuses[day - 1])")
                            .pixelLabel(.caption2, color: reached ? Palette.ink : Palette.cream)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(reached ? Palette.sunset : Palette.ink.opacity(0.6))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Streak rewards: day 1 pays \(Daily.streakBonuses[0]), rising to \(Daily.streakBonuses.last ?? 0) from day 7")
            if let featured {
                let paid = p.daily.featuredDay == today
                Button {
                    router.go(.missionSelect)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Job of the day").pixelLabel(.caption2, color: Palette.teal)
                            Text(featured.title).pixelLabel(.callout)
                        }
                        Spacer()
                        Text(paid ? "Paid" : "2× pay").pixelLabel(.callout, color: paid ? Palette.teal : Palette.sunset)
                    }
                    .padding(10)
                    .background(Palette.asphaltLight)
                }
                .buttonStyle(.plain)
                .accessibilityHint(paid ? "Already paid double today" : "Pays its base pay again as a bonus, once today")
                .accessibilityIdentifier("phone.featured")
            }
        }
        .padding(14)
        .background(Palette.ink.opacity(0.6))
        .overlay(Rectangle().strokeBorder(Palette.sunset.opacity(0.7), lineWidth: 2))
    }
}

/// How last week's league went: shown once, the first time the phone opens after it ends.
struct LeagueResultCard: View {
    let result: LeagueResult
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last week: #\(result.rank) in \(result.division.name)")
                .pixelLabel(.headline, color: Palette.sunset)
            Text(lines).pixelLabel(.caption, color: Palette.cream)
                .fixedSize(horizontal: false, vertical: true)
            Button("Nice", action: onClose).buttonStyle(.neon(Palette.sunset))
        }
        .padding(14)
        .background(Palette.ink.opacity(0.8))
        .overlay(Rectangle().strokeBorder(Palette.sunset, lineWidth: 3))
        .accessibilityElement(children: .combine)
    }

    private var lines: String {
        var text = "You earned \(result.earnings) cr."
        if result.prize > 0 { text += " Prize: +\(result.prize) cr, paid into your cash." }
        if result.movement > 0, let up = result.division.next { text += " Promoted to \(up.name)!" }
        if result.movement < 0, let down = result.division.previous { text += " Down to \(down.name). Win it back." }
        return text
    }
}
