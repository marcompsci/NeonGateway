import SpriteKit
import UIKit
import GameCore

/// The numbers the SwiftUI HUD shows. Updated at ~15 Hz, not every frame.
struct HUDState: Equatable {
    var speed = 0          // display units
    var speedFraction = 0.0
    var isDrifting = false
    var driftScore = 0
    var hits = 0
    var hull = 5
    var hullMax = 5
    var heatPoints = 0
    var heatStars = 0
    var heatLabel = "Calm"
    var chasing = 0
    /// 0...1: how close the player is to being busted.
    var bustFraction = 0.0
    var timeRemaining: Double?
    var objective = ""
    var areaName = ""
    var notice: String?
    var targetName: String?
    var targetMetres: Int?
    var targetBearing: String?
    /// Car, targets and patrols as 0...1 fractions of the district (y up), for the minimap.
    var mapCar = CGPoint.zero
    var mapHeading: Double = .pi / 2
    var mapTargets: [CGPoint] = []
    var mapPatrols: [CGPoint] = []

    // On foot, guns and rides.
    var onFoot = false
    /// 0...100, on foot.
    var health = 100
    var vehicleName: String?
    var weaponName: String?
    var ammo = 0
    /// The 35-round starter limit, when the equipped gun still has it.
    var ammoCap: Int?
    var isMelee = false
    var canFire = false
    var weaponCount = 0
    /// What the context button does right now (get in, get out, shop, keep the car).
    var context: ContextAction?
    /// Witnesses on the phone to Harbor Patrol right now.
    var witnessCalls = 0
    /// Seconds until the first of those calls goes through.
    var witnessSeconds: Double?

    enum ContextAction: Equatable {
        case enter(String)
        case exit
        case shop
        case deal
        case keep(String)

        var title: String {
            switch self {
            case .enter: "Get in"
            case .exit: "Get out"
            case .shop: "Shop"
            case .deal: "Deal"
            case .keep: "Keep car"
            }
        }

        var hint: String {
            switch self {
            case .enter(let name): "Get into the \(name)"
            case .exit: "Get out and go on foot"
            case .shop: "Open the Bolt & Barrel gun store"
            case .deal: "See what the alley dealer is selling"
            case .keep(let name): "Store the \(name) in your Safehouse garage. It becomes yours."
            }
        }
    }
}

enum DriveMode: Hashable {
    case freeDrive
    case mission(MissionID)
    /// Free roam with other players (Game Center match).
    case live
}

/// Owns one run: the scene, the shared control input, the HUD numbers and the job's lifecycle.
/// SwiftUI talks to the session; the scene talks back only through the closures set here.
@MainActor
@Observable
final class GameSession {
    enum Phase: Equatable {
        case briefing, driving, paused, shopping, photo, finished
    }

    @ObservationIgnored let scene: DriveScene
    @ObservationIgnored let input = ControlInput()
    @ObservationIgnored private let haptics: HapticsService
    @ObservationIgnored private let audio: SynthAudio
    /// Saves a finished run and reports what changed. Set by the owner (it writes the save).
    @ObservationIgnored var record: (@MainActor (MissionResult, MissionDef) -> ProgressionRules.Update)?
    /// Saves weapons and ammo as they stand (after shooting, pickups, the shop).
    @ObservationIgnored var saveInventory: (@MainActor (Inventory) -> Void)?
    /// Adds a car to the player's garage; false when the garage is full.
    @ObservationIgnored var keepVehicle: (@MainActor (VehicleID) -> Bool)?
    /// Pays a Harbor Patrol ticket; returns what was paid.
    @ObservationIgnored var payTicket: (@MainActor () -> Int)?
    /// Turns what the player did on the street into skill XP.
    @ObservationIgnored var saveStats: (@MainActor (RunStats) -> Void)?

    let mode: DriveMode
    let mission: MissionDef?
    let district = District.portAuroraDocks

    private(set) var phase: Phase
    /// Who's selling while the shop sheet is open.
    private(set) var seller: GunSeller = .store
    var hud = HUDState()
    private(set) var result: MissionResult?
    private(set) var update: ProgressionRules.Update?
    /// Free roam only: how it ended (busted or knocked out).
    private(set) var freeDriveOutcome: MissionOutcome?

    init(mode: DriveMode, vehicle: VehicleID, tuning: UpgradeLevels, inventory: Inventory,
         profile: PlayerProfile? = nil, design: PaintDesign? = nil, skills: SkillLevels = .init(),
         aimAssist: AimAssist = .standard, weather: Weather = .clear, timeOfDay: TimeOfDay = .day,
         reduceMotion: Bool, haptics: HapticsService, audio: SynthAudio, autopilot: Bool = false) {
        self.mode = mode
        self.haptics = haptics
        self.audio = audio
        let district = District.portAuroraDocks
        let mission: MissionDef?
        let spawn: SpawnPoint
        switch mode {
        case .mission(let id):
            mission = MissionDef.with(id)
            spawn = mission?.start ?? GameCoreSpawns.safehouseRoad
        case .freeDrive, .live:
            mission = nil
            spawn = GameCoreSpawns.safehouseRoad
        }
        self.mission = mission
        // The autopilot (debug only) skips the brief so a hands-free run starts straight away.
        phase = mission == nil || autopilot ? .driving : .briefing

        let scene = DriveScene(size: CGSize(width: 402, height: 874), district: district,
                               mission: mission, spawn: spawn,
                               startVehicle: mission?.startsOnFoot == true ? nil : vehicle,
                               tuning: tuning, inventory: inventory, profile: profile, design: design,
                               skills: skills, aimAssist: aimAssist.coneMultiplier, weather: weather,
                               timeOfDay: timeOfDay)
        scene.scaleMode = .resizeFill
        scene.reduceMotion = reduceMotion
        self.scene = scene
        scene.controls = input
        scene.isRunning = phase == .driving
        scene.useAutopilot = autopilot
        scene.onHUD = { [weak self] state in
            guard let self else { return }
            self.audio.setEngine(speed: state.speedFraction, running: self.phase == .driving)
            self.audio.setSiren(state.chasing > 0 && self.phase == .driving)
            if self.hud != state { self.hud = state }
        }
        scene.onImpact = { [weak self] strength in self?.haptics.impact(strength: strength) }
        scene.onDriftStart = { [weak self] in self?.haptics.tick() }
        scene.onCue = { [weak self] cue in self?.audio.play(cue) }
        scene.onMissionFinished = { [weak self] result in self?.missionFinished(result) }
        scene.onFreeDriveEnded = { [weak self] outcome in self?.freeDriveEnded(outcome) }
        scene.onTicket = { [weak self] in
            guard let self else { return }
            let paid = self.payTicket?() ?? 0
            self.haptics.failure()
            self.scene.show(paid > 0 ? "Ticket: \(paid) cr fine. Heat cleared" : "Ticket: let off with a warning",
                            seconds: 3.5)
        }
        input.onControllerContext = { [weak self] in self?.performContext() }
        input.onControllerCycle = { [weak self] in
            guard self?.phase == .driving else { return }
            self?.cycleWeapon()
        }
        input.onControllerPause = { [weak self] in self?.pause() }
    }

    /// Skill XP for everything since the last save.
    private func flushStats() {
        saveStats?(scene.takeStats())
    }

    // MARK: Photo mode

    /// Freezes the street with the HUD hidden so the player can frame a shot.
    func enterPhotoMode() {
        guard phase == .paused else { return }
        phase = .photo
    }

    func leavePhotoMode() {
        guard phase == .photo else { return }
        phase = .paused
    }

    /// The street as it looks now, without the HUD.
    func snapshot() -> UIImage? {
        scene.snapshot()
    }

    func start() {
        guard phase == .briefing else { return }
        phase = .driving
        scene.isRunning = true
    }

    func pause() {
        guard phase == .driving else { return }
        phase = .paused
        input.releaseAll()
        scene.isRunning = false
        quietAudio()
        saveInventory?(scene.inventory)
        flushStats()
    }

    /// The context button: get in or out, walk into the gun store, or keep a car at the Safehouse.
    func performContext() {
        guard phase == .driving, let action = scene.contextAction else { return }
        switch action {
        case .enter, .exit:
            input.enterExitTapped = true
        case .shop, .deal:
            seller = action == .deal ? .dealer : .store
            phase = .shopping
            input.releaseAll()
            scene.isRunning = false
            quietAudio()
            saveInventory?(scene.inventory)
        case .keep:
            guard let model = scene.city.currentVehicle?.model else { return }
            if keepVehicle?(model) == true {
                _ = scene.keepCurrentVehicle()
                haptics.success()
                audio.play(.success)
            } else {
                scene.show("Garage full: sell a car from the Garage screen")
                haptics.failure()
            }
        }
    }

    /// Back from the gun store with whatever the player now carries.
    func closeShop(inventory: Inventory) {
        guard phase == .shopping else { return }
        scene.replaceInventory(inventory)
        phase = .driving
        scene.isRunning = true
    }

    func cycleWeapon() {
        scene.cycleWeapon()
        haptics.tick()
    }

    /// Leaving the run: keep whatever ammo and pickups the player ended with.
    func leave() {
        input.releaseAll()
        scene.isRunning = false
        quietAudio()
        saveInventory?(scene.inventory)
        flushStats()
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .driving
        scene.isRunning = true
    }

    /// Restart from the spawn point. Skips the brief: the player has just read it.
    func restart() {
        input.releaseAll()
        result = nil
        update = nil
        freeDriveOutcome = nil
        // Ammo spent stays spent; a restart doesn't refill the guns.
        let carried = scene.inventory
        saveInventory?(carried)
        flushStats()
        scene.resetRun()
        scene.replaceInventory(carried)
        phase = .driving
        scene.isRunning = true
    }

    private func quietAudio() {
        audio.setEngine(speed: 0, running: false)
        audio.setSiren(false)
    }

    private func missionFinished(_ result: MissionResult) {
        input.releaseAll()
        quietAudio()
        saveInventory?(scene.inventory)
        flushStats()
        self.result = result
        if let mission, result.outcome != .quit {
            update = record?(result, mission)
        }
        switch result.outcome {
        case .success:
            haptics.success()
            audio.play(.success)
        case .busted:
            haptics.failure()
            audio.play(.busted)
        default:
            haptics.failure()
            audio.play(.failure)
        }
        phase = .finished
    }

    private func freeDriveEnded(_ outcome: MissionOutcome) {
        input.releaseAll()
        quietAudio()
        saveInventory?(scene.inventory)
        flushStats()
        freeDriveOutcome = outcome
        haptics.failure()
        audio.play(outcome == .busted ? .busted : .failure)
        phase = .finished
    }
}
