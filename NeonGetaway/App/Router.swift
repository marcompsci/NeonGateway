import SwiftUI

enum Screen: Hashable {
    case missionSelect
    case drive(DriveMode)
    case garage
    case records
    case settings
    case business
    case bodyShop
    case paintStudio
    case rankings
    case phone
    case league
    case bank
    case properties
    case trophies
    case skills
    case controls
    case online
}

@MainActor
@Observable
final class Router {
    var path: [Screen] = []

    func go(_ screen: Screen) { path.append(screen) }
    func back() { if !path.isEmpty { path.removeLast() } }
    func home() { path.removeAll() }
}
