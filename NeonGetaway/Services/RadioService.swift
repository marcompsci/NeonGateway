import SwiftUI
import MusicKit
import AVFoundation
import GameCore

/// Aurora FM, the in-game station. Songs stream from Apple Music through MusicKit; the game
/// never ships or stores any music.
///
/// - Apple Music subscribers hear full songs through `ApplicationMusicPlayer`.
/// - Everyone else hears Apple's 30-second previews, with a "+" that opens the song in Apple Music.
///
/// Each launch starts a new shuffle; every song plays once per loop, then the order reshuffles
/// (`RadioQueue`). The game drives the order one song at a time and moves on when a song ends.
@MainActor
@Observable
final class RadioService {
    enum Access: Equatable {
        case unknown
        case asking
        /// The player said no to Apple Music access (they can change it in Settings).
        case denied
        /// Screen Time or a profile blocks Apple Music.
        case restricted
        /// Apple Music couldn't be searched (offline, or the service isn't set up for the app).
        case unavailable(String)
        case ready
    }

    private(set) var access: Access = .unknown
    /// Full songs (an Apple Music subscription) rather than 30-second previews.
    private(set) var fullSongs = false
    /// The Apple Music song found for each track, by `RadioTrack.id`.
    private(set) var songs: [String: Song] = [:]
    private(set) var queue: RadioQueue
    private(set) var isPlaying = false
    /// 0...1 through the current song.
    private(set) var progress: Double = 0
    /// The last thing that went wrong, in Apple's words (shown on the phone so it can be fixed).
    private(set) var lastError: String?

    /// A song found through Apple's public iTunes search: its 30-second preview, its Apple Music
    /// page and cover. Used when MusicKit can't be reached (no Apple Music access, or Apple's
    /// developer token isn't available), so the station always plays.
    struct CatalogHit: Equatable, Decodable {
        let trackName: String
        let artistName: String
        let previewUrl: URL?
        let trackViewUrl: URL?
        let artworkUrl100: URL?
    }
    private(set) var hits: [String: CatalogHit] = [:]
    /// Playing iTunes previews because MusicKit wasn't available (and why).
    private(set) var fallbackReason: String?

    /// Mirrors Settings › Aurora FM.
    var enabled = true {
        didSet { if !enabled { pause() } }
    }

    private var preview: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var ticker: Timer?
    /// The radio should be making sound (false while paused or in the menus).
    private var wantsPlaying = false
    /// Which track is loaded in a player right now.
    private var loaded: Int?
    private var lastTime: TimeInterval = 0
    private var resolving = false
    private var missesInARow = 0

    init() {
        queue = RadioQueue(count: AuroraFM.tracks.count, seed: UInt64.random(in: 1...UInt64.max))
    }

    var tracks: [RadioTrack] { AuroraFM.tracks }
    var current: RadioTrack? { queue.current.map { AuroraFM.tracks[$0] } }
    func song(for track: RadioTrack) -> Song? { songs[track.id] }

    /// Opens the song in Apple Music, where it can be added to the library.
    func appleMusicURL(for track: RadioTrack) -> URL {
        if let url = songs[track.id]?.url { return url }
        if let url = hits[track.id]?.trackViewUrl { return url }
        var parts = URLComponents(string: "https://music.apple.com/us/search")!
        parts.queryItems = [URLQueryItem(name: "term", value: track.searchTerm)]
        return parts.url!
    }

    // MARK: Setup

    /// Asks for Apple Music access (once) and finds each song in the catalog.
    func prepare() async {
        guard access != .ready, !resolving else { return }
        resolving = true
        defer { resolving = false }

        var status = MusicAuthorization.currentStatus
        if status == .notDetermined {
            access = .asking
            status = await MusicAuthorization.request()
        }
        switch status {
        case .authorized: break
        case .restricted:
            await useFallback(because: "Apple Music is restricted on this phone")
            if access != .ready { access = .restricted }
            return
        default:
            await useFallback(because: "Apple Music access is off")
            if access != .ready { access = .denied }
            return
        }

        if let subscription = try? await MusicSubscription.current {
            fullSongs = subscription.canPlayCatalogContent
        }
        for track in AuroraFM.tracks where songs[track.id] == nil {
            do {
                var request = MusicCatalogSearchRequest(term: track.searchTerm, types: [Song.self])
                request.limit = 15
                let response = try await request.response()
                if let match = response.songs.first(where: {
                    AuroraFM.matches(track, title: $0.title, artist: $0.artistName)
                }) {
                    songs[track.id] = match
                }
            } catch {
                let why = describe(error)
                await useFallback(because: "Apple Music couldn't be reached: " + why)
                if access != .ready {
                    lastError = why
                    access = .unavailable("Apple Music search failed.")
                }
                return
            }
        }
        if songs.isEmpty {
            await useFallback(because: "None of the songs turned up through MusicKit")
            if access != .ready { access = .unavailable("None of the songs turned up in Apple Music.") }
            return
        }
        access = .ready
        lastError = nil
        fallbackReason = nil
    }

    /// Finds each song's preview through Apple's public iTunes search (no developer token or
    /// Apple Music access needed) and plays those instead.
    private func useFallback(because reason: String) async {
        fullSongs = false
        let country = Locale.current.region?.identifier.lowercased() ?? "us"
        for track in AuroraFM.tracks where hits[track.id] == nil {
            var parts = URLComponents(string: "https://itunes.apple.com/search")!
            parts.queryItems = [URLQueryItem(name: "term", value: track.searchTerm),
                                URLQueryItem(name: "entity", value: "song"),
                                URLQueryItem(name: "limit", value: "15"),
                                URLQueryItem(name: "country", value: country)]
            guard let url = parts.url else { continue }
            struct Results: Decodable { let results: [CatalogHit] }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let found = try JSONDecoder().decode(Results.self, from: data).results
                if let match = found.first(where: {
                    $0.previewUrl != nil && AuroraFM.matches(track, title: $0.trackName, artist: $0.artistName)
                }) {
                    hits[track.id] = match
                }
            } catch {
                lastError = "iTunes search failed too: " + describe(error)
            }
        }
        if !hits.isEmpty {
            access = .ready
            lastError = nil
            fallbackReason = reason
        }
    }

    /// Forget a failed setup and try again (after turning on MusicKit, signing in, going online).
    func retry() {
        if access != .ready || fallbackReason != nil {
            access = .unknown
            fallbackReason = nil
        }
        lastError = nil
        missesInARow = 0
        loaded = nil
        wantsPlaying = true
        Task { await playCurrent(fromStart: true) }
    }

    /// How many of the station's songs were found in Apple Music.
    var foundCount: Int { Set(songs.keys).union(hits.keys).count }

    /// Cover art from the iTunes search (MusicKit songs carry their own artwork).
    func artworkURL(for track: RadioTrack) -> URL? {
        hits[track.id]?.artworkUrl100.flatMap {
            URL(string: $0.absoluteString.replacingOccurrences(of: "100x100", with: "300x300"))
        }
    }

    private func describe(_ error: Error) -> String {
        let text = String(describing: error)
        let local = error.localizedDescription
        return text == local ? local : "\(local) (\(text.prefix(160)))"
    }

    // MARK: Playback

    /// Starts (or carries on with) the station.
    func resume() {
        guard enabled else { return }
        wantsPlaying = true
        Task { await playCurrent(fromStart: loaded != queue.current) }
    }

    func pause() {
        wantsPlaying = false
        isPlaying = false
        stopTicker()
        if fullSongs { ApplicationMusicPlayer.shared.pause() }
        preview?.pause()
    }

    func togglePlay() {
        if wantsPlaying { pause() } else { resume() }
    }

    func next() {
        queue.next()
        restartIfPlaying()
    }

    /// Back to the start of the song, or to the previous one if it only just started.
    func previous() {
        if progress * duration(of: current) < 3 { queue.previous() }
        loaded = nil
        restartIfPlaying()
    }

    /// The player tapped a song in the list.
    func play(_ track: RadioTrack) {
        guard let index = AuroraFM.tracks.firstIndex(of: track) else { return }
        queue.play(index)
        loaded = nil
        wantsPlaying = true
        Task { await playCurrent(fromStart: true) }
    }

    private func restartIfPlaying() {
        loaded = nil
        progress = 0
        if wantsPlaying {
            Task { await playCurrent(fromStart: true) }
        }
    }

    private func playCurrent(fromStart: Bool) async {
        if access != .ready { await prepare() }
        guard wantsPlaying, access == .ready, let index = queue.current else { return }
        let track = AuroraFM.tracks[index]
        let song = songs[track.id]
        let hit = hits[track.id]
        guard song != nil || hit?.previewUrl != nil else {
            // Not in this storefront's catalog: skip it (but don't spin if nothing is found).
            missesInARow += 1
            if missesInARow < AuroraFM.tracks.count {
                queue.next()
                await playCurrent(fromStart: true)
            }
            return
        }
        missesInARow = 0
        activateAudioSession()

        if !fromStart, loaded == index {
            // Carry on where it was.
            if fullSongs { try? await ApplicationMusicPlayer.shared.play() } else { preview?.play() }
            isPlaying = true
            startTicker()
            return
        }

        stopPreview()
        lastTime = 0
        progress = 0
        loaded = index
        guard let song else {
            // iTunes preview (MusicKit unavailable).
            playPreview(url: hit!.previewUrl!, title: track.title)
            startTicker()
            return
        }
        if fullSongs {
            let player = ApplicationMusicPlayer.shared
            player.queue = ApplicationMusicPlayer.Queue(for: [song])
            do {
                try await player.play()
                isPlaying = true
                lastError = nil
            } catch {
                // No subscription after all (or it lapsed): fall back to the preview.
                lastError = "Full song wouldn't play, so previews are on: " + describe(error)
                fullSongs = false
                playPreview(song)
            }
        } else {
            playPreview(song)
        }
        startTicker()
    }

    private func playPreview(_ song: Song) {
        guard let url = song.previewAssets?.first?.url else {
            lastError = "No preview for \(song.title)."
            queue.next()
            loaded = nil
            Task { await playCurrent(fromStart: true) }
            return
        }
        playPreview(url: url, title: song.title)
    }

    private func playPreview(url: URL, title: String) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.songEnded() }
        }
        preview = player
        player.play()
        isPlaying = true
    }

    private func stopPreview() {
        preview?.pause()
        preview = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func songEnded() {
        guard wantsPlaying else { return }
        queue.next()
        loaded = nil
        Task { await playCurrent(fromStart: true) }
    }

    /// Music plays over the game's own sound, and keeps going with the ringer switch off.
    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func duration(of track: RadioTrack?) -> Double {
        if !fullSongs { return 30 }
        guard let track, let d = songs[track.id]?.duration else { return 0 }
        return d
    }

    // MARK: Progress

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard wantsPlaying else { return }
        if fullSongs {
            let player = ApplicationMusicPlayer.shared
            let t = player.playbackTime
            let length = duration(of: current)
            if length > 0 { progress = min(1, t / length) }
            let playing = player.state.playbackStatus == .playing
            isPlaying = playing
            // A one-song queue stops (and rewinds) when the song is over: move on.
            if !playing && lastTime > 1 && (length == 0 || lastTime >= length - 3) {
                lastTime = 0
                songEnded()
                return
            }
            if playing { lastTime = t }
        } else if let preview {
            progress = min(1, preview.currentTime().seconds / 30)
        }
    }
}
