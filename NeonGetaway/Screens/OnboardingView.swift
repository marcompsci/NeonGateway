import SwiftUI
import GameCore

/// First launch: arrive in Port Aurora, make your player, pick a first weapon, learn the street
/// rules, get your resident card. Five steps, each one screen, with Back always available.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    enum Step: Int, CaseIterable {
        case arrive, create, weapon, rules, card
    }

    @State private var step: Step = .arrive
    @State private var draft = PlayerProfile(name: "", skin: 1, hair: 0, jacket: 0, starter: .pistol)
    @State private var nameProblem: String?

    private var reduceMotion: Bool { model.reduceMotion(system: systemReduceMotion) }

    var body: some View {
        ZStack {
            SkylineBackdrop()
                .onAppear(perform: applyDebugStep)
            // After the arrival screen, dim the city so the controls read clearly.
            Palette.ink.opacity(step == .arrive ? 0 : 0.72)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                if step != .arrive { progressBar.padding(.top, 8) }
                Group {
                    switch step {
                    case .arrive: ArriveStep(reduceMotion: reduceMotion) { go(.create) }
                    case .create: CreateStep(draft: $draft, problem: $nameProblem, reduceMotion: reduceMotion,
                                             onBack: { go(.arrive) }, onNext: confirmName)
                    case .weapon: WeaponStep(draft: $draft, onBack: { go(.create) }, onNext: { go(.rules) })
                    case .rules: RulesStep(draft: draft, reduceMotion: reduceMotion,
                                           onBack: { go(.weapon) }, onNext: { go(.card) })
                    case .card: CardStep(draft: draft, reduceMotion: reduceMotion,
                                         onBack: { go(.rules) }, onFinish: finish)
                    }
                }
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases.dropFirst(), id: \.self) { s in
                Rectangle()
                    .fill(s.rawValue <= step.rawValue ? Palette.magenta : Palette.cream.opacity(0.2))
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue) of \(Step.allCases.count - 1)")
    }

    private func applyDebugStep() {
        let steps: [String: Step] = ["create": .create, "weapon": .weapon, "rules": .rules, "card": .card]
        guard let name = DebugLaunch.onboardingStep, let target = steps[name] else { return }
        draft.name = "Nova"
        draft.jacket = 1
        draft.hair = 3
        step = target
    }

    private func go(_ next: Step) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { step = next }
    }

    private func confirmName() {
        if let clean = PlayerProfile.cleanName(draft.name) {
            draft.name = clean
            nameProblem = nil
            go(.weapon)
        } else {
            nameProblem = "2–16 letters or numbers. Spaces, - ' and . are fine."
            model.haptics.failure()
        }
    }

    private func finish() {
        if model.completeOnboarding(draft) != nil {
            go(.create)
            nameProblem = "That name didn't work. Try another."
        }
    }
}

// MARK: - Shared pieces

/// Header + body + Back/Next row used by every step after the first.
private struct StepFrame<Content: View>: View {
    let kicker: String
    let title: String
    let nextTitle: String
    var nextEnabled = true
    var nextID = "onboarding.next"
    let onBack: () -> Void
    let onNext: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(kicker).pixelLabel(.caption, color: Palette.teal)
                    Text(title).pixelLabel(.largeTitle, color: Palette.cream)
                        .accessibilityAddTraits(.isHeader)
                        .fixedSize(horizontal: false, vertical: true)
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 12) {
                Button("Back", action: onBack)
                    .buttonStyle(.neon(Palette.cream))
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("onboarding.back")
                Button(nextTitle, action: onNext)
                    .buttonStyle(.neon(Palette.magenta))
                    .disabled(!nextEnabled)
                    .opacity(nextEnabled ? 1 : 0.45)
                    .accessibilityIdentifier(nextID)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .padding(.top, 8)
            .background(Palette.ink.opacity(0.85))
        }
    }
}

/// Text that types itself out (shown whole under Reduce Motion).
private struct TypewriterText: View {
    let text: String
    let reduceMotion: Bool
    var delay: Double = 0
    @State private var shown = 0

    var body: some View {
        Text(String(text.prefix(reduceMotion ? text.count : shown)))
            .font(.pixel(.title3, weight: .bold))
            .foregroundStyle(Palette.cream)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(delay))
                for i in 0...text.count {
                    shown = i
                    try? await Task.sleep(for: .milliseconds(28))
                }
            }
    }
}

// MARK: - Step 1: arrive

private struct ArriveStep: View {
    let reduceMotion: Bool
    let onNext: () -> Void
    @State private var glow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 40)
            TitleLockup()
                .frame(maxWidth: .infinity)
                .scaleEffect(glow || reduceMotion ? 1 : 0.94)
            VStack(alignment: .leading, spacing: 12) {
                TypewriterText(text: "Port Aurora never sleeps.", reduceMotion: reduceMotion, delay: 0.3)
                TypewriterText(text: "The docks pay. The streets pay more.", reduceMotion: reduceMotion, delay: 1.2)
                TypewriterText(text: "Every hustle starts with a name.", reduceMotion: reduceMotion, delay: 2.4)
            }
            .padding(16)
            .background(Palette.ink.opacity(0.75))
            .overlay(alignment: .leading) { Rectangle().fill(Palette.teal).frame(width: 3) }
            Spacer()
            Button("Make your player", action: onNext)
                .buttonStyle(.neon(Palette.magenta))
                .accessibilityIdentifier("onboarding.start")
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever()) { glow = true }
        }
    }
}

// MARK: - Step 2: create

private struct CreateStep: View {
    @Binding var draft: PlayerProfile
    @Binding var problem: String?
    let reduceMotion: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    @FocusState private var nameFocused: Bool
    @State private var bob = false
    @State private var spins = 0.0

    var body: some View {
        StepFrame(kicker: "STEP 1 · YOUR PLAYER", title: "Who's new in town?", nextTitle: "Next",
                  nextEnabled: !draft.name.trimmingCharacters(in: .whitespaces).isEmpty,
                  onBack: onBack, onNext: onNext) {
            HStack(alignment: .center, spacing: 18) {
                CharacterPreview(look: HumanLook.player(draft), reduceMotion: reduceMotion)
                    .frame(width: 150, height: 210)
                    .background(Palette.ink.opacity(0.7))
                    .overlay(Rectangle().strokeBorder(Palette.teal, lineWidth: 3))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(lookDescription)
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        var rng = SystemRandomNumberGenerator()
                        let random = PlayerProfile.random(name: draft.name, using: &rng)
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                            draft.skin = random.skin
                            draft.hair = random.hair
                            draft.jacket = random.jacket
                            draft.hairStyle = random.hairStyle
                            draft.outfit = random.outfit
                            draft.build = random.build
                            draft.frame = random.frame
                            draft.facialHair = random.facialHair
                            spins += 360
                        }
                    } label: {
                        Label("Shuffle", systemImage: "dice.fill")
                            .pixelLabel(.callout, color: Palette.ink)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Palette.sunset)
                    }
                    .accessibilityHint("Random skin, hair and jacket")
                    .accessibilityIdentifier("onboarding.shuffle")
                    Text("Tap a colour below to change one thing at a time.")
                        .pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever()) { bob = true }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").pixelLabel(.caption, color: Palette.teal)
                TextField("", text: $draft.name, prompt: Text("Your street name").foregroundStyle(Palette.cream.opacity(0.4)))
                    .font(.pixel(.title3, weight: .bold))
                    .foregroundStyle(Palette.cream)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($nameFocused)
                    .onSubmit(onNext)
                    .onChange(of: draft.name) { _, new in
                        if new.count > PlayerProfile.nameLength.upperBound {
                            draft.name = String(new.prefix(PlayerProfile.nameLength.upperBound))
                        }
                        problem = nil
                    }
                    .padding(12)
                    .background(Palette.ink.opacity(0.8))
                    .overlay(Rectangle().strokeBorder(problem == nil ? Palette.teal : Palette.sunset, lineWidth: 2))
                    .accessibilityLabel("Name")
                    .accessibilityIdentifier("onboarding.name")
                if let problem {
                    Text(problem).pixelLabel(.caption, color: Palette.sunset)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LookPickers(draft: $draft)
        }
    }

    private var lookDescription: String {
        let n = draft.normalized
        return "Your player: skin tone \(n.skin + 1), \(PixelArt.lookHairNames[n.hair]) hair, \(PixelArt.lookJacketNames[n.jacket]) jacket"
    }
}

private struct SwatchRow: View {
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
                            Rectangle().fill(colors[i])
                                .frame(width: 38, height: 38)
                                .overlay(Rectangle().strokeBorder(i == selection ? Palette.cream : Palette.ink,
                                                                  lineWidth: i == selection ? 4 : 2))
                                .overlay {
                                    if i == selection {
                                        Image(systemName: "checkmark").font(.caption.weight(.black))
                                            .foregroundStyle(Palette.ink)
                                            .padding(2)
                                            .background(Palette.cream)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                    }
                                }
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

// MARK: - Step 3: first weapon

private struct WeaponStep: View {
    @Binding var draft: PlayerProfile
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        StepFrame(kicker: "STEP 2 · FIRST WEAPON", title: "Pick what you carry",
                  nextTitle: "Take the \(draft.starter.spec.name.components(separatedBy: " ").first ?? "")",
                  nextID: "onboarding.takeWeapon", onBack: onBack, onNext: onNext) {
            Text("Swipe through five. You can buy or find others later.")
                .pixelLabel(.footnote, color: Palette.cream.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            TabView(selection: $draft.starter) {
                ForEach(WeaponID.allCases, id: \.self) { weapon in
                    WeaponCard(weapon: weapon)
                        .padding(.horizontal, 4)
                        .tag(weapon)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: 360)
            .accessibilityIdentifier("onboarding.weapons")
            HStack(spacing: 8) {
                ForEach(WeaponID.allCases, id: \.self) { weapon in
                    Button {
                        withAnimation { draft.starter = weapon }
                    } label: {
                        Image(uiImage: PixelArt.weaponImage(weapon, scale: 2))
                            .interpolation(.high)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(draft.starter == weapon ? Palette.magenta.opacity(0.35) : Palette.ink.opacity(0.6))
                            .overlay(Rectangle().strokeBorder(draft.starter == weapon ? Palette.magenta : Palette.cream.opacity(0.25),
                                                              lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(weapon.spec.name)
                    .accessibilityAddTraits(draft.starter == weapon ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("onboarding.weapon.\(weapon.rawValue)")
                }
            }
        }
    }
}

private struct WeaponCard: View {
    let weapon: WeaponID

    var body: some View {
        let spec = weapon.spec
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Image(uiImage: PixelArt.weaponImage(weapon, scale: 8))
                    .interpolation(.high)
                    .frame(height: 70)
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.vertical, 10)
            .background(Palette.ink.opacity(0.6))
            Text(spec.name).pixelLabel(.title2, color: Palette.sunset)
            Text(weapon.pitch).pixelLabel(.footnote, color: Palette.cream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            StatBar(label: "Hit", value: Double(spec.damage) / 4)
            StatBar(label: "Reach", value: spec.range / 620)
            StatBar(label: "Speed", value: min(1, (1 / spec.fireInterval) / 9))
            Label(spec.isMelee ? "Melee · never runs out"
                               : "Starter limit: \(Inventory.starterAmmoCap) rounds",
                  systemImage: spec.isMelee ? "infinity" : "exclamationmark.triangle.fill")
                .font(.pixel(.caption, weight: .bold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(spec.isMelee ? Palette.teal : Palette.sunset)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.asphalt.opacity(0.9))
        .overlay(Rectangle().strokeBorder(Palette.magenta.opacity(0.7), lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}

private struct StatBar: View {
    let label: String
    let value: Double

    var body: some View {
        let blocks = max(1, min(10, Int((value * 10).rounded())))
        HStack(spacing: 8) {
            Text(label).pixelLabel(.caption, color: Palette.cream.opacity(0.7))
                .frame(width: 60, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { i in
                    Rectangle().fill(i < blocks ? Palette.teal : Palette.cream.opacity(0.15))
                        .frame(height: 10)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(blocks) out of 10")
    }
}

// MARK: - Step 4: street rules

private struct RulesStep: View {
    let draft: PlayerProfile
    let reduceMotion: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    @State private var revealed = 0

    var body: some View {
        let melee = draft.starter.spec.isMelee
        StepFrame(kicker: "STEP 3 · STREET RULES", title: "How it works out here", nextTitle: "Got it",
                  onBack: onBack, onNext: onNext) {
            rule(0, icon: melee ? "infinity" : "exclamationmark.triangle.fill",
                 title: melee ? "Your bat never runs out" : "Your \(draft.starter.spec.name) holds 35 rounds",
                 body: melee ? "It only reaches arm's length, so pick your moments."
                             : "That's the starter limit. Buying ammo only tops it back up to 35.")
            rule(1, icon: "wrench.and.screwdriver.fill", title: "Raise the limit",
                 body: "Mod it with an Extended Mag at Bolt & Barrel (\(GunStore.extendedMagPrice) credits), or get a brand-new gun.")
            rule(2, icon: "hand.raised.fill", title: "New guns: buy them or take them",
                 body: "Bolt & Barrel and the alley dealer sell them. Cruisers you disable, the dealer and some civilians drop one. Taking guns from other players comes with online play.")
            rule(3, icon: "chart.line.uptrend.xyaxis", title: "Run it like a business",
                 body: "Every credit you earn and spend lands in your ledger. Profit is what's left after costs: check the Business screen.")
        }
        .task {
            guard !reduceMotion else { revealed = 4; return }
            for i in 1...4 {
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(.spring(duration: 0.4)) { revealed = i }
            }
        }
    }

    private func rule(_ index: Int, icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(index == 0 ? Palette.sunset : Palette.teal)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).pixelLabel(.callout, color: Palette.cream)
                    .fixedSize(horizontal: false, vertical: true)
                Text(body).font(.pixel(.footnote, weight: .medium))
                    .foregroundStyle(Palette.cream.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ink.opacity(0.75))
        .opacity(index < revealed ? 1 : 0)
        .offset(x: index < revealed || reduceMotion ? 0 : 30)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Step 5: resident card

private struct CardStep: View {
    let draft: PlayerProfile
    let reduceMotion: Bool
    let onBack: () -> Void
    let onFinish: () -> Void
    @State private var flipped = false

    var body: some View {
        StepFrame(kicker: "STEP 4 · YOU'RE IN", title: "Welcome to Port Aurora", nextTitle: "Hit the streets",
                  nextID: "onboarding.finish", onBack: onBack, onNext: onFinish) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("PORT AURORA · RESIDENT").pixelLabel(.caption, color: Palette.ink)
                    Spacer()
                    Text("No. \(String(format: "%05d", Int(UInt(bitPattern: draft.name.hashValue) % 100_000)))")
                        .pixelLabel(.caption2, color: Palette.ink.opacity(0.7))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Palette.teal)
                HStack(alignment: .top, spacing: 16) {
                    Image(uiImage: PixelArt.portraitImage(draft, scale: 7))
                        .interpolation(.none)
                        .padding(8)
                        .background(Palette.ink)
                        .overlay(Rectangle().strokeBorder(Palette.cream.opacity(0.4), lineWidth: 2))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Fact(label: "Name", value: draft.name)
                        Fact(label: "Carrying", value: draft.starter.spec.name)
                        Fact(label: "Reputation", value: "Level 0")
                        Fact(label: "Credits", value: "0")
                    }
                }
                .padding(.horizontal, 12)
                Text("First move: take a job from the map, or walk into free roam and find a ride.")
                    .font(.pixel(.footnote, weight: .medium))
                    .foregroundStyle(Palette.cream.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .background(Palette.asphaltLight)
            .overlay(Rectangle().strokeBorder(Palette.teal, lineWidth: 3))
            .rotation3DEffect(.degrees(flipped || reduceMotion ? 0 : 90), axis: (x: 0, y: 1, z: 0))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Resident card. \(draft.name), carrying the \(draft.starter.spec.name), reputation level 0")
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.7)) { flipped = true }
            }
        }
    }
}
