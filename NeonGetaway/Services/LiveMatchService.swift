import SwiftUI
@preconcurrency import GameKit
import GameCore

/// Finds other players with Game Center matchmaking and passes `NetMessage`s between up to four
/// phones. No chat: players only share where they are, what they look like, hits and drops.
@MainActor
@Observable
final class LiveMatchService {
    enum State: Equatable {
        case idle, searching, playing
        case failed(String)
    }

    private(set) var state = State.idle
    /// Other players in the match: Game Center id → Game Center name.
    private(set) var players: [String: String] = [:]

    /// Set by the session while a street is open.
    @ObservationIgnored var onMessage: ((String, NetMessage) -> Void)?
    @ObservationIgnored var onLeft: ((String) -> Void)?

    @ObservationIgnored private var match: GKMatch?
    @ObservationIgnored private var relay: MatchRelay?

    var isPlaying: Bool { state == .playing && match != nil }

    /// Auto-matches with 1–3 other players looking for a game right now.
    func find() async {
        guard state != .searching else { return }
        guard GKLocalPlayer.local.isAuthenticated else {
            state = .failed("Sign in to Game Center to play online.")
            return
        }
        state = .searching
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = PvP.maxPlayers
        do {
            let found = try await GKMatchmaker.shared().findMatch(for: request)
            attach(found)
        } catch {
            state = .failed("Nobody found right now. Try again in a minute.")
        }
    }

    func cancel() {
        GKMatchmaker.shared().cancel()
        if state == .searching { state = .idle }
    }

    func leave() {
        match?.disconnect()
        match?.delegate = nil
        match = nil
        relay = nil
        players = [:]
        state = .idle
    }

    /// Sends to everyone, or to one player. Positions go unreliable (the next one replaces them);
    /// hits, drops and claims go reliable.
    func send(_ message: NetMessage, to player: String? = nil, reliable: Bool = true) {
        guard let match, let data = NetCodec.encode(message) else { return }
        let mode: GKMatch.SendDataMode = reliable ? .reliable : .unreliable
        if let player {
            guard let target = match.players.first(where: { $0.gamePlayerID == player }) else { return }
            try? match.send(data, to: [target], dataMode: mode)
        } else {
            try? match.sendData(toAllPlayers: data, with: mode)
        }
    }

    private func attach(_ found: GKMatch) {
        let relay = MatchRelay(
            onData: { [weak self] data, from in
                Task { @MainActor in self?.receive(data, from: from) }
            },
            onChange: { [weak self] id, name, connected in
                Task { @MainActor in self?.playerChanged(id, name: name, connected: connected) }
            })
        found.delegate = relay
        self.relay = relay
        match = found
        players = Dictionary(found.players.map { ($0.gamePlayerID, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        state = .playing
    }

    private func receive(_ data: Data, from player: String) {
        guard let message = NetCodec.decode(data) else { return }
        onMessage?(player, message)
    }

    private func playerChanged(_ id: String, name: String, connected: Bool) {
        if connected {
            players[id] = name
        } else {
            players[id] = nil
            onLeft?(id)
            if players.isEmpty { leave() }
        }
    }
}

/// GKMatch's delegate. GameKit calls it off the main thread, so it only copies out plain values.
private final class MatchRelay: NSObject, GKMatchDelegate, @unchecked Sendable {
    let onData: @Sendable (Data, String) -> Void
    let onChange: @Sendable (String, String, Bool) -> Void

    init(onData: @escaping @Sendable (Data, String) -> Void,
         onChange: @escaping @Sendable (String, String, Bool) -> Void) {
        self.onData = onData
        self.onChange = onChange
    }

    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        onData(data, player.gamePlayerID)
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        onChange(player.gamePlayerID, player.displayName, state == .connected)
    }
}
