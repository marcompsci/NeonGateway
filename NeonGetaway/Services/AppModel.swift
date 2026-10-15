import SwiftUI
import GameCore

/// App-wide state: saved progress and settings, plus shared services. Saves to UserDefaults
/// through `SaveCodec`; a CloudKit store can later sit behind the same load/save calls.
@MainActor
@Observable
final class AppModel {
    static let progressKey = "neon.progress.v1"
    static let settingsKey = "neon.settings.v1"

    private let defaults: UserDefaults
    let haptics = HapticsService()
    let audio = SynthAudio()
    let gameCenter = GameCenterService()
    let market = CloudMarket()
    let live = LiveMatchService()
    /// Aurora FM (Apple Music through MusicKit).
    let radio = RadioService()
    let atlas = AtlasService()

    var progress: PlayerProgress {
        didSet { save(progress, key: Self.progressKey) }
    }

    var settings: GameSettings {
        didSet {
            save(settings, key: Self.settingsKey)
            haptics.enabled = settings.hapticsOn
            audio.enabled = settings.soundOn
            radio.enabled = settings.radioOn
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        progress = SaveCodec.loadProgress(from: defaults.data(forKey: Self.progressKey))
        settings = SaveCodec.loadSettings(from: defaults.data(forKey: Self.settingsKey))
        haptics.enabled = settings.hapticsOn
        audio.enabled = settings.soundOn
        radio.enabled = settings.radioOn
    }

    var repLevel: Int { ProgressionRules.level(forXP: progress.reputationXP) }

    // MARK: Solara State

    /// A delivered Solara job: pay, reputation and a line in the ledger.
    func recordStateJob(_ job: StateJob, payout: StatePayout) {
        var p = progress
        p.reputationXP += payout.repXP
        p.earn(payout.credits, .jobPay, job.title(in: SolaraState.district))
        p.completedJobs += 1
        p.lastUpdated = Date()
        progress = p
        gameCenter.submit(OnlineBoards.scores(progress))
    }

    // MARK: Street Challenge

    @ObservationIgnored private var rivalCache: (week: Int, ghost: Ghost)?

    var challengeWeek: Int { StreetChallenge.week(of: Date()) }

    /// This week's Nova run (worked out once per week, then kept).
    func challengeRival() -> Ghost {
        let week = challengeWeek
        if let cached = rivalCache, cached.week == week { return cached.ghost }
        let ghost = StreetChallenge.rival(for: StreetChallenge.def(week: week))
        rivalCache = (week, ghost)
        return ghost
    }

    var challengeState: ChallengeState { StreetChallenge.state(week: challengeWeek, progress: progress) }

    /// Nova in magenta, and your best this week in teal.
    func challengeGhostCars() -> [DriveScene.GhostCar] {
        var cars = [DriveScene.GhostCar(ghost: challengeRival(), label: StreetChallenge.rivalName,
                                        tint: Palette.UI.magenta)]
        if let best = challengeState.ghost {
            cars.append(DriveScene.GhostCar(ghost: best, label: "Your best", tint: Palette.UI.teal))
        }
        return cars
    }

    func recordChallenge(time: Double, ghost: Ghost) -> StreetChallenge.Outcome {
        var p = progress
        let outcome = StreetChallenge.record(time: time, ghost: ghost, rivalTime: challengeRival().duration,
                                             week: challengeWeek, progress: &p)
        progress = p
        return outcome
    }

    func recordChallengeAttempt() {
        var p = progress
        StreetChallenge.recordAttempt(week: challengeWeek, progress: &p)
        progress = p
    }

    /// Paint on the car the player starts runs in.
    var selectedDesign: PaintDesign? {
        let garage = progress.garage
        guard garage.indices.contains(progress.selectedVehicle),
              let id = garage[progress.selectedVehicle].design else { return nil }
        return BodyShop.design(id, progress: progress)
    }

    /// What the design market sold after the last job (shown on the results screen).
    private(set) var lastMarketReport: BodyShop.Report?
    /// Streak and Job-of-the-day bonuses from the last job (shown on the results screen).
    private(set) var lastDaily: Daily.Update?

    // MARK: Online

    /// The player's online id (Game Center), or nil when offline.
    var onlineID: String? { gameCenter.isAuthenticated ? gameCenter.playerID : nil }

    /// What the online market paid out since the last check (shown once on the menu).
    private(set) var lastOnlinePayout: OnlineMarket.Payout?

    /// Posts scores and collects online design sales. Safe to call often; does nothing offline.
    func syncOnline() async {
        guard let id = onlineID else { return }
        gameCenter.submit(OnlineBoards.scores(progress))
        guard !progress.online.published.isEmpty, let sales = await market.sales(of: id) else { return }
        var p = progress
        let payout = OnlineMarket.collectSales(sales, myID: id, progress: &p)
        if payout.sales > 0 {
            progress = p
            lastOnlinePayout = payout
            haptics.success()
        }
    }

    func takeOnlinePayout() -> OnlineMarket.Payout? {
        defer { lastOnlinePayout = nil }
        return lastOnlinePayout
    }

    /// Buys another player's design. The purchase record (which pays the creator) is written
    /// first; credits only leave once it's saved. Returns a problem to show, or nil.
    func buyOnline(_ design: MarketDesign) async -> String? {
        guard let id = onlineID else { return "Sign in to Game Center to buy online." }
        var check = progress
        if let refusal = OnlineMarket.buy(design, myID: id, progress: &check) { return Self.text(refusal) }
        guard await market.recordPurchase(design, buyerID: id) else {
            haptics.failure()
            return "Couldn't reach the market. Nothing was charged."
        }
        var p = progress
        if let refusal = OnlineMarket.buy(design, myID: id, progress: &p) { return Self.text(refusal) }
        progress = p
        haptics.success()
        return nil
    }

    /// Publishes one of the player's own designs for everyone (Legendary only).
    func publishOnline(_ localID: String, price: Int) async -> String? {
        guard let id = onlineID else { return "Sign in to Game Center to sell online." }
        if let refusal = OnlineMarket.checkPublish(localID, price: price, progress: progress) { return Self.text(refusal) }
        guard let design = progress.designs.first(where: { $0.id == localID }) else { return "Design not found." }
        let name = progress.profile?.name ?? gameCenter.displayName ?? "Driver"
        guard let record = await market.publish(design, price: price, creatorID: id, creatorName: name) else {
            return "Couldn't reach the market. Try again."
        }
        OnlineMarket.markPublished(localID, record: record, progress: &progress)
        haptics.success()
        await market.refresh()
        return nil
    }

    func reportOnline(_ design: MarketDesign, reason: OnlineMarket.ReportReason) async -> Bool {
        guard let id = onlineID else { return false }
        var p = progress
        guard OnlineMarket.markReported(design.id, progress: &p) else { return true }
        guard await market.report(design, reason: reason, reporterID: id) else { return false }
        progress = p
        return true
    }

    func block(_ playerID: String) {
        OnlineMarket.block(playerID, progress: &progress)
    }

    func unblock(_ playerID: String) {
        OnlineMarket.unblock(playerID, progress: &progress)
    }

    func recordLive(_ event: LiveCoordinator.LiveEvent) {
        switch event {
        case .knockedOutSomeone: progress.online.knockouts += 1
        case .tookGun: progress.online.gunsTaken += 1
        case .lostGun: break
        }
    }

    static func text(_ refusal: OnlineMarket.Refusal) -> String {
        switch refusal {
        case .notEnoughCredits(let needed): "You need \(needed) more credits."
        case .alreadyOwned: "You already own it."
        case .ownDesign: "That's your own design."
        case .hidden: "That design isn't available."
        case .notLegendary: "Reach Legendary rank to sell online."
        case .badName: "That name can't be shown to other players. Rename it in the studio."
        case .badDesign: "That design can't be published."
        case .badPrice: "Pick a price from \(BodyShop.priceRange.lowerBound) to \(BodyShop.priceRange.upperBound)."
        case .alreadyPublished: "It's already on the online market."
        }
    }

    // MARK: Money: league, bank, businesses, trophies

    /// Settles a finished league week and pays any savings interest. Called when the menus
    /// appear, so a week that ended while the app was closed is settled on return.
    func refreshEconomy(now: Date = Date()) {
        var p = progress
        League.refresh(&p, now: now)
        Bank.accrue(&p, now: now)
        if p != progress { progress = p }
    }

    /// The league result the player hasn't seen yet; clears once shown.
    func takeLeagueResult() -> LeagueResult? {
        guard let result = progress.league.unseen else { return nil }
        progress.league.unseen = nil
        return result
    }

    @discardableResult
    func deposit(_ amount: Int) -> Bank.Refusal? {
        var p = progress
        let refusal = Bank.deposit(amount, progress: &p)
        if refusal == nil { progress = p; haptics.success() } else { haptics.failure() }
        return refusal
    }

    @discardableResult
    func withdraw(_ amount: Int) -> Bank.Refusal? {
        var p = progress
        let refusal = Bank.withdraw(amount, progress: &p)
        if refusal == nil { progress = p; haptics.success() } else { haptics.failure() }
        return refusal
    }

    @discardableResult
    func buyProperty(_ id: PropertyID) -> Properties.Refusal? {
        var p = progress
        let refusal = Properties.buy(id, progress: &p)
        if refusal == nil { progress = p; haptics.success() } else { haptics.failure() }
        return refusal
    }

    @discardableResult
    func upgradeProperty(_ id: PropertyID) -> Properties.Refusal? {
        var p = progress
        let refusal = Properties.upgrade(id, progress: &p)
        if refusal == nil { progress = p; haptics.success() } else { haptics.failure() }
        return refusal
    }

    @discardableResult
    func collect(_ id: PropertyID) -> Properties.Till? {
        var p = progress
        let till = Properties.collect(id, progress: &p)
        progress = p
        if till != nil { haptics.success(); audio.play(.pickup) }
        return till
    }

    @discardableResult
    func collectAll() -> Properties.Till {
        var p = progress
        let till = Properties.collectAll(progress: &p)
        progress = p
        if till.revenue > 0 { haptics.success(); audio.play(.pickup) }
        return till
    }

    @discardableResult
    func sellProperty(_ id: PropertyID) -> Int? {
        var p = progress
        let value = Properties.sell(id, progress: &p)
        progress = p
        if value != nil { haptics.success() }
        return value
    }

    @discardableResult
    func claimTrophy(_ id: String) -> Achievements.Refusal? {
        var p = progress
        let refusal = Achievements.claim(id, progress: &p)
        if refusal == nil { progress = p; haptics.success(); audio.play(.success) } else { haptics.failure() }
        return refusal
    }

    /// A Harbor Patrol ticket. Paid from cash, then savings; whatever can't be paid is waived.
    /// Returns what was paid.
    @discardableResult
    func payTicket() -> Int {
        var p = progress
        let fine = Pursuit.ticketFine
        let fromCash = min(p.credits, fine)
        let fromSavings = min(p.bank.balance, fine - fromCash)
        p.credits -= fromCash
        p.bank.balance -= fromSavings
        let paid = fromCash + fromSavings
        if paid > 0 { p.books.record(-paid, .fines, "Harbor Patrol ticket") }
        p.career.tickets += 1
        progress = p
        return paid
    }

    /// Skill XP for what the player did on the street.
    func award(_ stats: RunStats) {
        guard stats.driven > 0 || stats.run > 0 || stats.hitsLanded > 0 else { return }
        var p = progress
        Skills.award(stats, to: &p)
        // Miles and knocks wear the car you took out (the mechanic fixes it).
        if p.garage.indices.contains(p.selectedVehicle), stats.driven > 0 || stats.knocks > 0 {
            var wear = p.garage[p.selectedVehicle].wear ?? CarWear()
            wear.add(driven: stats.driven, knocks: stats.knocks)
            p.garage[p.selectedVehicle].wear = wear
        }
        if p != progress { progress = p }
    }

    func recordPhoto() {
        progress.career.photos += 1
    }

    /// Weather and light for a new trip: the player's real clock, or a clear day if they
    /// turned live weather off.
    func conditions(now: Date = Date()) -> (Weather, TimeOfDay) {
        if let forced = DebugLaunch.timeOfDay { return (.clear, forced) }
        guard settings.liveWeather else { return (.clear, .day) }
        let hour = Calendar.current.component(.hour, from: now)
        // The same hour of the same day always has the same weather.
        let seed = UInt64(max(0, GameClock.day(now))) &* 24 &+ UInt64(hour)
        return (Weather.roll(seed: seed), TimeOfDay.at(hour: hour))
    }

    // MARK: Workbench and body shop

    @discardableResult
    func fit(_ part: GunPart?, slot: GunPart.Slot, on weapon: WeaponID) -> Workbench.Refusal? {
        var p = progress
        let refusal = Workbench.fit(part, slot: slot, on: weapon, progress: &p)
        if refusal == nil { progress = p; haptics.success() } else { haptics.failure() }
        return refusal
    }

    @discardableResult
    func paint(_ weapon: WeaponID, finish: Int) -> Workbench.Refusal? {
        var p = progress
        let refusal = Workbench.paint(weapon, finish: finish, progress: &p)
        if refusal == nil { progress = p; haptics.tick() } else { haptics.failure() }
        return refusal
    }

    @discardableResult
    func buyDesign(_ id: String) -> BodyShop.Refusal? {
        var p = progress
        let refusal = BodyShop.buy(id, progress: &p)
        if refusal == nil { progress = p; haptics.success() } else { haptics.failure() }
        return refusal
    }

    func applyDesign(_ id: String?, toSlot slot: Int) {
        var p = progress
        if BodyShop.apply(id, toSlot: slot, progress: &p) == nil {
            progress = p
            haptics.tick()
        }
    }

    func createDesign(name: String, cells: [UInt8]) -> Result<PaintDesign, BodyShop.Refusal> {
        var p = progress
        let result = BodyShop.create(name: name, cells: cells, progress: &p)
        if case .success = result { progress = p; haptics.success() } else { haptics.failure() }
        return result
    }

    @discardableResult
    func listDesign(_ id: String, price: Int) -> BodyShop.Refusal? {
        var p = progress
        let refusal = BodyShop.list(id, price: price, progress: &p)
        if refusal == nil { progress = p; haptics.success() } else { haptics.failure() }
        return refusal
    }

    func unlistDesign(_ id: String) {
        BodyShop.unlist(id, progress: &progress)
    }

    #if DEBUG
    /// Debug launch only: enough reputation to be Legendary.
    func makeLegendaryForTesting() {
        progress.reputationXP = max(progress.reputationXP, 5000)
    }
    #endif

    /// The player's selected car with Garage upgrades applied.
    var playerSpec: VehicleSpec {
        let spec = UpgradeShop.spec(progress.selectedModel.spec, levels: progress.upgrades)
        return selectedCar?.wear?.apply(to: spec) ?? spec
    }
    var selectedCar: OwnedVehicle? {
        progress.garage.indices.contains(progress.selectedVehicle) ? progress.garage[progress.selectedVehicle] : nil
    }

    // MARK: Cars, rims, mechanic

    /// New look from the Style screen (name and starter weapon stay).
    func updateLook(_ look: PlayerProfile) {
        guard var p = progress.profile else { return }
        p.skin = look.skin
        p.hair = look.hair
        p.jacket = look.jacket
        p.hairStyle = look.hairStyle
        p.outfit = look.outfit
        p.build = look.build
        p.frame = look.frame
        p.facialHair = look.facialHair
        progress.profile = p.normalized
    }

    func acquireCar(_ model: VehicleID) -> CarLineup.Refusal? {
        var p = progress
        let refusal = CarLineup.acquire(model, progress: &p)
        if refusal == nil { progress = p }
        return refusal
    }

    func fitRims(_ setup: RimSetup, slot: Int) -> RimShop.Refusal? {
        var p = progress
        let refusal = RimShop.fit(setup, slot: slot, progress: &p)
        if refusal == nil { progress = p }
        return refusal
    }

    func fixPart(_ part: CarPart, slot: Int) -> Int? {
        var p = progress
        let paid = Mechanic.fix(part, slot: slot, progress: &p)
        if paid != nil { progress = p }
        return paid
    }

    // MARK: Gun store

    @discardableResult
    func buyWeapon(_ weapon: WeaponID, from seller: GunSeller = .store) -> GunStore.Refusal? {
        var p = progress
        let refusal = GunStore.buy(weapon, from: seller, progress: &p)
        finish(p, refusal: refusal)
        return refusal
    }

    @discardableResult
    func buyAmmo(_ weapon: WeaponID) -> GunStore.Refusal? {
        var p = progress
        let refusal = GunStore.buyAmmo(weapon, progress: &p)
        finish(p, refusal: refusal)
        return refusal
    }

    @discardableResult
    func buyExtendedMag(_ weapon: WeaponID) -> GunStore.Refusal? {
        var p = progress
        let refusal = GunStore.buyExtendedMag(weapon, progress: &p)
        finish(p, refusal: refusal)
        return refusal
    }

    // MARK: Player

    /// Finishes onboarding: saves the character and hands over the first weapon.
    @discardableResult
    func completeOnboarding(_ draft: PlayerProfile) -> Onboarding.Problem? {
        var p = progress
        let problem = Onboarding.complete(draft, progress: &p)
        if problem == nil {
            progress = p
            haptics.success()
        }
        return problem
    }

    #if DEBUG
    /// Debug launch only: forget the character so onboarding runs again (weapons stay).
    func forgetProfileForTesting() {
        progress.profile = nil
    }
    #endif

    private func finish(_ p: PlayerProgress, refusal: GunStore.Refusal?) {
        if refusal == nil {
            progress = p
            haptics.success()
        } else {
            haptics.failure()
        }
    }

    /// Saves weapons and ammo after a run (or before the shop opens).
    func saveInventory(_ inventory: Inventory) {
        guard progress.inventory != inventory else { return }
        progress.inventory = inventory
    }

    // MARK: Garage

    /// Keeps a street car in the Safehouse garage. False if the garage is full.
    func keepVehicle(_ model: VehicleID) -> Bool {
        var p = progress
        guard GarageRules.keep(model, progress: &p) else { return false }
        progress = p
        return true
    }

    func selectVehicle(slot: Int) {
        guard progress.garage.indices.contains(slot) else { return }
        progress.selectedVehicle = slot
        haptics.tick()
    }

    @discardableResult
    func sellVehicle(slot: Int) -> Int? {
        var p = progress
        guard let paid = GarageRules.sell(slot: slot, progress: &p) else { return nil }
        progress = p
        haptics.success()
        return paid
    }

    /// Buys the next level of an upgrade track if allowed; saves on success.
    @discardableResult
    func buy(_ track: UpgradeTrack) -> Result<UpgradeTier, UpgradeShop.Refusal> {
        var p = progress
        let result = UpgradeShop.buy(track, progress: &p)
        if case .success = result {
            progress = p
            haptics.success()
        } else {
            haptics.failure()
        }
        return result
    }

    /// Folds a finished job into the save (written immediately by `progress.didSet`).
    func record(_ result: MissionResult, def: MissionDef) -> ProgressionRules.Update {
        var p = progress
        let update = ProgressionRules.apply(result, def: def, to: &p)
        let daily = Daily.recordJob(def, success: result.outcome.isSuccess, progress: &p)
        lastDaily = daily.total > 0 ? daily : nil
        // Each finished job is a day on the design market.
        let report = BodyShop.marketDay(&p)
        lastMarketReport = report.isEmpty ? nil : report
        progress = p
        gameCenter.submit(OnlineBoards.scores(progress))
        return update
    }

    /// Reduce Motion from the player's override, else from iOS.
    func reduceMotion(system: Bool) -> Bool {
        settings.reduceMotionOverride ?? system
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = SaveCodec.encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
