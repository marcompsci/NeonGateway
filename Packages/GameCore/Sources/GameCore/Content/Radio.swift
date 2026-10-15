import Foundation

/// One song on the in-game station. The audio itself always comes from Apple Music (the game
/// never ships or stores music); this is what to look up and how to credit it.
public struct RadioTrack: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let artist: String
    /// Featured artists, as credited on the release.
    public let featuring: [String]
    public let explicit: Bool

    public init(id: String, title: String, artist: String, featuring: [String] = [], explicit: Bool = true) {
        self.id = id
        self.title = title
        self.artist = artist
        self.featuring = featuring
        self.explicit = explicit
    }

    /// "Veeze feat. Babyface Ray".
    public var credit: String {
        featuring.isEmpty ? artist : "\(artist) feat. \(featuring.joined(separator: " & "))"
    }

    /// What to type into an Apple Music search to find it.
    public var searchTerm: String { "\(title) \(artist)" }
}

/// Aurora FM: Port Aurora's station. Seven Michigan rap cuts, picked by Omari.
public enum AuroraFM {
    public static let name = "Aurora FM"

    public static let tracks: [RadioTrack] = [
        RadioTrack(id: "freeJoeExotic", title: "Free Joe Exotic", artist: "Bfb Da Packman", featuring: ["Sada Baby"]),
        RadioTrack(id: "proudOfMe", title: "Proud of Me", artist: "Ysr Gramz"),
        RadioTrack(id: "lawNOrder", title: "Law N Order", artist: "Veeze"),
        RadioTrack(id: "treehouse", title: "Treehouse", artist: "3200 Tre"),
        RadioTrack(id: "sevenSixers", title: "7sixers", artist: "Veeze", featuring: ["Babyface Ray"]),
        RadioTrack(id: "lmao", title: "Lmaoooooooo", artist: "Fox BD"),
        RadioTrack(id: "shakeyButts", title: "Shakey Butts", artist: "3200 Tre")
    ]

    /// Does an Apple Music search result look like this track? Titles are compared loosely
    /// (case, punctuation, a "(feat. …)" tail and stretched letters don't matter) and the
    /// artist has to appear in the result's artist line.
    public static func matches(_ track: RadioTrack, title: String, artist: String) -> Bool {
        let wantedArtist = squash(track.artist)
        guard squash(artist).contains(wantedArtist) else { return false }
        let wanted = squash(stripFeature(track.title))
        let got = squash(stripFeature(title))
        return got == wanted || got.hasPrefix(wanted) || wanted.hasPrefix(got) && got.count >= 4
    }

    /// Lowercase letters and digits only, with runs of the same letter collapsed
    /// ("Lmaoooooooo" and "LMAOOO" both become "lmao").
    static func squash(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() where ch.isLetter || ch.isNumber {
            if let last = out.last, last == ch, ch.isLetter { continue }
            out.append(ch)
        }
        return out
    }

    static func stripFeature(_ title: String) -> String {
        for marker in [" (feat", " (ft", " [feat", " feat.", " ft."] {
            if let range = title.lowercased().range(of: marker) {
                return String(title[title.startIndex..<range.lowerBound])
            }
        }
        return title
    }
}

/// The station's play order: every song once in a shuffled order, then a fresh shuffle.
/// A new loop never repeats the old order and never opens with the song that just played.
public struct RadioQueue: Codable, Sendable, Equatable {
    public private(set) var order: [Int]
    public private(set) var position = 0
    /// How many times the playlist has gone round (0 for the first pass).
    public private(set) var loop = 0
    private var seed: UInt64

    public init(count: Int, seed: UInt64) {
        self.seed = seed
        order = []
        order = Self.shuffled(count: count, seed: seed, previous: nil)
    }

    public var count: Int { order.count }
    /// Index into the track list of the song playing now.
    public var current: Int? { order.indices.contains(position) ? order[position] : nil }
    /// The rest of this loop, after the current song.
    public var upNext: [Int] { position + 1 < order.count ? Array(order[(position + 1)...]) : [] }

    /// The next song; past the end, reshuffles into a new loop.
    @discardableResult
    public mutating func next() -> Int? {
        guard !order.isEmpty else { return nil }
        if position + 1 < order.count {
            position += 1
        } else {
            loop += 1
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            order = Self.shuffled(count: order.count, seed: seed, previous: order)
            position = 0
        }
        return current
    }

    /// Back one song (stays on the first song of a loop).
    @discardableResult
    public mutating func previous() -> Int? {
        if position > 0 { position -= 1 }
        return current
    }

    /// The player picked a song: it plays now, and the loop carries on from there with the
    /// songs not yet heard, so nothing repeats before the reshuffle.
    @discardableResult
    public mutating func play(_ track: Int) -> Int? {
        guard let at = order.firstIndex(of: track) else { return current }
        if at > position {
            // Bring it forward to play next, keep the rest in their shuffled order.
            order.remove(at: at)
            order.insert(track, at: position + 1)
            position += 1
        } else {
            position = at
        }
        return current
    }

    /// A shuffle of 0..<count that differs from `previous` and doesn't start with its last song.
    static func shuffled(count: Int, seed: UInt64, previous: [Int]?) -> [Int] {
        guard count > 1 else { return Array(0..<count) }
        var rng = SplitMix64(seed: seed)
        var best = Array(0..<count)
        for _ in 0..<16 {
            var order = Array(0..<count)
            // Fisher–Yates with the seeded generator.
            for i in stride(from: count - 1, to: 0, by: -1) {
                let j = Int(rng.next() % UInt64(i + 1))
                order.swapAt(i, j)
            }
            best = order
            guard let previous else { break }
            if order != previous && order.first != previous.last { break }
        }
        if let previous, best.first == previous.last {
            best.swapAt(0, count - 1)
        }
        return best
    }
}
