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
    private var startInventory: Inventory
    private var pilot: Autopilot?
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
    private var tracerPool: [SKShapeNode] = []
    private var tracerIndex = 0
    private var lookAhead = CGVector.zero
    private var skidPool: [SKSpriteNode] = []
    private var skidIndex = 0
    private var skidCountdown = 0
    /// Stats already turned into skill XP this trip.
    private var statsTaken = RunStats()

    // Camera tuning; numbers only matter on a phone.
    private let baseZoom: CGFloat = 1.15
    private let footZoom: CGFloat = 0.85
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
         weather: Weather = .clear, timeOfDay: TimeOfDay = .day) {
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
                    inventory: inventory, startingHeat: mission?.startingHeat ?? 0, seed: 1, playerDesign: design,
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
        buildZoneMarkers()
        buildSkidPool()
        buildTracers()
        buildPlayer()
        buildDealer()
        buildArrow()
        buildAtmosphere()
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
        case .night: (UIColor(red: 0.05, green: 0.06, blue: 0.22, alpha: 1), 0.38)
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
                    playerDesign: design, skills: skills, aimAssist: aimAssist, weather: weather)
        statsTaken = RunStats()
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

    func cycleWeapon() {
        city.inventory.cycle()
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
        }
        syncNodes()
        render(smooth: true)

        frameCount += 1
        if frameCount % 4 == 0 { onHUD?(hudState) }
    }

    private func stepOnce(dt: Double) {
        var input = controls?.vehicleInput ?? .idle
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

        guard let mission, !run.isFinished else { return }
        let (next, events) = MissionRunner.step(run, def: mission, district: district,
                                                carPosition: city.playerPosition,
                                                heatStars: city.pursuit.heat.stars, dt: dt)
        run = next
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
        guard let mission else { return [] }
        return MissionRunner.activeZones(run, def: mission).compactMap { district.zones[$0] }
    }

    private var hudState: HUDState {
        var h = HUDState()
        let body = city.player
        let vehicle = city.currentVehicle
        h.onFoot = city.isOnFoot
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
        h.context = contextAction
        let pursuit = city.pursuit
        h.heatPoints = Int(pursuit.heat.points.rounded())
        h.heatStars = pursuit.heat.stars
        h.heatLabel = pursuit.heat.label
        h.chasing = pursuit.chasingCount
        h.bustFraction = pursuit.bustProgress / Pursuit.bustSeconds
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
            playerNode.position = CGPoint(city.foot.position)
            playerNode.zRotation = CGFloat(city.foot.heading - .pi / 2)
        }
        updateArrow()

        let targetZoom: CGFloat
        if city.isOnFoot {
            targetZoom = footZoom
        } else {
            let fraction = CGFloat(city.currentVehicle.map { min(1, $0.state.speed / $0.spec.maxSpeed) } ?? 0)
            targetZoom = reduceMotion ? baseZoom + 0.1 : baseZoom + speedZoom * fraction
        }
        let zoom = smooth && !reduceMotion ? cam.xScale + (targetZoom - cam.xScale) * 0.06 : targetZoom
        cam.setScale(zoom)

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
        let lift = size.height * carScreenLift * zoom
        cam.position = CGPoint(x: CGFloat(body.position.x) + lookAhead.dx + shake.dx,
                               y: CGFloat(body.position.y) + lookAhead.dy - lift + shake.dy)
    }

    /// Keeps one node per vehicle, person, pickup and patrol in step with GameCore.
    private func syncNodes() {
        for vehicle in city.vehicles {
            let node: VehicleNode
            if let existing = vehicleNodes[vehicle.id] {
                node = existing
            } else {
                node = VehicleNode(model: vehicle.model, design: vehicle.design)
                world.addChild(node)
                vehicleNodes[vehicle.id] = node
            }
            node.update(vehicle)
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
            node.texture = PixelArt.personTexture(look: person.look)
            node.size = CGSize(width: 7 * PixelArt.streetScale * 1.25, height: 7 * PixelArt.streetScale * 1.25)
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
                let node = PatrolNode(reduceMotion: reduceMotion)
                world.addChild(node)
                patrolNodes[patrol.id] = node
                node.update(patrol)
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
        icon.size = CGSize(width: icon.texture!.size().width * 3, height: icon.texture!.size().height * 3)
        node.addChild(icon)
        if !reduceMotion {
            node.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.5), .scale(to: 1, duration: 0.5)])))
        }
        return node
    }

    private func drawTracer(_ trace: ShotTrace) {
        guard !tracerPool.isEmpty else { return }
        let line = tracerPool[tracerIndex]
        tracerIndex = (tracerIndex + 1) % tracerPool.count
        let path = CGMutablePath()
        path.move(to: CGPoint(trace.from))
        path.addLine(to: CGPoint(trace.to))
        line.path = path
        let finish = city.inventory.equipped.map { city.inventory.build(for: $0).finish } ?? 0
        line.strokeColor = trace.hit ? Palette.UI.sunset
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
        let b = district.bounds
        let ground = SKSpriteNode(texture: DistrictArt.worldTexture(for: district),
                                  size: CGSize(width: b.width, height: b.height))
        ground.anchorPoint = .zero
        ground.position = .zero
        ground.zPosition = 0
        world.addChild(ground)
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
        let body = SKSpriteNode(texture: PixelArt.dealerTexture())
        body.size = CGSize(width: 7 * PixelArt.streetScale * 1.4, height: 7 * PixelArt.streetScale * 1.4)
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
        playerNode.texture = PixelArt.playerTexture(profile)
        playerNode.size = CGSize(width: 7 * PixelArt.streetScale * 1.4, height: 7 * PixelArt.streetScale * 1.4)
        playerNode.zPosition = 10
        world.addChild(playerNode)
    }
}

/// Any car or bike on the street, with a drop shadow. Wrecks go dark.
@MainActor
final class VehicleNode: SKNode {
    private let body = SKSpriteNode()
    private let shadow = SKSpriteNode()

    init(model: VehicleID, design: PaintDesign? = nil) {
        super.init()
        let texture = PixelArt.vehicleTexture(model, design: design)
        let size = CGSize(width: texture.size().width * PixelArt.streetScale,
                          height: texture.size().height * PixelArt.streetScale)
        body.texture = texture
        body.size = size
        body.zPosition = 10
        shadow.texture = texture
        shadow.size = size
        shadow.color = .black
        shadow.colorBlendFactor = 1
        shadow.alpha = 0.35
        shadow.position = CGPoint(x: 4, y: -5)
        shadow.zPosition = 9
        addChild(shadow)
        addChild(body)
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
        } else {
            body.colorBlendFactor = 0
        }
    }
}

/// A patrol cruiser plus its vision cone. The cone is faint while cruising, sunset while
/// searching, magenta while chasing; the light bar flashes only while chasing (steady under
/// Reduce Motion).
@MainActor
final class PatrolNode: SKNode {
    private static var textures: (SKTexture, SKTexture)?
    private static var steady: SKTexture?

    private let body = SKSpriteNode()
    private let cone = SKShapeNode()
    private let reduceMotion: Bool
    private var mode: PatrolMode?

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        super.init()
        if Self.textures == nil {
            Self.textures = PixelArt.patrolTextures()
            Self.steady = PixelArt.patrolSteadyTexture()
        }
        body.texture = Self.steady
        body.size = CGSize(width: 14 * 2.4, height: 24 * 2.4)
        body.zPosition = 10
        addChild(body)

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
        switch patrol.mode {
        case .cruise:
            cone.fillColor = Palette.UI.teal.withAlphaComponent(0.07)
            body.texture = Self.steady
        case .search:
            cone.fillColor = Palette.UI.sunset.withAlphaComponent(0.11)
            body.texture = Self.steady
        case .chase:
            cone.fillColor = Palette.UI.magenta.withAlphaComponent(0.14)
            if reduceMotion {
                body.texture = Self.steady
            } else if let frames = Self.textures {
                body.run(.repeatForever(.animate(with: [frames.0, frames.1], timePerFrame: 0.22)))
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
        person.size = CGSize(width: 7 * PixelArt.streetScale * 1.4, height: 7 * PixelArt.streetScale * 1.4)
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
            person.texture = PixelArt.playerTexture(look?.profile)
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
            person.isHidden = true
        } else {
            vehicleNode?.isHidden = true
            person.isHidden = false
            person.zRotation = CGFloat(avatar.isDown ? avatar.heading : avatar.heading - .pi / 2)
            person.alpha = avatar.isDown ? 0.5 : 1
        }
    }
}
