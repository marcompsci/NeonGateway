import SceneKit
import UIKit
import simd
import GameCore

/// How a 3D person looks: skin, face, hair, clothes and body.
struct HumanLook: Hashable {
    var skin: UInt32
    var hair: UInt32
    var hairStyle = 0          // PlayerProfile.hairStyles
    var top: UInt32
    var outfit = 0             // PlayerProfile.outfits
    var legs: UInt32 = 0x2E4A78
    var shorts = false
    var shoes: UInt32 = 0x1A1B1F
    var build = 1              // 0 slim … 3 broad
    var frame = 0              // 0 straight, 1 curvy
    var facialHair = 0         // 0 none, 1 stubble, 2 beard
    var eyes: UInt32 = 0x4A2E1C
    var lips: UInt32? = nil    // lipstick (crowd variety)
    var height: Float = 1.0
    var cap = false
    var officer = false

    @MainActor static func player(_ profile: PlayerProfile?) -> HumanLook {
        let base = HDArt.playerLook(profile)
        let n = profile?.normalized
        return HumanLook(skin: base.skin, hair: base.hair, hairStyle: n?.hairStyle ?? 0, top: base.top,
                         outfit: n?.outfit ?? 0, legs: 0x2E4A78, shoes: 0xF2F2F2, build: n?.build ?? 1,
                         frame: n?.frame ?? 0, facialHair: n?.facialHair ?? 0)
    }

    @MainActor static func crowd(_ i: Int) -> HumanLook {
        let l = HDArt.crowdLook(i)
        let k = abs(i)
        let curvy = k % 2 == 1
        let styles = curvy ? [3, 6, 7, 4, 2, 5] : [0, 1, 2, 5, 8, 0]
        let outfits = curvy ? [5, 6, 1, 3, 2, 7, 4] : [4, 1, 2, 7, 0, 3, 4]
        let eyes: [UInt32] = [0x4A2E1C, 0x2B1A10, 0x5C7A3A, 0x3D6E9E, 0x6B4A2A]
        return HumanLook(skin: l.skin, hair: l.hair, hairStyle: styles[(k / 3) % styles.count], top: l.top,
                         outfit: outfits[(k / 5) % outfits.count], legs: [0x2E4A78, 0x1E2A44, 0xC9B48A, 0x23252C][k % 4],
                         shorts: k % 9 == 0, shoes: [0x1A1B1F, 0xF2F2F2, 0x6B4A2E, 0x2E5FB8][k % 4],
                         build: (k / 2) % 4, frame: curvy ? 1 : 0, facialHair: curvy ? 0 : (k / 7) % 3,
                         eyes: eyes[k % eyes.count], lips: curvy && k % 3 == 0 ? 0xA8354A : nil,
                         height: (curvy ? 0.94 : 0.98) + Float(k % 5) * 0.025)
    }

    @MainActor static func officer(_ id: Int) -> HumanLook {
        let l = HDArt.officerLook(id)
        return HumanLook(skin: l.skin, hair: 0x15110E, hairStyle: 1, top: 0x1F3C78, outfit: 0, legs: 0x141C30,
                         shoes: 0x0B0C0F, build: 2, facialHair: id % 3 == 0 ? 1 : 0,
                         height: 1.0 + Float(id % 3) * 0.02, cap: true, officer: true)
    }
}

// MARK: - Mesh building

/// One cross-section of a lofted tube: an ellipse around `center` in the plane of `u` and `w`.
private struct Ring {
    var center: SIMD3<Float>
    var rx: Float
    var rz: Float
    /// Extra push out the front (−Z) for chests and bellies, as a fraction of rz.
    var front: Float = 0
    var bones: [(Int, Float)] = []
    var u = SIMD3<Float>(1, 0, 0)
    var w = SIMD3<Float>(0, 0, 1)
}

/// Accumulates vertices (with optional bone weights) and triangles, then makes SceneKit geometry.
private struct MeshBuilder {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var weights: [SIMD4<Float>] = []
    var boneIdx: [SIMD4<UInt16>] = []
    var tris: [UInt32] = []

    mutating func add(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float>, _ bones: [(Int, Float)]) {
        positions.append(p)
        normals.append(simd_normalize(n))
        uvs.append(uv)
        var b = bones.filter { $0.1 > 0.001 }.sorted { $0.1 > $1.1 }
        if b.count > 4 { b = Array(b.prefix(4)) }
        let total = max(0.0001, b.reduce(0) { $0 + $1.1 })
        var wv = SIMD4<Float>(0, 0, 0, 0), iv = SIMD4<UInt16>(0, 0, 0, 0)
        for (k, e) in b.enumerated() {
            wv[k] = e.1 / total
            iv[k] = UInt16(e.0)
        }
        if b.isEmpty { wv[0] = 1 }
        weights.append(wv)
        boneIdx.append(iv)
    }

    /// A lofted tube through `rings`, `segments` around. The seam is at the back (+Z), so u = 0.5
    /// is the front. `vertexBones` can override weights per vertex.
    mutating func tube(_ rings: [Ring], segments: Int = 18, capStart: Bool = false, capEnd: Bool = false,
                       vRepeat: Float = 1, vertexBones: ((SIMD3<Float>, Ring) -> [(Int, Float)])? = nil,
                       bulge: ((Float, Int) -> Float)? = nil) {
        let base = UInt32(positions.count)
        var length: Float = 0
        var vs: [Float] = [0]
        for i in 1..<rings.count {
            length += simd_distance(rings[i].center, rings[i - 1].center)
            vs.append(length)
        }
        let total = max(0.001, length)
        for (ri, ring) in rings.enumerated() {
            for s in 0...segments {
                let t = Float(s) / Float(segments)
                let theta = t * 2 * .pi + .pi / 2
                let c = cos(theta), sn = sin(theta)
                var rz = ring.rz
                if sn < 0 { rz *= 1 + ring.front * sn * sn }
                var r: Float = 1
                if let bulge { r += bulge(t, ri) }
                let p = ring.center + ring.u * (c * ring.rx * r) + ring.w * (sn * rz * r)
                let n = ring.u * (c / max(0.001, ring.rx)) + ring.w * (sn / max(0.001, rz))
                let bones = vertexBones?(p, ring) ?? ring.bones
                add(p, n, SIMD2(t, vs[ri] / total * vRepeat), bones)
            }
        }
        let stride = UInt32(segments + 1)
        for ri in 0..<(rings.count - 1) {
            for s in 0..<segments {
                let a = base + UInt32(ri) * stride + UInt32(s)
                let b = a + 1, c = a + stride, d = c + 1
                tris += [a, c, b, b, c, d]
            }
        }
        func cap(_ ri: Int, flip: Bool) {
            let ring = rings[ri]
            let dir = simd_normalize(simd_cross(ring.u, ring.w)) * (flip ? -1 : 1)
            let centre = UInt32(positions.count)
            add(ring.center, dir, SIMD2(0.5, ri == 0 ? 0 : vRepeat), vertexBones?(ring.center, ring) ?? ring.bones)
            let start = base + UInt32(ri) * stride
            for s in 0..<UInt32(segments) {
                tris += flip ? [centre, start + s + 1, start + s] : [centre, start + s, start + s + 1]
            }
        }
        if capStart { cap(0, flip: false) }
        if capEnd { cap(rings.count - 1, flip: true) }
    }

    func geometry(_ material: SCNMaterial) -> SCNGeometry {
        let pos = positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let nor = normals.map { SCNVector3($0.x, $0.y, $0.z) }
        let tex = uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor),
                                      SCNGeometrySource(textureCoordinates: tex)],
                            elements: [SCNGeometryElement(indices: tris, primitiveType: .triangles)])
        g.firstMaterial = material
        return g
    }

    func skinSources() -> (SCNGeometrySource, SCNGeometrySource) {
        let wData = weights.withUnsafeBufferPointer { Data(buffer: $0) }
        let iData = boneIdx.withUnsafeBufferPointer { Data(buffer: $0) }
        let w = SCNGeometrySource(data: wData, semantic: .boneWeights, vectorCount: weights.count, usesFloatComponents: true,
                                  componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0,
                                  dataStride: MemoryLayout<SIMD4<Float>>.stride)
        let i = SCNGeometrySource(data: iData, semantic: .boneIndices, vectorCount: boneIdx.count, usesFloatComponents: false,
                                  componentsPerVector: 4, bytesPerComponent: 2, dataOffset: 0,
                                  dataStride: MemoryLayout<SIMD4<UInt16>>.stride)
        return (w, i)
    }
}

// MARK: - Textures (face, fabric, hair)

@MainActor
private enum HumanTextures {
    static var cache: [String: UIImage] = [:]

    static func face(_ look: HumanLook) -> UIImage {
        let key = "face|\(look.skin)|\(look.hair)|\(look.eyes)|\(look.lips ?? 0)|\(look.facialHair)|\(look.frame)"
        if let hit = cache[key] { return hit }
        let W: CGFloat = 512, H: CGFloat = 256
        let skin = UIColor(hex: look.skin)
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H)).image { ctx in
            let g = ctx.cgContext
            skin.setFill()
            g.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let cx = W * 0.75   // the face (front, −Z) sits at u = 0.75 on the head
            func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: UIColor) {
                c.setFill()
                g.fillEllipse(in: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h))
            }
            func soft(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: UIColor) {
                let colors = [c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray
                let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                g.drawRadialGradient(grad, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                     endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
            }
            // Gentle modelling: darker under the brow ridge, cheekbones catch the light.
            soft(cx, H * 0.47, 60, skin.darker(0.12).withAlphaComponent(0.5))
            for s: CGFloat in [-1, 1] {
                soft(cx + s * 34, H * 0.6, 26, skin.lighter(0.08).withAlphaComponent(0.6))
                soft(cx + s * 30, H * 0.63, 18, UIColor(hex: 0xD06A6A).withAlphaComponent(look.frame == 1 ? 0.22 : 0.1))
            }
            // Facial hair under everything else.
            if look.facialHair > 0 {
                let beard = UIColor(hex: look.hair).withAlphaComponent(look.facialHair == 1 ? 0.35 : 0.9)
                beard.setFill()
                let p = CGMutablePath()
                p.move(to: CGPoint(x: cx - 58, y: H * 0.56))
                p.addQuadCurve(to: CGPoint(x: cx, y: H * 0.98), control: CGPoint(x: cx - 60, y: H * 0.95))
                p.addQuadCurve(to: CGPoint(x: cx + 58, y: H * 0.56), control: CGPoint(x: cx + 60, y: H * 0.95))
                p.addLine(to: CGPoint(x: cx + 40, y: H * 0.66))
                p.addQuadCurve(to: CGPoint(x: cx - 40, y: H * 0.66), control: CGPoint(x: cx, y: H * 0.7))
                p.closeSubpath()
                g.addPath(p)
                g.fillPath()
                // Moustache.
                ellipse(cx, H * 0.665, 40, 7, beard)
            }
            // Eyes: almond whites, coloured iris, pupil, catchlight, lid line and lashes.
            for s: CGFloat in [-1, 1] {
                let ex = cx + s * 30, ey = H * 0.5
                ellipse(ex, ey + 1, 30, 13, skin.darker(0.18).withAlphaComponent(0.5))   // socket shade
                let eye = CGMutablePath()
                eye.move(to: CGPoint(x: ex - 13, y: ey))
                eye.addQuadCurve(to: CGPoint(x: ex + 13, y: ey), control: CGPoint(x: ex, y: ey - 9))
                eye.addQuadCurve(to: CGPoint(x: ex - 13, y: ey), control: CGPoint(x: ex, y: ey + 7))
                g.addPath(eye)
                UIColor(hex: 0xF3EFE8).setFill()
                g.fillPath()
                g.saveGState()
                g.addPath(eye)
                g.clip()
                ellipse(ex, ey, 11, 11, UIColor(hex: look.eyes))
                ellipse(ex, ey, 11, 11, UIColor(white: 0, alpha: 0.15))
                ellipse(ex, ey, 7, 7, UIColor(hex: look.eyes).lighter(0.15))
                ellipse(ex, ey, 4.5, 4.5, UIColor(hex: 0x0A0806))
                ellipse(ex + 2, ey - 2, 2.2, 2.2, UIColor(white: 1, alpha: 0.9))
                g.restoreGState()
                // Upper lid line, thicker for a lash line on curvy frames.
                g.setStrokeColor(UIColor(hex: 0x1A120D).cgColor)
                g.setLineWidth(look.frame == 1 ? 2.6 : 1.8)
                g.move(to: CGPoint(x: ex - 13, y: ey))
                g.addQuadCurve(to: CGPoint(x: ex + 13 + (look.frame == 1 ? s * 2 : 0), y: ey - (look.frame == 1 ? 1.5 : 0)),
                               control: CGPoint(x: ex, y: ey - 9.5))
                g.strokePath()
                // Brow.
                g.setStrokeColor(UIColor(hex: look.hair).darker(0.25).cgColor)
                g.setLineWidth(look.frame == 1 ? 3.2 : 4.4)
                g.setLineCap(.round)
                g.move(to: CGPoint(x: ex - s * 14, y: H * 0.44))
                g.addQuadCurve(to: CGPoint(x: ex + s * 15, y: H * 0.445), control: CGPoint(x: ex + s * 2, y: H * 0.405))
                g.strokePath()
            }
            // Nose: soft shadows either side and under the tip.
            soft(cx - 9, H * 0.61, 8, skin.darker(0.3).withAlphaComponent(0.6))
            soft(cx + 9, H * 0.61, 8, skin.darker(0.3).withAlphaComponent(0.6))
            ellipse(cx, H * 0.635, 14, 4, skin.darker(0.25))
            // Mouth.
            let lip = look.lips.map { UIColor(hex: $0) } ?? skin.darker(0.28).mixedRed()
            let mouthY = H * 0.71
            let upper = CGMutablePath()
            upper.move(to: CGPoint(x: cx - 19, y: mouthY))
            upper.addQuadCurve(to: CGPoint(x: cx - 3, y: mouthY - 5), control: CGPoint(x: cx - 11, y: mouthY - 6))
            upper.addLine(to: CGPoint(x: cx, y: mouthY - 3.5))
            upper.addLine(to: CGPoint(x: cx + 3, y: mouthY - 5))
            upper.addQuadCurve(to: CGPoint(x: cx + 19, y: mouthY), control: CGPoint(x: cx + 11, y: mouthY - 6))
            upper.closeSubpath()
            g.addPath(upper)
            lip.setFill()
            g.fillPath()
            let lower = CGMutablePath()
            lower.move(to: CGPoint(x: cx - 18, y: mouthY))
            lower.addQuadCurve(to: CGPoint(x: cx + 18, y: mouthY), control: CGPoint(x: cx, y: mouthY + 11))
            lower.closeSubpath()
            g.addPath(lower)
            lip.lighter(0.06).setFill()
            g.fillPath()
            g.setStrokeColor(lip.darker(0.4).cgColor)
            g.setLineWidth(1.3)
            g.move(to: CGPoint(x: cx - 19, y: mouthY))
            g.addQuadCurve(to: CGPoint(x: cx + 19, y: mouthY), control: CGPoint(x: cx, y: mouthY + 1.5))
            g.strokePath()
        }
        cache[key] = img
        return img
    }

    enum Pattern: String { case solid, plaid, stripes, dots, denim, knit, jacket }

    static func fabric(_ pattern: Pattern, _ hex: UInt32, accent: UInt32 = 0xF2F0EA) -> UIImage {
        let key = "fab|\(pattern.rawValue)|\(hex)|\(accent)"
        if let hit = cache[key] { return hit }
        let S: CGFloat = 256
        let base = UIColor(hex: hex)
        let img = UIGraphicsImageRenderer(size: CGSize(width: S, height: S)).image { ctx in
            let g = ctx.cgContext
            base.setFill()
            g.fill(CGRect(x: 0, y: 0, width: S, height: S))
            // A fine weave so nothing looks like plastic.
            var seed: UInt32 = 7
            func rnd() -> CGFloat { seed = seed &* 1664525 &+ 1013904223; return CGFloat(seed >> 8) / CGFloat(1 << 24) }
            for _ in 0..<900 {
                UIColor(white: rnd() > 0.5 ? 1 : 0, alpha: 0.035).setFill()
                g.fill(CGRect(x: rnd() * S, y: rnd() * S, width: 2, height: 1))
            }
            switch pattern {
            case .solid: break
            case .plaid:
                for i in 0..<8 {
                    let x = CGFloat(i) * 32
                    base.darker(0.35).withAlphaComponent(0.55).setFill()
                    g.fill(CGRect(x: x, y: 0, width: 12, height: S))
                    g.fill(CGRect(x: 0, y: x, width: S, height: 12))
                    UIColor(hex: accent).withAlphaComponent(0.5).setFill()
                    g.fill(CGRect(x: x + 20, y: 0, width: 2, height: S))
                    g.fill(CGRect(x: 0, y: x + 20, width: S, height: 2))
                }
            case .stripes:
                UIColor(hex: accent).withAlphaComponent(0.7).setFill()
                for i in 0..<10 { g.fill(CGRect(x: 0, y: CGFloat(i) * 25.6, width: S, height: 9)) }
            case .dots:
                UIColor(hex: accent).setFill()
                for row in 0..<6 {
                    for col in 0..<6 {
                        let x = CGFloat(col) * 42.6 + (row % 2 == 0 ? 0 : 21), y = CGFloat(row) * 42.6 + 21
                        g.fillEllipse(in: CGRect(x: x - 9, y: y - 9, width: 18, height: 18))
                    }
                }
            case .denim:
                for _ in 0..<1600 {
                    UIColor(white: rnd() > 0.4 ? 1 : 0, alpha: 0.08).setFill()
                    g.fill(CGRect(x: rnd() * S, y: rnd() * S, width: 1, height: 3 + rnd() * 5))
                }
                UIColor(hex: 0xC99A48).withAlphaComponent(0.6).setFill()
                g.fill(CGRect(x: S * 0.25, y: 0, width: 1.5, height: S))
                g.fill(CGRect(x: S * 0.75, y: 0, width: 1.5, height: S))
            case .knit:
                base.darker(0.2).withAlphaComponent(0.5).setFill()
                for i in 0..<32 { g.fill(CGRect(x: CGFloat(i) * 8, y: 0, width: 2, height: S)) }
            case .jacket:
                // An open front: the shirt underneath, and buttons/zip line.
                UIColor(hex: accent).setFill()
                g.fill(CGRect(x: S * 0.5 - 16, y: 0, width: 32, height: S))
                base.darker(0.3).setFill()
                g.fill(CGRect(x: S * 0.5 - 18, y: 0, width: 3, height: S))
                g.fill(CGRect(x: S * 0.5 + 15, y: 0, width: 3, height: S))
            }
        }
        cache[key] = img
        return img
    }

    /// Fine strands running the length of the hair (tiles cleanly both ways).
    static func hair(_ hex: UInt32) -> UIImage {
        let key = "hair2|\(hex)"
        if let hit = cache[key] { return hit }
        let S: CGFloat = 256
        let base = UIColor(hex: hex)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: S, height: S), format: format).image { ctx in
            let g = ctx.cgContext
            base.setFill()
            g.fill(CGRect(x: 0, y: 0, width: S, height: S))
            var seed: UInt32 = 3
            func rnd() -> CGFloat { seed = seed &* 1664525 &+ 1013904223; return CGFloat(seed >> 8) / CGFloat(1 << 24) }
            // Broad clumps, then individual strands.
            for _ in 0..<40 {
                (rnd() > 0.5 ? base.lighter(0.12) : base.darker(0.22)).withAlphaComponent(0.35).setFill()
                g.fill(CGRect(x: rnd() * S, y: 0, width: 3 + rnd() * 8, height: S))
            }
            for _ in 0..<520 {
                let light = rnd() > 0.55
                g.setStrokeColor((light ? base.lighter(0.3) : base.darker(0.4)).withAlphaComponent(0.22 + rnd() * 0.25).cgColor)
                g.setLineWidth(0.6 + rnd() * 0.9)
                let x = rnd() * S, wobble = (rnd() - 0.5) * 3
                g.move(to: CGPoint(x: x, y: 0))
                g.addCurve(to: CGPoint(x: x, y: S), control1: CGPoint(x: x + wobble, y: S * 0.33),
                           control2: CGPoint(x: x - wobble, y: S * 0.66))
                g.strokePath()
            }
        }
        cache[key] = img
        return img
    }
}

private extension UIColor {
    /// A little warmer and redder (lips from skin).
    func mixedRed() -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r * 1.08 + 0.05), green: g * 0.85, blue: b * 0.88, alpha: 1)
    }
}

// MARK: - Baked bodies

/// A body mesh made by tools/make_bodies.py (Scene/Bodies/body_b{build}_f{frame}_{hi|lo}.bin):
/// one smooth surface with bone weights, a UV atlas for painting clothes, and baked occlusion.
private final class BodyData {
    let joints: [SIMD3<Float>]
    let armOut: Float
    let legOut: Float
    let sources: [SCNGeometrySource]
    let weights: SCNGeometrySource
    let indices: SCNGeometrySource
    let element: SCNGeometryElement

    /// Joint positions if a body file is missing (keeps the rig usable).
    static let fallbackJoints: [SIMD3<Float>] = [
        SIMD3(0, 0.95, 0), SIMD3(0, 1.03, 0), SIMD3(0, 1.21, 0), SIMD3(0, 1.48, 0), SIMD3(0, 1.555, 0),
        SIMD3(-0.19, 1.44, 0), SIMD3(-0.19, 1.16, 0), SIMD3(0.19, 1.44, 0), SIMD3(0.19, 1.16, 0),
        SIMD3(-0.086, 0.91, 0), SIMD3(-0.086, 0.48, 0), SIMD3(0.086, 0.91, 0), SIMD3(0.086, 0.48, 0)
    ]

    @MainActor private static var cache: [String: BodyData] = [:]

    @MainActor static func load(build: Int, frame: Int, detail: Bool) -> BodyData? {
        let name = "body_b\(build)_f\(frame)_\(detail ? "hi" : "lo")"
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "bin")
                ?? Bundle.main.url(forResource: name, withExtension: "bin", subdirectory: "Bodies"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let body = BodyData(data) else { return nil }
        cache[name] = body
        return body
    }

    init?(_ d: Data) {
        guard d.count > 180, d.prefix(4) == Data("NGB1".utf8) else { return nil }
        func u32(_ at: Int) -> Int { Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self) }) }
        func f32(_ at: Int) -> Float { d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: Float.self) } }
        let n = u32(8), tris = u32(12)
        var off = 16
        var js: [SIMD3<Float>] = []
        for _ in 0..<13 {
            js.append(SIMD3(f32(off), f32(off + 4), f32(off + 8)))
            off += 12
        }
        joints = js
        armOut = f32(off); legOut = f32(off + 4)
        off += 8
        let posAt = off, norAt = posAt + n * 12, uvAt = norAt + n * 12, aoAt = uvAt + n * 8
        let idxAt = aoAt + n + (4 - n % 4) % 4, wAt = idxAt + n * 4, triAt = wAt + n * 4
        guard d.count >= triAt + tris * 6 else { return nil }
        let pos = d.subdata(in: posAt..<norAt), nor = d.subdata(in: norAt..<uvAt), uv = d.subdata(in: uvAt..<aoAt)
        // Occlusion as a vertex shade (multiplies the painted texture).
        var shade = [SIMD3<Float>](); shade.reserveCapacity(n)
        var idx = [SIMD4<UInt16>](); idx.reserveCapacity(n)
        var wts = [SIMD4<Float>](); wts.reserveCapacity(n)
        d.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            for v in 0..<n {
                let a = Float(b[aoAt + v]) / 255
                shade.append(SIMD3(a, a, a))
                let i = idxAt + v * 4, w = wAt + v * 4
                idx.append(SIMD4(UInt16(b[i]), UInt16(b[i + 1]), UInt16(b[i + 2]), UInt16(b[i + 3])))
                var wv = SIMD4(Float(b[w]), Float(b[w + 1]), Float(b[w + 2]), Float(b[w + 3]))
                wv /= max(1, wv.sum())
                wts.append(wv)
            }
        }
        let shadeData = shade.withUnsafeBufferPointer { Data(buffer: $0) }
        sources = [
            SCNGeometrySource(data: pos, semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: nor, semantic: .normal, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: uv, semantic: .texcoord, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8),
            SCNGeometrySource(data: shadeData, semantic: .color, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0,
                              dataStride: MemoryLayout<SIMD3<Float>>.stride)
        ]
        let wData = wts.withUnsafeBufferPointer { Data(buffer: $0) }
        let iData = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        weights = SCNGeometrySource(data: wData, semantic: .boneWeights, vectorCount: n, usesFloatComponents: true,
                                    componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0,
                                    dataStride: MemoryLayout<SIMD4<Float>>.stride)
        indices = SCNGeometrySource(data: iData, semantic: .boneIndices, vectorCount: n, usesFloatComponents: false,
                                    componentsPerVector: 4, bytesPerComponent: 2, dataOffset: 0,
                                    dataStride: MemoryLayout<SIMD4<UInt16>>.stride)
        element = SCNGeometryElement(data: d.subdata(in: triAt..<(triAt + tris * 6)), primitiveType: .triangles,
                                     primitiveCount: tris, bytesPerIndex: 2)
    }
}

/// A sculpted head (with its face masks) or a hairstyle, made by tools/make_heads.py. Meshes are
/// in metres relative to the head joint.
private final class HeadData {
    let sources: [SCNGeometrySource]
    let element: SCNGeometryElement
    /// Face masks, one plane each (see `Plane`), `maskSize`² bytes per plane.
    let masks: Data?
    let maskSize: Int

    enum Plane: Int { case shade, lips, brows, beard, stubble, white, iris, pupil, lash, glint, scalp }

    @MainActor private static var cache: [String: HeadData] = [:]

    @MainActor static func head(frame: Int) -> HeadData? { load("head_f\(frame)") }
    @MainActor static func hair(style: Int) -> HeadData? { load("hair_s\(style)") }

    @MainActor private static func load(_ name: String) -> HeadData? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "bin")
                ?? Bundle.main.url(forResource: name, withExtension: "bin", subdirectory: "Bodies"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let parsed = HeadData(data) else { return nil }
        cache[name] = parsed
        return parsed
    }

    init?(_ d: Data) {
        guard d.count > 16 else { return nil }
        let isHead = d.prefix(4) == Data("NGH1".utf8)
        guard isHead || d.prefix(4) == Data("NGR1".utf8) else { return nil }
        func u32(_ at: Int) -> Int { Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self) }) }
        let n = u32(8), tris = u32(12)
        maskSize = isHead ? u32(16) : 0
        let posAt = isHead ? 20 : 16
        let norAt = posAt + n * 12, uvAt = norAt + n * 12, triAt = uvAt + n * 8, end = triAt + tris * 6
        guard d.count >= end else { return nil }
        sources = [
            SCNGeometrySource(data: d.subdata(in: posAt..<norAt), semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: d.subdata(in: norAt..<uvAt), semantic: .normal, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: d.subdata(in: uvAt..<triAt), semantic: .texcoord, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        ]
        element = SCNGeometryElement(data: d.subdata(in: triAt..<end), primitiveType: .triangles,
                                     primitiveCount: tris, bytesPerIndex: 2)
        if isHead, d.count >= end + 4 {
            let len = u32(end)
            let comp = d.subdata(in: (end + 4)..<min(d.count, end + 4 + len)) as NSData
            masks = try? comp.decompressed(using: .zlib) as Data
        } else {
            masks = nil
        }
    }
}

extension HumanTextures {
    /// The face and scalp for a sculpted head: skin, then lips, beard or stubble, brows, eyes
    /// and lash lines from the head's masks, all shaded by its baked occlusion.
    static func faceAtlas(_ look: HumanLook, head: HeadData, size: Int) -> UIImage {
        let key = "face2|\(size)|\(look.skin)|\(look.hair)|\(look.hairStyle)|\(look.eyes)|\(look.lips ?? 0)|\(look.facialHair)|\(look.frame)|\(look.cap)"
        if let hit = cache[key] { return hit }
        let M = head.maskSize
        guard let masks = head.masks, M > 0, masks.count >= M * M * 11 else { return face(look) }
        let S = max(64, min(M, size))
        guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return face(look) }
        let rect = CGRect(x: 0, y: 0, width: S, height: S)
        ctx.interpolationQuality = .high
        func plane(_ p: HeadData.Plane) -> CGImage? {
            let bytes = masks.subdata(in: (p.rawValue * M * M)..<((p.rawValue + 1) * M * M))
            guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
            return CGImage(width: M, height: M, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: M,
                           space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                           provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
        func paint(_ p: HeadData.Plane, _ color: UIColor, _ alpha: CGFloat) {
            guard alpha > 0, let mask = plane(p) else { return }
            ctx.saveGState()
            ctx.clip(to: rect, mask: mask)
            ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
            ctx.fill(rect)
            ctx.restoreGState()
        }
        let skin = UIColor(hex: look.skin)
        let hair = UIColor(hex: look.hair)
        ctx.setFillColor(skin.cgColor)
        ctx.fill(rect)
        let scalpTint: CGFloat = look.cap ? 0.5 : (look.hairStyle == 8 ? 0 : (look.hairStyle == 1 ? 0.75 : 0.9))
        paint(.scalp, hair.darker(0.12), scalpTint)
        paint(.lips, look.lips.map { UIColor(hex: $0) } ?? skin.darker(0.12).mixedRed().mixedRed(), look.lips == nil ? 0.7 : 0.92)
        paint(.stubble, hair.darker(0.15), look.facialHair == 1 ? 0.34 : 0)
        paint(.beard, hair.darker(0.15), look.facialHair == 2 ? 0.94 : 0)
        if look.facialHair > 0, let mask = plane(.beard) {
            // Hair texture in the beard: short dark and light flecks.
            ctx.saveGState()
            ctx.clip(to: rect, mask: mask)
            var seed: UInt32 = 11
            func rnd() -> CGFloat { seed = seed &* 1664525 &+ 1013904223; return CGFloat(seed >> 8) / CGFloat(1 << 24) }
            let k = CGFloat(S) / 512
            for _ in 0..<(look.facialHair == 2 ? 2600 : 1400) {
                let light = rnd() > 0.6
                ctx.setFillColor((light ? hair.lighter(0.15) : hair.darker(0.45)).withAlphaComponent(look.facialHair == 2 ? 0.45 : 0.3).cgColor)
                ctx.fill(CGRect(x: rnd() * CGFloat(S), y: rnd() * CGFloat(S), width: 0.8 * k, height: (1.5 + rnd() * 2) * k))
            }
            ctx.restoreGState()
        }
        paint(.brows, hair.darker(0.28), 0.92)
        paint(.white, UIColor(red: 0.93, green: 0.91, blue: 0.88, alpha: 1), 1)
        paint(.iris, UIColor(hex: look.eyes), 1)
        paint(.pupil, UIColor(red: 0.04, green: 0.03, blue: 0.025, alpha: 1), 1)
        paint(.lash, UIColor(red: 0.08, green: 0.06, blue: 0.05, alpha: 1), 1)
        paint(.glint, .white, 0.9)
        if let shade = plane(.shade) {
            ctx.setBlendMode(.multiply)
            ctx.draw(shade, in: rect)
            ctx.setBlendMode(.normal)
        }
        guard let cg = ctx.makeImage() else { return face(look) }
        let img = UIImage(cgImage: cg)
        cache[key] = img
        return img
    }
}

// MARK: - Painting clothes onto the body

/// The body texture's layout (matches tools/make_bodies.py): each region is a cylinder around
/// that part, unrolled with the front in the middle (u = 0.5) and the character's right at
/// u = 0.75; height runs down the rect.
@MainActor
private struct BodyAtlas {
    enum Region { case torso, armL, armR, legL, legR }
    let size: CGFloat

    private func rect(_ r: Region) -> CGRect {
        let (x, y, w, h): (CGFloat, CGFloat, CGFloat, CGFloat) = switch r {
        case .torso: (0, 0, 0.5, 0.5)
        case .armL: (0.5, 0, 0.25, 0.5)
        case .armR: (0.75, 0, 0.25, 0.5)
        case .legL: (0, 0.5, 0.5, 0.5)
        case .legR: (0.5, 0.5, 0.5, 0.5)
        }
        let pad: CGFloat = 0.004
        return CGRect(x: (x + pad) * size, y: (y + pad) * size, width: (w - 2 * pad) * size, height: (h - 2 * pad) * size)
    }
    private func range(_ r: Region) -> (CGFloat, CGFloat) {
        switch r {
        case .torso: (1.70, 0.75)
        case .armL, .armR: (1.56, 0.62)
        case .legL, .legR: (1.02, -0.02)
        }
    }
    /// Pixel position of (u around, height in metres) in a region.
    func point(_ r: Region, u: CGFloat, y: CGFloat) -> CGPoint {
        let rc = rect(r), (top, bot) = range(r)
        return CGPoint(x: rc.minX + rc.width * u, y: rc.minY + rc.height * (top - y) / (top - bot))
    }
    /// The band between two heights (and optionally part of the way around), with a little bleed.
    func band(_ r: Region, from yTop: CGFloat, to yBot: CGFloat, u0: CGFloat = 0, u1: CGFloat = 1) -> CGRect {
        let a = point(r, u: u0, y: yTop), b = point(r, u: u1, y: yBot)
        let rc = rect(r)
        let x0 = u0 <= 0 ? rc.minX - 3 : a.x, x1 = u1 >= 1 ? rc.maxX + 3 : b.x
        return CGRect(x: x0, y: a.y, width: x1 - x0, height: b.y - a.y)
    }
    /// A filled shape whose top edge follows `edge(u)` (a height per u) down to `bottom`.
    func underCurve(_ r: Region, bottom: CGFloat, u0: CGFloat = 0, u1: CGFloat = 1, edge: (CGFloat) -> CGFloat) -> CGPath {
        let p = CGMutablePath()
        let steps = 48
        p.move(to: point(r, u: u0, y: bottom))
        for k in 0...steps {
            let u = u0 + (u1 - u0) * CGFloat(k) / CGFloat(steps)
            p.addLine(to: point(r, u: u, y: edge(u)))
        }
        p.addLine(to: point(r, u: u1, y: bottom))
        p.closeSubpath()
        return p
    }
}

extension HumanTextures {
    /// Skin, clothes and shoes for the whole body, painted into the atlas.
    static func body(_ look: HumanLook, size: Int) -> UIImage {
        var key = look
        key.height = 1
        key.hair = 0; key.hairStyle = 0; key.eyes = 0; key.lips = nil; key.facialHair = 0; key.cap = false
        let cacheKey = "body|\(size)|\(key.hashValue)"
        if let hit = cache[cacheKey] { return hit }
        let S = CGFloat(size)
        let atlas = BodyAtlas(size: S)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: S, height: S), format: format).image { ctx in
            let g = ctx.cgContext
            paintBody(g, atlas, look, S)
        }
        cache[cacheKey] = img
        return img
    }

    private static func paintBody(_ g: CGContext, _ a: BodyAtlas, _ look: HumanLook, _ S: CGFloat) {
        typealias R = BodyAtlas.Region
        let skin = UIColor(hex: look.skin)
        skin.setFill()
        g.fill(CGRect(x: 0, y: 0, width: S, height: S))
        let px = S / 1024
        let arms: [R] = [.armL, .armR], legs: [R] = [.legL, .legR]
        // Skin: a little warmth at knees, elbows and knuckles.
        for r in legs {
            soft(g, a.point(r, u: 0.5, y: 0.47), 26 * px, UIColor(hex: 0xC0605A).withAlphaComponent(0.12))
        }
        for r in arms {
            soft(g, a.point(r, u: 0.0, y: 1.16), 20 * px, skin.darker(0.12).withAlphaComponent(0.4))
            soft(g, a.point(r, u: 1.0, y: 1.16), 20 * px, skin.darker(0.12).withAlphaComponent(0.4))
        }

        let o = look.officer ? -1 : look.outfit
        let topHex: UInt32 = look.officer ? 0x23417E : (o == 6 ? 0xF1EEE8 : look.top)
        let top = UIColor(hex: topHex)
        let skirt = o == 6, jumpsuit = o == 5
        let bottomHex: UInt32 = look.officer ? 0x141C30 : jumpsuit ? topHex : o == 7 ? 0xC9B48A : look.legs
        let denim = !look.officer && !skirt && !jumpsuit && o != 7 && (bottomHex == 0x2E4A78 || bottomHex == 0x1E2A44)

        func fillPattern(_ rect: CGRect, _ image: UIImage, _ scale: CGFloat = 1) {
            g.saveGState()
            g.clip(to: rect)
            let tile = image.size.width * scale * px
            var y = floor(rect.minY / tile) * tile
            while y < rect.maxY {
                var x = floor(rect.minX / tile) * tile
                while x < rect.maxX {
                    image.draw(in: CGRect(x: x, y: y, width: tile, height: tile))
                    x += tile
                }
                y += tile
            }
            g.restoreGState()
        }
        func fillPath(_ path: CGPath, _ image: UIImage, _ scale: CGFloat = 1) {
            g.saveGState()
            g.addPath(path)
            g.clip()
            fillPattern(path.boundingBox, image, scale)
            g.restoreGState()
        }
        func line(_ r: R, _ pts: [(CGFloat, CGFloat)], _ c: UIColor, _ w: CGFloat) {
            g.setStrokeColor(c.cgColor)
            g.setLineWidth(w * px)
            g.setLineCap(.round)
            g.move(to: a.point(r, u: pts[0].0, y: pts[0].1))
            for p in pts.dropFirst() { g.addLine(to: a.point(r, u: p.0, y: p.1)) }
            g.strokePath()
        }
        func ring(_ r: R, _ y: CGFloat, _ c: UIColor, _ h: CGFloat) {
            c.setFill()
            g.fill(a.band(r, from: y + h / 2, to: y - h / 2))
        }

        // ---- Bottoms: legs and the hips ----
        let bottomPattern: Pattern = denim ? .denim : o == 7 ? .solid : .solid
        let bottomImg = fabric(bottomPattern, bottomHex)
        let legHem: CGFloat = skirt ? 1.2 : look.shorts ? 0.6 : 0.1
        if !skirt {
            for r in legs { fillPattern(a.band(r, from: 1.03, to: legHem), bottomImg) }
            fillPattern(a.band(.torso, from: 1.0, to: 0.74), bottomImg)
            let seam = UIColor(hex: bottomHex).darker(0.3)
            if denim {
                let stitch = UIColor(hex: 0xC99A48).withAlphaComponent(0.8)
                // Fly, front pockets, back pockets, side seams.
                line(.torso, [(0.5, 0.99), (0.5, 0.86), (0.48, 0.84)], stitch, 2.2)
                for s: CGFloat in [-1, 1] {
                    line(.torso, [(0.5 + s * 0.17, 0.995), (0.5 + s * 0.2, 0.93), (0.5 + s * 0.26, 0.92)], stitch, 2)
                    let pc = 0.5 + s * 0.42
                    let pocket = CGMutablePath()
                    pocket.move(to: a.point(.torso, u: pc - 0.05, y: 0.965))
                    pocket.addLine(to: a.point(.torso, u: pc + 0.05, y: 0.965))
                    pocket.addLine(to: a.point(.torso, u: pc + 0.045, y: 0.88))
                    pocket.addLine(to: a.point(.torso, u: pc, y: 0.86))
                    pocket.addLine(to: a.point(.torso, u: pc - 0.045, y: 0.88))
                    pocket.closeSubpath()
                    g.addPath(pocket)
                    g.setStrokeColor(stitch.cgColor)
                    g.setLineWidth(2 * px)
                    g.strokePath()
                }
                for r in legs {
                    line(r, [(0.25, 1.02), (0.25, legHem)], seam.withAlphaComponent(0.5), 2.5)
                    line(r, [(0.75, 1.02), (0.75, legHem)], seam.withAlphaComponent(0.5), 2.5)
                }
            } else {
                line(.torso, [(0.5, 0.99), (0.5, 0.87)], seam.withAlphaComponent(0.6), 2)
                for r in legs { line(r, [(0.5, 0.98), (0.5, max(legHem, 0.2))], seam.withAlphaComponent(0.25), 2) }
            }
            // Hems: a rolled cuff on jeans, a clean hem otherwise.
            for r in legs { ring(r, legHem + 0.012, UIColor(hex: bottomHex).darker(denim ? 0.15 : 0.25), 0.02) }
            // Waistband and belt.
            ring(.torso, 0.99, look.officer || denim ? UIColor(hex: 0x1A1612) : UIColor(hex: bottomHex).darker(0.2), 0.03)
            if look.officer || denim {
                UIColor(hex: look.officer ? 0xD8B04A : 0xB8B2A6).setFill()
                let c = a.point(.torso, u: 0.5, y: 0.99)
                g.fill(CGRect(x: c.x - 7 * px, y: c.y - 6 * px, width: 14 * px, height: 12 * px))
            }
        } else {
            // Under the skirt: skirt colour at the hips so nothing shows through gaps.
            UIColor(hex: 0x1B2A5E).setFill()
            g.fill(a.band(.torso, from: 1.06, to: 0.74))
        }

        // ---- Top ----
        let hem: CGFloat
        switch o {
        case 0, 2: hem = 0.87        // jacket, hoodie
        case 7: hem = 0.86           // cardigan
        case 5: hem = 0.74           // jumpsuit (all one piece)
        case 6: hem = 1.03           // blouse tucked in
        default: hem = 0.9
        }
        let sleeveEnd: CGFloat? = switch o {
        case 3, 5: nil                          // tank, jumpsuit
        case 1, 4: 1.27                         // T-shirt, plaid shirt (short)
        case 6: 1.31                            // blouse puff sleeve
        default: 0.95                           // jacket, hoodie, cardigan, officer
        }
        let pattern: Pattern = o == 4 ? .plaid : o == 7 ? .knit : .solid
        let topImg = fabric(pattern, topHex, accent: 0xF2F0EA)
        let neckFront: CGFloat = o == 3 ? 1.38 : o == 5 ? 1.43 : o == 6 ? 1.43 : 1.465
        let neckBack: CGFloat = o == 3 ? 1.45 : o == 5 ? 1.49 : 1.515
        let sideLift: CGFloat = (o == 3) ? 0 : 0.03
        let neckline: (CGFloat) -> CGFloat = { u in
            let c = cos(2 * .pi * u)      // 1 at the back, −1 at the front
            let s = sin(2 * .pi * u)      // ±1 at the sides, where the collar rides up the neck
            return (neckFront + neckBack) / 2 + (neckBack - neckFront) / 2 * c + sideLift * s * s
        }
        if o == 3 || o == 5 {
            // Sleeveless: the body up to the armholes, straps over the shoulders.
            fillPath(a.underCurve(.torso, bottom: hem, edge: { u in
                let side = min(abs(u - 0.25), abs(u - 0.75))
                let arm: CGFloat = side < 0.09 ? 1.33 : (o == 5 ? 1.5 : 1.4)
                return min(arm, neckline(u))
            }), topImg)
            if o == 3 {
                for uc: CGFloat in [0.32, 0.68, 0.18, 0.82] {
                    fillPattern(a.band(.torso, from: 1.5, to: 1.36, u0: uc - 0.035, u1: uc + 0.035), topImg)
                }
            }
        } else {
            fillPath(a.underCurve(.torso, bottom: hem, edge: neckline), topImg)
            // Collar/neck rib.
            g.setStrokeColor(top.darker(0.18).cgColor)
            g.setLineWidth(5 * px)
            g.addPath({ let p = CGMutablePath()
                for k in 0...48 {
                    let u = CGFloat(k) / 48
                    let pt = a.point(.torso, u: u, y: neckline(u) - 0.006)
                    if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                return p }())
            g.strokePath()
        }
        if let sleeveEnd {
            for r in arms {
                fillPattern(a.band(r, from: 1.6, to: sleeveEnd), topImg)
                ring(r, sleeveEnd + 0.01, top.darker(0.2), sleeveEnd < 1 ? 0.035 : 0.018)
            }
        }
        // The top hangs over the hips, which belong to the legs' part of the texture up there.
        if hem < 1.02 && o != 5 {
            for r in legs { fillPattern(a.band(r, from: 1.03, to: hem), topImg) }
        }
        // Hem line.
        if o != 5 {
            ring(.torso, hem + 0.008, top.darker(0.22), 0.016)
            if hem < 1.02 { for r in legs { ring(r, hem + 0.008, top.darker(0.22), 0.016) } }
        }

        switch o {
        case 0:
            // Open jacket: the shirt underneath down the front, lapels, zip tape.
            let shirt = UIColor(hex: 0xEDEAE2)
            shirt.setFill()
            g.fill(a.band(.torso, from: 1.46, to: hem - 0.01, u0: 0.455, u1: 0.545))
            line(.torso, [(0.45, 1.47), (0.455, 1.3), (0.455, hem)], top.darker(0.35), 3)
            line(.torso, [(0.55, 1.47), (0.545, 1.3), (0.545, hem)], top.darker(0.35), 3)
            line(.torso, [(0.45, 1.47), (0.42, 1.36)], top.darker(0.3), 2.5)
            line(.torso, [(0.55, 1.47), (0.58, 1.36)], top.darker(0.3), 2.5)
            for s: CGFloat in [-1, 1] { line(.torso, [(0.5 + s * 0.14, 1.04), (0.5 + s * 0.2, 1.04)], top.darker(0.3), 2.5) }
        case 2:
            // Hoodie: kangaroo pocket, drawstrings, ribbed hem and cuffs.
            let pocket = CGMutablePath()
            pocket.move(to: a.point(.torso, u: 0.38, y: 0.9))
            pocket.addLine(to: a.point(.torso, u: 0.62, y: 0.9))
            pocket.addLine(to: a.point(.torso, u: 0.585, y: 1.03))
            pocket.addLine(to: a.point(.torso, u: 0.415, y: 1.03))
            pocket.closeSubpath()
            g.addPath(pocket)
            g.setStrokeColor(top.darker(0.3).cgColor)
            g.setLineWidth(3 * px)
            g.strokePath()
            line(.torso, [(0.475, 1.46), (0.47, 1.33)], UIColor(hex: 0xEDEAE2), 3)
            line(.torso, [(0.525, 1.46), (0.53, 1.33)], UIColor(hex: 0xEDEAE2), 3)
            ring(.torso, hem + 0.02, top.darker(0.15), 0.035)
        case 4:
            // Shirt placket, buttons, collar points, a breast pocket.
            line(.torso, [(0.5, 1.46), (0.5, hem)], UIColor(hex: topHex).darker(0.3), 3)
            for k in 0..<5 {
                let p = a.point(.torso, u: 0.505, y: 1.42 - CGFloat(k) * 0.09)
                UIColor(hex: 0xF2F0EA).setFill()
                g.fillEllipse(in: CGRect(x: p.x - 3 * px, y: p.y - 3 * px, width: 6 * px, height: 6 * px))
            }
            line(.torso, [(0.46, 1.47), (0.44, 1.42)], UIColor(hex: topHex).darker(0.35), 3)
            line(.torso, [(0.54, 1.47), (0.56, 1.42)], UIColor(hex: topHex).darker(0.35), 3)
        case 5:
            // Jumpsuit belt and a front zip.
            ring(.torso, 1.07, UIColor(hex: topHex).darker(0.35), 0.025)
            line(.torso, [(0.5, neckFront), (0.5, 1.08)], UIColor(hex: topHex).darker(0.3), 2)
            for r in legs { fillPattern(a.band(r, from: 1.03, to: 0.1), topImg) }
            fillPattern(a.band(.torso, from: 1.07, to: 0.74), topImg)
        case 6:
            // Blouse buttons and a tuck line.
            for k in 0..<4 {
                let p = a.point(.torso, u: 0.5, y: 1.38 - CGFloat(k) * 0.08)
                UIColor(hex: 0xC9C2B6).setFill()
                g.fillEllipse(in: CGRect(x: p.x - 3 * px, y: p.y - 3 * px, width: 6 * px, height: 6 * px))
            }
        case 7:
            // Open cardigan over a cream camisole; buttons on one edge.
            let cami = UIColor(hex: 0xEDE6D8)
            cami.setFill()
            g.fill(a.band(.torso, from: 1.4, to: 1.02, u0: 0.45, u1: 0.55))
            fillPath(a.underCurve(.torso, bottom: 1.4, u0: 0.43, u1: 0.57, edge: { u in 1.47 - 0.07 * (1 - abs(u - 0.5) / 0.07) }), fabric(.solid, 0xEDE6D8))
            line(.torso, [(0.44, 1.47), (0.45, 1.02), (0.47, hem)], UIColor(hex: topHex).darker(0.3), 3)
            line(.torso, [(0.56, 1.47), (0.55, 1.02), (0.53, hem)], UIColor(hex: topHex).darker(0.3), 3)
            for k in 0..<4 {
                let p = a.point(.torso, u: 0.555, y: 1.2 - CGFloat(k) * 0.08)
                UIColor(hex: 0x6B4A2E).setFill()
                g.fillEllipse(in: CGRect(x: p.x - 3.5 * px, y: p.y - 3.5 * px, width: 7 * px, height: 7 * px))
            }
        default:
            if look.officer {
                // Uniform shirt: placket, pocket flaps, shoulder epaulettes, tie.
                line(.torso, [(0.5, 1.46), (0.5, hem)], top.darker(0.3), 2.5)
                for s: CGFloat in [-1, 1] {
                    UIColor(hex: topHex).darker(0.25).setFill()
                    g.fill(a.band(.torso, from: 1.36, to: 1.33, u0: 0.5 + s * 0.06 - 0.04, u1: 0.5 + s * 0.06 + 0.04))
                }
                UIColor(hex: 0x0E1424).setFill()
                g.fill(a.band(.torso, from: 1.46, to: 1.17, u0: 0.49, u1: 0.51))
            }
        }

        // ---- Shoes ----
        let boots = o == 7 || look.officer
        let flats = o == 5 || o == 6
        let shoeHex: UInt32 = o == 7 ? 0x6B4A2E : look.shoes
        let shoe = UIColor(hex: shoeHex)
        let shoeTop: CGFloat = boots ? 0.25 : flats ? 0.062 : 0.105
        for r in legs {
            shoe.setFill()
            g.fill(a.band(r, from: shoeTop, to: -0.05))
            // Sole.
            UIColor(hex: flats || boots ? 0x15161A : 0xF2F0EA).setFill()
            g.fill(a.band(r, from: 0.024, to: -0.05))
            if !flats && !boots {
                // Sneakers: collar, laces, a side swoosh-free stripe of our own.
                UIColor(hex: shoeHex).darker(0.25).setFill()
                g.fill(a.band(r, from: shoeTop, to: shoeTop - 0.012))
                let lace = UIColor(hex: shoeHex == 0xF2F2F2 ? 0xD9D6CF : 0xF2F0EA)
                for k in 0..<3 {
                    let y = 0.092 - CGFloat(k) * 0.012
                    line(r, [(0.47, y), (0.53, y)], lace, 2.5)
                }
                for side: CGFloat in [0.27, 0.73] {
                    line(r, [(side - 0.05, 0.045), (side + 0.05, 0.06)], UIColor(hex: 0xE2564A), 4)
                }
            } else if boots {
                UIColor(hex: shoeHex).lighter(0.08).setFill()
                g.fill(a.band(r, from: shoeTop, to: shoeTop - 0.02))
            }
        }
    }

    private static func soft(_ g: CGContext, _ c: CGPoint, _ r: CGFloat, _ color: UIColor) {
        let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        g.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }
}

// MARK: - The rig

/// A person with one continuous, bending body: a skinned mesh for the skin (torso, neck, arms,
/// legs), skinned clothes over it, a shaped head with a painted face, hair meshes, hands and shoes.
/// Joints are animated each frame by `pose(...)`. Built in metres; scaled to the street
/// (1 m = 0.4 units).
@MainActor
final class HumanRig {
    let node = SCNNode()
    private let body = SCNNode()
    private let hips = SCNNode()
    private let spine = SCNNode()
    private let chest = SCNNode()
    private let neck = SCNNode()
    private let head = SCNNode()
    private let shoulderL = SCNNode(), shoulderR = SCNNode()
    private let elbowL = SCNNode(), elbowR = SCNNode()
    private let handR = SCNNode()
    private let thighL = SCNNode(), thighR = SCNNode()
    private let kneeL = SCNNode(), kneeR = SCNNode()
    private var gun: SCNNode?
    private var gunWeapon: WeaponID?
    let look: HumanLook

    static let metre: Float = 0.4

    // Bone indices in `bones`.
    private enum B: Int { case hips, spine, chest, neck, head, shoulderL, elbowL, shoulderR, elbowR, thighL, kneeL, thighR, kneeR }
    private var bones: [SCNNode] { [hips, spine, chest, neck, head, shoulderL, elbowL, shoulderR, elbowR, thighL, kneeL, thighR, kneeR] }

    private static func material(_ contents: Any, rough: CGFloat, sheen: CGFloat = 0, doubleSided: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = contents
        m.roughness.contents = rough
        m.metalness.contents = 0.0
        m.isDoubleSided = doubleSided
        if sheen > 0 {
            m.emission.contents = contents
            m.emission.intensity = sheen
        }
        return m
    }

    /// - Parameter detail: the full mesh and a 1024 px body texture (the player, officers, the
    ///   Style screen); `false` for the crowd (a lighter mesh and 512 px).
    init(look: HumanLook, detail: Bool = true) {
        self.look = look
        let build = max(0, min(3, look.build))
        let curvy = look.frame == 1
        let data = BodyData.load(build: build, frame: curvy ? 1 : 0, detail: detail)

        // Skeleton (same joints the animation drives), placed where the baked body expects them.
        let j = data?.joints ?? BodyData.fallbackJoints
        func at(_ b: B) -> SIMD3<Float> { j[b.rawValue] }
        func place(_ n: SCNNode, _ b: B, from parent: SIMD3<Float>) {
            let d = at(b) - parent
            n.position = SCNVector3(d.x, d.y, d.z)
        }
        node.addChildNode(body)
        place(hips, .hips, from: .zero); body.addChildNode(hips)
        place(spine, .spine, from: at(.hips)); hips.addChildNode(spine)
        place(chest, .chest, from: at(.spine)); spine.addChildNode(chest)
        place(neck, .neck, from: at(.chest)); chest.addChildNode(neck)
        place(head, .head, from: at(.neck)); neck.addChildNode(head)
        place(shoulderL, .shoulderL, from: at(.chest)); chest.addChildNode(shoulderL)
        place(shoulderR, .shoulderR, from: at(.chest)); chest.addChildNode(shoulderR)
        place(elbowL, .elbowL, from: at(.shoulderL)); shoulderL.addChildNode(elbowL)
        place(elbowR, .elbowR, from: at(.shoulderR)); shoulderR.addChildNode(elbowR)
        handR.position = SCNVector3(0, -0.27, 0); elbowR.addChildNode(handR)
        place(thighL, .thighL, from: at(.hips)); hips.addChildNode(thighL)
        place(thighR, .thighR, from: at(.hips)); hips.addChildNode(thighR)
        place(kneeL, .kneeL, from: at(.thighL)); thighL.addChildNode(kneeL)
        place(kneeR, .kneeR, from: at(.thighR)); thighR.addChildNode(kneeR)

        let skinTone = UIColor(hex: look.skin)
        let skinMat = Self.material(skinTone, rough: 0.55, sheen: 0.04)
        let o = look.officer ? 0 : look.outfit

        // ---- Body: one smooth skinned surface; clothes, skin and shoes are painted on ----
        if let data {
            let painted = HumanTextures.body(look, size: detail ? 1024 : 512)
            let mat = Self.material(painted, rough: 0.72, sheen: 0.03, doubleSided: false)
            let geometry = SCNGeometry(sources: data.sources, elements: [data.element])
            geometry.firstMaterial = mat
            // Bind in the pose the mesh was built in (arms out, legs a little apart).
            shoulderL.eulerAngles.z = -data.armOut
            shoulderR.eulerAngles.z = data.armOut
            thighL.eulerAngles.z = -data.legOut
            thighR.eulerAngles.z = data.legOut
            attachSkinned(geometry, weights: data.weights, indices: data.indices)
            for n in [shoulderL, shoulderR, thighL, thighR] { n.eulerAngles = SCNVector3Zero }
        } else {
            let stand = SCNNode(geometry: SCNCapsule(capRadius: 0.17, height: 1.6))
            stand.geometry!.firstMaterial = skinMat
            stand.position = SCNVector3(0, -0.15, 0)
            hips.addChildNode(stand)
        }

        // Skirt: an A-line from the waist, swaying with the hips and each thigh.
        if o == 6 && !look.officer {
            let hipW = Float(curvy ? 1.12 : 0.96) * ([0.9, 1.0, 1.08, 1.18] as [Float])[build]
            let skirtMat = Self.material(HumanTextures.fabric(.dots, 0x1B2A5E), rough: 0.9)
            skirtMat.diffuse.wrapS = .repeat
            skirtMat.diffuse.wrapT = .repeat
            skirtMat.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 2, 1)
            var skirt = MeshBuilder()
            let rings: [Ring] = [(1.07, 0.15, 0.108), (1.0, 0.178, 0.122), (0.9, 0.205, 0.15), (0.74, 0.235, 0.172),
                                 (0.62, 0.25, 0.18)].map {
                Ring(center: SIMD3(0, $0.0, 0.01), rx: $0.1 * hipW, rz: $0.2, front: 0, bones: [(B.hips.rawValue, 1)])
            }
            skirt.tube(rings, segments: 28, vertexBones: { p, _ in
                let down = max(0, min(1, (0.98 - p.y) / 0.34))
                let leg: B = p.x < 0 ? .thighL : .thighR
                return [(B.hips.rawValue, 1 - down * 0.6), (leg.rawValue, down * 0.6)]
            })
            let (sw, si) = skirt.skinSources()
            attachSkinned(skirt.geometry(skirtMat), weights: sw, indices: si)
        }

        // ---- Head, face, hair ----
        if let headData = HeadData.head(frame: curvy ? 1 : 0) {
            let faceImage = HumanTextures.faceAtlas(look, head: headData, size: detail ? 512 : 256)
            let faceMat = Self.material(faceImage, rough: 0.5, sheen: 0.03, doubleSided: false)
            let geometry = SCNGeometry(sources: headData.sources, elements: [headData.element])
            geometry.firstMaterial = faceMat
            head.addChildNode(SCNNode(geometry: geometry))
            // A touch larger than life, as stylised people are.
            head.scale = SCNVector3(1.1, 1.1, 1.1)
        } else {
            let ball = SCNNode(geometry: SCNSphere(radius: 0.11))
            ball.geometry!.firstMaterial = skinMat
            ball.position = SCNVector3(0, 0.11, 0)
            head.addChildNode(ball)
        }
        if look.cap {
            addCap()
        } else {
            addHair()
        }

        if o == 2 && !look.officer {
            // Hood bunched behind the neck.
            let hood = SCNNode(geometry: SCNSphere(radius: 0.12))
            hood.geometry!.firstMaterial = Self.material(UIColor(hex: look.top), rough: 0.85)
            hood.scale = SCNVector3(1.12, 0.5, 0.7)
            hood.position = SCNVector3(0, at(.neck).y - at(.chest).y + 0.01, 0.085)
            chest.addChildNode(hood)
        }
        if look.officer {
            let badge = SCNNode(geometry: SCNBox(width: 0.04, height: 0.05, length: 0.01, chamferRadius: 0.005))
            badge.geometry!.firstMaterial = Self.material(UIColor(hex: 0xE2B13C), rough: 0.25)
            badge.position = SCNVector3(-0.07, 0.15, -0.126)
            chest.addChildNode(badge)
        }

        let s = Self.metre * look.height
        node.scale = SCNVector3(s, s, s)
    }

    /// Adds a skinned mesh bound to the rig's joints in their current pose.
    private func attachSkinned(_ geometry: SCNGeometry, weights w: SCNGeometrySource, indices i: SCNGeometrySource) {
        let inverseBinds = bones.map { bone -> NSValue in
            NSValue(scnMatrix4: SCNMatrix4Invert(bone.convertTransform(SCNMatrix4Identity, to: node)))
        }
        let skinner = SCNSkinner(baseGeometry: geometry, bones: bones, boneInverseBindTransforms: inverseBinds,
                                 boneWeights: w, boneIndices: i)
        let n = SCNNode(geometry: geometry)
        n.skinner = skinner
        skinner.skeleton = node
        node.addChildNode(n)
    }

    /// A peaked cap shaped to the skull.
    private func addCap() {
        let cloth = Self.material(UIColor(hex: look.officer ? 0x14213D : 0x23252C), rough: 0.6)
        let band = SCNNode(geometry: SCNCylinder(radius: 1, height: 1))
        band.geometry!.firstMaterial = cloth
        band.scale = SCNVector3(0.087, 0.05, 0.103)
        band.position = SCNVector3(0, 0.178, 0.012)
        head.addChildNode(band)
        let crown = SCNNode(geometry: SCNSphere(radius: 1))
        crown.geometry!.firstMaterial = cloth
        crown.scale = SCNVector3(0.087, 0.045, 0.103)
        crown.position = SCNVector3(0, 0.2, 0.012)
        head.addChildNode(crown)
        if look.officer {
            let badge = SCNNode(geometry: SCNBox(width: 0.026, height: 0.026, length: 0.006, chamferRadius: 0.004))
            badge.geometry!.firstMaterial = Self.material(UIColor(hex: 0xE2B13C), rough: 0.25)
            badge.position = SCNVector3(0, 0.185, -0.092)
            head.addChildNode(badge)
        }
        let brim = SCNNode(geometry: SCNBox(width: 0.15, height: 0.01, length: 0.075, chamferRadius: 0.005))
        brim.geometry!.firstMaterial = Self.material(UIColor(hex: 0x0B0C0F), rough: 0.4)
        brim.position = SCNVector3(0, 0.156, -0.105)
        brim.eulerAngles.x = 0.12
        head.addChildNode(brim)
    }

    /// The hairstyle's mesh (tools/make_heads.py) with a strand texture in the hair colour.
    private func addHair() {
        let style = look.hairStyle
        guard style != 8, let data = HeadData.hair(style: style) else { return }   // 8 = bald
        let mat = Self.material(HumanTextures.hair(look.hair), rough: 0.42, doubleSided: false)
        mat.diffuse.wrapS = .repeat
        mat.diffuse.wrapT = .repeat
        mat.diffuse.contentsTransform = SCNMatrix4MakeScale(5, 1.5, 1)
        let geometry = SCNGeometry(sources: data.sources, elements: [data.element])
        geometry.firstMaterial = mat
        head.addChildNode(SCNNode(geometry: geometry))
    }
    // MARK: Gun in hand

    func hold(_ weapon: WeaponID?) {
        guard weapon != gunWeapon else { return }
        gunWeapon = weapon
        gun?.removeFromParentNode()
        gun = nil
        guard let weapon else { return }
        let length: CGFloat = switch weapon {
        case .pistol: 0.22
        case .smg: 0.4
        case .shotgun: 0.85
        case .rifle: 0.9
        case .bat: 0.8
        }
        // Along the hand's long axis (−Y), so the barrel follows the arm. Long guns reach back
        // towards the shoulder.
        let g = SCNNode(geometry: SCNBox(width: 0.045, height: length, length: 0.09, chamferRadius: 0.012))
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = weapon == .bat ? UIColor(hex: 0xB9834A) : UIColor(hex: 0x23262C)
        m.metalness.contents = weapon == .bat ? 0.0 : 0.7
        m.roughness.contents = 0.35
        g.geometry!.firstMaterial = m
        let back: Float = weapon == .shotgun || weapon == .rifle ? 0.24 : weapon == .smg ? 0.1 : 0.02
        g.position = SCNVector3(0, -Float(length) / 2 + back, -0.02)
        handR.addChildNode(g)
        gun = g
    }

    // MARK: Animation

    /// Sets the pose for this frame.
    /// - Parameters:
    ///   - time: seconds (shared clock); `phase` offsets people so they don't march in step.
    ///   - speed: 0 standing, 1 walking, 2 running.
    ///   - punch: seconds since a punch and which one, if within the last 0.35 s.
    ///   - aiming: a gun held up.
    func pose(time: Double, phase: Double, speed: Double, punch: (Double, Strike)?, aiming: Bool, down: Bool) {
        if down {
            body.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            body.position = SCNVector3(0, 0.12, 0.85)
            reset()
            return
        }
        body.eulerAngles = SCNVector3Zero
        let running = speed > 1.5
        let moving = speed > 0.1
        let freq = running ? 11.0 : 7.0
        let p = time * freq + phase
        let s = Float(sin(p))
        let swing: Float = moving ? (running ? 0.8 : 0.45) : 0
        // Legs: thigh swings forward and back; the knee folds on the way through.
        thighL.eulerAngles.x = swing * s
        thighR.eulerAngles.x = -swing * s
        let foldL = Float(max(0, sin(p - 1.3))), foldR = Float(max(0, sin(p + .pi - 1.3)))
        kneeL.eulerAngles.x = moving ? -(0.12 + foldL * (running ? 1.3 : 0.75)) : -0.04
        kneeR.eulerAngles.x = moving ? -(0.12 + foldR * (running ? 1.3 : 0.75)) : -0.04
        // Body bob, lean and a little counter-twist.
        let bob: Float = moving ? abs(s) * (running ? 0.05 : 0.025) : Float(sin(time * 1.6 + phase)) * 0.004
        body.position = SCNVector3(0, bob, 0)
        spine.eulerAngles.x = running ? -0.18 : (moving ? -0.04 : 0)
        chest.eulerAngles.y = moving ? s * 0.12 : 0
        hips.eulerAngles.y = moving ? -s * 0.08 : 0
        // Breathing.
        chest.scale = SCNVector3(1, 1 + Float(sin(time * 1.8 + phase)) * 0.012, 1)
        head.eulerAngles = SCNVector3(moving ? 0.04 : Float(sin(time * 0.7 + phase)) * 0.04,
                                      moving ? -s * 0.06 : Float(sin(time * 0.4 + phase)) * 0.15, 0)

        // Arms swing opposite the legs, elbows bent more when running.
        let armSwing: Float = moving ? (running ? 0.9 : 0.4) : 0
        shoulderL.eulerAngles = SCNVector3(-armSwing * s, 0, -0.09)
        shoulderR.eulerAngles = SCNVector3(armSwing * s, 0, 0.09)
        elbowL.eulerAngles = SCNVector3((running ? 1.3 : 0.25) + max(0, -s) * 0.3, 0, 0)
        elbowR.eulerAngles = SCNVector3((running ? 1.3 : 0.25) + max(0, s) * 0.3, 0, 0)

        if aiming {
            // Two-handed hold, gun up at eye line.
            let pistol = gunWeapon == .pistol
            shoulderR.eulerAngles = SCNVector3(1.45, pistol ? 0.15 : 0.05, -0.05)
            elbowR.eulerAngles = SCNVector3(pistol ? 0.08 : 0.25, 0, 0)
            shoulderL.eulerAngles = SCNVector3(pistol ? 1.35 : 1.15, pistol ? -0.55 : -0.7, 0.05)
            elbowL.eulerAngles = SCNVector3(pistol ? 0.35 : 0.9, 0, 0)
            chest.eulerAngles.y = pistol ? 0 : 0.25
        }

        if let (age, strike) = punch, age < 0.35 {
            let k = Float(sin(min(1, age / 0.3) * .pi))
            // Fists up, then the strike.
            switch strike {
            case .jab:
                shoulderR.eulerAngles = SCNVector3(0.6 + 0.95 * k, 0.1 * (1 - k), -0.05)
                elbowR.eulerAngles = SCNVector3(1.6 * (1 - k) + 0.05, 0, 0)
                shoulderL.eulerAngles = SCNVector3(0.9, -0.3, 0.1)
                elbowL.eulerAngles = SCNVector3(1.9, 0, 0)
                chest.eulerAngles.y = -0.25 * k
            case .left:
                shoulderL.eulerAngles = SCNVector3(1.2 + 0.2 * k, -0.9 * k, 0.5 * k)
                elbowL.eulerAngles = SCNVector3(1.35, 0, 0)
                shoulderR.eulerAngles = SCNVector3(0.9, 0.3, -0.1)
                elbowR.eulerAngles = SCNVector3(1.9, 0, 0)
                chest.eulerAngles.y = -0.55 * k
                hips.eulerAngles.y = -0.2 * k
            case .right:
                shoulderR.eulerAngles = SCNVector3(1.2 + 0.2 * k, 0.9 * k, -0.5 * k)
                elbowR.eulerAngles = SCNVector3(1.35, 0, 0)
                shoulderL.eulerAngles = SCNVector3(0.9, -0.3, 0.1)
                elbowL.eulerAngles = SCNVector3(1.9, 0, 0)
                chest.eulerAngles.y = 0.55 * k
                hips.eulerAngles.y = 0.2 * k
            }
        }
    }

    private func reset() {
        for n in [thighL, thighR, kneeL, kneeR, shoulderL, shoulderR, elbowL, elbowR, chest, hips, spine, head] {
            n.eulerAngles = SCNVector3Zero
        }
        shoulderL.eulerAngles.z = -0.25
        shoulderR.eulerAngles.z = 0.25
    }
}

extension UIColor {
    var hexValue32: UInt32 { UInt32(hexValue) }
}
