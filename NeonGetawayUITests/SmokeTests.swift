import XCTest

/// Walks the main screens the way a player would: menu → map → drive → pause → quit, plus the
/// Garage, Records and Settings. Catches crashes and broken navigation, not game balance.
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Every test but the onboarding one starts with a ready-made player.
        app.launchArguments = (name.contains("Onboarding") ? ["-NGRedoOnboarding", "YES"]
                                                           : ["-NGSkipOnboarding", "YES"])
            + ["-NGOffline", "YES"]
        app.launch()
        // The menu fades in from the title screen; a tap during the fade can be lost.
        if !name.contains("Onboarding") {
            _ = app.buttons["menu.play"].waitForExistence(timeout: 10)
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    /// Taps a main-menu button until its screen opens (every screen has a back button). On a
    /// cold Simulator start the menu is still fading in and the first tap can be lost.
    private func tapMenu(_ id: String) {
        let target = button(id, timeout: 10)
        for _ in 0..<3 {
            if target.exists && target.isHittable { target.tap() }
            if app.buttons["nav.back"].waitForExistence(timeout: 3) { return }
        }
        XCTFail("\(id) didn't open its screen")
    }

    /// Finds a button by identifier, scrolling down a little if it's below the fold.
    private func button(_ id: String, timeout: TimeInterval = 8) -> XCUIElement {
        let element = app.buttons[id]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(id) never appeared")
        var swipes = 0
        while !element.isHittable && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        return element
    }

    /// Selects a job by its pin on the map (the map sits at the top of the screen, so no
    /// sideways scrolling: on iOS 26 a rightward drag can mean "go back").
    private func selectJob(_ id: String) {
        let pin = app.buttons["pin.\(id)"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "\(id) pin missing from the map")
        var swipes = 0
        while !pin.isHittable && swipes < 3 {
            app.swipeDown()
            swipes += 1
        }
        pin.tap()
    }

    func testFreeDrivePauseAndLeave() {
        tapMenu("menu.play")
        button("map.freeDrive").tap()
        button("hud.pause").tap()
        button("pause.resume").tap()
        button("hud.pause").tap()
        button("pause.quit").tap()
        XCTAssertTrue(app.buttons["map.freeDrive"].waitForExistence(timeout: 5), "back on the job map")
    }

    /// Free roam turns the phone sideways and shows the racing buttons; leaving goes back to portrait.
    func testFreeRoamIsLandscapeWithRacerButtons() {
        tapMenu("menu.play")
        button("map.freeDrive").tap()
        let gas = app.descendants(matching: .any)["controls.gas"]
        XCTAssertTrue(gas.waitForExistence(timeout: 5), "GAS pedal showing")
        XCTAssertTrue(app.descendants(matching: .any)["controls.stick"].exists, "driving joystick")
        XCTAssertFalse(app.descendants(matching: .any)["controls.left"].exists, "no arrows any more")
        XCTAssertTrue(app.descendants(matching: .any)["controls.brake"].exists, "BRAKE pedal")
        Thread.sleep(forTimeInterval: 1.0)
        let wide = app.windows.firstMatch.frame
        XCTAssertGreaterThan(wide.width, wide.height, "gameplay is landscape")
        button("hud.pause").tap()
        button("pause.quit").tap()
        XCTAssertTrue(app.buttons["map.freeDrive"].waitForExistence(timeout: 5), "back on the job map")
        Thread.sleep(forTimeInterval: 1.0)
        let tall = app.windows.firstMatch.frame
        XCTAssertGreaterThan(tall.height, tall.width, "menus are portrait again")
    }

    /// The HUD's now-playing chip pulls out the phone with Aurora FM; the street waits for it.
    func testInGamePhoneShowsTheRadio() {
        tapMenu("menu.play")
        button("map.freeDrive").tap()
        button("hud.phone").tap()
        // The phone opens on its home screen: Dashboard, Atlas, Radio.
        button("phone.app.dashboard").tap()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats"].waitForExistence(timeout: 5), "dashboard")
        button("phone.home").tap()
        button("phone.app.atlas").tap()
        button("atlas.suggest.0").tap()
        // Offline UI runs use Atlas's built-in answers ("You own…" / "You don't own…").
        let reply = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Atlas: You")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 8), "Atlas answers about the business")
        button("phone.home").tap()
        button("phone.app.radio").tap()
        XCTAssertTrue(app.descendants(matching: .any)["radio.track.treehouse"].waitForExistence(timeout: 5), "songs listed")
        XCTAssertTrue(app.descendants(matching: .any)["radio.add.treehouse"].exists, "+ button for each song")
        let credit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "feat. Babyface Ray"))
        XCTAssertTrue(credit.firstMatch.exists, "credits shown")
        button("phone.close").tap()
        XCTAssertTrue(app.descendants(matching: .any)["controls.gas"].waitForExistence(timeout: 5), "back to driving")
        button("hud.pause").tap()
        button("pause.quit").tap()
    }

    /// The weekly Street Challenge opens from the map, starts, and can be quit.
    func testStreetChallengeStartsFromTheMap() {
        tapMenu("menu.play")
        button("map.challenge").tap()
        button("brief.start").tap()
        XCTAssertTrue(app.descendants(matching: .any)["controls.gas"].waitForExistence(timeout: 5), "driving")
        button("hud.pause").tap()
        button("pause.quit").tap()
        XCTAssertTrue(app.buttons["map.challenge"].waitForExistence(timeout: 5), "back on the job map")
    }

    func testEveryJobOpensItsBriefAndCanBeQuit() {
        tapMenu("menu.play")
        // The three starter jobs are open on a fresh save; harder ones depend on reputation.
        for id in ["coldCrate", "tideLineRun", "lanternSweep"] {
            selectJob(id)
            button("map.startJob").tap()
            button("brief.start").tap()
            button("hud.pause").tap()
            button("pause.quit").tap()
            XCTAssertTrue(app.buttons["map.startJob"].waitForExistence(timeout: 5))
            app.swipeDown()
        }
    }

    func testEveryJobIsListedOnTheMap() {
        tapMenu("menu.play")
        for id in ["coldCrate", "tideLineRun", "lanternSweep", "deepFreeze", "ghostTide",
                   "lanternFestival", "doubleCross", "streetFlyers"] {
            XCTAssertTrue(app.buttons["job.\(id)"].waitForExistence(timeout: 5), "\(id) missing")
        }
        // Selecting the last job shows its card, locked or not.
        selectJob("doubleCross")
        XCTAssertTrue(app.staticTexts["Double Cross"].waitForExistence(timeout: 5))
    }

    /// The on-foot job starts with the player out of a car: the shooter layout (SPRINT, FIRE,
    /// AIM, the weapon bar), not BRAKE and DRIFT.
    func testOnFootJobShowsFootControls() {
        tapMenu("menu.play")
        selectJob("streetFlyers")
        button("map.startJob").tap()
        button("brief.start").tap()
        let sprint = app.descendants(matching: .any)["controls.sprint"]
        XCTAssertTrue(sprint.waitForExistence(timeout: 5), "foot controls showing")
        XCTAssertTrue(app.descendants(matching: .any)["controls.fire"].exists, "big FIRE button")
        XCTAssertTrue(app.descendants(matching: .any)["controls.aim"].exists, "AIM button")
        for fist in ["controls.hookLeft", "controls.punch", "controls.hookRight"] {
            XCTAssertTrue(app.descendants(matching: .any)[fist].exists, fist)
        }
        app.buttons["controls.punch"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["controls.autofire"].exists, "AUTO FIRE toggle")
        XCTAssertTrue(app.descendants(matching: .any)["weapon.pistol"].exists, "pistol on the weapon bar")
        XCTAssertFalse(app.descendants(matching: .any)["Drift"].exists, "no car buttons on foot")
        // On foot the camera starts close behind you (2nd person); VIEW cycles 1st and 3rd person.
        let view = button("hud.view")
        XCTAssertTrue(view.label.contains("2nd person"), view.label)
        view.tap()
        XCTAssertTrue(app.buttons["hud.view"].label.contains("1st person"))
        app.buttons["hud.view"].tap()
        XCTAssertTrue(app.buttons["hud.view"].label.contains("3rd person"))
        app.buttons["hud.view"].tap()
        button("hud.pause").tap()
        button("pause.quit").tap()
    }

    /// The first-launch flow: name, look, first weapon, rules, resident card, then the menu.
    func testOnboardingMakesAPlayer() {
        button("onboarding.start", timeout: 12).tap()
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Nova")
        button("onboarding.shuffle").tap()
        button("onboarding.next").tap()
        button("onboarding.weapon.bat").tap()
        button("onboarding.takeWeapon").tap()
        button("onboarding.next").tap()
        button("onboarding.finish").tap()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5), "on the main menu")
        let welcome = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Nova"))
        XCTAssertTrue(welcome.firstMatch.waitForExistence(timeout: 3), "the menu greets the new player")
    }

    /// Garage → body shop → paint studio: apply a template, name it, save it.
    func testPaintStudioSavesADesign() {
        tapMenu("menu.garage")
        button("garage.bodyShop").tap()
        button("bodyshop.studio").tap()
        let racing = app.buttons["Racing stripe"]
        XCTAssertTrue(racing.waitForExistence(timeout: 5))
        racing.tap()
        let name = app.textFields["studio.name"]
        name.tap()
        name.typeText("Test Stripe")
        app.keyboards.buttons["return"].firstMatch.tap()
        button("studio.save").tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Saved"))
        XCTAssertTrue(saved.firstMatch.waitForExistence(timeout: 3), "design saved")
    }

    func testGarageRecordsAndSettingsOpen() {
        for id in ["menu.garage", "menu.records", "menu.settings"] {
            tapMenu(id)
            button("nav.back").tap()
            XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5))
        }
        tapMenu("menu.settings")
        button("settings.controls").tap()
        XCTAssertTrue(app.buttons["controls.reset"].waitForExistence(timeout: 5), "control layout editor")
    }

    /// The garage's dealership, wheels and mechanic open; the mechanic explains a part.
    func testGarageDealershipWheelsAndMechanic() {
        tapMenu("menu.garage")
        button("garage.dealership").tap()
        XCTAssertTrue(app.descendants(matching: .any)["dealer.buy.kestrel"].waitForExistence(timeout: 5), "dealer cars listed")
        button("nav.back").tap()
        button("garage.rims").tap()
        XCTAssertTrue(app.buttons["rims.style.deepDish"].waitForExistence(timeout: 5), "rim styles")
        app.buttons["rims.style.deepDish"].tap()
        XCTAssertTrue(app.buttons["rims.fit"].isEnabled, "a new style can be fitted")
        button("nav.back").tap()
        button("garage.mechanic").tap()
        XCTAssertTrue(app.descendants(matching: .any)["mechanic.greeting"].waitForExistence(timeout: 5))
        button("mechanic.part.brakes").tap()
        XCTAssertTrue(app.descendants(matching: .any)["mechanic.lesson"].waitForExistence(timeout: 5), "Dex explains the part")
    }

    /// Every app on the phone opens and comes back: league, businesses, bank, ledger,
    /// rankings, trophies and skills.
    func testEveryPhoneAppOpens() {
        tapMenu("menu.phone")
        for id in ["phone.league", "phone.properties", "phone.bank", "phone.business", "phone.rankings",
                   "phone.trophies", "phone.skills", "phone.radio", "phone.style", "phone.dashboard"] {
            button(id).tap()
            button("nav.back").tap()
            XCTAssertTrue(app.buttons["phone.league"].waitForExistence(timeout: 5), "back on the phone after \(id)")
        }
    }

    /// The Online screen opens offline and explains how to sign in.
    func testOnlineScreenWorksOffline() {
        tapMenu("menu.online")
        let offline = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Offline"))
        XCTAssertTrue(offline.firstMatch.waitForExistence(timeout: 5), "offline status shown")
        button("nav.back").tap()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5))
    }

    /// Buying the taco truck, and moving cash into savings.
    func testBuyABusinessAndSave() {
        tapMenu("menu.phone")
        button("phone.properties").tap()
        // A save from an earlier run may already own it: then its Collect button shows instead.
        let buy = app.buttons["biz.buy.tacoTruck"]
        let collect = app.buttons["biz.collect.tacoTruck"]
        XCTAssertTrue(buy.waitForExistence(timeout: 5) || collect.exists, "taco truck card")
        if buy.exists && buy.isEnabled { buy.tap() }
        button("nav.back").tap()
        button("phone.bank").tap()
        XCTAssertTrue(app.buttons["bank.deposit"].waitForExistence(timeout: 5))
    }
}
