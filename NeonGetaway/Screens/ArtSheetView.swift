import SwiftUI
import SpriteKit
import GameCore

/// Debug only (`-NGArtSheet 1|2|3`): every generated sprite on one screen so the art can be
/// reviewed from a Simulator screenshot. 1 = vehicles, people and props; 2 = a downtown street
/// at full size; 3 = the docks and the Safehouse.
struct ArtSheetView: View {
    let page: Int

    var body: some View {
        ZStack {
            Color(white: 0.16).ignoresSafeArea()
            switch page {
            case 2: worldCrop(col: 9, row: 3, tiles: 5)
            case 3: worldCrop(col: 15, row: 1, tiles: 8)
            default: sprites
            }
        }
    }

    private var sprites: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach([VehicleID.vesper, .dorado, .ridgeback, .flicker, .harborPatrol], id: \.self) { model in
                    Image(uiImage: HDArt.vehicleImage(model, lightFrame: model == .harborPatrol ? 0 : nil))
                        .resizable().interpolation(.high)
                        .frame(width: HDArt.vehicleSize(model).width * 2, height: HDArt.vehicleSize(model).height * 2)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<5) { frame in
                    Image(uiImage: HDArt.personImage(HDArt.crowdLook(frame), frame: frame))
                        .resizable().interpolation(.high).frame(width: 66, height: 66)
                }
            }
            HStack(spacing: 6) {
                Image(uiImage: HDArt.personImage(HDArt.playerLook(PlayerProfile(name: "A", skin: 1, hair: 0, jacket: 0)), frame: 2))
                    .resizable().interpolation(.high).frame(width: 66, height: 66)
                Image(uiImage: HDArt.personImage(HDArt.dealerLook, frame: 0))
                    .resizable().interpolation(.high).frame(width: 66, height: 66)
                Image(uiImage: HDArt.vehicleImage(.dorado, design: PaintDesign(id: "t", name: "T", creator: "x",
                        cells: PaintDesign.cells(.flames, a: 3, b: 2), price: 0)))
                    .resizable().interpolation(.high).frame(width: 67, height: 108)
            }
            HStack(spacing: 10) {
                image(HDProps.texture(.tree(0)), 84)
                image(HDProps.texture(.palm(1)), 92)
                image(HDProps.texture(.lamp(facing: 0)), 60)
                image(HDProps.texture(.sign("RAMEN", 0xFF3EA5)), 110)
            }
        }
    }

    private func image(_ texture: SKTexture, _ width: CGFloat) -> some View {
        let cg = texture.cgImage()
        let ratio = CGFloat(cg.height) / CGFloat(max(1, cg.width))
        return Image(uiImage: UIImage(cgImage: cg)).resizable().interpolation(.high)
            .frame(width: width, height: width * ratio)
    }

    /// `tiles` × `tiles` of the ground texture starting at map column/row, drawn at 1 pt per point.
    private func worldCrop(col: Int, row: Int, tiles: Int) -> some View {
        let d = District.portAuroraDocks
        let t = CGFloat(d.tileSize)
        let chunkTiles = HDWorld.chunkTiles
        let chunks = HDWorld.chunks(for: d)
        let perRow = Int(ceil(Double(d.cols) / Double(chunkTiles)))
        let size = CGSize(width: CGFloat(tiles) * t, height: CGFloat(tiles) * t)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            for (i, chunk) in chunks.enumerated() {
                let c0 = (i % perRow) * chunkTiles, r0 = (i / perRow) * chunkTiles
                let origin = CGPoint(x: CGFloat(c0 - col) * t, y: CGFloat(r0 - row) * t)
                UIImage(cgImage: chunk.texture.cgImage()).draw(in: CGRect(origin: origin, size: chunk.size))
            }
            // Props on top, to judge them in place.
            for prop in HDProps.props(for: d) {
                let px = prop.position.x - CGFloat(col) * t
                let py = (CGFloat(d.rows) * t - prop.position.y) - CGFloat(row) * t
                let tex = HDProps.texture(prop.kind)
                let img = UIImage(cgImage: tex.cgImage())
                let w: CGFloat
                switch prop.kind {
                case .tree: w = HDProps.treeSize.width
                case .palm: w = HDProps.palmSize.width
                case .lamp: w = HDProps.lampSize.width
                case .sign(let word, _): w = HDProps.signSize(word).width
                }
                let h = w * img.size.height / max(1, img.size.width)
                img.draw(in: CGRect(x: px - w / 2, y: py - h / 2, width: w, height: h))
            }
            ctx.cgContext.setFillColor(UIColor.clear.cgColor)
        }
        return ScrollView([.horizontal, .vertical]) {
            Image(uiImage: image).resizable().frame(width: size.width / 1.6, height: size.height / 1.6)
        }
    }
}
