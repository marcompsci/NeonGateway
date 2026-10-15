import Foundation

/// One thing Atlas, the phone's assistant, knows. Atlas answers only from these facts and the
/// player's own progress: nothing from the outside world.
public struct AtlasFact: Sendable, Equatable, Identifiable {
    public let id: String
    /// Short heading ("Freight hauls").
    public let topic: String
    /// Words a question might use for this fact (lower case).
    public let keywords: [String]
    public let text: String

    public init(id: String, topic: String, keywords: [String], text: String) {
        self.id = id
        self.topic = topic
        self.keywords = keywords
        self.text = text
    }
}

/// Everything Atlas is allowed to know.
///
/// **Studio notes** are the list you control: add a fact there and Atlas can talk about it; take
/// one out and it can't. The rule facts below are built from the game's own numbers so they stay
/// right when the balance changes.
public enum AtlasKnowledge {
    /// Hand-written by the studio. Edit freely: id must be unique, keywords lower case.
    public static let studioNotes: [AtlasFact] = [
        AtlasFact(id: "note.welcome", topic: "About Neon Getaway",
                  keywords: ["game", "about", "what is", "neon getaway", "help", "start", "new"],
                  text: "Neon Getaway is about building a life in Port Aurora: take driving jobs, earn credits, buy businesses, save at Harbor Savings, and climb the weekly league. Start with jobs under Play, then buy a Taco truck when you can."),
        AtlasFact(id: "note.priorities", topic: "What to do first",
                  keywords: ["first", "begin", "beginner", "best way", "tips", "advice", "strategy", "should i"],
                  text: "A good order: finish a few jobs, keep a cushion of cash for tickets, put spare money in Harbor Savings, then buy your first business. Collect tills before they fill, and upgrade the business with the best payback."),
        AtlasFact(id: "note.safety", topic: "Playing safely",
                  keywords: ["online", "stranger", "report", "block", "safe", "chat"],
                  text: "Online, other players only see your name, car and designs. You can block or report anyone from their design in the market. Atlas never asks for personal details and never needs them.")
    ]

    /// The game's rules, written from the live numbers.
    public static var rules: [AtlasFact] {
        var facts: [AtlasFact] = [
            AtlasFact(id: "rule.jobs", topic: "Jobs",
                      keywords: ["job", "jobs", "mission", "missions", "play", "work", "earn", "money", "credits"],
                      text: "Jobs are under Play. Each one pays credits and reputation; harder jobs unlock as your reputation level rises. The Job of the day pays double once a day."),
            AtlasFact(id: "rule.streak", topic: "Daily streak",
                      keywords: ["streak", "daily", "bonus", "shield", "every day"],
                      text: "Finish any job each day to grow your streak. Day 1 pays \(Daily.streakBonuses[0]) cr, rising to \(Daily.streakBonuses.last ?? 0) cr from day \(Daily.streakBonuses.count). Miss a day and it starts over unless you have a streak shield."),
            AtlasFact(id: "rule.bank", topic: "Harbor Savings",
                      keywords: ["bank", "save", "savings", "interest", "deposit", "withdraw"],
                      text: "Harbor Savings pays \(Int(Bank.dailyRate * 100))% a day, compounded, on up to \(Bank.interestCap.formatted()) cr. Interest builds for at most \(Bank.maxCatchUpDays) days while you're away. Cash in your pocket earns nothing and pays tickets; savings are safe."),
            AtlasFact(id: "rule.business", topic: "Businesses",
                      keywords: ["business", "businesses", "property", "biz", "buy", "till", "tills", "collect", "upgrade", "passive", "income"],
                      text: "Businesses take money every real hour, even with the game closed, and hold the profit in a till. Tills fill after \(Int(Properties.tillHours[0])) hours at level 1 (\(Int(Properties.tillHours[2])) at level \(Properties.maxLevel)), then stop, so collect often. Upgrades multiply takings by \(Properties.levelRevenue[1])× and \(Properties.levelRevenue[2])×. Selling returns \(Int(Properties.resaleShare * 100))% of what you put in."),
            AtlasFact(id: "rule.ledger", topic: "The ledger",
                      keywords: ["ledger", "profit", "expenses", "margin", "books", "spent", "income"],
                      text: "The Ledger app records every credit in and out. Profit is income minus everyday costs; buying businesses counts as investing, not spending."),
            AtlasFact(id: "rule.league", topic: "Weekly league",
                      keywords: ["league", "rank", "division", "week", "weekly", "prize", "promotion"],
                      text: "The league ranks what you earn each week against rivals in your division. Finish high to win a prize and move up a division; the week resets every Monday."),
            AtlasFact(id: "rule.heat", topic: "Heat and Harbor Patrol",
                      keywords: ["heat", "police", "patrol", "harbor patrol", "wanted", "stars", "busted", "ticket", "escape", "chase"],
                      text: "Heat rises when Harbor Patrol sees you hit things or drive into restricted areas. \(HeatRules.labels.count - 1) stars run from \(HeatRules.labels[1]) to \(HeatRules.labels.last ?? ""). Break line of sight for \(Int(HeatRules.graceSeconds)) seconds and heat starts falling. Caught with low heat you get a ticket; with high heat, you're busted."),
            AtlasFact(id: "rule.challenge", topic: "Street Challenge",
                      keywords: ["challenge", "street challenge", "ghost", "nova", "medal", "race", "gold", "silver", "bronze"],
                      text: "The Street Challenge is a weekly route against \(StreetChallenge.rivalName)'s ghost. Bronze pays \(Medal.bronze.bonus) cr, silver \(Medal.silver.bonus) and gold \(Medal.gold.bonus); beat \(StreetChallenge.rivalName)'s time for gold. The route changes every week."),
            AtlasFact(id: "rule.radio", topic: "Aurora FM",
                      keywords: ["radio", "music", "song", "songs", "playlist", "aurora fm", "apple music"],
                      text: "Aurora FM plays on shuffle from the Radio app and reshuffles each time the playlist ends. Tap + on a song to add it in Apple Music. It needs Apple Music access in Settings."),
            AtlasFact(id: "rule.solara", topic: "Solara State",
                      keywords: ["solara", "state", "road trip", "city", "cities", "travel", "drive", "highway", "map"],
                      text: "Solara State is the big map under Play: \(SolaraState.cities.count) cities joined by highways, with landmarks and parks between them. Cities: \(SolaraState.cities.map(\.name).joined(separator: ", ")). Each city has a freight depot with a job board."),
            AtlasFact(id: "rule.depots", topic: "Depot jobs",
                      keywords: ["depot", "board", "courier", "city run", "delivery", "deliver", "deliveries", "parcel"],
                      text: "Stop slowly inside a depot and tap Jobs. Courier runs take a parcel to a landmark; city runs go to another city's depot. Both are timed, and finishing with 40% of the clock left adds a fifth to the pay. Pay grows with distance."),
            AtlasFact(id: "rule.freight", topic: "Freight hauls",
                      keywords: ["freight", "truck", "rig", "diesel", "haul", "hauler", "long", "semi", "big delivery", "ride home", "motorcycle", "bike"],
                      text: "Freight hauls lend you a diesel rig at the depot and pay the most, with an ammo crate on top. There's no clock, but damage to the rig comes off the pay (up to half), and a wrecked rig fails the job. Stay in the rig to deliver. At the other end a car and a motorbike wait in the yard: take either and drive to any city."),
            AtlasFact(id: "rule.landmarks", topic: "Landmarks",
                      keywords: ["landmark", "landmarks", "park", "parks", "national park", "sights", "scenic"],
                      text: "Solara's landmarks: \(Set(SolaraState.landmarks.map(\.name)).sorted().joined(separator: ", ")). Courier jobs often deliver to them.")
        ]
        facts.append(AtlasFact(id: "rule.cars", topic: "Buying cars",
                               keywords: ["car", "cars", "dealership", "dealer", "buy a car", "exclusive", "legendary", "classic", "brand", "supercar"],
                               text: "The Dealership in the garage sells cars from Kaze, Ironside, Halcyon, Brisa, Volta and Corvane. Exclusive builds are one each and need reputation. Legendary classics can't be bought: win Street Challenge golds (1, 3 and 5) to claim them. You can keep \(GarageRules.slots) cars."))
        facts.append(AtlasFact(id: "rule.mechanic", topic: "The mechanic",
                               keywords: ["mechanic", "dex", "repair", "fix", "wear", "oil", "tyres", "tires", "brakes", "rims", "wheels"],
                               text: "Driving wears your car: oil, tyres, brakes, engine, suspension and body. Worn parts make it slower, slide more and stop later. Dex, the garage mechanic, shows each part, explains how it works, fixes it for credits and recommends body and paint shops around Solara. Rims are in the garage's Wheels section."))
        facts.append(AtlasFact(id: "rule.fists", topic: "Fist fights",
                               keywords: ["punch", "fight", "fists", "hook", "melee", "hit"],
                               text: "On foot you can throw a left hook, a right hook or a quick punch. Two hooks or three punches knock someone down. Hitting people is a crime if someone sees it, and punching an officer makes them open fire."))
        let shops = PropertyID.allCases.map { id -> String in
            let s = id.spec
            return "\(s.name): \(s.price.formatted()) cr, about \(Int(s.profitPerHour)) cr profit an hour, rep level \(s.requiredRepLevel)"
        }
        facts.append(AtlasFact(id: "rule.shops", topic: "Businesses for sale",
                               keywords: ["taco", "car wash", "laundromat", "print", "arcade", "price", "cost", "cheapest", "which business", "payback"],
                               text: shops.joined(separator: ". ") + "."))
        let skills = Skill.allCases.map { "\($0.name) (\($0.effect)): \($0.howToTrain.lowercased())" }
        facts.append(AtlasFact(id: "rule.skills", topic: "Skills",
                               keywords: ["skill", "skills", "level up", "driving skill", "shooting", "stamina", "hustle", "train"],
                               text: "Skills grow as you play. " + skills.joined(separator: " ")))
        return facts
    }

    /// Everything Atlas may use: the rules plus the studio's notes.
    public static var all: [AtlasFact] { rules + studioNotes }
}

/// What the player is doing right now, as the game sees it.
public struct AtlasContext: Sendable, Equatable {
    /// "Freight haul: Solar panels to Cinder Flats".
    public var activity: String?
    /// "12.4 km NE" or "320 m N".
    public var target: String?
    /// "Solara State" or "Port Aurora".
    public var place: String?

    public init(activity: String? = nil, target: String? = nil, place: String? = nil) {
        self.activity = activity
        self.target = target
        self.place = place
    }
}

/// Atlas, the assistant on the player's phone. The app asks Apple's on-device model when it can,
/// using `instructions` and `brief`; otherwise `answer` replies from the facts by itself.
public enum Atlas {
    public static let name = "Atlas"

    public static let suggestions = [
        "How is my business doing?",
        "What should I do next?",
        "How do freight hauls work?",
        "Where am I headed?",
        "How does the bank work?",
        "Which business should I buy?"
    ]

    /// The model's standing orders. Facts and the player's state follow in the prompt.
    public static let instructions = """
    You are Atlas, the assistant on the player's phone in the video game Neon Getaway.
    Only talk about Neon Getaway: its jobs, businesses, money, league, skills, Solara State and the player's progress.
    Use only the FACTS and PLAYER STATE you are given. If they don't cover a question, say you don't know that yet.
    If asked about anything outside the game, politely say you can only help with Neon Getaway.
    Never ask for or discuss personal information. Never invent places, prices or features.
    Answer in two to four short sentences, friendly and direct. Use "cr" for credits.
    """

    /// The player's state in plain lines, for the model and for the fallback.
    public static func brief(_ p: PlayerProgress, context: AtlasContext? = nil, now: Date = Date()) -> String {
        let s = DashboardSummary(p, now: now)
        var lines = [
            "Cash: \(p.credits) cr. Savings: \(p.bank.balance) cr. Net worth: \(s.netWorth) cr.",
            "Reputation level \(s.repLevel). Jobs done: \(p.completedJobs).",
            "League: \(p.league.division.name) division, \(p.league.earnings) cr earned this week.",
            "Ledger: income \(p.books.income) cr, costs \(p.books.expenses) cr, profit \(p.books.profit) cr."
        ]
        if p.properties.isEmpty {
            lines.append("Businesses: none yet.")
        } else {
            for b in s.businesses {
                lines.append("Business \(b.name) level \(b.level): till holds \(b.tillProfit) cr\(b.tillFull ? " (full)" : ""), about \(b.profitPerHour) cr an hour.")
            }
        }
        if let next = s.nextBusiness {
            lines.append("Next business to buy: \(next.spec.name) for \(next.spec.price) cr (needs rep level \(next.spec.requiredRepLevel)).")
        }
        if let c = context {
            if let place = c.place { lines.append("Location: \(place).") }
            if let a = c.activity { lines.append("Doing now: \(a).") }
            if let t = c.target { lines.append("Target: \(t).") }
        }
        return lines.joined(separator: "\n")
    }

    /// The facts most related to a question, best first.
    public static func relevant(to question: String, in facts: [AtlasFact] = AtlasKnowledge.all, limit: Int = 4) -> [AtlasFact] {
        let q = " " + normalise(question) + " "
        let scored = facts.map { fact -> (AtlasFact, Int) in
            var score = 0
            for k in fact.keywords where q.contains(" " + k + " ") || (k.count > 4 && q.contains(k)) {
                score += k.contains(" ") ? 3 : 2
            }
            if q.contains(fact.topic.lowercased()) { score += 3 }
            return (fact, score)
        }
        return scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// The full prompt for the model: facts, the player's state, then the question.
    public static func prompt(_ question: String, progress: PlayerProgress, context: AtlasContext?,
                              facts: [AtlasFact] = AtlasKnowledge.all, now: Date = Date()) -> String {
        var chosen = relevant(to: question, in: facts, limit: 5)
        if chosen.isEmpty { chosen = facts.filter { $0.id == "note.welcome" || $0.id == "note.priorities" } }
        return """
        FACTS:
        \(chosen.map { "- \($0.topic): \($0.text)" }.joined(separator: "\n"))

        PLAYER STATE:
        \(brief(progress, context: context, now: now))

        QUESTION: \(question)
        """
    }

    /// Atlas without the on-device model: answers about the player's own state directly, else
    /// the best matching fact, else a polite "only Neon Getaway".
    public static func answer(_ question: String, progress p: PlayerProgress, context: AtlasContext? = nil,
                              facts: [AtlasFact] = AtlasKnowledge.all, now: Date = Date()) -> String {
        let q = " " + normalise(question) + " "
        func has(_ words: String...) -> Bool { words.contains { q.contains(" " + $0 + " ") || ($0.count > 5 && q.contains($0)) } }
        let s = DashboardSummary(p, now: now)

        if has("where", "headed", "heading", "destination", "how far", "lost", "direction", "current job", "my job", "my mission") {
            if let a = context?.activity {
                return "You're on \(a)" + (context?.target.map { ". It's \($0) from here; follow the teal marker." } ?? ".")
            }
            if context?.place == "Solara State" {
                return "No job right now. Head to any city's freight depot, stop inside slowly, and tap Jobs to see the board."
            }
        }
        if has("how is my business", "my business", "my businesses", "tills", "till", "collect") {
            if p.properties.isEmpty {
                return "You don't own a business yet. " + (s.nextBusiness.map { "The \($0.spec.name) costs \($0.spec.price.formatted()) cr; you have \(p.credits.formatted()) cr." } ?? "")
            }
            let full = s.businesses.filter(\.tillFull).map(\.name)
            var reply = "You own \(p.properties.count) business\(p.properties.count == 1 ? "" : "es") making about \(s.profitPerHour) cr an hour. Tills hold \(s.tillsWaiting.formatted()) cr right now."
            reply += full.isEmpty ? " None are full yet." : " Full: \(full.joined(separator: ", ")). Collect from the Biz app so nothing is wasted."
            return reply
        }
        if has("how much money", "my money", "my cash", "net worth", "how rich", "balance", "how am i doing") {
            return "You have \(p.credits.formatted()) cr in cash and \(p.bank.balance.formatted()) cr saved. Net worth is \(s.netWorth.formatted()) cr, and you've earned \(p.league.earnings.formatted()) cr this week in the \(p.league.division.name) league."
        }
        if has("what should i do", "do next", "what now", "next step", "bored", "suggest") {
            return nextStep(p, summary: s, context: context)
        }
        if has("which business", "what business", "should i buy", "next business") {
            if let next = s.nextBusiness {
                let short = next.spec.price - p.credits
                return "Next up is the \(next.spec.name) at \(next.spec.price.formatted()) cr" + (short > 0 ? ": you're \(short.formatted()) cr short." : ", and you can afford it now.") + " It makes about \(Int(next.spec.profitPerHour)) cr an hour at level 1."
            }
            return "You own every business. Upgrades are the best use of money now."
        }
        if let fact = relevant(to: question, in: facts, limit: 1).first {
            return fact.text
        }
        if looksOffTopic(q) {
            return "I can only help with Neon Getaway: your jobs, businesses, money and trips around Solara. Try asking what to do next."
        }
        return "I don't know that one yet. Ask me about jobs, your businesses, the bank, the league or Solara State."
    }

    static func nextStep(_ p: PlayerProgress, summary s: DashboardSummary, context: AtlasContext?) -> String {
        if let a = context?.activity { return "Finish what you're on: \(a)." }
        if !s.businesses.filter(\.tillFull).isEmpty { return "Your tills are full. Collect from the Biz app first, then take a job." }
        if let next = s.nextBusiness, p.credits >= next.spec.price, s.repLevel >= next.spec.requiredRepLevel {
            return "You can afford the \(next.spec.name) (\(next.spec.price.formatted()) cr). Buying it adds about \(Int(next.spec.profitPerHour)) cr an hour."
        }
        if p.credits > 3_000 && p.bank.balance < Bank.interestCap {
            return "Put some cash in Harbor Savings: it earns \(Int(Bank.dailyRate * 100))% a day and is safe from tickets."
        }
        if context?.place == "Solara State" {
            return "Pick up a freight haul at the nearest depot: it pays the most, and a car and bike wait for the drive back."
        }
        return "Take a job under Play. The Job of the day pays double, and any job keeps your daily streak going."
    }

    private static let offTopicWords = ["weather", "news", "president", "homework", "recipe", "stock", "bitcoin", "address",
                                        "phone number", "password", "real life", "football", "movie"]

    static func looksOffTopic(_ q: String) -> Bool { offTopicWords.contains { q.contains($0) } }

    static func normalise(_ s: String) -> String {
        s.lowercased().map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }
}

/// The phone's Dashboard: the business at a glance.
public struct DashboardSummary: Sendable, Equatable {
    public struct Business: Sendable, Equatable, Identifiable {
        public let id: PropertyID
        public let name: String
        public let level: Int
        public let tillProfit: Int
        public let tillFull: Bool
        /// 0...1 of the till's capacity.
        public let tillFill: Double
        public let profitPerHour: Int
        public let lifetimeProfit: Int
    }

    public let netWorth: Int
    public let worth: NetWorth.Breakdown
    public let repLevel: Int
    public let businesses: [Business]
    public let profitPerHour: Int
    public let tillsWaiting: Int
    /// The cheapest business not yet owned.
    public let nextBusiness: PropertyID?
    /// Recent ledger entries, newest first.
    public let recent: [LedgerEntry]
    /// Income by category this session of the ledger, largest first.
    public let incomeMix: [(LedgerCategory, Int)]

    public init(_ p: PlayerProgress, now: Date = Date()) {
        worth = NetWorth.breakdown(p)
        netWorth = worth.total
        repLevel = ProgressionRules.level(forXP: p.reputationXP)
        let hustle = p.skills.level(.hustle)
        businesses = p.properties.map { o in
            let till = Properties.till(o, hustle: hustle, now: now)
            let cap = Properties.tillHours[o.level - 1]
            return Business(id: o.kind, name: o.kind.spec.name, level: o.level, tillProfit: till.profit,
                            tillFull: till.isFull, tillFill: min(1, till.hours / cap),
                            profitPerHour: Int(Properties.profitPerHour(o.kind, level: o.level, hustle: hustle)),
                            lifetimeProfit: o.lifetimeProfit)
        }
        profitPerHour = businesses.reduce(0) { $0 + $1.profitPerHour }
        tillsWaiting = businesses.reduce(0) { $0 + $1.tillProfit }
        nextBusiness = PropertyID.allCases.filter { Properties.owned($0, in: p) == nil }.min { $0.spec.price < $1.spec.price }
        recent = Array(p.books.entries.suffix(6).reversed())
        incomeMix = LedgerCategory.allCases.filter(\.isIncome).map { ($0, p.books.total($0)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }

    public static func == (a: DashboardSummary, b: DashboardSummary) -> Bool {
        a.netWorth == b.netWorth && a.businesses == b.businesses && a.recent == b.recent
    }
}
