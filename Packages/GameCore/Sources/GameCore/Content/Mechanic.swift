import Foundation

/// The parts the mechanic checks.
public enum CarPart: String, Codable, Sendable, CaseIterable, Identifiable {
    case oil, tires, brakes, engine, suspension, body

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .oil: "Engine oil"
        case .tires: "Tyres"
        case .brakes: "Brakes"
        case .engine: "Engine"
        case .suspension: "Suspension"
        case .body: "Body panels"
        }
    }

    public var icon: String {
        switch self {
        case .oil: "drop.fill"
        case .tires: "circle.circle"
        case .brakes: "exclamationmark.octagon"
        case .engine: "engine.combustion"
        case .suspension: "arrow.up.and.down"
        case .body: "car.side"
        }
    }

    /// How it works, in a sentence or two (the mechanic's lesson).
    public var howItWorks: String {
        switch self {
        case .oil: "Oil coats every moving metal part inside the engine so they slide instead of grinding. Heat breaks it down, so it gets thin and dirty over time."
        case .tires: "Tyres are the only part of the car touching the road. The tread pushes water away and the rubber grips; as it wears, grip goes, especially in turns and rain."
        case .brakes: "Pressing the pedal squeezes pads against discs on each wheel. Friction turns your speed into heat. Pads wear thin with every stop."
        case .engine: "Fuel and air burn in the cylinders, pushing pistons that turn the crankshaft and, through the gearbox, the wheels. Spark plugs and filters keep it breathing."
        case .suspension: "Springs hold the car up and shocks stop it bouncing, so the tyres stay pressed to the road over bumps and through corners."
        case .body: "Panels and the frame keep the shape of the car and protect you. Dents and bent frames make it weaker in the next crash."
        }
    }

    /// What wearing out does, and why fixing it matters.
    public var whyFix: String {
        switch self {
        case .oil: "Old oil lets parts rub, which wears the engine out fast and cuts power. An oil change is the cheapest way to save an engine."
        case .tires: "Bald tyres slide wide in corners and take longer to stop. New tyres bring the grip back."
        case .brakes: "Worn pads mean longer stops, and grinding metal damages the discs too, which costs more."
        case .engine: "A tired engine pulls slower and tops out lower. A tune-up restores power."
        case .suspension: "Worn shocks make the car wallow and bounce; it steers lazily and grips less."
        case .body: "A battered body can't take as many hits before the car is wrecked. Panel work makes it strong again."
        }
    }

    /// Credits to bring the part back to new, per point of wear (0...1).
    public var fullCost: Int {
        switch self {
        case .oil: 120
        case .tires: 600
        case .brakes: 450
        case .engine: 1_400
        case .suspension: 900
        case .body: 800
        }
    }
}

/// Wear on each part: 0 = new, 1 = worn out.
public struct CarWear: Codable, Sendable, Equatable {
    public var parts: [String: Double] = [:]

    public init() {}

    public func wear(_ part: CarPart) -> Double { parts[part.rawValue] ?? 0 }

    /// After a drive: distance in points, knocks taken in this car, drift seconds.
    public mutating func add(driven: Double, knocks: Int, drifting: Double = 0) {
        let km = driven / 12_800   // points per km
        func bump(_ part: CarPart, _ amount: Double) { parts[part.rawValue] = min(1, wear(part) + amount) }
        bump(.oil, km * 0.06)
        bump(.tires, km * 0.035 + drifting * 0.004)
        bump(.brakes, km * 0.03)
        bump(.engine, km * 0.012 + wear(.oil) * km * 0.03)   // dirty oil wears the engine faster
        bump(.suspension, km * 0.015 + Double(knocks) * 0.02)
        bump(.body, Double(knocks) * 0.05)
    }

    public mutating func fix(_ part: CarPart) { parts[part.rawValue] = nil }

    /// How worn parts change the way the car drives (applied on top of upgrades).
    public func apply(to spec: VehicleSpec) -> VehicleSpec {
        var s = spec
        s.maxSpeed *= 1 - 0.12 * wear(.engine) - 0.04 * wear(.oil)
        s.acceleration *= 1 - 0.18 * wear(.engine) - 0.06 * wear(.oil)
        s.brakeForce *= 1 - 0.3 * wear(.brakes)
        s.lateralRetention = min(0.95, s.lateralRetention + 0.12 * wear(.tires) + 0.06 * wear(.suspension))
        s.turnRate *= 1 - 0.1 * wear(.suspension)
        s.maxIntegrity = max(2, s.maxIntegrity - Int((Double(s.maxIntegrity) * 0.4 * wear(.body)).rounded()))
        return s
    }
}

/// A shop the mechanic sends you to.
public struct ShopTip: Sendable, Equatable, Identifiable {
    public let name: String
    /// "Port Aurora · Harborside" or a Solara city.
    public let place: String
    public let kind: Kind
    public let pitch: String
    public var id: String { name }

    public enum Kind: String, Sendable { case collision, paint, wheels, performance }
}

/// Dex, the garage mechanic: checks the car, explains every part, quotes fixes and says where to
/// take it for paint, bodywork and wheels.
public enum Mechanic {
    public static let name = "Dex"

    public static let shops: [ShopTip] = [
        ShopTip(name: "Aurora Body Shop", place: "Port Aurora · the docks garage", kind: .paint,
                pitch: "Paint designs from the top Legendary players, and your own from the paint studio. Right here in the garage."),
        ShopTip(name: "Cinder Flats Collision Center", place: "Solara · Cinder Flats", kind: .collision,
                pitch: "Frame straightening and panel work. They've rebuilt rigs that rolled on the Interstate."),
        ShopTip(name: "Chrome & Candy Customs", place: "Solara · Mesa Rojo", kind: .paint,
                pitch: "Candy and pearl paint, pinstriping by hand. The place for a classic."),
        ShopTip(name: "Starline Wrap Lab", place: "Solara · Starline Hills", kind: .paint,
                pitch: "Vinyl wraps in a day: matte, satin, colour-shift. No paint booth wait."),
        ShopTip(name: "Redwood Wheel & Tire", place: "Solara · Redwood Hollow", kind: .wheels,
                pitch: "Rims, tyres and alignment. They'll balance a deep dish so it doesn't shake at speed."),
        ShopTip(name: "Steamvale Tune Works", place: "Solara · Steamvale", kind: .performance,
                pitch: "Engine tune-ups and dyno runs. Bring a tired V8 and leave with a loud one."),
    ]

    public struct Item: Sendable, Equatable, Identifiable {
        public let part: CarPart
        /// 0 = new, 1 = shot.
        public let wear: Double
        public let cost: Int
        public var id: String { part.rawValue }
        public var condition: String {
            switch wear {
            case ..<0.2: "Good"
            case ..<0.5: "Worn"
            case ..<0.8: "Needs work"
            default: "Fix now"
            }
        }
        public var needsWork: Bool { wear >= 0.5 }
    }

    public static func report(_ car: OwnedVehicle) -> [Item] {
        let wear = car.wear ?? CarWear()
        return CarPart.allCases.map { part in
            let w = wear.wear(part)
            return Item(part: part, wear: w, cost: Int((Double(part.fullCost) * w / 10).rounded()) * 10)
        }
        .sorted { $0.wear > $1.wear }
    }

    /// What Dex says first: the most urgent thing, in his words.
    public static func greeting(_ car: OwnedVehicle) -> String {
        let name = car.model.spec.displayName
        let items = report(car)
        guard let worst = items.first, worst.wear >= 0.2 else {
            return "The \(name) is in great shape. Keep changing the oil and she'll run forever. Ask me anything about how cars work."
        }
        if worst.needsWork {
            return "Your \(worst.part.name.lowercased()) on the \(name) needs work. \(worst.part.whyFix) I can do it for \(worst.cost) cr."
        }
        return "The \(name) is fine, but the \(worst.part.name.lowercased()) is getting worn. No rush, but don't leave it too long."
    }

    /// Shops for what the car needs (bodywork, paint, wheels or power).
    public static func recommendations(_ car: OwnedVehicle) -> [ShopTip] {
        let wear = car.wear ?? CarWear()
        var kinds: [ShopTip.Kind] = []
        if wear.wear(.body) >= 0.3 { kinds.append(.collision) }
        if wear.wear(.tires) >= 0.4 || wear.wear(.suspension) >= 0.4 { kinds.append(.wheels) }
        if wear.wear(.engine) >= 0.4 { kinds.append(.performance) }
        kinds.append(.paint)
        var out: [ShopTip] = []
        for kind in kinds { out += shops.filter { $0.kind == kind } }
        return Array(out.prefix(4))
    }

    @discardableResult
    public static func fix(_ part: CarPart, slot: Int, progress p: inout PlayerProgress, now: Date = Date()) -> Int? {
        guard p.garage.indices.contains(slot) else { return nil }
        let car = p.garage[slot]
        guard let item = report(car).first(where: { $0.part == part }), item.cost > 0, p.credits >= item.cost else { return nil }
        p.credits -= item.cost
        p.books.record(-item.cost, .upgrades, "Mechanic: \(part.name) on the \(car.model.spec.displayName)", on: now)
        var wear = car.wear ?? CarWear()
        wear.fix(part)
        p.garage[slot].wear = wear.parts.isEmpty ? nil : wear
        return item.cost
    }

    // MARK: Ask Dex

    public static let instructions = """
    You are Dex, the friendly mechanic in the player's garage in the video game Neon Getaway.
    Teach how car parts work, what needs fixing on the player's car and why, and which shops in Port Aurora or Solara State to visit.
    Use only the FACTS and CAR REPORT you are given. Never invent prices, shops or features.
    If asked about anything outside cars or the game, say you only know cars and the garage.
    Answer in two to four short sentences, warm and plain-spoken, like a good mechanic explaining to a customer. Use "cr" for credits.
    """

    public static func brief(_ car: OwnedVehicle) -> String {
        var lines = ["Car: \(car.model.spec.displayName) (\(CarLineup.brand(car.model).rawValue))."]
        for item in report(car) {
            lines.append("\(item.part.name): \(item.condition) (\(Int(item.wear * 100))% worn), fix \(item.cost) cr.")
        }
        lines.append("Shops: " + recommendations(car).map { "\($0.name) in \($0.place)" }.joined(separator: "; ") + ".")
        return lines.joined(separator: "\n")
    }

    public static func prompt(_ question: String, car: OwnedVehicle) -> String {
        let facts = CarPart.allCases.map { "- \($0.name): \($0.howItWorks) \($0.whyFix)" }.joined(separator: "\n")
        return "FACTS:\n\(facts)\n\nCAR REPORT:\n\(brief(car))\n\nQUESTION: \(question)"
    }

    public static let suggestions = ["What needs fixing?", "How do brakes work?", "Why change the oil?",
                                     "Where should I get it painted?", "How do tyres grip?", "Where for bodywork?"]

    /// Dex without the on-device model.
    public static func answer(_ question: String, car: OwnedVehicle) -> String {
        let q = Atlas.normalise(question)
        if q.contains("fix") || q.contains("wrong") || q.contains("repair") || q.contains("check") || q.contains("service") {
            return greeting(car)
        }
        if q.contains("paint") || q.contains("wrap") || q.contains("color") || q.contains("colour") {
            let paint = shops.filter { $0.kind == .paint }
            return "For paint: " + paint.map { "\($0.name) (\($0.place)): \($0.pitch)" }.joined(separator: " ")
        }
        if q.contains("body") || q.contains("dent") || q.contains("crash") || q.contains("collision") {
            let s = shops.first { $0.kind == .collision }!
            return "For bodywork go to \(s.name) in \(s.place). \(s.pitch) I can also do panels here: \(report(car).first { $0.part == .body }!.cost) cr right now."
        }
        if q.contains("rim") || q.contains("wheel") {
            let s = shops.first { $0.kind == .wheels }!
            return "Rims are in the Wheels tab here in the garage. For tyres and alignment on the road, \(s.name) in \(s.place) is the best."
        }
        for part in CarPart.allCases {
            let words = [part.rawValue, part.name.lowercased(), String(part.rawValue.dropLast())] + (part == .tires ? ["tire", "tyre", "grip"] : []) + (part == .oil ? ["oil change"] : [])
            if words.contains(where: { q.contains($0) }) {
                return part.howItWorks + " " + part.whyFix
            }
        }
        if Atlas.looksOffTopic(" \(q) ") { return "I only know cars and the garage. Ask me about a part, or what your car needs." }
        return "Ask me about oil, tyres, brakes, the engine, suspension or bodywork, or where to take the car for paint."
    }
}
