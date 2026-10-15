import SwiftUI
import SceneKit
import GameCore

/// The player's 3D character on a little turntable (character creation and the Style screen).
struct CharacterPreview: UIViewRepresentable {
    let look: HumanLook
    var reduceMotion = false

    @MainActor
    final class Coordinator {
        var look: HumanLook?
        let scene = SCNScene()
        let stand = SCNNode()
        var rig: HumanRig?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let c = context.coordinator
        let view = SCNView(frame: .zero)
        view.scene = c.scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isUserInteractionEnabled = true
        view.allowsCameraControl = false
        view.rendersContinuously = !reduceMotion

        let floor = SCNNode(geometry: SCNCylinder(radius: 0.35, height: 0.02))
        let fm = SCNMaterial()
        fm.diffuse.contents = UIColor(hex: 0x1F2230)
        fm.emission.contents = UIColor(hex: 0x0E1A22)
        floor.geometry!.firstMaterial = fm
        floor.position = SCNVector3(0, -0.01, 0)
        c.scene.rootNode.addChildNode(floor)
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.35, pipeRadius: 0.006))
        let rm = SCNMaterial()
        rm.diffuse.contents = UIColor(hex: 0x2EE6D6)
        rm.emission.contents = UIColor(hex: 0x2EE6D6)
        ring.geometry!.firstMaterial = rm
        c.scene.rootNode.addChildNode(ring)
        c.scene.rootNode.addChildNode(c.stand)
        // Face the camera first (people face −Z; the camera looks from +Z).
        c.stand.eulerAngles.y = .pi
        if !reduceMotion && !DebugLaunch.noSpin {
            c.stand.runAction(.repeatForever(.sequence([.wait(duration: 2.5),
                                                        .rotateBy(x: 0, y: .pi * 2, z: 0, duration: 10)])))
        } else {
            c.stand.eulerAngles.y = .pi
        }

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 900
        key.eulerAngles = SCNVector3(-0.6, -0.5, 0)
        c.scene.rootNode.addChildNode(key)
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light!.type = .directional
        rim.light!.intensity = 380
        rim.light!.color = UIColor(hex: 0xDCE8FF)
        rim.eulerAngles = SCNVector3(-0.3, 2.6, 0)
        c.scene.rootNode.addChildNode(rim)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .ambient
        fill.light!.intensity = 350
        c.scene.rootNode.addChildNode(fill)
        let env = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 64)).image { ctx in
            let colors = [UIColor(hex: 0xC9D8EA).cgColor, UIColor(hex: 0x6A6560).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: 64), options: [])
        }
        c.scene.lightingEnvironment.contents = env
        c.scene.lightingEnvironment.intensity = 1.0

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera!.fieldOfView = 30
        camera.position = SCNVector3(0, 0.48, 1.75)
        camera.look(at: SCNVector3(0, 0.38, 0))
        c.scene.rootNode.addChildNode(camera)
        view.pointOfView = camera
        setLook(c)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        setLook(context.coordinator)
    }

    private func setLook(_ c: Coordinator) {
        guard c.look != look else { return }
        c.look = look
        c.rig?.node.removeFromParentNode()
        let rig = HumanRig(look: look)
        rig.pose(time: 0.4, phase: 0, speed: 0, punch: nil, aiming: false, down: false)
        c.stand.addChildNode(rig.node)
        c.rig = rig
    }
}

/// A row of word chips for choosing one option.
struct ChipPicker: View {
    let title: String
    let options: [String]
    @Binding var selection: Int
    var id: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).pixelLabel(.caption, color: Palette.teal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options.indices, id: \.self) { i in
                        Button { selection = i } label: {
                            Text(options[i])
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(i == selection ? Palette.ink : Palette.cream)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .background(i == selection ? Palette.teal : Palette.ink.opacity(0.7), in: Capsule())
                                .overlay(Capsule().strokeBorder(Palette.teal.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title): \(options[i])")
                        .accessibilityAddTraits(i == selection ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("\(id).\(i)")
                    }
                }
            }
        }
    }
}

/// Change your look any time: skin, hair, style, clothes and build, with a 3D preview.
struct StyleView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = PlayerProfile(name: "")
    @State private var loaded = false
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Style") { router.back() }
                CharacterPreview(look: HumanLook.player(draft), reduceMotion: reduceMotion)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .background(Palette.ink.opacity(0.5))
                    .accessibilityLabel("Your character")
                LookPickers(draft: $draft)
                Button(saved ? "Saved" : "Save look") {
                    model.updateLook(draft)
                    saved = true
                }
                .buttonStyle(.neon(Palette.teal))
                .accessibilityIdentifier("style.save")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = (model.progress.profile ?? PlayerProfile(name: "Player")).normalized
        }
        .onChange(of: draft) { _, _ in saved = false }
    }
}

/// Every look option (onboarding and the Style screen share it).
struct LookPickers: View {
    @Binding var draft: PlayerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ColourRow(title: "Skin", colors: PixelArt.lookSkins.map(Color.init(uiColor:)),
                      names: (1...PixelArt.lookSkins.count).map { "Tone \($0)" }, selection: $draft.skin)
            ChipPicker(title: "Hair style", options: PlayerProfile.hairStyles,
                       selection: Binding(get: { draft.hairStyle ?? 0 }, set: { draft.hairStyle = $0 }), id: "look.hairStyle")
            ColourRow(title: "Hair colour", colors: PixelArt.lookHairs.map(Color.init(uiColor:)),
                      names: PixelArt.lookHairNames, selection: $draft.hair)
            ChipPicker(title: "Outfit", options: PlayerProfile.outfits,
                       selection: Binding(get: { draft.outfit ?? 0 }, set: { draft.outfit = $0 }), id: "look.outfit")
            ColourRow(title: "Top colour", colors: PixelArt.lookJackets.map(Color.init(uiColor:)),
                      names: PixelArt.lookJacketNames, selection: $draft.jacket)
            ChipPicker(title: "Frame", options: PlayerProfile.frames,
                       selection: Binding(get: { draft.frame ?? 0 }, set: { draft.frame = $0 }), id: "look.frame")
            ChipPicker(title: "Build", options: PlayerProfile.builds,
                       selection: Binding(get: { draft.build ?? 1 }, set: { draft.build = $0 }), id: "look.build")
            ChipPicker(title: "Facial hair", options: PlayerProfile.facialHairs,
                       selection: Binding(get: { draft.facialHair ?? 0 }, set: { draft.facialHair = $0 }), id: "look.facialHair")
        }
    }
}

/// Colour squares for one option.
struct ColourRow: View {
    let title: String
    let colors: [Color]
    let names: [String]
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).pixelLabel(.caption, color: Palette.teal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(colors.indices, id: \.self) { i in
                        Button { selection = i } label: {
                            Circle().fill(colors[i])
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(i == selection ? Palette.cream : Palette.ink, lineWidth: i == selection ? 3 : 1))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title): \(names[i])")
                        .accessibilityAddTraits(i == selection ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
    }
}
