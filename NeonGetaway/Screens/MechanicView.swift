import SwiftUI
import GameCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Dex, the garage mechanic: the car's condition part by part, what each part does, what to fix
/// and why, where to take it for paint or bodywork, and questions answered.
struct MechanicView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var open: CarPart?
    @State private var message: String?
    @State private var draft = ""
    @State private var chat: [(Bool, String)] = []
    @State private var thinking = false

    var body: some View {
        let slot = model.progress.selectedVehicle
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Mechanic") { router.back() }
                if let car = model.selectedCar {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 54, height: 54)
                            .background(Palette.sunset, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(Mechanic.name), your mechanic").pixelLabel(.headline, color: Palette.sunset)
                            Text(Mechanic.greeting(car)).pixelLabel(.callout, color: Palette.cream)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("mechanic.greeting")
                        }
                    }
                    Text("\(car.model.spec.displayName) · condition").pixelLabel(.caption, color: Palette.cream.opacity(0.7))
                    VStack(spacing: 8) {
                        ForEach(Mechanic.report(car)) { item in
                            partRow(item, slot: slot)
                        }
                    }
                    if let message { Text(message).pixelLabel(.footnote, color: Palette.teal) }

                    Text("Where Dex sends you").pixelLabel(.headline, color: Palette.teal)
                    VStack(spacing: 8) {
                        ForEach(Mechanic.recommendations(car)) { shop in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(shop.name).pixelLabel(.callout, color: Palette.cream)
                                    Spacer()
                                    Text(shop.kind.rawValue.capitalized).pixelLabel(.caption2, color: Palette.sunset)
                                }
                                Text(shop.place).pixelLabel(.caption2, color: Palette.teal)
                                Text(shop.pitch).pixelLabel(.caption, color: Palette.cream.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                                if shop.name == "Aurora Body Shop" {
                                    Button("Go to the body shop") { router.go(.bodyShop) }
                                        .font(.pixel(.caption)).foregroundStyle(Palette.magenta)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.ink.opacity(0.5))
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Text("Ask Dex").pixelLabel(.headline, color: Palette.teal)
                    ForEach(Array(chat.enumerated()), id: \.offset) { _, line in
                        Text((line.0 ? "You: " : "Dex: ") + line.1)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(line.0 ? Palette.teal : Palette.cream)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if thinking { ProgressView().tint(Palette.sunset) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(Mechanic.suggestions.enumerated()), id: \.offset) { i, s in
                                Button(s) { ask(s, car: car) }
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Palette.cream)
                                    .padding(.horizontal, 10).frame(minHeight: 32)
                                    .background(Palette.sunset.opacity(0.22), in: Capsule())
                                    .accessibilityIdentifier("mechanic.ask.\(i)")
                            }
                        }
                    }
                    HStack {
                        TextField("Ask about your car…", text: $draft)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Palette.cream)
                            .padding(.horizontal, 10).frame(minHeight: 40)
                            .background(Palette.ink.opacity(0.8))
                            .submitLabel(.send)
                            .onSubmit { ask(draft, car: car) }
                        Button { ask(draft, car: car) } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(Palette.sunset)
                        }
                        .accessibilityLabel("Ask")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }

    private func partRow(_ item: Mechanic.Item, slot: Int) -> some View {
        let colour: Color = item.wear >= 0.8 ? Palette.magenta : item.wear >= 0.5 ? Palette.sunset : Palette.teal
        return VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation { open = open == item.part ? nil : item.part } } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.part.icon).frame(width: 22).foregroundStyle(colour)
                    Text(item.part.name).pixelLabel(.callout)
                    Spacer()
                    Text(item.condition).pixelLabel(.caption, color: colour)
                    Image(systemName: open == item.part ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(Palette.cream.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.part.name), \(item.condition), \(Int(item.wear * 100)) percent worn")
            .accessibilityHint("Shows how it works and why to fix it")
            .accessibilityIdentifier("mechanic.part.\(item.part.rawValue)")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Palette.ink
                    colour.frame(width: geo.size.width * max(0.03, 1 - item.wear))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            if open == item.part {
                Text("How it works: " + item.part.howItWorks).pixelLabel(.caption, color: Palette.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mechanic.lesson")
                Text("Why fix it: " + item.part.whyFix).pixelLabel(.caption, color: Palette.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if item.cost > 0 {
                Button("Fix · \(item.cost) cr") {
                    if let paid = model.fixPart(item.part, slot: slot) {
                        message = "\(item.part.name) done for \(paid) cr."
                    } else {
                        message = "You need \(item.cost - model.progress.credits) more credits."
                    }
                }
                .font(.pixel(.caption))
                .foregroundStyle(colour)
                .frame(minHeight: 32)
                .accessibilityIdentifier("mechanic.fix.\(item.part.rawValue)")
            }
        }
        .padding(10)
        .background(Palette.ink.opacity(0.5))
    }

    private func ask(_ text: String, car: OwnedVehicle) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        draft = ""
        chat.append((true, q))
        thinking = true
        Task {
            let reply = await answer(q, car: car)
            chat.append((false, reply))
            thinking = false
        }
    }

    private func answer(_ q: String, car: OwnedVehicle) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), !DebugLaunch.offline, SystemLanguageModel.default.availability == .available {
            do {
                let session = LanguageModelSession(instructions: Mechanic.instructions)
                let r = try await session.respond(to: Mechanic.prompt(q, car: car), options: GenerationOptions(temperature: 0.3))
                let text = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            } catch {}
        }
        #endif
        return Mechanic.answer(q, car: car)
    }
}
