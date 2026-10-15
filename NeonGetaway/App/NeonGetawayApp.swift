import SwiftUI
import GameCore

@main
struct NeonGetawayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}

/// Launch splash, then the navigation stack. The CRT overlay sits over everything when on.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var router = Router()
    @State private var showingSplash = true

    var body: some View {
        ZStack {
            Palette.asphalt.ignoresSafeArea()

            if let page = DebugLaunch.artSheet {
                ArtSheetView(page: page)
            } else if showingSplash {
                LaunchView { showingSplash = false }
                    .transition(.opacity)
                    .onAppear(perform: applyDebugLaunch)
            } else if model.progress.profile == nil {
                OnboardingView()
                    .transition(.opacity)
            } else {
                NavigationStack(path: $router.path) {
                    MainMenuView()
                        .navigationDestination(for: Screen.self) { screen in
                            destination(for: screen)
                                .toolbar(.hidden, for: .navigationBar)
                        }
                        .toolbar(.hidden, for: .navigationBar)
                }
                .environment(router)
            }

            if model.settings.crtOn {
                CRTOverlay()
            }
        }
        // Menus scale with Dynamic Type up to the second accessibility size.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// Debug builds only: `-NGAutoJob coldCrate` opens that job directly (used by tools/check.command).
    private func applyDebugLaunch() {
        #if DEBUG
        if DebugLaunch.redoOnboarding { model.forgetProfileForTesting() }
        if DebugLaunch.legendary { model.makeLegendaryForTesting() }
        // Hands-free launches (UI tests, the check script's job runs) skip the creator.
        if model.progress.profile == nil
            && (DebugLaunch.skipOnboarding || DebugLaunch.autoJob != nil || DebugLaunch.autoState || DebugLaunch.openScreen != nil) {
            model.completeOnboarding(PlayerProfile(name: "Tester", starter: .pistol))
        }
        #endif
        if DebugLaunch.autoState {
            showingSplash = false
            router.path = [.missionSelect, .drive(.state)]
        } else if let id = DebugLaunch.autoJob {
            showingSplash = false
            router.path = [.missionSelect, .drive(.mission(id))]
        } else if let screen = DebugLaunch.openScreen {
            showingSplash = false
            router.path = [screen]
        }
    }

    @ViewBuilder
    private func destination(for screen: Screen) -> some View {
        switch screen {
        case .missionSelect: MissionSelectView()
        case .drive(let mode): GameplayView(mode: mode)
        case .garage: GarageView()
        case .records: RecordsView()
        case .settings: SettingsView()
        case .business: BusinessView()
        case .bodyShop: BodyShopView()
        case .paintStudio: PaintStudioView()
        case .rankings: RankingsView()
        case .phone: PhoneView()
        case .league: LeagueView()
        case .bank: BankView()
        case .properties: PropertiesView()
        case .trophies: TrophiesView()
        case .skills: SkillsView()
        case .controls: ControlLayoutView()
        case .online: OnlineView()
        case .radio: RadioScreen()
        case .dashboard: DashboardScreen()
        case .atlas: AtlasScreen()
        case .dealership: DealershipView()
        case .rims: RimsView()
        case .mechanic: MechanicView()
        case .style: StyleView()
        }
    }
}
