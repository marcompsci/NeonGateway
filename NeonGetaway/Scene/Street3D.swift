import SceneKit
import SwiftUI
import GameCore

/// Street level in 3D: the same city the game simulates (`City`), drawn with SceneKit from the
/// district's tiles, with a camera behind your car or over your shoulder on foot. The 2D scene
/// keeps running the simulation underneath; this only draws it.
///
/// Units: 32 points = 1 unit (a 128-point tile is 4 units ≈ a 10 m lane). World (x, y) maps to
/// SceneKit (x, 0, −y); a heading h becomes a yaw of h − π/2 (models face −Z).
@MainActor
final class Street3D {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let district: District
    private let timeOfDay: TimeOfDay
    private let worldRoot = SCNNode()
    private let dynamicRoot = SCNNode()
    private let sun = SCNNode()

    static let u: Float = 1 / 32
    static func pos(_ p: Vec2, _ y: Float = 0) -> SCNVector3 { SCNVector3(Float(p.x) * u, y, -Float(p.y) * u) }
    static func yaw(_ heading: Double) -> Float { Float(heading - .pi / 2) }

    private let chunkTiles = 8
    private var chunks: [Int: SCNNode] = [:]
    private var vehicleNodes: [Int: SCNNode] = [:]
    private var vehicleKeys: [Int: String] = [:]
    private var patrolNodes: [Int: SCNNode] = [:]
    private var people: [Int: HumanRig] = [:]
    private var officerRigs: [Int: HumanRig] = [:]
    private var pickupNodes: [Int: SCNNode] = [:]
    private var markerNodes: [SCNNode] = []
    private var playerRig: HumanRig?
    private var playerLook: HumanLook
    private var lastPunch: (Double, Strike)?
    private var lastShot: Double = -10

    /// The player threw a punch (for the arm swing).
    func punch(_ strike: Strike) { lastPunch = (time, strike) }
    /// The player fired (raises the gun for a moment).
    func shot() { lastShot = time }
    private var camPos = SCNVector3Zero
    private var camLook = SCNVector3Zero
    private var placedCamera = false
    private var time: Double = 0

    init(district: District, timeOfDay: TimeOfDay, playerLook: HumanLook) {
        self.district = district
        self.timeOfDay = timeOfDay
        self.playerLook = playerLook
        scene.rootNode.addChildNode(worldRoot)
        scene.rootNode.addChildNode(dynamicRoot)
        setUpSkyAndLight()
        let camera = SCNCamera()
        camera.fieldOfView = 62
        camera.zNear = 0.1
        camera.zFar = 200
        camera.wantsHDR = false
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: Sky, sun, fog

    private var skyColor: UIColor {
        switch timeOfDay {
        case .day: UIColor(hex: 0x8CC8F2)
        case .dawn: UIColor(hex: 0xF4B48C)
        case .dusk: UIColor(hex: 0xE8866A)
        case .night: UIColor(hex: 0x0D1530)
        }
    }

    private var isDark: Bool { timeOfDay == .night || timeOfDay == .dusk }

    private func setUpSkyAndLight() {
        // A vertical gradient sky.
        let top: UIColor = timeOfDay == .night ? UIColor(hex: 0x05081A) : timeOfDay == .day ? UIColor(hex: 0x3D8FE0) : UIColor(hex: 0x6A4A9C)
        let sky = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 256)).image { ctx in
            let colors = [top.cgColor, skyColor.cgColor, skyColor.lighter(0.25).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.75, 1])!
            ctx.cgContext.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
        scene.background.contents = sky
        // Image-based light for the people's skin and clothes (physically based materials).
        scene.lightingEnvironment.contents = sky
        scene.lightingEnvironment.intensity = timeOfDay == .night ? 0.5 : 1.3
        scene.fogColor = skyColor
        scene.fogStartDistance = 55
        scene.fogEndDistance = 95

        let light = SCNLight()
        light.type = .directional
        light.intensity = timeOfDay == .night ? 180 : timeOfDay == .day ? 1050 : 700
        light.color = timeOfDay == .day ? UIColor(white: 1, alpha: 1) : UIColor(hex: 0xFFC59A)
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowColor = UIColor(white: 0, alpha: 0.45)
        light.shadowMapSize = CGSize(width: 2048, height: 2048)
        light.automaticallyAdjustsShadowProjection = true
        light.maximumShadowDistance = 45
        sun.light = light
        sun.eulerAngles = SCNVector3(-0.95, 0.6, 0)
        scene.rootNode.addChildNode(sun)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = timeOfDay == .night ? 260 : 420
        ambient.light!.color = timeOfDay == .night ? UIColor(hex: 0x6A7BC4) : UIColor(white: 0.9, alpha: 1)
        scene.rootNode.addChildNode(ambient)
    }

    // MARK: Materials

    private var materialCache: [String: SCNMaterial] = [:]

    private func mat(_ hex: UInt32, emission: UInt32? = nil, shiny: Bool = false) -> SCNMaterial {
        let key = "\(hex)|\(emission ?? 0)|\(shiny)"
        if let m = materialCache[key] { return m }
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(hex: hex)
        if let emission { m.emission.contents = UIColor(hex: emission) }
        m.lightingModel = .blinn
        if shiny {
            m.specular.contents = UIColor(white: 0.9, alpha: 1)
            m.shininess = 0.6
        }
        materialCache[key] = m
        return m
    }

    /// Building faces: a window grid in one of five finishes, repeated by floors.
    private func facade(_ style: Int, floors: Int) -> SCNMaterial {
        let key = "facade|\(style)|\(floors)"
        if let m = materialCache[key] { return m }
        let wall: [UInt32] = [0xC9B79C, 0x5B7FA6, 0x9A4B3C, 0xE6E1D6, 0x2D3440]
        let glass: [UInt32] = [0x37475C, 0x9FD3F5, 0x2A2A35, 0x4E6A86, 0x1C2A44]
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { ctx in
            let g = ctx.cgContext
            g.setFillColor(UIColor(hex: wall[style]).cgColor)
            g.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            for row in 0..<4 {
                for col in 0..<4 {
                    let lit = isDark && (row * 7 + col * 3 + style) % 3 == 0
                    g.setFillColor((lit ? UIColor(hex: 0xFFE7A8) : UIColor(hex: glass[style])).cgColor)
                    g.fill(CGRect(x: 8 + col * 30, y: 10 + row * 30, width: 20, height: 20))
                    g.setFillColor(UIColor(white: 1, alpha: 0.18).cgColor)
                    g.fill(CGRect(x: 8 + col * 30, y: 10 + row * 30, width: 20, height: 4))
                }
            }
        }
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(1, Float(floors) / 2, 1)
        if isDark {
            m.emission.contents = image
            m.emission.intensity = 0.35
            m.emission.wrapS = .repeat
            m.emission.wrapT = .repeat
            m.emission.contentsTransform = m.diffuse.contentsTransform
        }
        m.lightingModel = .blinn
        materialCache[key] = m
        return m
    }

    // MARK: The city, in chunks around the player

    private func chunkKey(_ c0: Int, _ r0: Int) -> Int { r0 * 100_000 + c0 }

    private func stream(around p: Vec2) {
        let here = district.coord(at: p)
        let radius = 3
        let cc = here.col / chunkTiles, cr = here.row / chunkTiles
        var keep = Set<Int>()
        var built = 0
        for dr in -radius...radius {
            for dc in -radius...radius {
                let c0 = (cc + dc) * chunkTiles, r0 = (cr + dr) * chunkTiles
                guard c0 >= 0, r0 >= 0, c0 < district.cols, r0 < district.rows else { continue }
                let key = chunkKey(c0, r0)
                keep.insert(key)
                if chunks[key] == nil, built < (placedCamera ? 2 : 64) {
                    let node = buildChunk(c0: c0, r0: r0)
                    worldRoot.addChildNode(node)
                    chunks[key] = node
                    built += 1
                }
            }
        }
        for (key, node) in chunks where !keep.contains(key) {
            node.removeFromParentNode()
            chunks[key] = nil
        }
    }

    private func hash(_ c: Int, _ r: Int) -> Int {
        var h = UInt64(truncatingIfNeeded: c &* 73_856_093 ^ r &* 19_349_663)
        h ^= h >> 13
        h = h &* 0x5bd1e995
        return Int(h & 0x7fffffff)
    }

    private func buildChunk(c0: Int, r0: Int) -> SCNNode {
        let chunk = SCNNode()
        let t = Float(district.tileSize) * Self.u
        let ground = SCNNode()
        for r in r0..<min(r0 + chunkTiles, district.rows) {
            for c in c0..<min(c0 + chunkTiles, district.cols) {
                let coord = TileCoord(col: c, row: r)
                let kind = district.tile(coord)
                let centre = Self.pos(district.center(of: coord))
                let h = hash(c, r)
                func flat(_ color: UInt32, y: Float = 0, shiny: Bool = false) {
                    let plane = SCNPlane(width: CGFloat(t), height: CGFloat(t))
                    plane.firstMaterial = mat(color, shiny: shiny)
                    let n = SCNNode(geometry: plane)
                    n.eulerAngles.x = -.pi / 2
                    n.position = SCNVector3(centre.x, y, centre.z)
                    ground.addChildNode(n)
                }
                func box(_ w: Float, _ height: Float, _ d: Float, _ material: SCNMaterial, top: SCNMaterial? = nil,
                         at offset: SCNVector3 = SCNVector3Zero) {
                    let b = SCNBox(width: CGFloat(w), height: CGFloat(height), length: CGFloat(d), chamferRadius: 0)
                    b.materials = top.map { [material, material, material, material, $0, material] } ?? [material]
                    let n = SCNNode(geometry: b)
                    n.position = SCNVector3(centre.x + offset.x, height / 2 + offset.y, centre.z + offset.z)
                    ground.addChildNode(n)
                }
                switch kind {
                case .road, .highway, .bridge, .alley:
                    flat(kind == .alley ? 0x34353B : 0x2A2C31)
                    if kind == .bridge {
                        flat(0x1E5E8C, y: -1.2, shiny: true)
                        for side: Float in [-1, 1] { box(0.12, 0.6, t, mat(0xC8341F), at: SCNVector3(side * t * 0.46, 0, 0)) }
                    }
                    if kind != .alley { laneMarks(coord, centre: centre, t: t, into: ground, highway: kind != .road) }
                case .sidewalk:
                    box(t, 0.1, t, mat(0x9C9A94), top: mat(0xA9A69F))
                    if h % 9 == 0 { lamp(at: centre, into: ground) } else if h % 13 == 0 { palm(at: centre, into: ground, seed: h) }
                case .dock:
                    flat(0x6B5A45)
                case .plaza:
                    flat(0x8A8378)
                    if h % 7 == 0 { palm(at: centre, into: ground, seed: h) }
                case .safehouse:
                    flat(0x3D4048)
                case .building:
                    // Height by block (neighbouring tiles share a base) with per-tile steps.
                    let block = hash(c / 3, r / 3)
                    let floors = 2 + (block % 7) + (h % 3)
                    let style = (block / 7) % 5
                    let height = Float(floors) * 1.4
                    box(t, height, t, facade(style, floors: floors), top: mat(0x3A3D44))
                case .container:
                    let colors: [UInt32] = [0xB8442F, 0x2F6FB8, 0x3E8E4E, 0xD08A2A, 0x7A7F88]
                    box(t * 0.92, 1.3 + Float(h % 2) * 1.3, t * 0.45, mat(colors[h % colors.count]))
                case .fence:
                    flat(0x2A2C31)
                    box(t, 0.9, 0.06, mat(0x9AA0A8))
                case .water:
                    flat(0x1E5E8C, y: -0.25, shiny: true)
                case .grass:
                    flat(0x5E8F3A)
                case .sand:
                    flat(0xD2B07A)
                    if h % 23 == 0 { palm(at: centre, into: ground, seed: h) }
                case .forest:
                    flat(0x3F6B2C)
                    for i in 0..<2 { tree(at: centre, into: ground, seed: h &+ i * 977, spread: t * 0.35) }
                case .rock:
                    box(t, 2 + Float(h % 5) * 1.2, t, mat(0x8A7560), top: mat(0x9C8670))
                case .landmark:
                    flat(0x8A8378)
                    if h % 4 == 0 { box(t * 0.8, 6 + Float(h % 6), t * 0.8, mat(0xE2B13C, shiny: true)) }
                }
            }
        }
        chunk.addChildNode(ground.flattenedClone())
        return chunk
    }

    /// Dashed centre line (yellow, double on highways) along the road's direction.
    private func laneMarks(_ c: TileCoord, centre: SCNVector3, t: Float, into parent: SCNNode, highway: Bool) {
        func road(_ dc: Int, _ dr: Int) -> Bool {
            let n = TileCoord(col: c.col + dc, row: c.row + dr)
            guard n.col >= 0, n.row >= 0, n.col < district.cols, n.row < district.rows else { return false }
            return district.tile(n).isRoad
        }
        let horizontal = (road(-1, 0) || road(1, 0)) && !(road(0, -1) && road(0, 1))
        let vertical = (road(0, -1) || road(0, 1)) && !(road(-1, 0) && road(1, 0))
        guard horizontal != vertical else { return }
        let color = mat(0xF2C230, emission: isDark ? 0x2A2000 : nil)
        let offsets: [Float] = highway ? [-0.09, 0.09] : [0]
        for o in offsets {
            for i in 0..<(highway ? 1 : 2) {
                let length = highway ? t : t * 0.3
                let plane = SCNPlane(width: CGFloat(horizontal ? length : 0.1), height: CGFloat(horizontal ? 0.1 : length))
                plane.firstMaterial = color
                let n = SCNNode(geometry: plane)
                n.eulerAngles.x = -.pi / 2
                let along = highway ? 0 : (Float(i) - 0.5) * t * 0.5
                n.position = SCNVector3(centre.x + (horizontal ? along : o), 0.012, centre.z + (horizontal ? o : along))
                parent.addChildNode(n)
            }
        }
    }

    private func lamp(at p: SCNVector3, into parent: SCNNode) {
        let pole = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 3.2))
        pole.geometry!.firstMaterial = mat(0x5A5F68)
        pole.position = SCNVector3(p.x, 1.6, p.z)
        parent.addChildNode(pole)
        let head = SCNNode(geometry: SCNBox(width: 0.5, height: 0.12, length: 0.22, chamferRadius: 0.04))
        head.geometry!.firstMaterial = mat(0x2A2D33, emission: isDark ? 0xFFE3A0 : nil)
        head.position = SCNVector3(p.x + 0.2, 3.2, p.z)
        parent.addChildNode(head)
    }

    private func palm(at p: SCNVector3, into parent: SCNNode, seed: Int) {
        let height: Float = 3.6 + Float(seed % 3) * 0.6
        let trunk = SCNNode(geometry: SCNCylinder(radius: 0.1, height: CGFloat(height)))
        trunk.geometry!.firstMaterial = mat(0x8A6A48)
        trunk.position = SCNVector3(p.x, height / 2, p.z)
        parent.addChildNode(trunk)
        for i in 0..<6 {
            let frond = SCNNode(geometry: SCNBox(width: 0.28, height: 0.03, length: 1.5, chamferRadius: 0.02))
            frond.geometry!.firstMaterial = mat(0x3E8E3A)
            let a = Float(i) / 6 * 2 * .pi + Float(seed % 7) * 0.3
            frond.position = SCNVector3(p.x + sin(a) * 0.6, height - 0.1, p.z + cos(a) * 0.6)
            frond.eulerAngles = SCNVector3(0.35, a, 0)
            parent.addChildNode(frond)
        }
    }

    private func tree(at p: SCNVector3, into parent: SCNNode, seed: Int, spread: Float) {
        let dx = Float(seed % 100) / 100 * spread * 2 - spread
        let dz = Float((seed / 100) % 100) / 100 * spread * 2 - spread
        let h: Float = 3 + Float(seed % 4)
        let trunk = SCNNode(geometry: SCNCylinder(radius: 0.18, height: CGFloat(h * 0.4)))
        trunk.geometry!.firstMaterial = mat(0x5A3E28)
        trunk.position = SCNVector3(p.x + dx, h * 0.2, p.z + dz)
        parent.addChildNode(trunk)
        let crown = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 1.1, height: CGFloat(h)))
        crown.geometry!.firstMaterial = mat(0x2F5E2A)
        crown.position = SCNVector3(p.x + dx, h * 0.4 + h / 2, p.z + dz)
        parent.addChildNode(crown)
    }

    // MARK: Vehicles and people

    private func vehicleModel(_ model: VehicleID, color hex: UInt32, rims: RimSetup?, patrol: Bool = false) -> SCNNode {
        let size = HDArt.vehicleSize(model)
        let width = Float(size.width) * Self.u * 0.95, length = Float(size.height) * Self.u * 0.95
        let style = CarLineup.style(model)
        let car = SCNNode()
        let paint = mat(hex, shiny: true)
        let glass = mat(0x14202E, shiny: true)
        let wheelR: Float = style == .suv || style == .truck ? 0.3 : 0.24

        if model.isMotorcycle {
            let frame = SCNNode(geometry: SCNBox(width: 0.18, height: 0.32, length: CGFloat(length * 0.7), chamferRadius: 0.06))
            frame.geometry!.firstMaterial = paint
            frame.position = SCNVector3(0, 0.5, 0)
            car.addChildNode(frame)
            for z in [-length * 0.38, length * 0.38] {
                let w = SCNNode(geometry: SCNCylinder(radius: 0.26, height: 0.1))
                w.geometry!.firstMaterial = mat(0x0B0C0F)
                w.eulerAngles.z = .pi / 2
                w.position = SCNVector3(0, 0.26, z)
                car.addChildNode(w)
            }
            let light = SCNNode(geometry: SCNSphere(radius: 0.07))
            light.geometry!.firstMaterial = mat(0xFFF4D6, emission: 0xFFF4D6)
            light.position = SCNVector3(0, 0.75, -length * 0.4)
            car.addChildNode(light)
            return car
        }

        let bodyH: Float = style == .suv || style == .van || style == .truck ? 0.75 : style == .supercar || style == .wedge ? 0.42 : 0.52
        let ride: Float = wheelR * 0.9
        let body = SCNNode(geometry: SCNBox(width: CGFloat(width), height: CGFloat(bodyH), length: CGFloat(length), chamferRadius: 0.12))
        body.geometry!.firstMaterial = paint
        body.position = SCNVector3(0, ride + bodyH / 2, 0)
        car.addChildNode(body)

        if model == .hauler {
            // Cab up front, a long box trailer behind.
            let trailer = SCNNode(geometry: SCNBox(width: CGFloat(width), height: 1.3, length: CGFloat(length * 0.72), chamferRadius: 0.05))
            trailer.geometry!.firstMaterial = mat(0xE9E6DF)
            trailer.position = SCNVector3(0, ride + bodyH + 0.65, length * 0.13)
            car.addChildNode(trailer)
        } else {
            let cabinL: Float = style == .suv || style == .van ? 0.62 : style == .supercar || style == .wedge ? 0.32 : 0.42
            let cabinH: Float = style == .supercar || style == .wedge ? 0.3 : style == .van ? 0.55 : 0.4
            let cabin = SCNNode(geometry: SCNBox(width: CGFloat(width * 0.84), height: CGFloat(cabinH), length: CGFloat(length * cabinL), chamferRadius: 0.12))
            cabin.geometry!.firstMaterial = glass
            cabin.position = SCNVector3(0, ride + bodyH + cabinH / 2 - 0.04, length * (style == .supercar ? 0.02 : 0.06))
            car.addChildNode(cabin)
            let roof = SCNNode(geometry: SCNBox(width: CGFloat(width * 0.78), height: 0.05, length: CGFloat(length * cabinL * 0.8), chamferRadius: 0.02))
            roof.geometry!.firstMaterial = style == .ev ? glass : paint
            roof.position = SCNVector3(0, ride + bodyH + cabinH - 0.02, cabin.position.z)
            car.addChildNode(roof)
        }
        if patrol {
            let bar = SCNNode(geometry: SCNBox(width: CGFloat(width * 0.7), height: 0.1, length: 0.2, chamferRadius: 0.03))
            bar.geometry!.materials = [mat(0xFF2E4A, emission: 0xFF2E4A)]
            bar.name = "lightbar"
            bar.position = SCNVector3(0, ride + bodyH + 0.44, 0.05)
            car.addChildNode(bar)
        }
        // Wheels and rims.
        let rimHex = rims.map { RimColors.hex[$0.color % RimColors.hex.count] } ?? 0x8A909C
        for x in [-width / 2 + 0.06, width / 2 - 0.06] {
            for z in [-length * 0.32, length * 0.32] {
                let tyre = SCNNode(geometry: SCNCylinder(radius: CGFloat(wheelR), height: 0.2))
                tyre.geometry!.firstMaterial = mat(0x0B0C0F)
                tyre.eulerAngles.z = .pi / 2
                tyre.position = SCNVector3(x, wheelR, z)
                car.addChildNode(tyre)
                let rim = SCNNode(geometry: SCNCylinder(radius: CGFloat(wheelR * 0.62), height: 0.21))
                rim.geometry!.firstMaterial = mat(rimHex, shiny: true)
                rim.eulerAngles.z = .pi / 2
                rim.position = SCNVector3(x + (x < 0 ? -0.005 : 0.005), wheelR, z)
                car.addChildNode(rim)
            }
        }
        // Head and tail lights.
        for x in [-width * 0.32, width * 0.32] {
            let head = SCNNode(geometry: SCNBox(width: 0.22, height: 0.08, length: 0.04, chamferRadius: 0.02))
            head.geometry!.firstMaterial = mat(0xFFF4D6, emission: 0xFFF4D6)
            head.position = SCNVector3(x, ride + bodyH * 0.65, -length / 2 - 0.01)
            car.addChildNode(head)
            let tail = SCNNode(geometry: SCNBox(width: 0.24, height: 0.08, length: 0.04, chamferRadius: 0.02))
            tail.geometry!.firstMaterial = mat(0xFF2E4A, emission: 0x8A0F1E)
            tail.position = SCNVector3(x, ride + bodyH * 0.7, length / 2 + 0.01)
            car.addChildNode(tail)
        }
        if isDark {
            let beam = SCNLight()
            beam.type = .spot
            beam.color = UIColor(hex: 0xFFF1CF)
            beam.intensity = 900
            beam.spotInnerAngle = 20
            beam.spotOuterAngle = 45
            beam.attenuationEndDistance = 18
            let n = SCNNode()
            n.light = beam
            n.position = SCNVector3(0, ride + bodyH, -length / 2)
            n.eulerAngles.x = -0.18
            n.name = "beam"
            car.addChildNode(n)
        }
        return car
    }

    // MARK: Per frame

    /// Draws the city as it is now and moves the camera. `targets` are objective centres.
    func update(city: City, targets: [Vec2], dt: Double, shake: Bool, facing: Double, footView: FootView) {
        time += dt
        let player = city.player
        stream(around: player.position)
        SCNTransaction.begin()
        SCNTransaction.disableActions = true

        // Vehicles (parked and the one you're in).
        var live = Set<Int>()
        for v in city.vehicles where !v.retired {
            live.insert(v.id)
            let key = "\(v.model.rawValue)|\(v.rims?.style.rawValue ?? "-")\(v.rims?.color ?? -1)"
            if vehicleKeys[v.id] != key {
                vehicleNodes[v.id]?.removeFromParentNode()
                let colour = v.design.flatMap { $0.dominantHex } ?? UInt32(HDArt.factoryColor(v.model).hexValue)
                let node = vehicleModel(v.model, color: colour, rims: v.rims)
                dynamicRoot.addChildNode(node)
                vehicleNodes[v.id] = node
                vehicleKeys[v.id] = key
            }
            let node = vehicleNodes[v.id]!
            node.position = Self.pos(v.state.position)
            node.eulerAngles.y = Self.yaw(v.state.heading)
        }
        for (id, node) in vehicleNodes where !live.contains(id) {
            node.removeFromParentNode()
            vehicleNodes[id] = nil
            vehicleKeys[id] = nil
        }

        // Patrol cars, with flashing bars when chasing.
        let patrols = Set(city.pursuit.patrols.map(\.id))
        for (id, node) in patrolNodes where !patrols.contains(id) { node.removeFromParentNode(); patrolNodes[id] = nil }
        for patrol in city.pursuit.patrols {
            let node = patrolNodes[patrol.id] ?? {
                let n = vehicleModel(.harborPatrol, color: 0xEDEFF4, rims: nil, patrol: true)
                dynamicRoot.addChildNode(n)
                patrolNodes[patrol.id] = n
                return n
            }()
            node.position = Self.pos(patrol.car.position)
            node.eulerAngles.y = Self.yaw(patrol.car.heading)
            if let bar = node.childNode(withName: "lightbar", recursively: false) {
                let on = patrol.mode == .chase || patrol.parked
                let blue = Int(time * 6) % 2 == 0
                bar.geometry!.firstMaterial!.emission.contents = on ? UIColor(hex: blue ? 0x2E7BFF : 0xFF2E4A) : UIColor.black
            }
        }

        // People.
        let crowdIDs = Set(city.crowd.people.map(\.id))
        for (id, rig) in people where !crowdIDs.contains(id) { rig.node.removeFromParentNode(); people[id] = nil }
        for person in city.crowd.people {
            let rig = people[person.id] ?? {
                let r = HumanRig(look: HumanLook.crowd(person.look), detail: false)
                dynamicRoot.addChildNode(r.node)
                people[person.id] = r
                return r
            }()
            rig.node.position = Self.pos(person.position)
            rig.node.eulerAngles.y = Self.yaw(person.heading)
            rig.pose(time: time, phase: Double(person.id) * 1.7, speed: person.isDown ? 0 : (person.mode == .flee ? 2 : 1),
                     punch: nil, aiming: false, down: person.isDown)
        }
        let officerIDs = Set(city.officers.map(\.id))
        for (id, rig) in officerRigs where !officerIDs.contains(id) { rig.node.removeFromParentNode(); officerRigs[id] = nil }
        let drawn = city.standoff != .none
        for o in city.officers {
            let rig = officerRigs[o.id] ?? {
                let r = HumanRig(look: HumanLook.officer(o.id))
                r.hold(.pistol)
                dynamicRoot.addChildNode(r.node)
                officerRigs[o.id] = r
                return r
            }()
            rig.node.position = Self.pos(o.position)
            rig.node.eulerAngles.y = Self.yaw(o.heading)
            rig.pose(time: time, phase: Double(o.id), speed: o.returning ? 1 : 0, punch: nil,
                     aiming: drawn && !o.returning, down: o.isDown)
        }

        // The player on foot.
        if playerRig == nil {
            playerRig = HumanRig(look: playerLook)
            dynamicRoot.addChildNode(playerRig!.node)
        }
        let me = playerRig!
        me.node.isHidden = !city.isOnFoot
        if city.isOnFoot {
            let weapon = city.inventory.equipped
            me.hold(weapon)
            me.node.position = Self.pos(city.foot.position)
            me.node.eulerAngles.y = Self.yaw(city.foot.heading)
            let gun = weapon != nil && weapon != .bat
            let aiming = gun && (city.aimLock != nil || time - lastShot < 0.9)
            let punch = lastPunch.map { (time - $0.0, $0.1) }
            me.pose(time: time, phase: 0, speed: min(2.2, city.foot.speed / 150), punch: punch, aiming: aiming, down: false)
        }

        // Weapons lying in the street.
        let pickups = Set(city.pickups.filter(\.isAvailable).map(\.id))
        for (id, node) in pickupNodes where !pickups.contains(id) { node.removeFromParentNode(); pickupNodes[id] = nil }
        for pickup in city.pickups where pickup.isAvailable {
            let node = pickupNodes[pickup.id] ?? {
                let n = SCNNode(geometry: SCNBox(width: 0.5, height: 0.3, length: 0.5, chamferRadius: 0.06))
                n.geometry!.firstMaterial = mat(0xFF8A3D, emission: 0x7A3A10)
                dynamicRoot.addChildNode(n)
                pickupNodes[pickup.id] = n
                return n
            }()
            node.position = Self.pos(pickup.position, 0.4 + Float(sin(time * 3)) * 0.1)
            node.eulerAngles.y = Float(time)
        }

        // Objectives: tall light beams you can see over the rooftops.
        while markerNodes.count < targets.count {
            let beam = SCNNode(geometry: SCNCylinder(radius: 0.9, height: 40))
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(hex: 0x2EE6D6, alpha: 0.28)
            m.emission.contents = UIColor(hex: 0x2EE6D6)
            m.emission.intensity = 0.6
            m.transparencyMode = .singleLayer
            m.writesToDepthBuffer = false
            m.lightingModel = .constant
            beam.geometry!.firstMaterial = m
            beam.renderingOrder = 50
            dynamicRoot.addChildNode(beam)
            markerNodes.append(beam)
        }
        for (i, beam) in markerNodes.enumerated() {
            beam.isHidden = i >= targets.count
            if i < targets.count { beam.position = Self.pos(targets[i], 20) }
        }

        // 1st person: no body in the way.
        me.node.isHidden = !city.isOnFoot || footView == .eyes
        moveCamera(city: city, dt: dt, shake: shake, facing: facing, footView: footView)
        SCNTransaction.commit()
    }

    /// Behind the car, or over the shoulder on foot; it eases after you and swings round with
    /// your heading.
    private func moveCamera(city: City, dt: Double, shake: Bool, facing: Double, footView: FootView) {
        let body = city.player
        let heading = facing
        let fwd = SCNVector3(Float(cos(heading)), 0, -Float(sin(heading)))
        let right = SCNVector3(-fwd.z, 0, fwd.x)
        let at = Self.pos(body.position)
        let onFoot = city.isOnFoot
        let speed = Float(min(1, body.speed / 600))
        let truck = city.currentVehicle?.model.isTruck == true
        let eyes = onFoot && footView == .eyes
        let far = onFoot && footView == .overhead
        // People are 0.72 units tall (1.8 m); the shoulder camera sits just behind and above.
        let back: Float = eyes ? -0.05 : onFoot ? (far ? 2.8 : 1.55) : (truck ? 13 : 6.2 + speed * 1.6)
        let up: Float = eyes ? 0.66 : onFoot ? (far ? 1.5 : 0.86) : (truck ? 4.6 : 2.5 + speed * 0.3)
        let side: Float = eyes ? 0 : onFoot ? 0.26 : 0
        var want = at - fwd * back + SCNVector3(0, up, 0) + right * side
        let lookAt = at + fwd * (onFoot ? 4 : 9) + SCNVector3(0, eyes ? 0.62 : onFoot ? 0.6 : 0.8, 0) + right * side
        if shake { want = want + SCNVector3(Float.random(in: -0.08...0.08), Float.random(in: -0.06...0.06), 0) }
        if !placedCamera {
            camPos = want
            camLook = lookAt
            placedCamera = true
        } else {
            let k = Float(min(1, dt * (onFoot ? 7 : 4.5)))
            camPos = camPos + (want - camPos) * k
            camLook = camLook + (lookAt - camLook) * Float(min(1, dt * 8))
        }
        cameraNode.position = camPos
        cameraNode.look(at: camLook)
    }
}

// MARK: - Helpers

private func + (a: SCNVector3, b: SCNVector3) -> SCNVector3 { SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z) }
private func - (a: SCNVector3, b: SCNVector3) -> SCNVector3 { SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z) }
private func * (a: SCNVector3, k: Float) -> SCNVector3 { SCNVector3(a.x * k, a.y * k, a.z * k) }

extension UIColor {
    var hexValue: Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(r * 255) << 16) | (Int(g * 255) << 8) | Int(b * 255)
    }
}

extension PaintDesign {
    /// The colour covering most of a design (the 3D car is painted one colour).
    @MainActor var dominantHex: UInt32? {
        var counts: [UInt8: Int] = [:]
        for row in 0..<PaintDesign.height {
            for col in 0..<PaintDesign.width { counts[cell(col: col, row: row), default: 0] += 1 }
        }
        guard let top = counts.max(by: { $0.value < $1.value })?.key,
              let c = PixelArt.designColor(top) else { return nil }
        return UInt32(c.hexValue)
    }
}

/// The 3D street in SwiftUI.
struct Street3DView: UIViewRepresentable {
    let street: Street3D
    var fps: Int = 60

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = street.scene
        view.pointOfView = street.cameraNode
        view.rendersContinuously = true
        view.preferredFramesPerSecond = fps
        view.antialiasingMode = .multisampling2X
        view.isUserInteractionEnabled = false
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
