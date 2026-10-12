import XCTest
@testable import GameCore

/// Making a player, the five starting weapons, and the 35-round starter limit.
final class OnboardingTests: XCTestCase {
    let district = District.portAuroraDocks
    let dt = VehicleDynamics.fixedStep
    let now = Date(timeIntervalSince1970: 1_900_000_000)

    func at(_ col: Int, _ row: Int) -> Vec2 { district.center(of: TileCoord(col: col, row: row)) }

    // MARK: Profile

    func testNamesAreTidiedAndChecked() {
        XCTAssertEqual(PlayerProfile.cleanName("  Nova   Reyes "), "Nova Reyes")
        XCTAssertEqual(PlayerProfile.cleanName("O'Neil-2"), "O'Neil-2")
        XCTAssertNil(PlayerProfile.cleanName("A"), "too short")
        XCTAssertNil(PlayerProfile.cleanName(String(repeating: "x", count: 17)), "too long")
        XCTAssertNil(PlayerProfile.cleanName("<script>"))
        XCTAssertNil(PlayerProfile.cleanName("--"), "needs a letter or number")
    }

    func testFiveStartingWeaponsOneOfThemMelee() {
        XCTAssertEqual(WeaponID.allCases.count, 5)
        XCTAssertEqual(WeaponID.allCases.filter { $0.spec.isMelee }, [.bat])
        XCTAssertEqual(Set(WeaponID.allCases.map(\.spec.name)).count, 5)
        for weapon in WeaponID.allCases { XCTAssertFalse(weapon.pitch.isEmpty) }
    }

    func testOnboardingCreatesThePlayerAndHandsOverACappedStarterGun() {
        var p = PlayerProgress()
        XCTAssertNil(p.profile)
        let problem = Onboarding.complete(PlayerProfile(name: " Kai ", skin: 7, hair: -1, jacket: 2, starter: .smg),
                                          progress: &p)
        XCTAssertNil(problem)
        XCTAssertEqual(p.profile?.name, "Kai")
        XCTAssertEqual(p.profile?.skin, 2, "kept in range")
        XCTAssertEqual(p.profile?.hair, PlayerProfile.hairCount - 1)
        XCTAssertEqual(p.inventory.equipped, .smg)
        XCTAssertTrue(p.inventory.isCapped(.smg))
        XCTAssertEqual(p.inventory.ammo(for: .smg), Inventory.starterAmmoCap)
        XCTAssertEqual(Onboarding.complete(PlayerProfile(name: "Again"), progress: &p), .alreadyDone)
    }

    func testABadNameStopsOnboarding() {
        var p = PlayerProgress()
        XCTAssertEqual(Onboarding.complete(PlayerProfile(name: "!"), progress: &p), .badName)
        XCTAssertNil(p.profile)
        XCTAssertTrue(p.inventory.owned.isEmpty)
    }

    func testTheBatNeedsNoAmmo() {
        var p = PlayerProgress()
        Onboarding.complete(PlayerProfile(name: "Slugger", starter: .bat), progress: &p)
        XCTAssertTrue(p.inventory.canFire)
        XCTAssertFalse(p.inventory.isCapped(.bat))
        var inv = p.inventory
        for _ in 0..<100 { XCTAssertTrue(inv.consumeRound()) }
        XCTAssertEqual(GunStore.buyAmmo(.bat, progress: &p), .notSoldHere)
    }

    func testAProfileSurvivesASave() {
        var p = PlayerProgress()
        Onboarding.complete(PlayerProfile(name: "Rio", skin: 1, hair: 2, jacket: 3, starter: .rifle), progress: &p)
        XCTAssertEqual(SaveCodec.loadProgress(from: SaveCodec.encode(p)), p)
        var older = PlayerProgress()
        older.credits = 50
        XCTAssertNil(SaveCodec.loadProgress(from: SaveCodec.encode(older)).profile, "no profile → onboarding")
    }

    // MARK: The 35-round limit

    func starter(_ weapon: WeaponID, credits: Int = 5000) -> PlayerProgress {
        var p = PlayerProgress()
        p.credits = credits
        Onboarding.complete(PlayerProfile(name: "Test", starter: weapon), progress: &p)
        return p
    }

    func testStarterAmmoNeverPassesThirtyFive() {
        var p = starter(.pistol)
        XCTAssertEqual(GunStore.buyAmmo(.pistol, progress: &p), .full, "already full at 35")
        p.inventory.ammo["pistol"] = 30
        XCTAssertNil(GunStore.buyAmmo(.pistol, progress: &p))
        XCTAssertEqual(p.inventory.ammo(for: .pistol), 35, "a 24-round pack only tops up to 35")
        p.inventory.add(.pistol, ammo: 500)
        XCTAssertEqual(p.inventory.ammo(for: .pistol), 35)
    }

    func testExtendedMagLiftsTheLimit() {
        var p = starter(.pistol)
        XCTAssertNil(GunStore.buyExtendedMag(.pistol, progress: &p))
        XCTAssertFalse(p.inventory.isCapped(.pistol))
        XCTAssertNil(GunStore.buyAmmo(.pistol, progress: &p))
        XCTAssertEqual(p.inventory.ammo(for: .pistol), 35 + WeaponID.pistol.spec.ammoPack)
        XCTAssertEqual(GunStore.buyExtendedMag(.pistol, progress: &p), .notCapped)
        XCTAssertEqual(p.books.total(.weapons), -GunStore.extendedMagPrice)
    }

    func testBuyingANewCopyLiftsTheLimit() {
        var p = starter(.shotgun)
        XCTAssertNil(GunStore.buy(.shotgun, progress: &p, now: now), "a fresh one replaces the starter")
        XCTAssertFalse(p.inventory.isCapped(.shotgun))
        XCTAssertEqual(GunStore.buy(.shotgun, progress: &p), .alreadyOwned)
    }

    func testTheDealerIsCheaperButSellsNoMods() {
        XCTAssertLessThan(GunSeller.dealer.price(.rifle), GunSeller.store.price(.rifle))
        XCTAssertFalse(GunSeller.dealer.sellsAmmoAndMods)
        var p = starter(.bat, credits: 2000)
        XCTAssertNil(GunStore.buy(.rifle, from: .dealer, progress: &p, now: now))
        XCTAssertEqual(p.credits, 2000 - GunSeller.dealer.price(.rifle))
        XCTAssertFalse(p.inventory.isCapped(.rifle), "a bought gun is a full gun")
    }

    // MARK: Taking guns in the city

    func city(_ inventory: Inventory, at col: Int, _ row: Int, heading: Double = 0,
              dealer: TileCoord? = nil) -> City {
        City(district: district, start: SpawnPoint(position: at(col, row), heading: heading), playerVehicle: nil,
             inventory: inventory, seed: 11, parked: [], pickups: [], dealer: dealer)
    }

    func cappedPistol() -> Inventory {
        var inv = Inventory()
        inv.addStarter(.pistol)
        return inv
    }

    func testPickingUpADroppedPistolLiftsTheStarterLimit() {
        var c = city(cappedPistol(), at: 12, 4)
        c.pickups = [WeaponPickup(id: 5000, weapon: .pistol, ammo: 12, position: at(12, 4), isDrop: true, lifetime: 30)]
        let events = c.step(input: .idle, actions: .init(), dt: dt)
        XCTAssertTrue(events.contains { if case .pickedUp(.pistol, _) = $0 { return true } else { return false } })
        XCTAssertFalse(c.inventory.isCapped(.pistol))
        XCTAssertEqual(c.inventory.ammo(for: .pistol), 35 + 12)
        XCTAssertTrue(c.pickups.isEmpty, "a drop is taken once")
    }

    func testDropsDisappearAfterAWhile() {
        var c = city(Inventory(), at: 12, 4)
        c.pickups = [WeaponPickup(id: 5000, weapon: .smg, ammo: 12, position: at(20, 4), isDrop: true, lifetime: 1)]
        for _ in 0..<70 { _ = c.step(input: .idle, actions: .init(), dt: dt) }
        XCTAssertTrue(c.pickups.isEmpty)
    }

    func testDisabledCruisersDropAGun() {
        var inv = Inventory()
        inv.acquire(.shotgun, ammo: 8)
        var c = city(inv, at: 12, 4)
        c.crowd.people = []
        c.pursuit.patrols = [Patrol(id: 70, car: VehicleState(position: at(12, 4) + Vec2(190, 0), heading: .pi))]
        var events: [CityEvent] = []
        for _ in 0..<60 { events += c.step(input: .idle, actions: CityActions(fire: true), dt: dt) }
        XCTAssertTrue(events.contains(.patrolDisabled(70)))
        XCTAssertTrue(events.contains { if case .droppedWeapon = $0 { return true } else { return false } })
        XCTAssertTrue(c.pickups.contains { $0.isDrop })
    }

    func testSomeCiviliansCarry() {
        // Over many knockdowns roughly a quarter drop a pistol; the RNG is seeded, so this is stable.
        var c = city(Inventory(), at: 12, 4)
        var inv = Inventory()
        inv.acquire(.pistol, ammo: 120)
        c.inventory = inv
        var downs = 0, drops = 0
        for _ in 0..<80 {
            c.crowd.people = [Pedestrian(id: 1, position: at(12, 4) + Vec2(150, 0), heading: 0,
                                         target: at(12, 4) + Vec2(150, 0), look: 0)]
            for _ in 0..<25 {
                for event in c.step(input: .idle, actions: CityActions(fire: true), dt: dt) {
                    if event == .pedestrianDown(1) { downs += 1 }
                    if case .droppedWeapon(.pistol) = event { drops += 1 }
                }
            }
            c.inventory.ammo["pistol"] = 120
            c.pickups = []
            // Keep Harbor Patrol out of the line of fire for this count.
            c.pursuit.patrols = []
            c.pursuit.heat = HeatState()
        }
        XCTAssertGreaterThan(downs, 50)
        XCTAssertGreaterThan(drops, downs / 10)
        XCTAssertLessThan(drops, downs / 2)
    }

    func testTheDealerTradesOrDropsHisCase() {
        var inv = Inventory()
        inv.addStarter(.bat)
        var c = city(inv, at: 8, 2, heading: .pi, dealer: TileCoord(col: 7, row: 2))
        c.crowd.people = []
        XCTAssertTrue(c.nearDealer == false, "a tile away")
        // Walk west toward him until close enough to talk.
        for _ in 0..<30 { _ = c.step(input: VehicleInput(throttle: 1), actions: .init(), dt: dt) }
        XCTAssertTrue(c.nearDealer)
        // A swing knocks him down: his case spills a gun and heat rises.
        let events = c.step(input: .idle, actions: CityActions(fire: true), dt: dt)
        XCTAssertTrue(events.contains(.dealerRobbed))
        XCTAssertTrue(events.contains(.swing(hit: true)))
        XCTAssertTrue(events.contains {
            if case .droppedWeapon(let w) = $0 { return [.smg, .shotgun, .rifle].contains(w) } else { return false }
        })
        XCTAssertTrue(c.reports.isEmpty, "nobody around to call it in")
        XCTAssertFalse(c.nearDealer, "gone for a while")
        for _ in 0..<Int(City.dealerAwaySeconds / dt) + 2 { _ = c.step(input: .idle, actions: .init(), dt: dt) }
        XCTAssertTrue(c.dealer!.isHere, "back on his corner")
    }

    func testABatSwingOnlyReachesWhatsClose() {
        var inv = Inventory()
        inv.addStarter(.bat)
        var c = city(inv, at: 12, 4)
        c.crowd.people = [Pedestrian(id: 3, position: at(12, 4) + Vec2(120, 0), heading: 0,
                                     target: at(12, 4) + Vec2(120, 0), look: 0)]
        var events = c.step(input: .idle, actions: CityActions(fire: true), dt: dt)
        XCTAssertEqual(events.filter { if case .swing = $0 { return true } else { return false } }, [.swing(hit: false)])
        XCTAssertFalse(events.contains { if case .shot = $0 { return true } else { return false } }, "no tracer")
        c.crowd.people[0].position = at(12, 4) + Vec2(40, 0)
        c.crowd.people[0].target = c.crowd.people[0].position
        for _ in 0..<40 { events = c.step(input: .idle, actions: CityActions(fire: true), dt: dt); if events.contains(.pedestrianDown(3)) { break } }
        XCTAssertTrue(events.contains(.pedestrianDown(3)))
    }
}
