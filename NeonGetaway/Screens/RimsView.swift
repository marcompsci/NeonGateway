import SwiftUI
import GameCore

/// Wheels for the car you're driving: pick a rim style and a colour, see it, fit it.
struct RimsView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var draft = RimSetup()
    @State private var message: String?
    @State private var loaded = false

    var body: some View {
        let slot = model.progress.selectedVehicle
        let car = model.selectedCar
        let current = car?.rims ?? RimSetup()
        let cost = RimShop.cost(from: current, to: draft)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Wheels") { router.back() }
                if let car {
                    HStack(spacing: 16) {
                        Image(uiImage: HDArt.rimImage(draft, size: 150))
                            .accessibilityLabel("\(draft.style.name) rims in \(RimColors.names[draft.color])")
                        Image(uiImage: HDArt.vehiclePreview(car.model, design: car.design.flatMap { BodyShop.design($0, progress: model.progress) },
                                                            height: 150, rims: draft))
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                    Text(car.model.spec.displayName).pixelLabel(.headline)
                    Text("Style").pixelLabel(.caption, color: Palette.cream.opacity(0.7))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(RimStyle.allCases, id: \.self) { style in
                            Button { draft.style = style } label: {
                                VStack(spacing: 4) {
                                    Image(uiImage: HDArt.rimImage(RimSetup(style: style, color: draft.color), size: 64))
                                    Text(style.name).pixelLabel(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                                    Text(style.price == 0 ? "Free" : "\(style.price) cr")
                                        .pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(draft.style == style ? Palette.teal.opacity(0.22) : Palette.ink.opacity(0.55))
                                .overlay(Rectangle().strokeBorder(draft.style == style ? Palette.teal : Palette.cream.opacity(0.25),
                                                                  lineWidth: draft.style == style ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(style.name), \(style.price) credits")
                            .accessibilityAddTraits(draft.style == style ? .isSelected : [])
                            .accessibilityIdentifier("rims.style.\(style.rawValue)")
                        }
                    }
                    Text("Colour · \(RimColors.price) cr to change").pixelLabel(.caption, color: Palette.cream.opacity(0.7))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                        ForEach(RimColors.hex.indices, id: \.self) { i in
                            Button { draft.color = i } label: {
                                Circle().fill(Color(hex: RimColors.hex[i]))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(draft.color == i ? Palette.teal : Palette.cream.opacity(0.3),
                                                                   lineWidth: draft.color == i ? 3 : 1))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(RimColors.names[i])
                            .accessibilityAddTraits(draft.color == i ? .isSelected : [])
                        }
                    }
                    Button(cost == 0 ? "Fitted" : "Fit for \(cost) cr") {
                        switch model.fitRims(draft, slot: slot) {
                        case nil: message = "\(draft.style.name) rims in \(RimColors.names[draft.color].lowercased()) fitted."
                        case .notEnoughCredits(let short): message = "You need \(short) more credits."
                        case .noCar: message = nil
                        }
                    }
                    .buttonStyle(.neon(cost == 0 ? Palette.cream.opacity(0.35) : Palette.teal))
                    .disabled(cost == 0)
                    .accessibilityIdentifier("rims.fit")
                    if let message { Text(message).pixelLabel(.footnote, color: Palette.sunset) }
                    Text("Rims are cosmetic and stay with this car if you swap to another.")
                        .pixelLabel(.caption2, color: Palette.cream.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = current
        }
    }
}
