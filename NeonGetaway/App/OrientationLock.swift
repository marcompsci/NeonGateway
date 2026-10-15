import SwiftUI
import UIKit

/// Menus stay portrait; the street (free roam, jobs, live play) and the touch-control editor
/// turn the phone sideways so you can see more of Port Aurora.
@MainActor
enum OrientationLock {
    static private(set) var mask: UIInterfaceOrientationMask = .portrait

    static func set(_ newMask: UIInterfaceOrientationMask) {
        guard newMask != mask else { return }
        mask = newMask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

extension View {
    /// Holds the screen in landscape while this view is up, and goes back to portrait after.
    func landscapeWhileVisible() -> some View {
        onAppear { OrientationLock.set(.landscape) }
            .onDisappear { OrientationLock.set(.portrait) }
    }
}
