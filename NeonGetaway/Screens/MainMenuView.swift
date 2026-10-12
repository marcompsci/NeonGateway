import SwiftUI
import GameCore

struct MainMenuView: View {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            SkylineBackdrop()
                .onAppear {
                    model.refreshEconomy()
                    model.gameCenter.authenticate()
                }
                .task(id: model.gameCenter.isAuthenticated) { await model.syncOnline() }
            VStack(spacing: 16) {
                Spacer(minLength: 40)
                TitleLockup()
                if let profile = model.progress.profile {
                    HStack(spacing: 10) {
                        Image(uiImage: PixelArt.portraitImage(profile, scale: 3))
                            .interpolation(.none)
                            .accessibilityHidden(true)
                        Text("Welcome back, \(profile.name)").pixelLabel(.callout, color: Palette.cream)
                    }
                }
                Text("Credits \(model.progress.credits)")
                    .pixelLabel(.subheadline, color: Palette.sunset)
                    .accessibilityLabel("\(model.progress.credits) credits")
                if let payout = model.lastOnlinePayout {
                    Badge(text: "Online sales: \(payout.sales) · +\(payout.net) cr", icon: "paintbrush.fill")
                }
                Spacer()
                VStack(spacing: 12) {
                    Button("Play") { router.go(.missionSelect) }
                        .buttonStyle(.neon(Palette.magenta))
                        .accessibilityIdentifier("menu.play")
                        .accessibilityHint("Open the Port Aurora job map")
                    Button("Online") { router.go(.online) }
                        .buttonStyle(.neon(Palette.sunset))
                        .accessibilityIdentifier("menu.online")
                        .accessibilityHint("Play with other people, the online market and online leaderboards")
                    Button("Garage") { router.go(.garage) }
                        .buttonStyle(.neon)
                        .accessibilityIdentifier("menu.garage")
                    Button("Phone") { router.go(.phone) }
                        .buttonStyle(.neon(Palette.teal))
                        .accessibilityIdentifier("menu.phone")
                        .accessibilityHint("League, daily streak, businesses, bank, ledger, trophies and skills")
                        .overlay(alignment: .topTrailing) {
                            let waiting = Achievements.claimable(model.progress).count
                            if waiting > 0 {
                                Text("\(waiting)")
                                    .font(.pixel(.caption2))
                                    .foregroundStyle(Palette.cream)
                                    .frame(minWidth: 22, minHeight: 22)
                                    .background(Palette.magenta)
                                    .offset(x: 6, y: -8)
                                    .accessibilityLabel("\(waiting) trophies to claim")
                            }
                        }
                    Button("Records") { router.go(.records) }
                        .buttonStyle(.neon)
                        .accessibilityIdentifier("menu.records")
                    Button("Settings") { router.go(.settings) }
                        .buttonStyle(.neon(Palette.sunset))
                        .accessibilityIdentifier("menu.settings")
                }
                .padding(.horizontal, 40)
                Spacer(minLength: 30)
                Text("v\(Self.version) · Rep level \(model.repLevel)")
                    .pixelLabel(.caption2, color: Palette.cream.opacity(0.5))
                    .padding(.bottom, 12)
            }
        }
    }
}

/// A flat pixel skyline along the bottom of the menu, drawn with rectangles.
struct SkylineBackdrop: View {
    // Heights as fractions of the band, fixed so the skyline never changes between launches.
    private let towers: [CGFloat] = [0.35, 0.6, 0.45, 0.8, 0.5, 0.95, 0.4, 0.7, 0.55, 0.85, 0.3, 0.65]

    var body: some View {
        GeometryReader { geo in
            let band = geo.size.height * 0.32
            let width = geo.size.width / CGFloat(towers.count)
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Palette.ink, Palette.asphalt, Color(hex: 0x3A1730)],
                               startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(LinearGradient(colors: [Palette.sunset, Palette.magenta],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: geo.size.width * 0.55)
                    .position(x: geo.size.width / 2, y: geo.size.height - band * 0.9)
                    .opacity(0.55)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(towers.indices, id: \.self) { i in
                        Rectangle()
                            .fill(Palette.ink)
                            .overlay(alignment: .top) {
                                Rectangle().fill(i.isMultiple(of: 2) ? Palette.teal : Palette.magenta)
                                    .frame(height: 3)
                            }
                            .frame(width: width, height: band * towers[i])
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
