import SwiftUI
import GameCore

struct SettingsView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(title: "Settings") { router.back() }
                VStack(spacing: 4) {
                    SettingToggle(title: "Sound", detail: "Engine, siren and effects (follows the silent switch)",
                                  isOn: $model.settings.soundOn)
                    SettingToggle(title: "Haptics", detail: "Bumps on hits and drifts",
                                  isOn: $model.settings.hapticsOn)
                    SettingToggle(title: "CRT scanlines", detail: "Retro screen effect",
                                  isOn: $model.settings.crtOn)
                    SettingToggle(title: "Live weather and time", detail: "Rain and night follow your real clock. Off: always a clear day",
                                  isOn: $model.settings.liveWeather)
                    ReduceMotionPicker(selection: $model.settings.reduceMotionOverride)
                    SettingPicker(title: "Aim assist", detail: "How much shots snap to whatever you're facing",
                                  selection: $model.settings.aimAssist,
                                  options: AimAssist.allCases.map { ($0, $0.label) })
                    SettingPicker(title: "Frame rate", detail: "30 saves battery and heat. 120 needs a ProMotion screen",
                                  selection: $model.settings.frameRate,
                                  options: [(30, "30"), (60, "60"), (120, "120")])
                    Button("Customise touch controls") { router.go(.controls) }
                        .buttonStyle(.neon(Palette.teal))
                        .accessibilityHint("Move, resize and fade the on-screen buttons, or swap sides")
                        .accessibilityIdentifier("settings.controls")
                        .padding(.vertical, 8)
                    Text("Game controllers work too: left stick steers, right trigger is gas, left trigger brakes, B drifts, right shoulder fires, A gets in or out, Y switches weapon, Menu pauses.")
                        .font(.pixel(.caption, weight: .medium))
                        .foregroundStyle(Palette.cream.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }
}

struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).pixelLabel(.headline)
                Text(detail).font(.pixel(.caption, weight: .medium))
                    .foregroundStyle(Palette.cream.opacity(0.6))
            }
        }
        .tint(Palette.teal)
        .padding(.vertical, 12)
        .accessibilityHint(detail)
    }
}

struct ReduceMotionPicker: View {
    @Binding var selection: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reduce motion").pixelLabel(.headline)
            Picker("Reduce motion", selection: $selection) {
                Text("iOS").tag(Bool?.none)
                Text("On").tag(Bool?.some(true))
                Text("Off").tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            Text("Turns off camera sway and zoom while driving.")
                .font(.pixel(.caption, weight: .medium))
                .foregroundStyle(Palette.cream.opacity(0.6))
        }
        .padding(.vertical, 12)
    }
}

/// A labelled segmented picker for a setting.
struct SettingPicker<Value: Hashable>: View {
    let title: String
    let detail: String
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).pixelLabel(.headline)
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { i in
                    Text(options[i].1).tag(options[i].0)
                }
            }
            .pickerStyle(.segmented)
            Text(detail)
                .font(.pixel(.caption, weight: .medium))
                .foregroundStyle(Palette.cream.opacity(0.6))
        }
        .padding(.vertical, 12)
    }
}
