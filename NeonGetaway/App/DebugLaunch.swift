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

    static var autoJob: MissionID? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "NGAutoJob").flatMap(MissionID.init(rawValue:))
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
