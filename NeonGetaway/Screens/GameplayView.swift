import SwiftUI
import SpriteKit
import GameCore

struct GameplayView: View {
    let mode: DriveMode
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: GameSession?
    @State private var live: LiveCoordinator?
    @State private var showControlsTip = !UserDefaults.standard.bool(forKey: GameplayView.tipKey)
    static let tipKey = "neon.seenControlsTip"

    private func dismissTip() {
        UserDefaults.standard.set(true, forKey: Self.tipKey)
        withAnimation { showControlsTip = false }
    }

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()
            if let session {
                SpriteView(scene: session.scene,
                           preferredFramesPerSecond: model.settings.frameRate,
                           options: [.ignoresSiblingOrder],
                           debugOptions: Self.debugOptions)
                    .ignoresSafeArea()
                    .accessibilityLabel("Port Aurora street view")

                if session.phase != .photo {
                    Group {
                        HUDView(hud: session.hud, district: session.district,
                                onPause: { session.pause() },
                                onCycleWeapon: { session.cycleWeapon() })
                        TouchControlsView(input: session.input, hud: session.hud,
                                          layout: ControlLayout(model.settings),
                                          onContext: { session.performContext() })
                            .disabled(session.phase != .driving)
                    }
                    .dynamicTypeSize(...DynamicTypeSize.large)
                }

                if showControlsTip && session.phase == .driving {
                    ControlsTip { dismissTip() }
                        .transition(.opacity)
                }

                switch session.phase {
                case .briefing:
                    if let mission = session.mission {
                        BriefingCard(def: mission,
                                     best: model.progress.missionBests[mission.id.rawValue],
                                     onStart: { session.start() },
                                     onBack: { router.back() })
                    }
                case .paused:
                    PauseMenu(
                        isJob: session.mission != nil,
                        onResume: { session.resume() },
                        onPhoto: { session.enterPhotoMode() },
                        onRestart: { session.restart() },
                        onQuit: {
                            session.leave()
                            router.back()
                        }
                    )
                case .shopping:
                    GunStoreView(seller: session.seller) { session.closeShop(inventory: model.progress.inventory) }
                case .photo:
                    PhotoModeBar(snap: { session.snapshot() },
                                 onTaken: { model.recordPhoto() },
                                 onDone: { session.leavePhotoMode() })
                case .finished:
                    if let outcome = session.freeDriveOutcome {
                        FreeDriveEndCard(outcome: outcome,
                                         onContinue: { session.restart() },
                                         onLeave: {
                                             session.leave()
                                             router.back()
                                         })
                    } else if let mission = session.mission, let result = session.result {
                        MissionCompleteView(def: mission, result: result, update: session.update,
                                            onRetry: { session.restart() },
                                            onReturn: { router.back() })
                    }
                case .driving:
                    EmptyView()
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if session == nil {
                let (weather, light) = model.conditions()
                let s = GameSession(mode: mode,
                                    vehicle: model.progress.selectedModel,
                                    tuning: model.progress.upgrades,
                                    inventory: model.progress.inventory,
                                    profile: model.progress.profile,
                                    design: model.selectedDesign,
                                    skills: model.progress.skills.levels,
                                    aimAssist: model.settings.aimAssist,
                                    weather: weather,
                                    timeOfDay: light,
                                    reduceMotion: model.reduceMotion(system: systemReduceMotion),
                                    haptics: model.haptics,
                                    audio: model.audio,
                                    autopilot: DebugLaunch.autopilot)
                s.record = { [model] result, def in model.record(result, def: def) }
                s.saveInventory = { [model] inventory in model.saveInventory(inventory) }
                s.keepVehicle = { [model] vehicle in model.keepVehicle(vehicle) }
                s.payTicket = { [model] in model.payTicket() }
                s.saveStats = { [model] stats in model.award(stats) }
                session = s
                if mode == .live, model.live.isPlaying, let id = model.onlineID {
                    let coordinator = LiveCoordinator(service: model.live, myID: id,
                                                      name: model.progress.profile?.name ?? "Driver",
                                                      profile: model.progress.profile, paint: model.selectedDesign,
                                                      blocked: model.progress.online.blocked, scene: s.scene)
                    coordinator.onRecord = { [model] event in model.recordLive(event) }
                    live = coordinator
                }
            }
            if model.settings.soundOn { model.audio.start() }
        }
        .onDisappear {
            session?.leave()
            model.audio.stop()
            if live != nil {
                live?.stop()
                live = nil
                model.live.leave()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session?.pause() }
        }
    }

    private static var debugOptions: SpriteView.DebugOptions {
        #if DEBUG
        [.showsFPS, .showsNodeCount]
        #else
        []
        #endif
    }
}

/// Dimmed full-screen backdrop shared by the overlays.
struct OverlayBackdrop<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.93).ignoresSafeArea()
            ScrollView {
                content
                    .padding(.horizontal, 28)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct PauseMenu: View {
    let isJob: Bool
    let onResume: () -> Void
    var onPhoto: () -> Void = {}
    let onRestart: () -> Void
    let onQuit: () -> Void

    var body: some View {
        OverlayBackdrop {
            VStack(spacing: 18) {
                Spacer(minLength: 60)
                Text("Paused").pixelLabel(.largeTitle, color: Palette.teal)
                    .accessibilityAddTraits(.isHeader)
                Button("Resume", action: onResume).buttonStyle(.neon(Palette.magenta))
                    .accessibilityIdentifier("pause.resume")
                Button("Photo mode", action: onPhoto).buttonStyle(.neon(Palette.teal))
                    .accessibilityHint("Hide the HUD and take a picture of the street")
                    .accessibilityIdentifier("pause.photo")
                Button(isJob ? "Restart job" : "Back to start", action: onRestart).buttonStyle(.neon)
                Button(isJob ? "Quit job" : "Leave", action: onQuit).buttonStyle(.neon(Palette.sunset))
                    .accessibilityIdentifier("pause.quit")
                if isJob {
                    Text("Quitting pays nothing.")
                        .pixelLabel(.caption, color: Palette.cream.opacity(0.6))
                }
            }
        }
    }
}

struct BriefingCard: View {
    static func tip(for def: MissionDef) -> String {
        switch def.kind {
        case .escape:
            "Patrols see in a cone ahead. Break their line of sight and your heat cools. Follow the teal arrow."
        case .double:
            "The clock only runs until the drop. After that there's no timer, just Harbor Patrol: break their line of sight to cool off. Follow the teal arrow."
        case .timedDelivery, .pickupRun:
            def.startingHeat > 0
                ? "You start with heat, so patrols are already looking. Faster, cleaner and more drift pays more. Follow the teal arrow."
                : "Faster, cleaner and more drift pays more. Patrols chase if your heat rises. Follow the teal arrow."
        }
    }

    let def: MissionDef
    let best: MissionBest?
    let onStart: () -> Void
    let onBack: () -> Void

    var body: some View {
        OverlayBackdrop {
            VStack(alignment: .leading, spacing: 16) {
                Text(def.kind.label).pixelLabel(.caption, color: Palette.teal)
                Text(def.title).pixelLabel(.largeTitle, color: Palette.magenta)
                    .accessibilityAddTraits(.isHeader)
                Text(def.brief)
                    .font(.pixel(.body, weight: .medium))
                    .foregroundStyle(Palette.cream)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(def.objectiveLines, id: \.self) { line in
                        Label(line, systemImage: "flag.fill")
                            .font(.pixel(.callout))
                            .foregroundStyle(Palette.teal)
                    }
                }
                HStack(spacing: 22) {
                    if let limit = def.timeLimit {
                        Fact(label: def.clockedObjectives == nil ? "Clock" : "Drop clock", value: "\(Int(limit)) s")
                    }
                    Fact(label: "Pay", value: "\(def.baseReward) cr")
                    Fact(label: "Best", value: best.flatMap { $0.bestTime }.map { String(format: "%.1f s", $0) } ?? "—")
                }
                Text(Self.tip(for: def))
                    .font(.pixel(.footnote, weight: .medium))
                    .foregroundStyle(Palette.cream.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start", action: onStart).buttonStyle(.neon(Palette.magenta))
                    .accessibilityIdentifier("brief.start")
                    .padding(.top, 6)
                Button("Back to map", action: onBack).buttonStyle(.neon(Palette.sunset))
            }
        }
    }
}

/// Free roam ends only when you're busted or knocked out: no pay, straight back to the Safehouse.
struct FreeDriveEndCard: View {
    let outcome: MissionOutcome
    let onContinue: () -> Void
    let onLeave: () -> Void

    var body: some View {
        OverlayBackdrop {
            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 60)
                Text(outcome == .busted ? "Busted" : "Knocked out")
                    .pixelLabel(.largeTitle, color: Palette.sunset)
                    .accessibilityAddTraits(.isHeader)
                Text(outcome == .busted
                     ? "Harbor Patrol boxed you in. They let you go with a warning."
                     : "You took one knock too many. You wake up at the Safehouse, a little dizzy.")
                    .font(.pixel(.callout, weight: .medium))
                    .foregroundStyle(Palette.cream)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Back to the Safehouse", action: onContinue).buttonStyle(.neon(Palette.magenta))
                Button("Leave", action: onLeave).buttonStyle(.neon(Palette.sunset))
            }
        }
    }
}

/// Shown on the first drive only: how the controls work. Tap anywhere on it to dismiss;
/// it also clears itself after a few seconds.
struct ControlsTip: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("How to drive").pixelLabel(.headline, color: Palette.teal)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                Label("Drag the left strip to steer", systemImage: "arrow.left.and.right")
                Label("Hold GAS to go", systemImage: "arrow.up")
                Label("BRAKE slows; hold it at a stop to reverse", systemImage: "arrow.down")
                Label("Hold DRIFT in a turn to slide", systemImage: "tornado")
                Label("GET OUT to go on foot; walk up to any car to GET IN", systemImage: "figure.walk")
            }
            .font(.pixel(.footnote, weight: .medium))
            .foregroundStyle(Palette.cream)
            Text("Tap to close").pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
        }
        .padding(16)
        .background(Palette.ink.opacity(0.92))
        .overlay(Rectangle().strokeBorder(Palette.teal, lineWidth: 2))
        .padding(.horizontal, 28)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Closes the driving tips")
        .task {
            try? await Task.sleep(for: .seconds(7))
            onDismiss()
        }
    }
}

/// Photo mode: the street frozen with the HUD hidden. Snap a picture, then share or save it.
struct PhotoModeBar: View {
    let snap: () -> UIImage?
    let onTaken: () -> Void
    let onDone: () -> Void
    @State private var photo: UIImage?
    @State private var flash = false

    var body: some View {
        VStack {
            Spacer()
            if let photo {
                HStack(spacing: 12) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .overlay(Rectangle().strokeBorder(Palette.cream, lineWidth: 2))
                        .accessibilityLabel("Your photo")
                    ShareLink(item: Image(uiImage: photo),
                              preview: SharePreview("Neon Getaway", image: Image(uiImage: photo))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .pixelLabel(.callout, color: Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(Palette.teal)
                    }
                    .accessibilityHint("Save to Photos or send it")
                }
                .padding(10)
                .background(Palette.ink.opacity(0.85))
            }
            HStack(spacing: 12) {
                Button("Snap") {
                    guard let image = snap() else { return }
                    photo = image
                    onTaken()
                    flash = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        flash = false
                    }
                }
                .buttonStyle(.neon(Palette.magenta))
                .accessibilityIdentifier("photo.snap")
                Button("Done", action: onDone)
                    .buttonStyle(.neon(Palette.sunset))
                    .accessibilityIdentifier("photo.done")
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 30)
        }
        .background(Color.white.opacity(flash ? 0.6 : 0).ignoresSafeArea().allowsHitTesting(false))
        .animation(.easeOut(duration: 0.15), value: flash)
    }
}
