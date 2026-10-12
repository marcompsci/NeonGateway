import SwiftUI
import GameCore

/// Draw a car paint design: a 12×20 grid laid over the car body. Pen, fill and eraser, a
/// mirror switch for symmetric designs, templates to start from, and a live car preview.
struct PaintStudioView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var cells = PaintDesign.blank
    @State private var colour: UInt8 = 1
    @State private var tool: Tool = .pen
    @State private var mirror = true
    @State private var name = ""
    @State private var message: String?
    @State private var previewModel: VehicleID = .vesper

    enum Tool: String, CaseIterable { case pen = "Pen", fill = "Fill", eraser = "Eraser" }

    private var draft: PaintDesign {
        PaintDesign(id: "draft", name: name, creator: model.progress.profile?.name ?? "You", cells: cells, price: 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Paint studio") { router.back() }
                HStack(alignment: .top, spacing: 14) {
                    canvas
                    VStack(spacing: 10) {
                        Image(uiImage: PixelArt.vehicleImage(previewModel, design: draft, scale: 4))
                            .interpolation(.none)
                            .frame(height: 130)
                            .accessibilityLabel("Preview on the \(previewModel.spec.displayName)")
                        Picker("Preview", selection: $previewModel) {
                            ForEach(VehicleID.drivable, id: \.self) { m in
                                Text(m.spec.displayName.components(separatedBy: " ").first ?? "").tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Palette.teal)
                        Toggle(isOn: $mirror) { Text("Mirror").pixelLabel(.caption) }
                            .tint(Palette.magenta)
                            .accessibilityHint("Paints both sides of the car at once")
                    }
                    .frame(maxWidth: .infinity)
                }

                Picker("Tool", selection: $tool) {
                    ForEach(Tool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(1...PaintDesign.colorCount, id: \.self) { i in
                            let value = UInt8(i)
                            Button { colour = value; if tool == .eraser { tool = .pen } } label: {
                                Rectangle().fill(Color(uiColor: PixelArt.designColor(value)!))
                                    .frame(width: 34, height: 34)
                                    .overlay(Rectangle().strokeBorder(colour == value ? Palette.cream : Palette.ink,
                                                                      lineWidth: colour == value ? 4 : 2))
                                    .frame(minWidth: 40, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(PixelArt.designColorNames[i - 1])
                            .accessibilityAddTraits(colour == value ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Start from a template (in your colour + the next)").pixelLabel(.caption, color: Palette.teal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PaintDesign.Template.allCases, id: \.self) { t in
                                Button(t.name) {
                                    let next = UInt8(Int(colour) % PaintDesign.colorCount + 1)
                                    cells = PaintDesign.cells(t, a: colour, b: next)
                                }
                                .font(.pixel(.caption))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 40)
                                .background(Palette.sunset)
                            }
                            Button("Clear") { cells = PaintDesign.blank }
                                .font(.pixel(.caption))
                                .foregroundStyle(Palette.cream)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 40)
                                .overlay(Rectangle().strokeBorder(Palette.cream.opacity(0.5), lineWidth: 1))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").pixelLabel(.caption, color: Palette.teal)
                    TextField("", text: $name, prompt: Text("Name your design").foregroundStyle(Palette.cream.opacity(0.4)))
                        .font(.pixel(.body, weight: .bold))
                        .foregroundStyle(Palette.cream)
                        .padding(10)
                        .background(Palette.ink.opacity(0.8))
                        .overlay(Rectangle().strokeBorder(Palette.teal, lineWidth: 2))
                        .accessibilityIdentifier("studio.name")
                }
                if let message {
                    Text(message).pixelLabel(.footnote, color: Palette.sunset)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Save design") { save() }
                    .buttonStyle(.neon(Palette.magenta))
                    .accessibilityIdentifier("studio.save")
                Text(Ranking.isLegendary(model.progress)
                     ? "You're Legendary: list saved designs for sale in the body shop."
                     : "Paint your own cars with it any time. Reach Legendary rank to sell designs to other drivers.")
                    .font(.pixel(.footnote, weight: .medium))
                    .foregroundStyle(Palette.cream.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }

    // MARK: Canvas

    private let cellSize: CGFloat = 13

    private var canvas: some View {
        let w = PaintDesign.width, h = PaintDesign.height
        return Canvas { context, _ in
            for r in 0..<h {
                for c in 0..<w {
                    let rect = CGRect(x: CGFloat(c) * cellSize, y: CGFloat(r) * cellSize, width: cellSize, height: cellSize)
                    let value = cells[r * w + c]
                    let fill = PixelArt.designColor(value).map { Color(uiColor: $0) }
                        ?? ((r + c) % 2 == 0 ? Palette.asphaltLight : Palette.ink)
                    context.fill(Path(rect), with: .color(fill))
                }
            }
            // Centre line, so mirrored work is easy to place.
            var mid = Path()
            mid.move(to: CGPoint(x: CGFloat(w) * cellSize / 2, y: 0))
            mid.addLine(to: CGPoint(x: CGFloat(w) * cellSize / 2, y: CGFloat(h) * cellSize))
            context.stroke(mid, with: .color(Palette.cream.opacity(mirror ? 0.35 : 0.1)), lineWidth: 1)
        }
        .frame(width: CGFloat(w) * cellSize, height: CGFloat(h) * cellSize)
        .overlay(Rectangle().strokeBorder(Palette.teal, lineWidth: 2))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in paint(at: drag.location, dragging: drag.translation != .zero) }
        )
        .accessibilityElement()
        .accessibilityLabel("Design canvas, nose at the top. \(cells.filter { $0 != 0 }.count) of \(w * h) squares painted.")
        .accessibilityHint("Drag to paint. Templates below fill it in one tap.")
        .accessibilityIdentifier("studio.canvas")
    }

    private func paint(at point: CGPoint, dragging: Bool) {
        let c = Int(point.x / cellSize), r = Int(point.y / cellSize)
        guard (0..<PaintDesign.width).contains(c), (0..<PaintDesign.height).contains(r) else { return }
        let value: UInt8 = tool == .eraser ? 0 : colour
        switch tool {
        case .pen, .eraser:
            set(c, r, value)
            if mirror { set(PaintDesign.width - 1 - c, r, value) }
        case .fill:
            guard !dragging else { return }
            flood(c, r, to: value)
        }
    }

    private func set(_ c: Int, _ r: Int, _ value: UInt8) {
        let i = r * PaintDesign.width + c
        if cells[i] != value { cells[i] = value }
    }

    /// Fills the touching area of the same colour.
    private func flood(_ c: Int, _ r: Int, to value: UInt8) {
        let w = PaintDesign.width, h = PaintDesign.height
        let target = cells[r * w + c]
        guard target != value else { return }
        var stack = [(c, r)]
        while let next = stack.popLast() {
            let (x, y) = next
            guard (0..<w).contains(x), (0..<h).contains(y), cells[y * w + x] == target else { continue }
            cells[y * w + x] = value
            stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        }
    }

    private func save() {
        switch model.createDesign(name: name, cells: cells) {
        case .success(let design):
            message = "Saved \"\(design.name)\". Paint it on a car in the body shop."
            name = ""
        case .failure(.badName):
            message = "Give it a name (2–20 characters)."
        case .failure(.badDesign):
            message = "Paint at least one square first."
        case .failure:
            message = "Couldn't save that design."
        }
    }
}
