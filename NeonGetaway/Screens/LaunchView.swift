import SwiftUI

/// Short title card shown once per launch. Tap to skip; no motion under Reduce Motion.
struct LaunchView: View {
    let onFinished: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            TitleLockup()
                .scaleEffect(shown || reduceMotion ? 1 : 0.9)
                .opacity(shown ? 1 : 0)
            Text("Port Aurora · after dark")
                .pixelLabel(.footnote, color: Palette.sunset)
                .opacity(shown ? 1 : 0)
            Spacer()
            Text("Tap to start").pixelLabel(.caption, color: Palette.cream.opacity(0.6))
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onFinished() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the main menu")
        .task {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { shown = true }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { onFinished() }
        }
    }

    private var reduceMotion: Bool { model.reduceMotion(system: systemReduceMotion) }
}

/// The game's wordmark, drawn in type: no image assets.
struct TitleLockup: View {
    var body: some View {
        VStack(spacing: -4) {
            Text("NEON")
                .font(.system(size: 64, weight: .black, design: .monospaced))
                .foregroundStyle(Palette.magenta)
                .shadow(color: Palette.magenta.opacity(0.7), radius: 12)
            Text("GETAWAY")
                .font(.system(size: 44, weight: .black, design: .monospaced))
                .foregroundStyle(Palette.teal)
                .shadow(color: Palette.teal.opacity(0.7), radius: 10)
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Neon Getaway")
        .accessibilityAddTraits(.isHeader)
    }
}
