import SwiftUI
import MusicKit
import GameCore

/// Aurora FM on the player's phone: what's playing, the rest of this shuffle, and every song's
/// credits with a "+" that opens it in Apple Music to add to your library.
struct RadioPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var model = model
        let radio = model.radio
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(AuroraFM.name).pixelLabel(.title3, color: Palette.magenta)
                        .accessibilityAddTraits(.isHeader)
                    Text("Shuffle · loop \(radio.queue.loop + 1)").pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
                }
                Spacer()
                Toggle(isOn: $model.settings.radioOn) {
                    Text("On").pixelLabel(.caption)
                }
                .tint(Palette.magenta)
                .fixedSize()
                .accessibilityLabel("Aurora FM on")
                .accessibilityIdentifier("radio.toggle")
            }

            if let track = radio.current {
                NowPlayingCard(track: track)
            }

            statusLine

            Text("Up next").pixelLabel(.caption, color: Palette.cream.opacity(0.7))
            VStack(spacing: 6) {
                ForEach(upNext) { track in
                    TrackRow(track: track, playing: track == radio.current) { radio.play(track) }
                }
            }
            Text("Music from Apple Music. Songs belong to their artists and labels.")
                .pixelLabel(.caption2, color: Palette.cream.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        // Opening the radio starts it (if it's switched on).
        .task {
            guard !DebugLaunch.offline else { return }
            if model.settings.radioOn { radio.resume() } else { await radio.prepare() }
        }
        .onChange(of: model.settings.radioOn) { _, on in if on { radio.resume() } }
    }

    /// The current song first, then this loop's remaining order, then the songs already played.
    private var upNext: [RadioTrack] {
        let radio = model.radio
        let order = radio.queue.order
        let at = radio.queue.position
        let rest = Array(order[at...]) + Array(order[..<at])
        return rest.map { AuroraFM.tracks[$0] }
    }

    @ViewBuilder
    private var statusLine: some View {
        let radio = model.radio
        VStack(alignment: .leading, spacing: 6) {
            accessLine
            if radio.access == .ready {
                Text("\(radio.foundCount) of \(radio.tracks.count) songs found in Apple Music")
                    .pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
                if let why = radio.fallbackReason {
                    Text("Previews come from the iTunes catalog. Full songs need MusicKit (\(why)).")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.cream.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("radio.fallback")
                }
            }
            if let error = radio.lastError {
                Text(error)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.sunset)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("radio.error")
            }
            if radio.access != .ready || radio.lastError != nil || radio.fallbackReason != nil {
                Button("Try again") { radio.retry() }
                    .buttonStyle(.neon(Palette.teal))
                    .accessibilityIdentifier("radio.retry")
            }
        }
    }

    @ViewBuilder
    private var accessLine: some View {
        let radio = model.radio
        switch radio.access {
        case .ready:
            Label(radio.fullSongs ? "Full songs with your Apple Music" : "30-second previews · Apple Music plays full songs",
                  systemImage: radio.fullSongs ? "music.note" : "music.note.list")
                .pixelLabel(.caption2, color: Palette.teal)
        case .asking, .unknown:
            Label("Connecting to Apple Music…", systemImage: "antenna.radiowaves.left.and.right")
                .pixelLabel(.caption2, color: Palette.cream.opacity(0.7))
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Allow Apple Music in Settings to play the radio", systemImage: "gearshape")
                    .pixelLabel(.caption2, color: Palette.sunset)
            }
        case .restricted:
            Label("Apple Music is restricted on this phone", systemImage: "lock.fill")
                .pixelLabel(.caption2, color: Palette.sunset)
        case .unavailable(let why):
            Label("\(why) The \"+\" buttons still open each song.", systemImage: "wifi.exclamationmark")
                .pixelLabel(.caption2, color: Palette.sunset)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The song playing now: artwork, credits, the transport and "+".
private struct NowPlayingCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let track: RadioTrack

    var body: some View {
        let radio = model.radio
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Cover(song: radio.song(for: track), url: radio.artworkURL(for: track), size: 72)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(track.title).pixelLabel(.headline, color: Palette.cream).lineLimit(2)
                        if track.explicit { ExplicitBadge() }
                    }
                    Text(track.credit).pixelLabel(.caption, color: Palette.cream.opacity(0.75)).lineLimit(2)
                }
                Spacer(minLength: 4)
                AddButton { openURL(radio.appleMusicURL(for: track)) }
                    .accessibilityLabel("Add \(track.title) in Apple Music")
                    .accessibilityIdentifier("radio.add.now")
            }
            ProgressView(value: radio.progress).tint(Palette.magenta)
            HStack(spacing: 34) {
                Spacer()
                Button(action: radio.previous) { Image(systemName: "backward.fill") }
                    .accessibilityLabel("Previous song")
                Button(action: radio.togglePlay) {
                    Image(systemName: radio.isPlaying ? "pause.fill" : "play.fill").font(.title)
                }
                .accessibilityLabel(radio.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("radio.play")
                Button(action: radio.next) { Image(systemName: "forward.fill") }
                    .accessibilityLabel("Next song")
                    .accessibilityIdentifier("radio.next")
                Spacer()
            }
            .font(.title2)
            .foregroundStyle(Palette.cream)
            .disabled(!model.settings.radioOn)
        }
        .padding(12)
        .background(Palette.magenta.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.magenta.opacity(0.6), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct TrackRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let track: RadioTrack
    let playing: Bool
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                HStack(spacing: 10) {
                    Cover(song: model.radio.song(for: track), url: model.radio.artworkURL(for: track), size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(track.title).pixelLabel(.callout, color: playing ? Palette.magenta : Palette.cream)
                                .lineLimit(1)
                            if track.explicit { ExplicitBadge() }
                        }
                        Text(track.credit).pixelLabel(.caption2, color: Palette.cream.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if playing {
                        Image(systemName: "waveform").foregroundStyle(Palette.magenta)
                            .accessibilityLabel("Playing")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Plays this song now")
            .accessibilityIdentifier("radio.track.\(track.id)")
            AddButton { openURL(model.radio.appleMusicURL(for: track)) }
                .accessibilityLabel("Add \(track.title) in Apple Music")
                .accessibilityIdentifier("radio.add.\(track.id)")
        }
        .padding(.vertical, 4)
    }
}

/// "+": opens the song in Apple Music, where it can be added to the library.
private struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Palette.cream))
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}

private struct ExplicitBadge: View {
    var body: some View {
        Text("E")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Palette.ink)
            .frame(width: 15, height: 15)
            .background(RoundedRectangle(cornerRadius: 3).fill(Palette.cream.opacity(0.75)))
            .accessibilityLabel("Explicit")
    }
}

/// The Apple Music cover art, or a neon placeholder until it loads.
private struct Cover: View {
    let song: Song?
    var url: URL? = nil
    let size: CGFloat

    var body: some View {
        Group {
            if let artwork = song?.artwork {
                ArtworkImage(artwork, width: size, height: size)
            } else if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Palette.magenta, Palette.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note").foregroundStyle(Palette.cream.opacity(0.8))
        }
    }
}

/// Aurora FM from the main-menu phone.
struct RadioScreen: View {
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Radio") { router.back() }
                RadioPanel()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }
}

/// The phone you pull out mid-game: Aurora FM in an iPhone-shaped frame on the right. The
/// street holds still while it's out.
struct InGamePhone: View {
    /// What the player is doing, for Atlas.
    var context: AtlasContext?
    let onClose: () -> Void
    @State private var app: PhoneApp? = nil

    enum PhoneApp: String, CaseIterable, Identifiable {
        case dashboard, atlas, radio
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .atlas: "Atlas"
            case .radio: "Radio"
            }
        }
        var icon: String {
            switch self {
            case .dashboard: "chart.bar.xaxis"
            case .atlas: "sparkles"
            case .radio: "radio.fill"
            }
        }
        var color: Color {
            switch self {
            case .dashboard: Palette.sunset
            case .atlas: Palette.teal
            case .radio: Palette.magenta
            }
        }
    }

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 0) {
                Capsule().fill(Color.black).frame(width: 90, height: 24)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                if let app {
                    HStack {
                        Button { withAnimation(.easeOut(duration: 0.15)) { self.app = nil } } label: {
                            Label("Home", systemImage: "chevron.left")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.cream)
                                .frame(minWidth: 64, minHeight: 36, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("phone.home")
                        Spacer()
                        Text(app.title).font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(app.color)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                }
                Group {
                    switch app {
                    case nil: home
                    case .dashboard: ScrollView { DashboardPanel().padding(14) }.scrollBounceBehavior(.basedOnSize)
                    case .atlas: AtlasPanel(context: context).padding(14)
                    case .radio: ScrollView { RadioPanel().padding(14) }.scrollBounceBehavior(.basedOnSize)
                    }
                }
                .frame(maxHeight: .infinity)
                Button(action: onClose) {
                    Capsule().fill(Palette.cream.opacity(0.8)).frame(width: 110, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .accessibilityLabel("Put the phone away")
                .accessibilityIdentifier("phone.close")
            }
            .frame(width: 340)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1A1030), Palette.ink], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(Color(hex: 0x3A3A44), lineWidth: 6))
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .shadow(color: .black.opacity(0.6), radius: 20)
            .padding(.vertical, 8)
            .padding(.trailing, 24)
        }
        .background(Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: onClose))
        .transition(.move(edge: .trailing))
    }

    private var home: some View {
        VStack(spacing: 14) {
            Text(Date.now, format: .dateTime.hour().minute())
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.cream)
                .padding(.top, 10)
                .accessibilityHidden(true)
            if let activity = context?.activity {
                Text(activity).pixelLabel(.caption, color: Palette.teal)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            HStack(spacing: 18) {
                ForEach(PhoneApp.allCases) { a in
                    Button { withAnimation(.easeOut(duration: 0.15)) { app = a } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: a.icon)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 62, height: 62)
                                .background(a.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text(a.title).font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.cream)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("phone.app.\(a.rawValue)")
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// The song playing, tucked under the heat meter. Tap it to pull out the phone.
struct NowPlayingChip: View {
    @Environment(AppModel.self) private var model
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: model.radio.isPlaying ? "music.note" : "iphone")
                    .font(.system(size: 12, weight: .bold))
                if let track = model.radio.current, model.settings.radioOn {
                    Text("\(track.title) · \(track.artist)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                } else {
                    Text("Phone").font(.system(size: 11, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(Palette.cream)
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .frame(maxWidth: 190)
            .background(Palette.magenta.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.magenta.opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.radio.current.map { "Now playing \($0.title) by \($0.credit). Open phone" } ?? "Open phone")
        .accessibilityIdentifier("hud.phone")
    }
}
