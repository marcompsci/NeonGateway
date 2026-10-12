import SwiftUI
import GameCore

/// Chrome Coast Body Shop: paint your cars with designs you own, buy designs from the
/// city's Legendary creators, and (once you're Legendary yourself) sell your own.
struct BodyShopView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var slot = 0
    @State private var message: String?

    var body: some View {
        let p = model.progress
        let carSlot = p.garage.indices.contains(slot) ? slot : 0
        let car = p.garage[carSlot]
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Body shop") { router.back() }
                Text("Chrome Coast · paint, designs, and a market for the city's best").pixelLabel(.caption, color: Palette.sunset)

                // The car being painted.
                HStack {
                    Spacer()
                    Image(uiImage: PixelArt.vehicleImage(car.model, design: car.design.flatMap { BodyShop.design($0, progress: p) },
                                                         scale: 7))
                        .interpolation(.none)
                        .accessibilityLabel("\(car.model.spec.displayName)" + (car.design.flatMap { BodyShop.design($0, progress: p)?.name }
                                                                               .map { " in \($0)" } ?? ", factory paint"))
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(Palette.ink.opacity(0.6))
                .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.6), lineWidth: 2))

                if p.garage.count > 1 {
                    Picker("Car", selection: $slot) {
                        ForEach(p.garage.indices, id: \.self) { i in
                            Text(p.garage[i].model.spec.displayName.components(separatedBy: " ").first ?? "").tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                section("Your designs") {
                    if p.designs.isEmpty {
                        Text("None yet. Buy one below or draw your own.")
                            .pixelLabel(.caption, color: Palette.cream.opacity(0.55))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        DesignTile(model: car.model, design: nil, title: "Factory", subtitle: car.design == nil ? "On" : "Strip",
                                   selected: car.design == nil) {
                            model.applyDesign(nil, toSlot: carSlot)
                        }
                        ForEach(p.designs) { design in
                            DesignTile(model: car.model, design: design, title: design.name,
                                       subtitle: car.design == design.id ? "On" : "Apply",
                                       selected: car.design == design.id) {
                                model.applyDesign(design.id, toSlot: carSlot)
                            }
                        }
                    }
                    Button("Open the paint studio") { router.go(.paintStudio) }
                        .buttonStyle(.neon(Palette.magenta))
                        .accessibilityIdentifier("bodyshop.studio")
                }

                section("From Legendary creators") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ForEach(BodyShop.houseDesigns) { design in
                            let owned = p.designs.contains { $0.id == design.id }
                            DesignTile(model: car.model, design: design, title: design.name,
                                       subtitle: owned ? "Owned · by \(design.creator)" : "\(design.price) cr · by \(design.creator)",
                                       selected: false) {
                                guard !owned else { model.applyDesign(design.id, toSlot: carSlot); return }
                                switch model.buyDesign(design.id) {
                                case nil: message = "\"\(design.name)\" is yours. Tap it above to paint."
                                case .notEnoughCredits(let needed)?: message = "You need \(needed) more credits."
                                default: message = nil
                                }
                            }
                        }
                    }
                    if let message {
                        Text(message).pixelLabel(.footnote, color: Palette.sunset)
                    }
                }

                MarketSection()
                OnlineMarketSection(slot: carSlot)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
        .onAppear { slot = model.progress.selectedVehicle }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).pixelLabel(.headline, color: Palette.magenta)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// A car in a design, as a tappable tile.
struct DesignTile: View {
    let model: VehicleID
    let design: PaintDesign?
    let title: String
    let subtitle: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(uiImage: PixelArt.vehicleImage(model, design: design, scale: 3))
                    .interpolation(.none)
                    .frame(height: 84)
                Text(title).pixelLabel(.caption, color: Palette.cream).lineLimit(1)
                Text(subtitle).pixelLabel(.caption2, color: selected ? Palette.teal : Palette.sunset)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(selected ? Palette.asphaltLight : Palette.ink.opacity(0.55))
            .overlay(Rectangle().strokeBorder(selected ? Palette.teal : Palette.cream.opacity(0.25), lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Selling your own designs: Legendary only. Offline, simulated buyers shop after each job.
private struct MarketSection: View {
    @Environment(AppModel.self) private var model
    @State private var prices: [String: Int] = [:]

    var body: some View {
        let p = model.progress
        let legendary = Ranking.isLegendary(p)
        let mine = p.designs.filter { BodyShop.isMine($0.id) }
        VStack(alignment: .leading, spacing: 10) {
            Text("Sell your designs").pixelLabel(.headline, color: Palette.magenta)
                .accessibilityAddTraits(.isHeader)
            if !legendary {
                Label("Legendary rank only. You need \(Ranking.pointsToLegendary(p)) more ranking points.",
                      systemImage: "lock.fill")
                    .font(.pixel(.footnote))
                    .foregroundStyle(Palette.sunset)
                    .fixedSize(horizontal: false, vertical: true)
            } else if mine.isEmpty {
                Text("Draw a design in the studio, then list it here.").pixelLabel(.caption, color: Palette.cream.opacity(0.6))
            }
            Text("Buyers shop after every job you finish. Higher prices earn more per sale but sell fewer. The shop keeps \(Int(BodyShop.platformFee * 100))%.")
                .font(.pixel(.footnote, weight: .medium))
                .foregroundStyle(Palette.cream.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if legendary {
                ForEach(mine) { design in
                    listingRow(design, listing: p.listings.first { $0.designID == design.id })
                }
            }
        }
    }

    private func listingRow(_ design: PaintDesign, listing: DesignListing?) -> some View {
        let price = prices[design.id] ?? listing?.price ?? 300
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(design.name).pixelLabel(.callout)
                Spacer()
                if let listing {
                    Text("\(listing.sold) sold · +\(listing.earned) cr").pixelLabel(.caption, color: Palette.teal)
                }
            }
            Stepper(value: Binding(get: { price }, set: { prices[design.id] = $0 }), in: BodyShop.priceRange, step: 50) {
                Text("Price \(price) cr · ~\(String(format: "%.1f", BodyShop.expectedSales(boldness: design.boldness, price: price))) buyers a day")
                    .pixelLabel(.caption, color: Palette.cream)
            }
            HStack(spacing: 10) {
                Button(listing == nil ? "List for sale" : "Update price") {
                    model.listDesign(design.id, price: price)
                }
                .buttonStyle(.neon(Palette.sunset))
                if listing != nil {
                    Button("Take down") { model.unlistDesign(design.id) }
                        .buttonStyle(.neon(Palette.cream))
                }
            }
        }
        .padding(12)
        .background(Palette.ink.opacity(0.5))
        .overlay(Rectangle().strokeBorder(Palette.sunset.opacity(0.5), lineWidth: 2))
    }
}

/// Designs from real players, from the game's iCloud market. Buying pays the creator (in credits,
/// after the 30% shop fee) when their game next checks in. Hold a design to report or block.
private struct OnlineMarketSection: View {
    @Environment(AppModel.self) private var model
    let slot: Int
    @State private var message: String?
    @State private var reporting: MarketDesign?
    @State private var busy = false

    var body: some View {
        let p = model.progress
        let market = model.market
        VStack(alignment: .leading, spacing: 10) {
            Text("Online market").pixelLabel(.headline, color: Palette.magenta)
                .accessibilityAddTraits(.isHeader)
            if model.onlineID == nil {
                Label("Sign in to Game Center to see designs from real players.", systemImage: "wifi.slash")
                    .font(.pixel(.footnote))
                    .foregroundStyle(Palette.sunset)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                switch market.status {
                case .loading:
                    ProgressView().tint(Palette.teal)
                case .unavailable(let why):
                    Text(why).pixelLabel(.footnote, color: Palette.sunset)
                default:
                    let shown = OnlineMarket.visible(market.designs, for: p)
                    if shown.isEmpty {
                        Text("No designs from other players yet.").pixelLabel(.caption, color: Palette.cream.opacity(0.6))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ForEach(shown) { design in tile(design, progress: p) }
                    }
                }
                if let message {
                    Text(message).pixelLabel(.footnote, color: Palette.sunset)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Hold a design to report it or block its creator.")
                    .pixelLabel(.caption2, color: Palette.cream.opacity(0.55))
                publishRows(p)
            }
        }
        .task(id: model.onlineID) {
            if model.onlineID != nil { await model.market.refresh() }
        }
        .confirmationDialog("Report this design", isPresented: Binding(get: { reporting != nil },
                                                                     set: { if !$0 { reporting = nil } }),
                            titleVisibility: .visible) {
            ForEach(OnlineMarket.ReportReason.allCases, id: \.self) { reason in
                Button(reason.rawValue) {
                    guard let design = reporting else { return }
                    Task {
                        let ok = await model.reportOnline(design, reason: reason)
                        message = ok ? "Thanks. Designs reported by several players are hidden." : "Couldn't send the report. Try again."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func tile(_ design: MarketDesign, progress p: PlayerProgress) -> some View {
        let owned = p.designs.contains { $0.id == design.localID }
        let mine = design.creatorID == model.onlineID
        let car = p.garage.indices.contains(slot) ? p.garage[slot].model : .vesper
        return DesignTile(model: car, design: design.asPaint, title: design.name,
                          subtitle: mine ? "Yours · \(design.sales) sold"
                              : owned ? "Owned · by \(design.creatorName)"
                              : "\(design.price) cr · by \(design.creatorName)",
                          selected: false) {
            guard !mine, !busy else { return }
            if owned {
                model.applyDesign(design.localID, toSlot: slot)
                return
            }
            busy = true
            Task {
                let problem = await model.buyOnline(design)
                message = problem ?? "\"\(design.name)\" is yours. \(design.creatorName) gets paid."
                busy = false
            }
        }
        .contextMenu {
            if !mine {
                Button("Report design", systemImage: "flag") { reporting = design }
                Button("Block \(design.creatorName)", systemImage: "hand.raised") {
                    model.block(design.creatorID)
                    message = "Blocked. You won't see their designs or meet them in live play."
                }
            }
        }
        .accessibilityAction(named: "Report design") { if !mine { reporting = design } }
        .accessibilityAction(named: "Block creator") { if !mine { model.block(design.creatorID) } }
    }

    @ViewBuilder
    private func publishRows(_ p: PlayerProgress) -> some View {
        let mine = p.designs.filter { BodyShop.isMine($0.id) }
        if Ranking.isLegendary(p) && !mine.isEmpty {
            Text("Publish to every player").pixelLabel(.callout, color: Palette.teal)
            ForEach(mine) { design in
                HStack {
                    Text(design.name).pixelLabel(.caption)
                    Spacer()
                    if p.online.published[design.id] != nil {
                        Text("Online").pixelLabel(.caption, color: Palette.teal)
                    } else {
                        let price = p.listings.first { $0.designID == design.id }?.price ?? 300
                        Button("Publish · \(price) cr") {
                            busy = true
                            Task {
                                message = await model.publishOnline(design.id, price: price)
                                    ?? "\"\(design.name)\" is on the online market."
                                busy = false
                            }
                        }
                        .font(.pixel(.caption))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(Palette.sunset)
                        .disabled(busy)
                    }
                }
            }
            Text("Price comes from your listing above (300 if not listed). The shop keeps 30%; you're paid when buyers' purchases reach your game.")
                .pixelLabel(.caption2, color: Palette.cream.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
