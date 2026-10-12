import SwiftUI
@preconcurrency import GameKit
import GameCore

/// Game Center: who the player is online, the three leaderboards, and the sign-in sheet.
/// Everything online starts here; when the player isn't signed in, the game stays fully offline.
@MainActor
@Observable
final class GameCenterService {
    struct BoardEntry: Identifiable, Equatable {
        let id: String
        let rank: Int
        let name: String
        let score: Int
        let isMe: Bool
    }

    private(set) var isAuthenticated = false
    private(set) var playerID: String?
    private(set) var displayName: String?
    private(set) var problem: String?
    private var started = false

    /// Asks Game Center who the player is. Shows Apple's sign-in sheet the first time if needed.
    func authenticate() {
        guard !started else { return }
        #if DEBUG
        if DebugLaunch.offline { return }
        #endif
        started = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let viewController {
                    Self.present(viewController)
                    return
                }
                let local = GKLocalPlayer.local
                self.isAuthenticated = local.isAuthenticated
                self.playerID = local.isAuthenticated ? local.gamePlayerID : nil
                self.displayName = local.isAuthenticated ? local.displayName : nil
                self.problem = error.map { _ in "Game Center isn't signed in. Open Settings › Game Center to play online." }
            }
        }
    }

    /// Posts the player's current scores to every leaderboard.
    func submit(_ scores: [String: Int]) {
        guard isAuthenticated else { return }
        for (board, value) in scores {
            GKLeaderboard.submitScore(value, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [board]) { _ in }
        }
    }

    /// The top 25 of a leaderboard, plus the player's own entry.
    func load(_ board: String) async -> (top: [BoardEntry], me: BoardEntry?)? {
        guard isAuthenticated else { return nil }
        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [board])
            guard let leaderboard = boards.first else { return nil }
            let (local, entries, _) = try await leaderboard.loadEntries(for: .global, timeScope: .allTime,
                                                                        range: NSRange(location: 1, length: 25))
            let me = playerID
            let top = entries.map {
                BoardEntry(id: $0.player.gamePlayerID, rank: $0.rank, name: $0.player.displayName,
                           score: $0.score, isMe: $0.player.gamePlayerID == me)
            }
            let mine = local.map {
                BoardEntry(id: $0.player.gamePlayerID, rank: $0.rank, name: $0.player.displayName,
                           score: $0.score, isMe: true)
            }
            return (top, mine)
        } catch {
            problem = "Couldn't load the online leaderboard. Check your connection."
            return nil
        }
    }

    /// The top-most view controller, to present Game Center's own screens on.
    static func present(_ controller: UIViewController) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow?.rootViewController
                ?? scenes.first?.keyWindow?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        top.present(controller, animated: true)
    }
}
