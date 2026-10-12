import SpriteKit
import GameCore

/// What another player looks like in the street.
struct RemoteLook: Equatable {
    var name: String
    var profile: PlayerProfile?
    var paint: PaintDesign?
}

/// Runs live play for one street: sends this player's position ten times a second, draws the
/// others, and turns hits, knockouts and dropped guns into messages. The player who gets hit
/// decides the damage; the player who drops a gun decides who gets it.
@MainActor
final class LiveCoordinator {
    let service: LiveMatchService
    let myID: String
    private weak var scene: DriveScene?
    private let hello: NetMessage
    private var blocked: Set<String>

    private var tracks: [String: RemoteTrack] = [:]
    private var looks: [String: RemoteLook] = [:]
    private var arbiter: DropArbiter
    /// Drop id → who owns it.
    private var dropOwners: [String: String] = [:]
    private var clock = 0.0
    private var sendTimer = 0.0
    private var helloTimer = 0.0

    /// Saves after a knockout or a taken gun.
    var onRecord: ((LiveEvent) -> Void)?

    enum LiveEvent {
        case knockedOutSomeone
        case tookGun(WeaponID)
        case lostGun(WeaponID)
    }

    init(service: LiveMatchService, myID: String, name: String, profile: PlayerProfile?, paint: PaintDesign?,
         blocked: [String], scene: DriveScene) {
        self.service = service
        self.myID = myID
        self.scene = scene
        self.blocked = Set(blocked)
        hello = .hello(name: name, profile: profile ?? PlayerProfile(name: name, starter: .pistol), paint: paint?.cells)
        arbiter = DropArbiter(owner: myID)
        service.onMessage = { [weak self] from, message in self?.handle(message, from: from) }
        service.onLeft = { [weak self] id in self?.forget(id) }
        service.send(hello)

        scene.liveMode = true
        scene.onStep = { [weak self] dt in self?.tick(dt) }
        scene.onHitPlayer = { [weak self] id, damage, weapon in
            self?.service.send(.hit(target: id, damage: damage, weapon: weapon), to: id)
        }
        scene.onClaimDrop = { [weak self] id in self?.claim(id) }
        scene.onLiveKnockout = { [weak self] in self?.knockedOut() }
    }

    func stop() {
        service.onMessage = nil
        service.onLeft = nil
        scene?.onStep = nil
        scene?.setRemotes([], looks: [:])
    }

    var playerCount: Int { tracks.count + 1 }

    // MARK: Every frame

    private func tick(_ dt: Double) {
        guard let scene else { return }
        clock += dt
        sendTimer += dt
        helloTimer += dt
        if sendTimer >= 1 / PvP.snapshotsPerSecond {
            sendTimer = 0
            service.send(.state(scene.liveSnapshot(time: clock)), reliable: false)
        }
        // Late joiners and lost packets: say hello again now and then.
        if helloTimer >= 5 {
            helloTimer = 0
            service.send(hello)
        }
        var avatars: [RemoteAvatar] = []
        for (id, track) in tracks where !blocked.contains(id) {
            guard !track.isStale(at: clock), let pose = track.pose(at: clock), let latest = track.latest else { continue }
            avatars.append(RemoteAvatar(id: id, position: pose.position, heading: pose.heading,
                                        vehicle: latest.vehicle, health: latest.health))
        }
        scene.setRemotes(avatars, looks: looks)
    }

    // MARK: Messages

    private func handle(_ message: NetMessage, from: String) {
        guard let scene, !blocked.contains(from) else { return }
        switch message {
        case .hello(let name, let profile, let paint):
            let shown = ContentFilter.isAllowedPublicName(name) ? name : (service.players[from] ?? "Driver")
            let design = paint.map { PaintDesign(id: "live.\(from)", name: "", creator: shown, cells: $0, price: 0) }
            looks[from] = RemoteLook(name: shown, profile: profile,
                                     paint: design?.isValid == true ? design : nil)
            if tracks[from] == nil { scene.show("\(shown) joined the street") }
        case .state(let snapshot):
            tracks[from, default: RemoteTrack()].receive(snapshot, at: clock)
        case .hit(let target, let damage, let weapon):
            guard target == myID, let shooter = tracks[from]?.pose(at: clock)?.position else { return }
            guard PvP.plausible(shooter: shooter, target: scene.city.playerPosition, weapon: weapon, damage: damage) else {
                return
            }
            scene.takeHit(damage: damage, from: from)
        case .knockedOut(let by):
            if by == myID {
                scene.show("You knocked out \(name(of: from))")
                onRecord?(.knockedOutSomeone)
            }
        case .drop(let drop):
            dropOwners[drop.id] = drop.owner
            scene.addNetworkDrop(drop)
        case .claim(let dropID):
            // Someone wants a gun I dropped: first come, first served.
            guard let winner = arbiter.claim(dropID, by: from) else { return }
            service.send(.granted(dropID: dropID, to: winner))
            scene.resolveNetworkDrop(dropID, mine: false)
            dropOwners[dropID] = nil
        case .granted(let dropID, let to):
            let weapon = scene.resolveNetworkDrop(dropID, mine: to == myID)
            if to == myID, let weapon {
                scene.show("Took \(name(of: from))'s \(weapon.spec.name)")
                onRecord?(.tookGun(weapon))
            }
            dropOwners[dropID] = nil
        }
    }

    private func claim(_ dropID: String) {
        guard let owner = dropOwners[dropID] else { return }
        if owner == myID {
            // Picking up your own dropped gun again.
            guard arbiter.claim(dropID, by: myID) != nil else { return }
            service.send(.granted(dropID: dropID, to: myID))
            scene?.resolveNetworkDrop(dropID, mine: true)
            dropOwners[dropID] = nil
        } else {
            service.send(.claim(dropID: dropID), to: owner)
        }
    }

    /// Knocked out in live play: drop a gun for whoever did it, then get back up at the Safehouse.
    private func knockedOut() {
        guard let scene else { return }
        let attacker = scene.city.lastAttacker
        if attacker != nil, let gun = scene.surrenderGun() {
            let (weapon, ammo) = gun
            let drop = arbiter.makeDrop(weapon: weapon, ammo: ammo, at: scene.city.playerPosition)
            dropOwners[drop.id] = myID
            scene.addNetworkDrop(drop)
            service.send(.drop(drop))
            onRecord?(.lostGun(weapon))
        }
        service.send(.knockedOut(by: attacker))
        scene.respawnAtSafehouse()
        scene.show(attacker.map { "Knocked out by \(name(of: $0)). Back at the Safehouse" }
                   ?? "Knocked out. Back at the Safehouse", seconds: 3.5)
    }

    private func forget(_ id: String) {
        tracks[id] = nil
        if let look = looks.removeValue(forKey: id) { scene?.show("\(look.name) left") }
    }

    private func name(of id: String) -> String {
        looks[id]?.name ?? service.players[id] ?? "another driver"
    }
}
