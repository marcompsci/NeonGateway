import Foundation
import GameCore

/// Launch arguments for hands-free testing. They do nothing in Release builds.
///
///     -NGAutoJob coldCrate   open that job directly, skipping the splash and menus
///     -NGAutopilot YES       let the autopilot drive (skips the brief)
///     -NGOpenScreen garage   open missionSelect, garage, records, settings, business, bodyShop,
///                            paintStudio, rankings, phone, league, bank, properties, trophies,
///                            skills or controls directly
///     -NGLegendary YES       enough reputation for Legendary rank
///     -NGUnlockAll YES       every job on the map is playable, whatever the reputation
///     -NGSkipOnboarding YES  make a stand-in player (pistol) if there isn't one yet
///     -NGRedoOnboarding YES  forget the player so onboarding runs again
///     -NGTime night          force day, dawn, dusk or night
enum DebugLaunch {
    static var openScreen: Screen? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "NGOpenScreen") {
        case "missionSelect": .missionSelect
        case "garage": .garage
        case "records": .records
        case "settings": .settings
        case "business": .business
        case "bodyShop": .bodyShop
        case "paintStudio": .paintStudio
        case "rankings": .rankings
        case "phone": .phone
        case "radio": .radio
        case "dashboard": .dashboard
        case "atlas": .atlas
        case "dealership": .dealership
        case "rims": .rims
        case "mechanic": .mechanic
        case "style": .style
        case "league": .league
        case "bank": .bank
        case "properties": .properties
        case "trophies": .trophies
        case "skills": .skills
        case "controls": .controls
        case "online": .online
        default: nil
        }
        #else
        nil
        #endif
    }

    /// -NGAutoJob solara: straight into Solara State.
    static var autoState: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "NGAutoJob") == "solara"
        #else
        false
        #endif
    }

    /// -NGAutoFreight YES: take the first freight haul at Port Aurora's depot on arrival.
    static var autoFreight: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NGAutoFreight")
        #else
        false
        #endif
    }

    /// -NGCops YES: a wanted player with a cruiser pulling up (to see the officers' warning).
    static var cops: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NGCops")
        #else
        false
        #endif
    }

    /// -NGNoSpin YES: character previews stay facing the camera (screenshots).
    static var noSpin: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NGNoSpin")
        #else
        false
        #endif
    }

    /// -NGOnFoot YES: step out of the car as the drive starts (screenshots of people).
    static var onFoot: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NGOnFoot")
        #else
        false
        #endif
    }

    /// -NG2D YES: the old top-down view for this launch.
    static var force2D: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NG2D")
        #else
        false
        #endif
    }

    /// -NGFootView close|eyes|overhead: the on-foot camera for this launch.
    static var footView: FootView? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "NGFootView").flatMap(FootView.init(rawValue:))
        #else
        nil
        #endif
    }

    static var autoJob: MissionID? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "NGAutoJob").flatMap(MissionID.init(rawValue:))
        #else
        nil
        #endif
    }

    /// -NGTime day|dawn|dusk|night: force the light (for screenshots).
    static var timeOfDay: TimeOfDay? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "NGTime") {
        case "day": .day
        case "dawn": .dawn
        case "dusk": .dusk
        case "night": .night
        default: nil
        }
        #else
        nil
        #endif
    }

    /// -NGArtSheet 1|2|3: show the art review sheet instead of the game.
    static var artSheet: Int? {
        #if DEBUG
        let v = UserDefaults.standard.integer(forKey: "NGArtSheet")
        return v > 0 ? v : nil
        #else
        nil
        #endif
    }

    static var autopilot: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NGAutopilot")
        #else
        false
        #endif
    }

    static var skipOnboarding: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NGSkipOnboarding")
        #else
        false
        #endif
    }

    static var redoOnboarding: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NGRedoOnboarding")
        #else
        false
        #endif
    }

    /// `-NGOnboardingStep create|weapon|rules|card` opens onboarding at that step (with a
    /// stand-in name), for screenshots.
    static var onboardingStep: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "NGOnboardingStep")
        #else
        nil
        #endif
    }

    /// `-NGLegendary YES`: enough reputation for Legendary rank (to try design selling).
    static var legendary: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NGLegendary")
        #else
        false
        #endif
    }

    /// `-NGOffline YES`: never contact Game Center or iCloud (UI tests, screenshots).
    static var offline: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NGOffline")
        #else
        false
        #endif
    }

    static var unlockAll: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NGUnlockAll")
        #else
        false
        #endif
    }
}
