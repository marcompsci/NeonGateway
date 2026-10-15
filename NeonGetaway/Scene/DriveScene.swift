import SpriteKit
import UIKit
import GameCore

extension CGPoint {
    init(_ v: Vec2) { self.init(x: v.x, y: v.y) }
}

/// The street scene. It draws Port Aurora and feeds input to `City`; every rule (driving,
/// walking, guns, patrols, the crowd) comes from GameCore. Everything runs at a fixed 1/60 s,
/// so the game feels the same on 60 Hz and 120 Hz screens. Nothing advances until `isRunning`.
@MainActor
final class DriveScene: SKScene {
    let district: District
    let mission: MissionDef?
    let spawn: SpawnPoint
    /// The player's own car at the start (nil = start on foot).
    let startVehicle: VehicleID?
    let tuning: UpgradeLevels
    /// The player's look (nil in old saves: the default magenta jacket).
    let profile: PlayerProfile?
    /// Paint on the car the player starts in.
    let design: PaintDesign?
    let skills: SkillLevels
    /// Auto-aim cone multiplier from Settings.
    let aimAssist: Double
    let weather: Weather
    let timeOfDay: TimeOfDay
    /// Street content: parked cars, weapons lying around, the dealer's corner.
    let parked: [ParkedSpawn]
    let pickupSpots: [PickupSpawn]
    let dealerTile: TileCoord?

    /// Solara State: the big map, streamed in chunks, with depots and freight jobs.
    var stateMode: Bool { district.isLarge }
    private(set) var jobs = StateJobRunner()
    /// Solara: a job was delivered (the session pays it).
    var onStatePayout: ((StateJob, StatePayout) -> Void)?
    /// Ground chunks on screen now, keyed by top-left tile.
    private var chunkNodes: [Int: SKNode] = [:]
    private var landmarkNodes: [String: SKNode] = [:]

    var reduceMotion = false
    var controls: ControlInput?
    /// Steps the world only while true (false during the brief, pause, shop and results).
    var isRunning = false {
        didSet { if !isRunning { lastTime = nil } }
    }
    var onHUD: ((HUDState) -> Void)?
    var onImpact: ((Double) -> Void)?
    var onDriftStart: (() -> Void)?
    var onCue: ((SoundCue) -> Void)?
    var onMissionFinished: ((MissionResult) -> Void)?
    /// Free roam only: the run ended (busted or knocked out) with no job attached.
    var onFreeDriveEnded: ((MissionOutcome) -> Void)?
    /// Harbor Patrol wrote the player a ticket (the session charges the fine).
    var onTicket: (() -> Void)?

    // Live play (set by `LiveCoordinator`).
    /// A knockout doesn't end the street; the coordinator respawns the player.
    var liveMode = false
    var onStep: ((Double) -> Void)?
    var onHitPlayer: ((String, Int, WeaponID?) -> Void)?
    var onClaimDrop: ((String) -> Void)?
    var onLiveKnockout: (() -> Void)?
    private var remoteNodes: [String: RemoteNode] = [:]
    /// Debug only: when set, an autopilot drives to the nearest objective instead of the controls.
    var useAutopilot = false {
        didSet { pilot = makePilot() }
    }

    private(set) var city: City
    private(set) var run = MissionRunState()

    /// See-through cars replaying earlier runs (Street Challenge: Nova and your best).
    struct GhostCar {
        let ghost: Ghost
        let label: String
        let tint: UIColor
    }
    var ghosts: [GhostCar] = []
    private var ghostNodes: [SKNode] = []
    /// Records this run as a ghost (Street Challenge only).
    private var recorder: GhostRecorder?
    /// The run just driven, as a ghost (nil outside the Street Challenge).
    var recordedGhost: Ghost? { recorder?.ghost }
    private var startInventory: Inventory
    private var pilot: Autopilot?
    /// Turns the touch stick into steering, gas and brake (Stick control style).
    private var stickDriver = StickDriver()
    private var pilotTarget: ZoneID?
    private var spottedTime: Double = 0
    /// Seconds left on a job alarm's HUD notice (the setup in a double job).
    private var alarmNoticeTime: Double = 0
    /// A short message of our own (garage, pickups, out of ammo) and how long it stays up.
    private var message: String?
    private var messageTime: Double = 0
    private var runSeed: UInt64 = 1

    private var accumulator: TimeInterval = 0
    private var lastTime: TimeInterval?
    private var frameCount = 0
    private var wasDrifting = false
    private var shakeTime: TimeInterval = 0
    private var built = false

    private let world = SKNode()
    private let cam = SKCameraNode()
    private let arrow = SKShapeNode()
    private let playerNode = SKSpriteNode()
    private let dealerNode = SKNode()
    private let swingNode = SKShapeNode()
    private var vehicleNodes: [Int: VehicleNode] = [:]
    private var personNodes: [Int: SKSpriteNode] = [:]
    private var pickupNodes: [Int: SKNode] = [:]
    private var zoneMarkers: [ZoneID: SKNode] = [:]
    private var patrolNodes: [Int: PatrolNode] = [:]
    private var officerNodes: [Int: SKSpriteNode] = [:]
    /// The player's own car from the garage: wear (drives worse when worn) and rims.
    private var playerWear: CarWear?
    private var playerRims: RimSetup?
    func applyPlayerCar(wear: CarWear?, rims: RimSetup?) {
        playerWear = wear
        playerRims = rims
        city.setPlayerCar(wear: wear, rims: rims)
    }
    private let heldGun = SKNode()
    private var heldWeapon: WeaponID?
    /// Street-level 3D on: the 2D world is hidden and `onFrame` feeds `Street3D` every frame.
    var threeD = false {
        didSet {
            world.isHidden = threeD
            for child in cam.children where child !== visionNode { child.isHidden = threeD }
            if threeD { visionNode.isHidden = true }
        }
    }
    /// After each frame: the city, objective centres, seconds since last frame, shaking, and the
    /// direction the camera faces (radians, world).
    var onFrame: ((City, [Vec2], Double, Bool, Double) -> Void)?
    /// The player threw a punch / fired (the 3D body poses for it).
    var onPunch: ((Strike) -> Void)?
    var onShot: (() -> Void)?
    /// The on-foot camera: 2nd person (close), 1st (eyes) or 3rd (overhead).
    var footView: FootView = .close {
        didSet { visionNode.isHidden = true }
    }
    /// How far the camera has turned (radians); 0 is north up.
    private var camTurn: CGFloat = 0
    /// 1st person: the dark beyond what you can see, fixed to the camera.
    private let visionNode = SKSpriteNode()
    private var visionSize = CGSize.zero
    private var tracerPool: [SKShapeNode] = []
    private var tracerIndex = 0
    private var lookAhead = CGVector.zero
    private var skidPool: [SKSpriteNode] = []
    private var skidIndex = 0
    private var skidCountdown = 0
    /// Seconds of animation time (walk cycles, flicker), advancing only while running.
    private var animTime: Double = 0
    private var playerLook = HDArt.Look(skin: 0x8D5A3B, hair: 0x0B0C10, top: 0xFF3EA5)
    /// Night lights (lamp pools, neon halos, headlights) sit above the night tint.
    static let lightZ: CGFloat = 950
    /// How strongly lights show at this time of day.
    var lightLevel: CGFloat {
        switch timeOfDay {
        case .day: 0
        case .dawn: 0.4
        case .dusk: 0.75
        case .night: 1
        }
    }
    /// Stats already turned into skill XP this trip.
    private var statsTaken = RunStats()

    // Camera tuning; numbers only matter on a phone.
    private let baseZoom: CGFloat = 1.0
    private let footZoom: CGFloat = 0.72
    /// Landscape: the screen is short, so everything is zoomed out by this much.
    private let landscapeZoom: CGFloat = 1.15
    /// AIM's lock-on marker over the target.
    private let reticle = DriveScene.makeReticle()
    private let speedZoom: CGFloat = 0.3
    private let lookAheadSeconds: CGFloat = 0.35
    private let maxLookAhead: CGFloat = 180
    /// Fraction of screen height the player sits above centre, keeping them clear of the thumbs.
    private let carScreenLift: CGFloat = 0.17
    /// Points per metre for HUD distances: one 128-point tile is about a 10 m city lane.
    static let pointsPerMetre = 12.8
    /// Below this speed, a street car parked in the Safehouse bay can be kept.
    static let keepSpeed = 40.0

    init(size: CGSize, district: District, mission: MissionDef?, spawn: SpawnPoint,
         startVehicle: VehicleID?, tuning: UpgradeLevels, inventory: Inventory, profile: PlayerProfile? = nil,
         design: PaintDesign? = nil, skills: SkillLevels = .init(), aimAssist: Double = 1,
         weather: Weather = .clear, timeOfDay: TimeOfDay = .day,
         parked: [ParkedSpawn] = District.docksParked, pickups: [PickupSpawn] = District.docksPickups,
         dealer: TileCoord? = District.docksDealer) {
        self.parked = parked
        self.pickupSpots = pickups
        self.dealerTile = dealer
        self.district = district
        self.mission = mission
        self.spawn = spawn
        self.startVehicle = startVehicle
        self.tuning = tuning
        self.startInventory = inventory
        self.profile = profile
        self.design = design
        self.skills = skills
        self.aimAssist = aimAssist
        self.weather = weather
        self.timeOfDay = timeOfDay
        city = City(district: district, start: spawn, playerVehicle: startVehicle, tuning: tuning,
                    inventory: inventory, startingHeat: mission?.startingHeat ?? 0, seed: 1, parked: parked,
                    pickups: pickups, dealer: dealer, playerDesign: design,
                    skills: skills, aimAssist: aimAssist, weather: weather)
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("DriveScene is created in code")
    }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = Palette.UI.ink
        addChild(world)
        addChild(cam)
        camera = cam
        buildGround()
        buildProps()
        buildZoneMarkers()
        buildSkidPool()
        buildTracers()
        buildPlayer()
        buildDealer()
        buildArrow()
        buildAtmosphere()
        buildGhosts()
        refreshMarkers()
        syncNodes()
        render(smooth: false)
        onHUD?(hudState)
        if weather == .rain { show("Rain: the roads are slippery", seconds: 3) }
    }

    /// Skill XP the player has earned since the last call (each bit of driving counts once).
    func takeStats() -> RunStats {
        let now = city.stats
        var delta = RunStats()
        delta.driven = max(0, now.driven - statsTaken.driven)
        delta.run = max(0, now.run - statsTaken.run)
        delta.hitsLanded = max(0, now.hitsLanded - statsTaken.hitsLanded)
        delta.knocks = max(0, now.knocks - statsTaken.knocks)
        statsTaken = now
        return delta
    }

    /// The street as it looks right now (the HUD is SwiftUI, so it isn't in the picture).
    func snapshot() -> UIImage? {
        guard let view else { return nil }
        return UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            _ = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    // MARK: Live play

    /// Where this player is, for the other phones.
    func liveSnapshot(time: Double) -> PlayerSnapshot {
        let body = city.player
        return PlayerSnapshot(x: body.position.x, y: body.position.y, heading: body.heading, speed: body.speed,
                              vehicle: city.currentVehicle?.model, weapon: city.inventory.equipped,
                              health: Int(city.health.rounded()), time: time)
    }

    /// Draws the other players and lets the city know where they are (to shoot or run over).
    func setRemotes(_ avatars: [RemoteAvatar], looks: [String: RemoteLook]) {
        city.remotes = avatars
        let present = Set(avatars.map(\.id))
        for (id, node) in remoteNodes where !present.contains(id) {
            node.removeFromParent()
            remoteNodes[id] = nil
        }
        for avatar in avatars {
            let node: RemoteNode
            if let existing = remoteNodes[avatar.id] {
                node = existing
            } else {
                node = RemoteNode()
                world.addChild(node)
                remoteNodes[avatar.id] = node
            }
            node.update(avatar, look: looks[avatar.id])
        }
    }

    func takeHit(damage: Int, from attacker: String) {
        for event in city.takeHit(damage: damage, from: attacker) {
            if case .impact(let strength) = event {
                shakeTime = max(shakeTime, 0.18)
                onImpact?(strength)
            }
        }
        onCue?(.hit)
        onHUD?(hudState)
    }

    func surrenderGun() -> (WeaponID, Int)? {
        let gun = city.surrenderGun()
        startInventory = city.inventory
        return gun
    }

    func respawnAtSafehouse() {
        city.respawn(at: GameCoreSpawns.safehouseRoad)
        render(smooth: false)
        onHUD?(hudState)
    }

    func addNetworkDrop(_ drop: NetDrop) {
        city.addNetworkDrop(drop)
    }

    /// The owner of a dropped gun decided. Returns the weapon if this player got it.
    @discardableResult
    func resolveNetworkDrop(_ id: String, mine: Bool) -> WeaponID? {
        for event in city.resolveNetworkDrop(id, mine: mine) {
            if case .pickedUp(let weapon, _) = event {
                onCue?(.pickup)
                startInventory = city.inventory
                onHUD?(hudState)
                return weapon
            }
        }
        return nil
    }

    /// Night, dusk and dawn tint the street; rain falls in front of the camera.
    private func buildAtmosphere() {
        let tint: (UIColor, CGFloat)? = switch timeOfDay {
        case .night: (UIColor(red: 0.04, green: 0.05, blue: 0.2, alpha: 1), 0.3)
        case .dusk: (UIColor(red: 0.55, green: 0.18, blue: 0.35, alpha: 1), 0.18)
        case .dawn: (UIColor(red: 0.95, green: 0.55, blue: 0.45, alpha: 1), 0.12)
        case .day: nil
        }
        if let tint {
            let (color, alpha) = tint
            let shade = SKSpriteNode(color: color, size: CGSize(width: 6_000, height: 6_000))
            shade.alpha = alpha
            shade.zPosition = 900
            shade.name = "atmosphere.tint"
            cam.addChild(shade)
        }
        guard weather == .rain else { return }
        let drop = SKTexture(image: UIGraphicsImageRenderer(size: CGSize(width: 2, height: 14)).image { ctx in
            UIColor(white: 0.85, alpha: 0.7).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 14))
        })
        let rain = SKEmitterNode()
        rain.particleTexture = drop
        rain.particleBirthRate = reduceMotion ? 60 : 220
        rain.particleLifetime = 1.4
        rain.particleSpeed = 900
        rain.particleSpeedRange = 200
        rain.emissionAngle = -.pi / 2 - 0.2
        rain.particleRotation = -0.2
        rain.particleAlpha = 0.55
        rain.particleAlphaRange = 0.25
        rain.particleScale = 1
        rain.particleScaleRange = 0.4
        rain.particlePositionRange = CGVector(dx: 1_400, dy: 0)
        rain.position = CGPoint(x: 0, y: 700)
        rain.zPosition = 901
        rain.name = "atmosphere.rain"
        rain.advanceSimulationTime(2)
        cam.addChild(rain)
    }

    /// Weapons and ammo as they stand now (for saving between runs and around the shop).
    var inventory: Inventory { city.inventory }

    /// After the gun store: the scene picks up what the player now carries.
    func replaceInventory(_ inventory: Inventory) {
        city.inventory = inventory
        startInventory = inventory
        onHUD?(hudState)
    }

    func resetRun() {
        runSeed &+= 1
        city = City(district: district, start: spawn, playerVehicle: startVehicle, tuning: tuning,
                    inventory: startInventory, startingHeat: mission?.startingHeat ?? 0, seed: runSeed,
                    parked: parked, pickups: pickupSpots, dealer: dealerTile,
                    playerDesign: design, skills: skills, aimAssist: aimAssist, weather: weather)
        jobs = StateJobRunner()
        statsTaken = RunStats()
        city.setPlayerCar(wear: playerWear, rims: playerRims)
        run = MissionRunState()
        spottedTime = 0
        alarmNoticeTime = 0
        message = nil
        wasDrifting = false
        accumulator = 0
        lastTime = nil
        lookAhead = .zero
        for skid in skidPool {
            skid.removeAllActions()
            skid.alpha = 0
        }
        pilot = makePilot()
        if mission?.id == .streetChallenge {
            recorder = GhostRecorder(vehicle: city.currentVehicle?.model ?? .vesper)
        }
        refreshMarkers()
        syncNodes()
        render(smooth: false)
        onHUD?(hudState)
    }

    private func makePilot() -> Autopilot? {
        guard useAutopilot, !city.isOnFoot else { return nil }
        let position = city.playerPosition
        guard let nearest = activeZones.min(by: { ($0.rect.center - position).length < ($1.rect.center - position).length }) else {
            return nil
        }
        pilotTarget = nearest.id
        return Autopilot(district: district, from: position, to: nearest.rect.center)
    }

    // MARK: Things the player taps outside the driving controls

    /// What the context button would do right now, if anything.
    var contextAction: HUDState.ContextAction? {
        if city.isOnFoot {
            if city.zone(ofKind: .shop) != nil { return .shop }
            if city.nearDealer { return .deal }
            if let i = city.enterableVehicle {
                return .enter(city.vehicles[i].spec.displayName)
            }
            return nil
        }
        if stateMode, jobs.active == nil, let depot = city.zone(ofKind: .depot),
           city.player.speed < Self.keepSpeed {
            return .jobs(SolaraState.city(for: depot.id)?.name ?? depot.name)
        }
        guard let vehicle = city.currentVehicle else { return nil }
        if !vehicle.owned, vehicle.state.speed < Self.keepSpeed, city.zone(ofKind: .safehouse) != nil {
            return .keep(vehicle.spec.displayName)
        }
        return city.canExit ? .exit : nil
    }

    /// The Safehouse garage took the car: it's the player's now.
    func keepCurrentVehicle() -> VehicleID? {
        let model = city.keepCurrentVehicle()
        if let model { show("\(model.spec.displayName) is in your garage") }
        onHUD?(hudState)
        return model
    }

    // MARK: Solara jobs

    /// The depot the player is in, if any (for the job board).
    var currentDepot: ZoneID? { city.zone(ofKind: .depot)?.id }

    func acceptJob(_ job: StateJob) {
        _ = jobs.accept(job, city: &city)
        onCue?(.door)
        let where_ = job.destinationName(in: district)
        show(job.kind == .freight ? "Rig's yours: haul it to \(where_)" : "Job on: \(job.cargo) to \(where_)", seconds: 3.5)
        if useAutopilot { pilot = makePilot() }
        onHUD?(hudState)
    }

    func dropJob() {
        _ = jobs.abandon(city: &city)
        show("Job dropped")
        onHUD?(hudState)
    }

    func cycleWeapon() {
        city.inventory.cycle()
        onHUD?(hudState)
    }

    /// The weapon bar: put this one in hand.
    func equipWeapon(_ weapon: WeaponID) {
        if city.inventory.equip(weapon) { onCue?(.door) }
        onHUD?(hudState)
    }

    func show(_ text: String, seconds: Double = 2.5) {
        message = text
        messageTime = seconds
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        guard isRunning else { return }
        controls?.pollController()
        let dt = lastTime.map { min(currentTime - $0, 0.25) } ?? 0
        lastTime = currentTime
        accumulator += dt

        let step = VehicleDynamics.fixedStep
        while accumulator >= step && isRunning {
            stepOnce(dt: step)
            accumulator -= step
            animTime += step
        }
        syncNodes()
        render(smooth: true)
        onFrame?(city, activeZones.map(\.rect.center), dt, shakeTime > 0, Double(camTurn) + .pi / 2)

        frameCount += 1
        if frameCount % 4 == 0 { onHUD?(hudState) }
    }

    private func stepOnce(dt: Double) {
        var input = controls?.vehicleInput ?? .idle
        if let controls, controls.style != .classic, city.currentVehicle == nil {
            // On foot (Racer and Stick): the shooter layout. Stick to move, AIM to lock on.
            input = VehicleInput(move: worldStick(controls.stickVector), sprint: controls.sprintHeld, aim: controls.aimHeld)
        } else if let controls, controls.style != .classic {
            // In a car (Racer and Stick): the joystick points where to drive; Racer's GAS and
            // BRAKE pedals work on top of it.
            let stick = worldStick(controls.stickVector)
            if let vehicle = city.currentVehicle {
                var driven = stickDriver.input(stick: stick, brake: controls.brakeHeld, drift: controls.driftHeld,
                                               car: vehicle.state, spec: vehicle.spec)
                // A controller's triggers still work as gas and brake on top of the stick.
                driven.throttle = max(driven.throttle, input.throttle > 0 && driven.brake == 0 ? input.throttle : 0)
                input = driven
            } else {
                input = VehicleInput(move: stick, sprint: controls.sprintHeld)
            }
        }
        let actions = controls?.takeActions() ?? CityActions()
        if pilot != nil, let body = city.currentVehicle?.state { input = pilot!.input(for: body, dt: dt) }

        for event in city.step(input: input, actions: actions, dt: dt) {
            switch event {
            case .impact(let strength):
                shakeTime = max(shakeTime, 0.18)
                onImpact?(strength)
            case .wallHit, .patrolContact:
                onCue?(.hit)
            case .spotted:
                spottedTime = 1.5
                onCue?(.spotted)
            case .busted:
                end(.busted)
                return
            case .knockedOut:
                if liveMode {
                    onCue?(.hit)
                    onLiveKnockout?()
                    continue
                }
                end(.knockedOut)
                return
            case .entered(_, let stolen):
                onCue?(.door)
                if stolen { show("Stolen ride: Safehouse garage keeps it") }
            case .exited:
                onCue?(.door)
            case .wrecked:
                onCue?(.hit)
                show("Wrecked! You're on foot")
            case .pickedUp(let weapon, let ammo):
                onCue?(.pickup)
                show("\(weapon.spec.name) +\(ammo)")
            case .shot(let trace):
                onCue?(.shot)
                drawTracer(trace)
                onShot?()
            case .pedestrianDown:
                onCue?(.knock)
            case .patrolDisabled:
                onCue?(.knock)
                show("Cruiser disabled")
            case .outOfAmmo:
                show(city.inventory.canFire ? "Switched weapon" : "Out of ammo: Bolt & Barrel sells more")
            case .swing(let hit):
                drawSwing()
                if hit { onCue?(.knock) }
            case .punch(let strike, let hit):
                throwFist(strike, hit: hit)
                onPunch?(strike)
                if hit { onCue?(.knock) }
            case .droppedWeapon(let weapon):
                show("\(weapon.spec.name) dropped: grab it")
            case .dealerRobbed:
                onCue?(.knock)
                show("Dealer down! His case spilled")
            case .witnessed:
                show("Someone saw that and is calling it in")
            case .reported:
                onCue?(.spotted)
                show("A witness called Harbor Patrol: they're heading to the scene")
            case .ticketed:
                onTicket?()
            case .hitPlayer(let id, let damage, let weapon):
                onCue?(.knock)
                onHitPlayer?(id, damage, weapon)
            case .claimDrop(let id):
                onClaimDrop?(id)
            case .officersOut:
                onCue?(.door)
            case .copsWarning, .copsOpenFire:
                // The HUD's FREEZE / SHOTS FIRED banner says it.
                onCue?(.spotted)
            case .copShot(let trace):
                onCue?(.shot)
                drawTracer(trace, cop: true)
                if trace.hit { shakeTime = max(shakeTime, 0.12) }
            case .officerDown:
                onCue?(.knock)
                show("Officer down: their sidearm dropped")
            }
        }
        onStep?(dt)
        spottedTime = max(0, spottedTime - dt)
        alarmNoticeTime = max(0, alarmNoticeTime - dt)
        shakeTime = max(0, shakeTime - dt)
        messageTime -= dt
        if messageTime <= 0 { message = nil }

        let driving = city.currentVehicle?.state
        let drifting = driving?.isDrifting ?? false
        if drifting && !wasDrifting { onDriftStart?() }
        wasDrifting = drifting
        if drifting, let body = driving {
            skidCountdown -= 1
            if skidCountdown <= 0 {
                dropSkidMarks(body)
                skidCountdown = 2
            }
        }

        if stateMode {
            for event in jobs.step(city: &city, dt: dt) {
                switch event {
                case .delivered(let job, let payout):
                    onCue?(.success)
                    onImpact?(0.5)
                    show("Delivered! +\(payout.credits) cr" + (payout.reward.label.map { " · \($0)" } ?? ""), seconds: 4)
                    onStatePayout?(job, payout)
                    if useAutopilot { pilot = nil }
                case .failed(_, let why):
                    onCue?(.failure)
                    show("Job failed: \(why)", seconds: 3.5)
                case .needTruck:
                    show("Get back in the rig: the load's in it", seconds: 3)
                case .rideHomeReady:
                    show("Your ride home is in the yard: take the car or the bike", seconds: 5)
                case .started:
                    break
                }
            }
        }

        guard let mission, !run.isFinished else { return }
        let (next, events) = MissionRunner.step(run, def: mission, district: district,
                                                carPosition: city.playerPosition,
                                                heatStars: city.pursuit.heat.stars, dt: dt)
        run = next
        if recorder != nil {
            let body = city.player
            if run.isFinished {
                recorder!.finish(t: run.elapsed, position: body.position, heading: body.heading)
            } else {
                recorder!.record(t: run.elapsed, position: body.position, heading: body.heading)
            }
        }
        var changed = false
        for event in events {
            switch event {
            case .collected:
                changed = true
                city.pursuit.add(.missionEvent(mission.pickupHeat))
                onCue?(.pickup)
            case .objectiveComplete(let index):
                changed = true
                if let alarm = mission.alarm, alarm.afterObjective == index {
                    city.pursuit.raiseAlarm(heat: alarm.heat, at: city.playerPosition)
                    alarmNoticeTime = 4
                    shakeTime = 0.25
                    onImpact?(0.8)
                    onCue?(.spotted)
                }
            case .finished:
                break
            }
        }
        if changed {
            refreshMarkers()
            if useAutopilot { pilot = makePilot() }
        }
        if let outcome = run.outcome {
            end(outcome)
        }
    }

    /// Ends the run: a job reports a result; free roam reports the outcome only.
    func end(_ outcome: MissionOutcome) {
        isRunning = false
        guard let mission else {
            onFreeDriveEnded?(outcome)
            return
        }
        if !run.isFinished { run = MissionRunner.end(run, with: outcome) }
        refreshMarkers()
        onHUD?(hudState)
        onMissionFinished?(MissionResult(missionID: mission.id, kind: mission.kind,
                                         outcome: run.outcome ?? outcome, elapsed: run.elapsed,
                                         timeLimit: mission.timeLimit, hits: city.hits,
                                         driftScore: city.totalDrift, clockElapsed: run.clockElapsed))
    }

    // MARK: HUD

    private var activeZones: [Zone] {
        if stateMode, let job = jobs.active { return district.zones[job.to].map { [$0] } ?? [] }
        guard let mission else { return [] }
        return MissionRunner.activeZones(run, def: mission).compactMap { district.zones[$0] }
    }

    private var hudState: HUDState {
        var h = HUDState()
        let body = city.player
        let vehicle = city.currentVehicle
        h.onFoot = city.isOnFoot
        h.stamina = city.stamina
        h.health = Int(city.health.rounded())
        h.speed = Int((body.speed * 0.3).rounded())
        h.speedFraction = vehicle.map { min(1, $0.state.speed / $0.spec.maxSpeed) } ?? 0
        h.isDrifting = body.isDrifting
        h.driftScore = Int(city.totalDrift)
        h.hits = city.hits
        if let vehicle {
            h.vehicleName = vehicle.spec.displayName
            h.hull = vehicle.hull
            h.hullMax = vehicle.spec.maxIntegrity
        }
        let inv = city.inventory
        h.weaponName = inv.equipped?.spec.name
        h.ammo = inv.equipped.map { inv.ammo(for: $0) } ?? 0
        h.ammoCap = inv.equipped.map { inv.isCapped($0) ? inv.ammoCap(for: $0) : nil } ?? nil
        h.isMelee = inv.equipped?.spec.isMelee ?? false
        h.canFire = inv.canFire
        h.weaponCount = inv.owned.count
        h.weapons = inv.owned.map {
            HUDState.WeaponSlot(id: $0, ammo: inv.ammo(for: $0), loaded: inv.isLoaded($0), equipped: $0 == inv.equipped)
        }
        h.aimLocked = city.aimLock != nil
        h.context = contextAction
        let pursuit = city.pursuit
        h.heatPoints = Int(pursuit.heat.points.rounded())
        h.heatStars = pursuit.heat.stars
        h.heatLabel = pursuit.heat.label
        h.chasing = pursuit.chasingCount
        h.bustFraction = pursuit.bustProgress / Pursuit.bustSeconds
        h.copWarning = city.standoff.secondsLeft
        h.copsFiring = city.standoff.isFiring && city.officers.contains { !$0.isDown }
        h.surrenderFraction = city.surrenderFraction
        h.footView = footView
        h.is3D = threeD
        h.witnessCalls = city.reports.count
        h.witnessSeconds = city.reports.map(\.timeLeft).min().map { $0.rounded(.up) }
        h.areaName = district.neighborhood(at: body.position)
        let bounds = district.bounds
        func map(_ p: Vec2) -> CGPoint { CGPoint(x: p.x / bounds.width, y: p.y / bounds.height) }
        h.mapCar = map(body.position)
        h.mapHeading = body.heading
        h.mapPatrols = pursuit.patrols.filter { $0.mode != .cruise }.map { map($0.car.position) }
        if let mission {
            h.timeRemaining = MissionRunner.timeRemaining(run, def: mission)
            h.objective = run.objectiveIndex < mission.objectiveLines.count
                ? mission.objectiveLines[run.objectiveIndex] : "Job done"
            if run.objectiveIndex == 0, let first = mission.objectives.first, case .collect(let ids) = first {
                h.objective += " (\(run.collected.count)/\(ids.count))"
            }
        } else {
            if liveMode {
                let others = city.remotes.count
                h.objective = others == 0 ? "Live street: waiting for the others to show up"
                    : "Live street: \(others) other driver\(others == 1 ? "" : "s") here"
            } else if stateMode {
                if let job = jobs.active {
                    h.timeRemaining = jobs.timeRemaining
                    h.objective = "\(job.kind.label): \(job.cargo) to \(job.destinationName(in: district)) · \(job.pay) cr"
                    if job.kind == .freight, let truck = jobs.truck, city.currentVehicleIndex != truck {
                        h.objective += " (get back in the rig)"
                    }
                } else if let depot = currentDepot {
                    h.objective = "\(SolaraState.city(for: depot)?.name ?? "Depot") Freight Depot: tap JOBS for work"
                } else {
                    let here = body.position
                    let nearest = ZoneID.stateDepots.compactMap { district.zones[$0] }
                        .min { ($0.rect.center - here).length < ($1.rect.center - here).length }
                    if let nearest {
                        let delta = nearest.rect.center - here
                        let km = delta.length / Self.pointsPerMetre / 1000
                        h.objective = String(format: "Solara State: nearest depot %@ · %.1f km %@",
                                             SolaraState.city(for: nearest.id)?.name ?? nearest.name, km, Self.compass(delta))
                    }
                }
            } else {
                h.objective = city.isOnFoot ? "Free roam: find a ride, a weapon or the gun store"
                                            : "Free roam: explore Port Aurora"
            }
        }
        let targets = activeZones
        h.mapTargets = targets.map { map($0.rect.center) }
        if let nearest = targets.min(by: { ($0.rect.center - body.position).length < ($1.rect.center - body.position).length }) {
            let delta = nearest.rect.center - body.position
            h.targetName = nearest.name
            h.targetMetres = Int((delta.length / Self.pointsPerMetre / 10).rounded()) * 10
            h.jobDistance = jobs.active != nil ? delta.length / Self.pointsPerMetre / 1000 : nil
            h.targetBearing = Self.compass(delta)
        }

        // One notice at a time, most urgent first.
        if h.bustFraction > 0.05 {
            h.notice = pursuit.heat.stars <= Pursuit.ticketMaxStars
                ? "Pull away or get a ticket" : "Pull away or get busted"
        } else if let seconds = h.witnessSeconds {
            h.notice = "Witness calling it in (\(Int(seconds)) s): ditch this ride or get clear"
        } else if city.health <= 25 && city.isOnFoot {
            h.notice = "Hurt: get to a car or the Safehouse"
        } else if alarmNoticeTime > 0, let alarm = mission?.alarm {
            h.notice = alarm.notice
        } else if let mission, MissionRunner.isWaitingForCalm(run, def: mission, district: district,
                                                              carPosition: body.position, heatStars: pursuit.heat.stars) {
            h.notice = "Lose the heat to finish"
        } else if let message {
            h.notice = message
        } else if pursuit.dispatchTime > 0 && pursuit.heat.stars > 0 {
            h.notice = "Dispatch is tracking you"
        } else if spottedTime > 0 {
            h.notice = "Spotted"
        } else if pursuit.heat.stars > 0, district.zones[.customsYard]?.rect.contains(body.position) == true {
            h.notice = "Restricted area"
        }
        return h
    }

    /// 8-point compass word for a world-space direction (north = +y).
    static func compass(_ v: Vec2) -> String {
        let names = ["E", "NE", "N", "NW", "W", "SW", "S", "SE"]
        var angle = atan2(v.y, v.x)
        if angle < 0 { angle += 2 * .pi }
        let index = Int((angle / (.pi / 4)).rounded()) % 8
        return names[index]
    }

    // MARK: Drawing

    private func render(smooth: Bool) {
        let body = city.player
        playerNode.isHidden = !city.isOnFoot
        if city.isOnFoot {
            updateHeldGun()
            playerNode.position = CGPoint(city.foot.position)
            playerNode.zRotation = CGFloat(city.foot.heading - .pi / 2)
            playerNode.texture = HDArt.personTexture(playerLook, frame: walkFrame(speed: city.foot.speed, offset: 0))
        }
        updateArrow()
        updateGhosts()

        // Landscape shows less street above and below, so pull the camera back a little.
        let wide: CGFloat = size.width > size.height ? landscapeZoom : 1
        let view: FootView = city.isOnFoot ? footView : .overhead
        let targetZoom: CGFloat
        if city.isOnFoot {
            switch view {
            case .close: targetZoom = 0.52 * wide
            case .eyes: targetZoom = 0.42 * wide
            case .overhead: targetZoom = footZoom * wide
            }
        } else {
            let fraction = CGFloat(city.currentVehicle.map { min(1, $0.state.speed / $0.spec.maxSpeed) } ?? 0)
            targetZoom = (reduceMotion ? baseZoom + 0.1 : baseZoom + speedZoom * fraction) * wide
        }
        var wantZoom = targetZoom
        if city.currentVehicle?.model.isTruck == true { wantZoom += 0.35 }
        if stateMode && !city.isOnFoot { wantZoom += 0.12 }
        let zoom = smooth && !reduceMotion ? cam.xScale + (wantZoom - cam.xScale) * 0.06 : wantZoom
        cam.setScale(zoom)

        // 2nd and 1st person turn the street so you face up the screen. Walking forward pulls
        // the camera round after you; sidestepping doesn't, so the stick stays predictable.
        if threeD {
            // Street level: the camera sits behind you. In a car it swings round with the car;
            // on foot, walking forward pulls it round and sidesteps don't (the stick stays put).
            let wanted = CGFloat(body.heading) - .pi / 2
            let delta = CGFloat(remainder(Double(wanted - camTurn), 2 * .pi))
            var weight: CGFloat = city.isOnFoot ? 0.35 : 1
            if city.isOnFoot, let stick = controls?.stickVector, stick.length > 0.2 {
                weight = max(0.12, CGFloat(cos(atan2(stick.x, stick.y))))
            }
            if city.isOnFoot, city.aimLock != nil { weight = 1 }
            camTurn = smooth ? camTurn + delta * min(1, (city.isOnFoot ? 0.08 : 0.14) * weight) : wanted
            camTurn = CGFloat(remainder(Double(camTurn), 2 * .pi))
        } else if view == .overhead {
            camTurn = smooth ? camTurn * 0.9 : 0
            if abs(camTurn) < 0.002 { camTurn = 0 }
        } else {
            let wanted = CGFloat(city.foot.heading) - .pi / 2
            let delta = CGFloat(remainder(Double(wanted - camTurn), 2 * .pi))
            var weight: CGFloat = 0.35
            if let stick = controls?.stickVector, stick.length > 0.2 {
                let off = atan2(stick.x, stick.y)   // angle from screen-up
                weight = max(0.15, CGFloat(cos(off)))
            }
            if city.aimLock != nil { weight = 1 }
            camTurn = smooth ? camTurn + delta * min(1, 0.09 * weight) : wanted
            camTurn = CGFloat(remainder(Double(camTurn), 2 * .pi))
        }
        cam.zRotation = camTurn
        for (_, node) in zoneMarkers { node.zRotation = camTurn }

        var targetLook = CGVector.zero
        if !reduceMotion {
            var lx = CGFloat(body.velocity.x) * lookAheadSeconds
            var ly = CGFloat(body.velocity.y) * lookAheadSeconds
            let length = (lx * lx + ly * ly).squareRoot()
            if length > maxLookAhead {
                lx *= maxLookAhead / length
                ly *= maxLookAhead / length
            }
            targetLook = CGVector(dx: lx, dy: ly)
        }
        if view != .overhead {
            // Close views look where you face, not where you're drifting.
            let ahead = size.height * zoom * (view == .eyes ? 0.3 : 0.15)
            let up = Double(camTurn) + .pi / 2
            targetLook = CGVector(dx: CGFloat(cos(up)) * ahead, dy: CGFloat(sin(up)) * ahead)
        }
        if smooth {
            lookAhead.dx += (targetLook.dx - lookAhead.dx) * 0.08
            lookAhead.dy += (targetLook.dy - lookAhead.dy) * 0.08
        } else {
            lookAhead = targetLook
        }

        var shake = CGVector.zero
        if shakeTime > 0 && !reduceMotion {
            shake = CGVector(dx: CGFloat.random(in: -6...6), dy: CGFloat.random(in: -6...6))
        }
        // Portrait lifts the player clear of the thumbs; landscape thumbs are at the sides.
        let lift = view == .overhead ? size.height * (size.width > size.height ? 0.03 : carScreenLift) * zoom : 0
        updateReticle()
        cam.position = CGPoint(x: CGFloat(body.position.x) + lookAhead.dx + shake.dx,
                               y: CGFloat(body.position.y) + lookAhead.dy - lift + shake.dy)
        updateVision(on: view == .eyes && !threeD)
        updateStreaming(budget: smooth ? 2 : 400)
    }

    /// Replaces the ghost cars (a restart may bring a new best).
    func setGhosts(_ cars: [GhostCar]) {
        ghosts = cars
        guard built else { return }
        ghostNodes.forEach { $0.removeFromParent() }
        ghostNodes = []
        buildGhosts()
    }

    private func buildGhosts() {
        if mission?.id == .streetChallenge {
            recorder = GhostRecorder(vehicle: city.currentVehicle?.model ?? .vesper)
        }
        for car in ghosts {
            let node = SKNode()
            let size = HDArt.vehicleSize(car.ghost.vehicle)
            let body = SKSpriteNode(texture: HDArt.vehicleTexture(car.ghost.vehicle), size: size)
            body.color = car.tint
            body.colorBlendFactor = 0.65
            body.alpha = 0.5
            body.blendMode = .add
            node.addChild(body)
            let halo = SKShapeNode(rectOf: CGSize(width: size.width + 8, height: size.height + 8), cornerRadius: 8)
            halo.strokeColor = car.tint.withAlphaComponent(0.7)
            halo.lineWidth = 2
            halo.glowWidth = 3
            halo.fillColor = .clear
            node.addChild(halo)
            let tag = SKLabelNode(text: car.label.uppercased())
            tag.fontName = "Menlo-Bold"
            tag.fontSize = 13
            tag.fontColor = car.tint
            tag.name = "tag"
            tag.verticalAlignmentMode = .center
            node.addChild(tag)
            node.zPosition = 30
            node.isHidden = true
            world.addChild(node)
            ghostNodes.append(node)
        }
    }

    private func updateGhosts() {
        let t = run.elapsed
        for (car, node) in zip(ghosts, ghostNodes) {
            guard let pose = car.ghost.pose(at: t) else { continue }
            node.isHidden = false
            node.position = CGPoint(pose.position)
            node.zRotation = CGFloat(pose.heading - .pi / 2)
            // Keep the name tag upright and above the car whatever way it faces.
            if let tag = node.childNode(withName: "tag") {
                tag.zRotation = -node.zRotation
                // The offset is turned back by the node's rotation so the tag always sits screen-up.
                let up: CGFloat = 42
                tag.position = CGPoint(x: up * sin(node.zRotation), y: up * cos(node.zRotation))
            }
            // Fade a ghost that has already finished.
            node.alpha = t > car.ghost.duration + 1.5 ? 0.35 : 1
        }
    }

    private static func makeReticle() -> SKNode {
        let node = SKNode()
        let ring = SKShapeNode(circleOfRadius: 22)
        ring.strokeColor = Palette.UI.magenta
        ring.lineWidth = 3
        ring.glowWidth = 4
        ring.fillColor = .clear
        node.addChild(ring)
        for i in 0..<4 {
            let tick = SKShapeNode(rectOf: CGSize(width: 3, height: 12))
            tick.fillColor = Palette.UI.cream
            tick.strokeColor = .clear
            let a = CGFloat(i) * .pi / 2
            tick.position = CGPoint(x: cos(a) * 30, y: sin(a) * 30)
            tick.zRotation = a + .pi / 2
            node.addChild(tick)
        }
        node.zPosition = DriveScene.lightZ + 5
        node.isHidden = true
        return node
    }

    private func updateReticle() {
        if reticle.parent == nil { world.addChild(reticle) }
        if let lock = city.aimLock {
            reticle.isHidden = false
            reticle.position = CGPoint(lock)
            reticle.zRotation = CGFloat(animTime * 2)
        } else {
            reticle.isHidden = true
        }
    }

    /// Keeps one node per vehicle, person, pickup and patrol in step with GameCore.
    private func syncNodes() {
        for vehicle in city.vehicles {
            let node: VehicleNode
            if let existing = vehicleNodes[vehicle.id] {
                node = existing
            } else {
                node = VehicleNode(model: vehicle.model, design: vehicle.design, rims: vehicle.rims)
                world.addChild(node)
                vehicleNodes[vehicle.id] = node
            }
            node.update(vehicle)
            node.isHidden = vehicle.retired
            let driving = city.currentVehicleIndex.map { city.vehicles[$0].id == vehicle.id } ?? false
            node.setLights(driving ? lightLevel : 0)
            node.setRider(driving && vehicle.model.isMotorcycle ? playerLook : nil)
        }

        for person in city.crowd.people {
            let node: SKSpriteNode
            if let existing = personNodes[person.id] {
                node = existing
            } else {
                node = SKSpriteNode()
                node.zPosition = 8
                world.addChild(node)
                personNodes[person.id] = node
            }
            let fleeing = person.mode == .flee
            node.texture = HDArt.personTexture(HDArt.crowdLook(person.look),
                                               frame: person.isDown ? 0
                                                   : walkFrame(speed: fleeing ? Crowd.fleeSpeed : Crowd.walkSpeed,
                                                               offset: Double(person.id) * 0.37))
            node.size = CGSize(width: 22, height: 22)
            node.position = CGPoint(person.position)
            if person.isDown {
                // Flat on the ground, cartoon style: tipped over and faded, no injuries.
                node.zRotation = CGFloat(person.heading)
                node.alpha = 0.55
                node.zPosition = 3
            } else {
                node.zRotation = CGFloat(person.heading - .pi / 2)
                node.alpha = 1
                node.zPosition = 8
            }
        }

        let livePickups = Set(city.pickups.map(\.id))
        for (id, node) in pickupNodes where !livePickups.contains(id) {
            node.removeFromParent()
            pickupNodes[id] = nil
        }
        if let dealer = city.dealer {
            dealerNode.isHidden = !dealer.isHere
            dealerNode.position = CGPoint(dealer.position)
        } else {
            dealerNode.isHidden = true
        }
        for pickup in city.pickups {
            let node: SKNode
            if let existing = pickupNodes[pickup.id] {
                node = existing
            } else {
                node = makePickupNode(pickup.weapon)
                node.position = CGPoint(pickup.position)
                world.addChild(node)
                pickupNodes[pickup.id] = node
            }
            node.isHidden = !pickup.isAvailable
        }

        let live = Set(city.pursuit.patrols.map(\.id))
        for (id, node) in patrolNodes where !live.contains(id) {
            node.removeFromParent()
            patrolNodes[id] = nil
        }
        for patrol in city.pursuit.patrols {
            if let node = patrolNodes[patrol.id] {
                node.update(patrol)
            } else {
                let node = PatrolNode(reduceMotion: reduceMotion, lightLevel: lightLevel)
                world.addChild(node)
                patrolNodes[patrol.id] = node
                node.update(patrol)
            }
        }

        let liveOfficers = Set(city.officers.map(\.id))
        for (id, node) in officerNodes where !liveOfficers.contains(id) {
            node.removeFromParent()
            officerNodes[id] = nil
        }
        for officer in city.officers {
            let node: SKSpriteNode
            if let existing = officerNodes[officer.id] {
                node = existing
            } else {
                node = SKSpriteNode()
                node.size = CGSize(width: 24, height: 24)
                world.addChild(node)
                officerNodes[officer.id] = node
            }
            node.texture = HDArt.personTexture(HDArt.officerLook(officer.id),
                                               frame: officer.isDown ? 0 : walkFrame(speed: CopRules.walkSpeed * 0.6,
                                                                                     offset: Double(officer.id) * 0.5))
            node.position = CGPoint(officer.position)
            if officer.isDown {
                node.zRotation = CGFloat(officer.heading)
                node.alpha = 0.55
                node.zPosition = 3
            } else {
                node.zRotation = CGFloat(officer.heading - .pi / 2)
                node.alpha = 1
                node.zPosition = 8
            }
        }
    }

    private func makePickupNode(_ weapon: WeaponID) -> SKNode {
        let node = SKNode()
        node.zPosition = 6
        let pad = SKShapeNode(rectOf: CGSize(width: 44, height: 30))
        pad.fillColor = Palette.UI.ink.withAlphaComponent(0.7)
        pad.strokeColor = Palette.UI.sunset
        pad.lineWidth = 3
        node.addChild(pad)
        let icon = SKSpriteNode(texture: PixelArt.weaponTexture(weapon))
        let natural = icon.texture!.size()
        let fit = min(40 / natural.width, 26 / natural.height)
        icon.size = CGSize(width: natural.width * fit, height: natural.height * fit)
        node.addChild(icon)
        if !reduceMotion {
            node.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.5), .scale(to: 1, duration: 0.5)])))
        }
        return node
    }

    private func drawTracer(_ trace: ShotTrace, cop: Bool = false) {
        guard !tracerPool.isEmpty else { return }
        let line = tracerPool[tracerIndex]
        tracerIndex = (tracerIndex + 1) % tracerPool.count
        let path = CGMutablePath()
        path.move(to: CGPoint(trace.from))
        path.addLine(to: CGPoint(trace.to))
        line.path = path
        let finish = city.inventory.equipped.map { city.inventory.build(for: $0).finish } ?? 0
        line.strokeColor = cop ? UIColor(red: 0.45, green: 0.7, blue: 1, alpha: 1)
            : trace.hit ? Palette.UI.sunset
            : (finish == 0 ? Palette.UI.cream : PixelArt.finishColors[finish % PixelArt.finishColors.count])
        line.removeAllActions()
        line.alpha = 0.9
        line.run(.fadeOut(withDuration: 0.12))
    }

    /// Arrow orbiting the player, pointing at the nearest active objective once it's off to the side.
    private func updateArrow() {
        let position = city.playerPosition
        let targets = activeZones
        guard let nearest = targets.min(by: { ($0.rect.center - position).length < ($1.rect.center - position).length }),
              !nearest.rect.contains(position) else {
            arrow.isHidden = true
            return
        }
        let delta = nearest.rect.center - position
        guard delta.length > 260 else {
            arrow.isHidden = true
            return
        }
        let angle = atan2(delta.y, delta.x)
        arrow.isHidden = false
        arrow.position = CGPoint(x: position.x + cos(angle) * 72, y: position.y + sin(angle) * 72)
        arrow.zRotation = CGFloat(angle - .pi / 2)
    }

    private func isObjectiveZone(_ id: ZoneID) -> Bool {
        mission?.objectives.contains { $0.zones.contains(id) } ?? false
    }

    private func refreshMarkers() {
        let active = Set(activeZones.map(\.id))
        for (id, node) in zoneMarkers {
            if isObjectiveZone(id) {
                node.isHidden = !active.contains(id)
            } else {
                // Job-only spots (drops, lanterns, flyers) stay hidden outside their job.
                let kind = district.zones[id]?.kind
                node.isHidden = kind == .dropOff || kind == .pickup
            }
        }
    }

    private func dropSkidMarks(_ car: VehicleState) {
        guard !skidPool.isEmpty else { return }
        let rear = car.position - car.forward * 18
        for side in [-9.0, 9.0] {
            let p = rear + car.right * side
            let skid = skidPool[skidIndex]
            skidIndex = (skidIndex + 1) % skidPool.count
            skid.removeAllActions()
            skid.position = CGPoint(p)
            skid.zRotation = CGFloat(car.heading - .pi / 2)
            skid.alpha = 0.55
            skid.run(.sequence([.wait(forDuration: 1.5), .fadeOut(withDuration: 1.5)]))
        }
    }

    // MARK: Building

    private func buildGround() {
        // Solara streams its ground (and props and landmarks) in around the camera instead.
        guard !stateMode else { return }
        for chunk in HDWorld.chunks(for: district) {
            let ground = SKSpriteNode(texture: chunk.texture, size: chunk.size)
            ground.anchorPoint = .zero
            ground.position = chunk.origin
            ground.zPosition = 0
            world.addChild(ground)
        }
        // The harbour glints: a slow shimmer over the water.
        if !reduceMotion, !stateMode, let shimmer = waterShimmer() { world.addChild(shimmer) }
    }

    /// Walk-cycle frame for a body moving at `speed` (0 = standing).
    private func walkFrame(speed: Double, offset: Double) -> Int {
        guard speed > 8 else { return 0 }
        let stepsPerSecond = min(9, 2.2 + speed / 45)
        let phase = (animTime * stepsPerSecond / 2 + offset).truncatingRemainder(dividingBy: 1)
        return 1 + Int(phase * Double(HDArt.walkFrames)) % HDArt.walkFrames
    }

    // MARK: Streaming (Solara State)

    /// Loads the chunks around the camera (a few per frame) and drops the far ones. `budget` caps
    /// how many new chunks are drawn this frame, so driving fast never stalls a frame for long.
    /// Debug: two stars and a cruiser pulling up just ahead of the player.
    func debugStandoff() {
        city.pursuit.add(.missionEvent(35))
        let p = city.playerPosition
        let roads = district.roadTiles(near: p, radius: 700).map { district.center(of: $0) }
            .filter { (($0 - p).length - 260).magnitude < 120 }
            .filter { PatrolBrain.lineOfSight(from: $0, to: p, district: district) }
        guard let spot = roads.first else { return }
        let d = p - spot
        city.pursuit.dispatchUnit(at: spot, heading: atan2(d.y, d.x))
    }

    /// The stick as the player sees it, turned into street directions (the camera may be turned).
    private func worldStick(_ v: Vec2) -> Vec2 {
        guard camTurn != 0 else { return v }
        let c = cos(Double(camTurn)), s = sin(Double(camTurn))
        return Vec2(v.x * c - v.y * s, v.x * s + v.y * c)
    }

    /// 1st person: everything outside a cone in front of you is in shadow.
    private func updateVision(on: Bool) {
        visionNode.isHidden = !on
        guard on else { return }
        if visionNode.parent == nil {
            visionNode.zPosition = 940
            cam.addChild(visionNode)
        }
        guard visionSize != size else { return }
        visionSize = size
        let w = size.width * 1.6, h = size.height * 1.6
        // The player sits 0.3 of the screen height below centre.
        let eye = CGPoint(x: w / 2, y: h / 2 + size.height * 0.3)
        let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            let g = ctx.cgContext
            g.setFillColor(UIColor(white: 0, alpha: 0.82).cgColor)
            g.fill(CGRect(x: 0, y: 0, width: w, height: h))
            g.setBlendMode(.clear)
            // The view cone, about 110° wide, plus a little circle around you.
            let reach = max(w, h)
            let half = CGFloat.pi * 0.31
            let path = CGMutablePath()
            path.move(to: eye)
            path.addLine(to: CGPoint(x: eye.x + sin(-half) * reach, y: eye.y - cos(half) * reach))
            path.addLine(to: CGPoint(x: eye.x + sin(half) * reach, y: eye.y - cos(half) * reach))
            path.closeSubpath()
            g.addPath(path)
            g.fillPath()
            g.fillEllipse(in: CGRect(x: eye.x - 46, y: eye.y - 46, width: 92, height: 92))
            g.setBlendMode(.normal)
            // Soft edges: a faint dim along the cone's sides.
            g.setStrokeColor(UIColor(white: 0, alpha: 0.35).cgColor)
            g.setLineWidth(60)
            g.move(to: eye); g.addLine(to: CGPoint(x: eye.x + sin(-half) * reach, y: eye.y - cos(half) * reach))
            g.move(to: eye); g.addLine(to: CGPoint(x: eye.x + sin(half) * reach, y: eye.y - cos(half) * reach))
            g.strokePath()
        }
        visionNode.texture = SKTexture(image: image)
        visionNode.size = CGSize(width: w, height: h)
    }

    private func updateStreaming(budget: Int) {
        guard stateMode else { return }
        let size = HDWorld.chunkTiles(for: district)
        let span = CGFloat(size) * CGFloat(district.tileSize)
        let half = CGSize(width: self.size.width * cam.xScale / 2 + span * 0.75,
                          height: self.size.height * cam.yScale / 2 + span * 0.75)
        let centre = cam.position
        // World rect → tile columns / rows (rows count down from the north).
        let t = CGFloat(district.tileSize)
        let c0 = max(0, Int((centre.x - half.width) / t) / size * size)
        let c1 = min(district.cols - 1, Int((centre.x + half.width) / t))
        let rTop = max(0, district.rows - 1 - Int((centre.y + half.height) / t)) / size * size
        let rBottom = min(district.rows - 1, district.rows - 1 - Int(max(0, centre.y - half.height) / t))
        var wanted: [(key: Int, col: Int, row: Int, distance: CGFloat)] = []
        var row = rTop
        while row <= rBottom {
            var col = c0
            while col <= c1 {
                let key = row * 100_000 + col
                let mid = CGPoint(x: (CGFloat(col) + CGFloat(size) / 2) * t,
                                  y: (CGFloat(district.rows - row) - CGFloat(size) / 2) * t)
                wanted.append((key, col, row, hypot(mid.x - centre.x, mid.y - centre.y)))
                col += size
            }
            row += size
        }
        let keep = Set(wanted.map(\.key))
        // Drop chunks well outside the view.
        for (key, node) in chunkNodes where !keep.contains(key) {
            let col = key % 100_000, row = key / 100_000
            let mid = CGPoint(x: (CGFloat(col) + CGFloat(size) / 2) * t, y: (CGFloat(district.rows - row) - CGFloat(size) / 2) * t)
            if abs(mid.x - centre.x) > half.width + span * 1.5 || abs(mid.y - centre.y) > half.height + span * 1.5 {
                node.removeFromParent()
                chunkNodes[key] = nil
            }
        }
        var made = 0
        for w in wanted.sorted(by: { $0.distance < $1.distance }) where chunkNodes[w.key] == nil {
            guard made < budget else { break }
            let chunk = HDWorld.chunk(for: district, col0: w.col, row0: w.row)
            let container = SKNode()
            let ground = SKSpriteNode(texture: chunk.texture, size: chunk.size)
            ground.anchorPoint = .zero
            ground.position = chunk.origin
            ground.zPosition = 0
            container.addChild(ground)
            for prop in HDProps.props(for: district, chunkCol0: w.col, row0: w.row) {
                addProp(prop, to: container)
            }
            world.addChild(container)
            chunkNodes[w.key] = container
            made += 1
        }
        // Landmarks appear as they come into range and then stay.
        for landmark in SolaraState.landmarks where landmarkNodes[landmark.id] == nil {
            let d = hypot(CGFloat(landmark.footprint.center.x) - centre.x, CGFloat(landmark.footprint.center.y) - centre.y)
            guard d < 3200 else { continue }
            if let node = HDLandmarks.node(for: landmark, lightLevel: lightLevel, reduceMotion: reduceMotion) {
                world.addChild(node)
                landmarkNodes[landmark.id] = node
            } else {
                landmarkNodes[landmark.id] = SKNode()
            }
        }
    }

    /// Trees, palms, street lamps and neon signs, plus their light at dusk and night.
    private func buildProps() {
        // Solara's props come and go with their ground chunks.
        guard !stateMode else { return }
        for prop in HDProps.props(for: district) {
            addProp(prop, to: world)
        }
    }

    private func addProp(_ prop: HDProps.Prop, to world: SKNode) {
        let level = lightLevel
        do {
            let texture = HDProps.texture(prop.kind)
            switch prop.kind {
            case .tree, .palm:
                let size: CGSize
                if case .palm = prop.kind { size = HDProps.palmSize } else { size = HDProps.treeSize }
                let shadow = SKSpriteNode(texture: texture, size: size)
                shadow.color = .black
                shadow.colorBlendFactor = 1
                shadow.alpha = 0.32
                shadow.position = CGPoint(x: prop.position.x + 12, y: prop.position.y - 14)
                shadow.zPosition = 1.5
                world.addChild(shadow)
                let canopy = SKSpriteNode(texture: texture, size: size)
                canopy.position = prop.position
                canopy.zRotation = CGFloat(prop.position.x.truncatingRemainder(dividingBy: 6.28))
                canopy.zPosition = 22
                canopy.alpha = 0.95
                world.addChild(canopy)
            case .lamp(let facing):
                let lamp = SKSpriteNode(texture: texture, size: HDProps.lampSize)
                lamp.anchorPoint = CGPoint(x: 0.12, y: 0.5)
                lamp.position = prop.position
                lamp.zRotation = CGFloat(facing)
                lamp.zPosition = 21
                world.addChild(lamp)
                let head = CGPoint(x: prop.position.x + CGFloat(cos(facing)) * 26,
                                   y: prop.position.y + CGFloat(sin(facing)) * 26)
                // A soft pool on the ground (always faintly there) and a bright one at night.
                let pool = SKSpriteNode(texture: HDArt.glowTexture(0xFFD9A0), size: CGSize(width: 190, height: 190))
                pool.position = head
                pool.blendMode = .add
                pool.zPosition = 1.6
                pool.alpha = 0.06 + 0.12 * level
                world.addChild(pool)
                if level > 0 {
                    let night = SKSpriteNode(texture: HDArt.glowTexture(0xFFC985), size: CGSize(width: 230, height: 230))
                    night.position = head
                    night.blendMode = .add
                    night.zPosition = Self.lightZ
                    night.alpha = 0.32 * level
                    world.addChild(night)
                }
            case .sign(let word, let hex):
                let sign = SKSpriteNode(texture: texture, size: HDProps.signSize(word))
                sign.position = prop.position
                sign.zPosition = level > 0 ? Self.lightZ + 1 : 5
                world.addChild(sign)
                let halo = SKSpriteNode(texture: HDArt.glowTexture(hex),
                                        size: CGSize(width: HDProps.signSize(word).width * 2.2, height: 90))
                halo.position = prop.position
                halo.blendMode = .add
                halo.zPosition = level > 0 ? Self.lightZ : 4
                halo.alpha = 0.12 + 0.3 * level
                world.addChild(halo)
                if !reduceMotion && HDWorld.hash(TileCoord(col: Int(prop.position.x), row: Int(prop.position.y)), 3) % 4 == 0 {
                    // One in four signs buzzes.
                    sign.run(.repeatForever(.sequence([.wait(forDuration: 2.6), .fadeAlpha(to: 0.4, duration: 0.05),
                                                       .fadeAlpha(to: 1, duration: 0.05), .wait(forDuration: 0.12),
                                                       .fadeAlpha(to: 0.5, duration: 0.04), .fadeAlpha(to: 1, duration: 0.06)])))
                }
            }
        }
    }

    /// Moving glints on open water.
    private func waterShimmer() -> SKNode? {
        let waterTiles = (0..<district.rows).flatMap { r in (0..<district.cols).map { TileCoord(col: $0, row: r) } }
            .filter { district.tile($0) == .water }
        guard !waterTiles.isEmpty else { return nil }
        let node = SKNode()
        node.zPosition = 1.2
        let glint = HDArt.glowTexture(0x7FD8FF)
        for (i, c) in waterTiles.enumerated() where i % 2 == 0 {
            let centre = district.center(of: c)
            let s = SKSpriteNode(texture: glint, size: CGSize(width: 46, height: 6))
            s.position = CGPoint(x: centre.x + Double(i % 5) * 14 - 28, y: centre.y + Double(i % 3) * 20 - 20)
            s.blendMode = .add
            s.alpha = 0
            let delay = Double(i % 7) * 0.45
            s.run(.repeatForever(.sequence([.wait(forDuration: delay), .fadeAlpha(to: 0.5, duration: 0.9),
                                            .fadeAlpha(to: 0, duration: 1.2), .wait(forDuration: 1.6 - delay * 0.2)])))
            node.addChild(s)
        }
        return node
    }

    private func label(_ text: String, color: UIColor, size: CGFloat = 26) -> SKLabelNode {
        let node = SKLabelNode(fontNamed: "Menlo-Bold")
        node.text = text
        node.fontSize = size
        node.fontColor = color
        node.verticalAlignmentMode = .center
        node.horizontalAlignmentMode = .center
        return node
    }

    /// The word painted on a job's target, from what the job asks there (a pier can be a drop
    /// in one job and the getaway in another).
    private func objectiveWord(for zone: Zone) -> String {
        guard let mission, let objective = mission.objectives.first(where: { $0.zones.contains(zone.id) }) else {
            return "TARGET"
        }
        if mission.id == .streetChallenge,
           let index = mission.objectives.firstIndex(where: { $0.zones.contains(zone.id) }) {
            return index == mission.objectives.count - 1 ? "FINISH" : "CHECK \(index + 1)"
        }
        switch objective {
        case .reach: return "DROP"
        case .collect: return mission.collectLabel
        case .returnTo: return zone.kind == .safehouse ? "HOME" : "RETURN"
        case .reachCalm: return "ESCAPE"
        }
    }

    private func buildZoneMarkers() {
        for zone in district.zones.values {
            let node = SKNode()
            node.position = CGPoint(zone.rect.center)
            node.zPosition = 6
            let size = CGSize(width: zone.rect.width - 12, height: zone.rect.height - 12)
            let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)

            if isObjectiveZone(zone.id) {
                let box = SKShapeNode(rect: rect)
                box.fillColor = Palette.UI.teal.withAlphaComponent(0.18)
                box.strokeColor = Palette.UI.teal
                box.lineWidth = 6
                node.addChild(box)
                let text = label(objectiveWord(for: zone), color: Palette.UI.cream, size: 28)
                text.zRotation = zone.rect.height > zone.rect.width * 1.5 ? .pi / 2 : 0
                node.addChild(text)
                if !reduceMotion {
                    box.run(.repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 0.6),
                                                      .fadeAlpha(to: 1, duration: 0.6)])))
                }
            } else {
                switch zone.kind {
                case .safehouse:
                    node.addChild(label("SAFEHOUSE", color: Palette.UI.sunset, size: 30))
                    let sub = label("heat clears · keep cars here", color: Palette.UI.cream.withAlphaComponent(0.6), size: 16)
                    sub.position = CGPoint(x: 0, y: -30)
                    node.addChild(sub)
                case .restricted:
                    let box = SKShapeNode(rect: rect)
                    box.fillColor = Palette.UI.magenta.withAlphaComponent(0.08)
                    box.strokeColor = Palette.UI.magenta.withAlphaComponent(0.8)
                    box.lineWidth = 4
                    node.addChild(box)
                    let text = label("CUSTOMS · KEEP OUT", color: Palette.UI.magenta, size: 22)
                    text.zRotation = .pi / 2
                    node.addChild(text)
                case .start:
                    let text = label(zone.name.uppercased(), color: Palette.UI.cream.withAlphaComponent(0.6), size: 24)
                    text.position = CGPoint(x: 0, y: -zone.rect.height / 2 + 30)
                    node.addChild(text)
                case .shop:
                    let box = SKShapeNode(rect: rect)
                    box.fillColor = Palette.UI.sunset.withAlphaComponent(0.15)
                    box.strokeColor = Palette.UI.sunset
                    box.lineWidth = 4
                    node.addChild(box)
                    node.addChild(label(zone.name.uppercased(), color: Palette.UI.sunset, size: 20))
                    let sub = label("GUN STORE · WALK IN", color: Palette.UI.cream.withAlphaComponent(0.7), size: 13)
                    sub.position = CGPoint(x: 0, y: -22)
                    node.addChild(sub)
                case .depot:
                    let box = SKShapeNode(rect: rect)
                    box.fillColor = Palette.UI.sunset.withAlphaComponent(0.12)
                    box.strokeColor = Palette.UI.sunset
                    box.lineWidth = 5
                    node.addChild(box)
                    node.addChild(label("FREIGHT DEPOT", color: Palette.UI.sunset, size: 26))
                    let sub = label((SolaraState.city(for: zone.id)?.name ?? "").uppercased() + " · JOBS",
                                    color: Palette.UI.cream.withAlphaComponent(0.75), size: 15)
                    sub.position = CGPoint(x: 0, y: -28)
                    node.addChild(sub)
                case .landmark:
                    let text = label(zone.name.uppercased(), color: Palette.UI.magenta, size: 18)
                    node.addChild(text)
                    let sub = label("SCENIC STOP", color: Palette.UI.cream.withAlphaComponent(0.6), size: 11)
                    sub.position = CGPoint(x: 0, y: -20)
                    node.addChild(sub)
                case .dropOff, .pickup:
                    break
                }
            }
            world.addChild(node)
            zoneMarkers[zone.id] = node
        }
    }

    private func buildArrow() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 16))
        path.addLine(to: CGPoint(x: -12, y: -10))
        path.addLine(to: CGPoint(x: 0, y: -4))
        path.addLine(to: CGPoint(x: 12, y: -10))
        path.closeSubpath()
        arrow.path = path
        arrow.fillColor = Palette.UI.teal
        arrow.strokeColor = Palette.UI.ink
        arrow.lineWidth = 2
        arrow.zPosition = 12
        arrow.isHidden = true
        world.addChild(arrow)
    }

    private func buildSkidPool() {
        for _ in 0..<240 {
            let skid = SKSpriteNode(color: UIColor(hex: 0x050608), size: CGSize(width: 5, height: 9))
            skid.alpha = 0
            skid.zPosition = 2
            world.addChild(skid)
            skidPool.append(skid)
        }
    }

    private func buildTracers() {
        for _ in 0..<12 {
            let line = SKShapeNode()
            line.lineWidth = 3
            line.alpha = 0
            line.zPosition = 11
            world.addChild(line)
            tracerPool.append(line)
        }
    }

    /// A quick arc in front of the player for a melee swing.
    /// The weapon in the player's hands, seen from above: a dark gun shape out in front, held
    /// two-handed for long guns. Rebuilt only when the weapon changes.
    private func updateHeldGun() {
        let weapon = city.inventory.equipped
        guard weapon != heldWeapon else { return }
        heldWeapon = weapon
        heldGun.removeAllChildren()
        heldGun.removeFromParent()
        guard let weapon else { return }
        let (w, h): (CGFloat, CGFloat) = switch weapon {
        case .pistol: (3.2, 9)
        case .smg: (4, 13)
        case .shotgun: (3.4, 19)
        case .rifle: (3.6, 20)
        case .bat: (3.4, 17)
        }
        let body = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 1.2)
        let finish = city.inventory.build(for: weapon).finish
        body.fillColor = weapon == .bat ? UIColor(hex: 0xB9834A)
            : (finish == 0 ? UIColor(hex: 0x23262C) : PixelArt.finishColors[finish % PixelArt.finishColors.count].darker(0.2))
        body.strokeColor = UIColor(white: 0, alpha: 0.7)
        body.lineWidth = 0.8
        body.position = CGPoint(x: 0, y: h / 2)
        heldGun.addChild(body)
        if weapon != .bat {
            // Barrel tip catches the light.
            let tip = SKShapeNode(rectOf: CGSize(width: w * 0.5, height: 2))
            tip.fillColor = UIColor(hex: 0x6B7280)
            tip.strokeColor = .clear
            tip.position = CGPoint(x: 0, y: h - 1)
            heldGun.addChild(tip)
        }
        // Two hands on long guns, one on a pistol.
        let skin = UIColor(hex: playerLook.skin)
        for y in weapon == .pistol ? [CGFloat(1)] : [1, h * 0.55] {
            let hand = SKShapeNode(circleOfRadius: 2.3)
            hand.fillColor = skin
            hand.strokeColor = UIColor(white: 0, alpha: 0.45)
            hand.lineWidth = 0.6
            hand.position = CGPoint(x: 0, y: y)
            heldGun.addChild(hand)
        }
        heldGun.position = CGPoint(x: 3.5, y: 6)
        heldGun.zPosition = 1
        playerNode.addChild(heldGun)
    }

    /// A fist shoots out from the side it's thrown with, with a swish, and a pop when it lands.
    private func throwFist(_ strike: Strike, hit: Bool) {
        let side: CGFloat = strike == .left ? -1 : strike == .right ? 1 : 0.35
        let fist = SKShapeNode(circleOfRadius: 3.6)
        fist.fillColor = UIColor(hex: playerLook.skin)
        fist.strokeColor = UIColor(white: 0, alpha: 0.5)
        fist.lineWidth = 1
        fist.zPosition = 2
        fist.position = CGPoint(x: 6 * side, y: 3)
        playerNode.addChild(fist)
        // Player node: +y is the way they face; a hook curls in from the side.
        let out = CGPoint(x: strike == .jab ? 3 : 4 * side, y: strike == .jab ? 17 : 13)
        fist.run(.sequence([.move(to: out, duration: 0.07), .move(to: fist.position, duration: 0.1), .removeFromParent()]))
        // The swish: a short arc on that side.
        let path = CGMutablePath()
        let centre = strike == .left ? CGFloat.pi / 6 : strike == .right ? -CGFloat.pi / 6 : 0
        path.addArc(center: .zero, radius: 30, startAngle: centre - 0.45, endAngle: centre + 0.45, clockwise: false)
        swingNode.path = path
        swingNode.position = CGPoint(city.foot.position)
        swingNode.zRotation = CGFloat(city.foot.heading)
        swingNode.removeAllActions()
        swingNode.alpha = 0.8
        swingNode.run(.fadeOut(withDuration: 0.14))
        if hit {
            let a = city.foot.heading + Double(centre)
            let pop = SKShapeNode(circleOfRadius: 7)
            pop.fillColor = UIColor(white: 1, alpha: 0.85)
            pop.strokeColor = Palette.UI.sunset
            pop.lineWidth = 2
            pop.zPosition = 30
            pop.position = CGPoint(x: city.foot.position.x + cos(a) * 34, y: city.foot.position.y + sin(a) * 34)
            world.addChild(pop)
            pop.run(.sequence([.group([.scale(to: 1.8, duration: 0.12), .fadeOut(withDuration: 0.16)]), .removeFromParent()]))
        }
    }

    private func drawSwing() {
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: 34, startAngle: -.pi / 3, endAngle: .pi / 3, clockwise: false)
        swingNode.path = path
        swingNode.position = CGPoint(city.foot.position)
        swingNode.zRotation = CGFloat(city.foot.heading)
        swingNode.removeAllActions()
        swingNode.alpha = 0.9
        swingNode.run(.fadeOut(withDuration: 0.15))
    }

    private func buildDealer() {
        let body = SKSpriteNode(texture: HDArt.personTexture(HDArt.dealerLook, frame: 0))
        body.size = HDArt.personSize
        body.zRotation = -.pi
        dealerNode.addChild(body)
        let tag = label("DEALER", color: Palette.UI.sunset, size: 13)
        tag.position = CGPoint(x: 0, y: 24)
        dealerNode.addChild(tag)
        dealerNode.zPosition = 9
        world.addChild(dealerNode)
        swingNode.strokeColor = Palette.UI.cream
        swingNode.lineWidth = 5
        swingNode.alpha = 0
        swingNode.zPosition = 11
        world.addChild(swingNode)
    }

    private func buildPlayer() {
        playerLook = HDArt.playerLook(profile)
        playerNode.texture = HDArt.personTexture(playerLook, frame: 0)
        playerNode.size = HDArt.personSize
        // A soft teal ring on the ground so the player is easy to find in a crowd.
        let ring = SKShapeNode(circleOfRadius: 17)
        ring.strokeColor = Palette.UI.teal.withAlphaComponent(0.75)
        ring.fillColor = Palette.UI.teal.withAlphaComponent(0.12)
        ring.lineWidth = 2
        ring.glowWidth = 3
        ring.zPosition = -1
        playerNode.addChild(ring)
        playerNode.zPosition = 10
        world.addChild(playerNode)
    }
}

/// Any car or bike on the street, with a soft drop shadow. Wrecks go dark. The car the player
/// drives gets headlight beams after dark, and a bike gets its rider.
@MainActor
final class VehicleNode: SKNode {
    private let body = SKSpriteNode()
    private let shadow = SKSpriteNode()
    private let beams = SKNode()
    private var rider: SKSpriteNode?
    private var riderLook: HDArt.Look?
    private let model: VehicleID

    init(model: VehicleID, design: PaintDesign? = nil, rims: RimSetup? = nil) {
        self.model = model
        super.init()
        let size = HDArt.vehicleSize(model)
        body.texture = HDArt.vehicleTexture(model, design: design, rims: rims)
        body.size = size
        body.zPosition = 10
        shadow.texture = HDArt.vehicleShadow(model)
        shadow.size = CGSize(width: size.width + HDArt.shadowPadding * 2, height: size.height + HDArt.shadowPadding * 2)
        shadow.alpha = 0.55
        shadow.position = CGPoint(x: 5, y: -6)
        shadow.zPosition = 9
        addChild(shadow)
        addChild(body)
        // Two beams from the headlights, pointing up the sprite (the nose).
        for side: CGFloat in model.isMotorcycle ? [0] : [-7, 7] {
            let beam = SKSpriteNode(texture: HDArt.beamTexture(), size: CGSize(width: 70, height: 130))
            beam.anchorPoint = CGPoint(x: 0.5, y: 0)
            beam.position = CGPoint(x: side, y: size.height / 2 - 4)
            beam.blendMode = .add
            beams.addChild(beam)
        }
        beams.zPosition = DriveScene.lightZ - 10
        beams.alpha = 0
        body.addChild(beams)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("VehicleNode is created in code")
    }

    /// Live play: another player's car, turned to face where they're heading.
    func setHeading(_ heading: Double) {
        body.zRotation = CGFloat(heading - .pi / 2)
        shadow.zRotation = body.zRotation
    }

    func update(_ vehicle: CityVehicle) {
        position = CGPoint(vehicle.state.position)
        body.zRotation = CGFloat(vehicle.state.heading - .pi / 2)
        shadow.zRotation = body.zRotation
        if vehicle.isWrecked {
            body.color = .black
            body.colorBlendFactor = 0.6
            beams.alpha = 0
        } else {
            body.colorBlendFactor = 0
        }
    }

    /// Headlights at `level` (0 = off).
    func setLights(_ level: CGFloat) {
        let target = level * 0.55
        if abs(beams.alpha - target) > 0.01 { beams.alpha = target }
    }

    /// Someone on the bike (nil = parked, no rider).
    func setRider(_ look: HDArt.Look?) {
        guard model.isMotorcycle, look != riderLook else { return }
        riderLook = look
        rider?.removeFromParent()
        rider = nil
        guard let look else { return }
        let node = SKSpriteNode(texture: HDArt.personTexture(look, frame: 0), size: CGSize(width: 21, height: 21))
        node.position = CGPoint(x: 0, y: 1)
        node.zPosition = 1
        body.addChild(node)
        rider = node
    }
}

/// A patrol cruiser plus its vision cone. The cone is faint while cruising, sunset while
/// searching, magenta while chasing; the light bar flashes only while chasing (steady under
/// Reduce Motion), and throws coloured light around it after dark.
@MainActor
final class PatrolNode: SKNode {
    private static var frames: (SKTexture, SKTexture)?
    private static var steady: SKTexture?

    private let body = SKSpriteNode()
    private let shadow = SKSpriteNode()
    private let cone = SKShapeNode()
    private let flashA = SKSpriteNode()
    private let flashB = SKSpriteNode()
    private let beams = SKNode()
    private let reduceMotion: Bool
    private let lightLevel: CGFloat
    private var mode: PatrolMode?

    init(reduceMotion: Bool, lightLevel: CGFloat = 0) {
        self.reduceMotion = reduceMotion
        self.lightLevel = lightLevel
        super.init()
        if Self.frames == nil {
            Self.frames = (HDArt.vehicleTexture(.harborPatrol, lightFrame: 0), HDArt.vehicleTexture(.harborPatrol, lightFrame: 1))
            Self.steady = HDArt.vehicleTexture(.harborPatrol)
        }
        let size = HDArt.vehicleSize(.harborPatrol)
        body.texture = Self.steady
        body.size = size
        body.zPosition = 10
        addChild(body)
        shadow.texture = HDArt.vehicleShadow(.harborPatrol)
        shadow.size = CGSize(width: size.width + HDArt.shadowPadding * 2, height: size.height + HDArt.shadowPadding * 2)
        shadow.alpha = 0.55
        shadow.position = CGPoint(x: 5, y: -6)
        shadow.zPosition = 9
        addChild(shadow)

        let path = CGMutablePath()
        path.move(to: .zero)
        let r = CGFloat(PatrolBrain.visionRange)
        let half = CGFloat(PatrolBrain.visionHalfAngle)
        // Node space: the car's nose points along +y.
        path.addArc(center: .zero, radius: r, startAngle: .pi / 2 - half, endAngle: .pi / 2 + half, clockwise: false)
        path.closeSubpath()
        cone.path = path
        cone.lineWidth = 0
        cone.zPosition = 7
        addChild(cone)

        // Light-bar wash: magenta one side, blue the other.
        for (node, hex, x) in [(flashA, UInt32(0xFF2E7E), CGFloat(-10)), (flashB, UInt32(0x2EC8FF), CGFloat(10))] {
            node.texture = HDArt.glowTexture(hex)
            node.size = CGSize(width: 170, height: 170)
            node.position = CGPoint(x: x, y: 2)
            node.blendMode = .add
            node.alpha = 0
            node.zPosition = DriveScene.lightZ
            addChild(node)
        }
        for side: CGFloat in [-7, 7] {
            let beam = SKSpriteNode(texture: HDArt.beamTexture(), size: CGSize(width: 70, height: 130))
            beam.anchorPoint = CGPoint(x: 0.5, y: 0)
            beam.position = CGPoint(x: side, y: size.height / 2 - 4)
            beam.blendMode = .add
            beams.addChild(beam)
        }
        beams.zPosition = DriveScene.lightZ - 10
        beams.alpha = lightLevel * 0.5
        addChild(beams)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("PatrolNode is created in code")
    }

    func update(_ patrol: Patrol) {
        position = CGPoint(patrol.car.position)
        zRotation = CGFloat(patrol.car.heading - .pi / 2)
        guard patrol.mode != mode else { return }
        mode = patrol.mode
        body.removeAllActions()
        flashA.removeAllActions()
        flashB.removeAllActions()
        let wash = 0.25 + 0.55 * lightLevel
        switch patrol.mode {
        case .cruise:
            cone.fillColor = Palette.UI.teal.withAlphaComponent(0.07)
            body.texture = Self.steady
            flashA.alpha = 0
            flashB.alpha = 0
        case .search:
            cone.fillColor = Palette.UI.sunset.withAlphaComponent(0.11)
            body.texture = Self.steady
            flashA.alpha = wash * 0.5
            flashB.alpha = wash * 0.5
        case .chase:
            cone.fillColor = Palette.UI.magenta.withAlphaComponent(0.14)
            if reduceMotion {
                body.texture = Self.steady
                flashA.alpha = wash * 0.6
                flashB.alpha = wash * 0.6
            } else if let frames = Self.frames {
                body.run(.repeatForever(.animate(with: [frames.0, frames.1], timePerFrame: 0.22)))
                flashA.run(.repeatForever(.sequence([.fadeAlpha(to: wash, duration: 0.02), .wait(forDuration: 0.2),
                                                     .fadeAlpha(to: 0, duration: 0.02), .wait(forDuration: 0.2)])))
                flashB.run(.repeatForever(.sequence([.fadeAlpha(to: 0, duration: 0.02), .wait(forDuration: 0.2),
                                                     .fadeAlpha(to: wash, duration: 0.02), .wait(forDuration: 0.2)])))
            }
        }
    }
}

/// Another player in live play: their character on foot, or their car (in their paint) with
/// their name over it. Knocked-out players lie flat and fade, cartoon style.
@MainActor
final class RemoteNode: SKNode {
    private let person = SKSpriteNode()
    private let label = SKLabelNode(fontNamed: "Menlo-Bold")
    private var vehicleNode: VehicleNode?
    private var vehicleKey: String?
    private var lookKey: String?

    override init() {
        super.init()
        person.size = HDArt.personSize
        person.zPosition = 10
        addChild(person)
        label.fontSize = 13
        label.fontColor = Palette.UI.teal
        label.position = CGPoint(x: 0, y: 34)
        label.zPosition = 30
        addChild(label)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("RemoteNode is created in code")
    }

    func update(_ avatar: RemoteAvatar, look: RemoteLook?) {
        position = CGPoint(avatar.position)
        let name = look?.name ?? "Driver"
        if label.text != name { label.text = name }
        let key = "\(look?.profile.map { "\($0.skin)-\($0.hair)-\($0.jacket)" } ?? "none")"
        if key != lookKey {
            lookKey = key
            person.texture = HDArt.personTexture(HDArt.playerLook(look?.profile), frame: 0)
        }
        if let model = avatar.vehicle {
            let vKey = "\(model.rawValue)-\(look?.paint != nil)"
            if vKey != vehicleKey {
                vehicleNode?.removeFromParent()
                let node = VehicleNode(model: model, design: look?.paint)
                addChild(node)
                vehicleNode = node
                vehicleKey = vKey
            }
            vehicleNode?.isHidden = false
            vehicleNode?.position = .zero
            vehicleNode?.setHeading(avatar.heading)
            vehicleNode?.setRider(model.isMotorcycle ? HDArt.playerLook(look?.profile) : nil)
            person.isHidden = true
        } else {
            vehicleNode?.isHidden = true
            person.isHidden = false
            person.zRotation = CGFloat(avatar.isDown ? avatar.heading : avatar.heading - .pi / 2)
            person.alpha = avatar.isDown ? 0.5 : 1
        }
    }
}
