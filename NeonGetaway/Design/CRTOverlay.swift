import SwiftUI

/// Optional scanline look laid over the whole app. Static (no flicker), so it is safe with
/// Reduce Motion, and invisible to touches and VoiceOver.
struct CRTOverlay: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(.black.opacity(0.22)))
                y += 3
            }
            let vignette = Gradient(colors: [.clear, .black.opacity(0.35)])
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(vignette,
                                               center: CGPoint(x: size.width / 2, y: size.height / 2),
                                               startRadius: min(size.width, size.height) * 0.45,
                                               endRadius: max(size.width, size.height) * 0.75))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
