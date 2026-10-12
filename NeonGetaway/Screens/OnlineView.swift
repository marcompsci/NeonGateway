import SwiftUI
import GameCore

/// Everything online in one place: Game Center status, live play, the online leaderboards, the
/// online design market, and safety (blocked players, how reporting works, contact).
struct OnlineView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var board = OnlineBoards.weekly
    @State private var entries: [GameCenterService.BoardEntry] = []
    @State private var me: GameCenterService.BoardEntry?
    @State private var loadingBoard = false

    var body: some View {
        let gc = model.gameCenter
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Online") { router.back() }
                statusCard(gc)
                if gc.isAuthenticated {
                    liveCard
                    boards
                    Button("Online design market") { router.go(.bodyShop) }
                        .buttonStyle(.neon(Palette.magenta))
                        .accessibilityIdentifier("online.market")
                }
                safety
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
        .onAppear { model.gameCenter.authenticate() }
        .task(id: "\(gc.isAuthenticated)-\(board)") { await loadBoard() }
        .onChange(of: model.live.state) { _, state in
            if state == .playing { router.go(.drive(.live)) }
        }
    }

    private func statusCard(_ gc: GameCenterService) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if gc.isAuthenticated {
                Label("Signed in as \(gc.displayName ?? "you")", systemImage: "checkmark.seal.fill")
                    .font(.pixel(.headline))
                    .foregroundStyle(Palette.teal)
                Text("Your weekly earnings, score and net worth post to the online leaderboards automatically.")
                    .pixelLabel(.caption, color: Palette.cream.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Offline", systemImage: "wifi.slash")
                    .font(.pixel(.headline))
                    .foregroundStyle(Palette.sunset)
                Text(gc.problem ?? "Sign in to Game Center (iPhone Settings › Game Center) to play with other people, use the online market and climb the online leaderboards. Everything else works offline.")
                    .pixelLabel(.caption, color: Palette.cream.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ink.opacity(0.6))
        .overlay(Rectangle().strokeBorder((gc.isAuthenticated ? Palette.teal : Palette.sunset).opacity(0.7), lineWidth: 2))
    }

    private var liveCard: some View {
        let live = model.live
        return VStack(alignment: .leading, spacing: 8) {
            Text("Live street").pixelLabel(.headline, color: Palette.magenta)
                .accessibilityAddTraits(.isHeader)
            Text("Share Port Aurora with up to \(PvP.maxPlayers - 1) other players. Knock someone out and their gun drops for you; get knocked out and you lose yours. No chat, cartoon knockouts only.")
                .pixelLabel(.caption, color: Palette.cream.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            switch live.state {
            case .searching:
                HStack {
                    ProgressView().tint(Palette.teal)
                    Text("Looking for players…").pixelLabel(.callout)
                    Spacer()
                    Button("Cancel") { live.cancel() }.buttonStyle(.neon(Palette.sunset))
                }
            case .failed(let why):
                Text(why).pixelLabel(.footnote, color: Palette.sunset)
                findButton
            default:
                findButton
            }
            Text("Knockouts \(model.progress.online.knockouts) · guns taken \(model.progress.online.gunsTaken)")
                .pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
        }
        .padding(14)
        .background(Palette.ink.opacity(0.55))
    }

    private var findButton: some View {
        Button("Find players") { Task { await model.live.find() } }
            .buttonStyle(.neon(Palette.teal))
            .accessibilityIdentifier("online.find")
    }

    private var boards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Online leaderboards").pixelLabel(.headline, color: Palette.sunset)
                .accessibilityAddTraits(.isHeader)
            Picker("Board", selection: $board) {
                Text("This week").tag(OnlineBoards.weekly)
                Text("All-time").tag(OnlineBoards.allTime)
                Text("Net worth").tag(OnlineBoards.netWorth)
            }
            .pickerStyle(.segmented)
            if loadingBoard {
                ProgressView().tint(Palette.teal)
            } else if entries.isEmpty {
                Text("No scores yet. Finish a job to post yours.")
                    .pixelLabel(.caption, color: Palette.cream.opacity(0.6))
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in boardRow(entry) }
                    if let me, !entries.contains(where: { $0.isMe }) {
                        boardRow(me)
                    }
                }
                .overlay(Rectangle().strokeBorder(Palette.cream.opacity(0.2), lineWidth: 1))
            }
        }
    }

    private func boardRow(_ entry: GameCenterService.BoardEntry) -> some View {
        HStack {
            Text("\(entry.rank)").pixelLabel(.callout).frame(width: 40, alignment: .trailing)
            Text(entry.name).pixelLabel(.callout, color: entry.isMe ? Palette.ink : Palette.cream).lineLimit(1)
            Spacer()
            Text("\(entry.score)").pixelLabel(.callout, color: entry.isMe ? Palette.ink : Palette.cream)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(entry.isMe ? Palette.teal : Color.clear)
        .accessibilityElement(children: .combine)
    }

    private var safety: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Safety").pixelLabel(.headline, color: Palette.teal)
                .accessibilityAddTraits(.isHeader)
            Text("There's no chat. Names and designs other players see are filtered. Press and hold any online design to report it or block its creator; designs reported by several players disappear for everyone.")
                .pixelLabel(.caption, color: Palette.cream.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            let blocked = model.progress.online.blocked
            if blocked.isEmpty {
                Text("You haven't blocked anyone.").pixelLabel(.caption2, color: Palette.cream.opacity(0.5))
            } else {
                Text("Blocked players").pixelLabel(.callout)
                ForEach(blocked, id: \.self) { id in
                    HStack {
                        Text("Player …\(String(id.suffix(6)))").pixelLabel(.caption)
                        Spacer()
                        Button("Unblock") { model.unblock(id) }
                            .font(.pixel(.caption))
                            .foregroundStyle(Palette.teal)
                            .frame(minHeight: 44)
                    }
                }
            }
            if let mail = Support.mailURL {
                Link("Report a problem or a player", destination: mail)
                    .font(.pixel(.callout))
                    .foregroundStyle(Palette.sunset)
                    .frame(minHeight: 44)
            }
        }
        .padding(14)
        .background(Palette.ink.opacity(0.5))
    }

    private func loadBoard() async {
        guard model.gameCenter.isAuthenticated else { return }
        loadingBoard = true
        model.gameCenter.submit(OnlineBoards.scores(model.progress))
        let result = await model.gameCenter.load(board)
        entries = result?.top ?? []
        me = result?.me
        loadingBoard = false
    }
}

/// How players reach the developer (App Review guideline 1.2 needs a published contact).
enum Support {
    /// Shown to players as "Report a problem or a player".
    static let email = "hello@phoronomicstudios.com"

    static var mailURL: URL? {
        email.isEmpty ? nil : URL(string: "mailto:\(email)?subject=Neon%20Getaway%20report")
    }
}
