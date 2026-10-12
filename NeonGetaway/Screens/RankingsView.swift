import SwiftUI
import GameCore

/// The city's leaderboard. The top five are Legendary: they get to sell their paint designs.
struct RankingsView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.progress
        let board = Ranking.board(p)
        let myRank = Ranking.rank(p)
        let tier = Ranking.tier(forRank: myRank)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Rankings") { router.back() }
                VStack(alignment: .leading, spacing: 6) {
                    Text("You're #\(myRank) · \(tier.rawValue)").pixelLabel(.title2, color: tierColor(tier))
                    Text(tier == .legendary
                         ? "Legendary: your designs can go on sale in the body shop."
                         : "\(Ranking.pointsToLegendary(p)) points to Legendary. Then you can sell your paint designs.")
                        .pixelLabel(.footnote, color: Palette.cream.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Score = reputation XP + 10 per job finished + profit ÷ 5.")
                        .pixelLabel(.caption2, color: Palette.cream.opacity(0.55))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.ink.opacity(0.6))
                .overlay(Rectangle().strokeBorder(tierColor(tier), lineWidth: 2))

                VStack(spacing: 0) {
                    ForEach(Array(board.enumerated()), id: \.offset) { index, entry in
                        let rank = index + 1
                        let rowTier = Ranking.tier(forRank: rank)
                        HStack(spacing: 10) {
                            Text("\(rank)").pixelLabel(.callout, color: tierColor(rowTier)).frame(width: 30, alignment: .trailing)
                            Text(entry.name).pixelLabel(.callout, color: entry.isPlayer ? Palette.ink : Palette.cream)
                                .lineLimit(1)
                            Spacer()
                            Text(rowTier.rawValue).pixelLabel(.caption2, color: entry.isPlayer ? Palette.ink : tierColor(rowTier))
                            Text("\(entry.score)").pixelLabel(.callout, color: entry.isPlayer ? Palette.ink : Palette.cream)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(entry.isPlayer ? Palette.teal : (rank % 2 == 0 ? Palette.ink.opacity(0.4) : Color.clear))
                        .overlay(alignment: .bottom) {
                            if rank == Ranking.legendaryCutoff {
                                Rectangle().fill(Palette.sunset).frame(height: 2)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(rank). \(entry.isPlayer ? "You, \(entry.name)" : entry.name), \(rowTier.rawValue), \(entry.score) points")
                    }
                }
                .overlay(Rectangle().strokeBorder(Palette.cream.opacity(0.2), lineWidth: 1))
                Text("Offline, the other names are rival drivers in Port Aurora. Online rankings with real players come later.")
                    .font(.pixel(.footnote, weight: .medium))
                    .foregroundStyle(Palette.cream.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }

    private func tierColor(_ tier: Ranking.Tier) -> Color {
        switch tier {
        case .legendary: Palette.sunset
        case .elite: Palette.magenta
        case .pro: Palette.teal
        case .street: Palette.cream.opacity(0.7)
        }
    }
}
