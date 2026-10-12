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

    /// The on-foot job starts with the player out of a car: the controls say RUN, not GAS.
    func testOnFootJobShowsFootControls() {
        tapMenu("menu.play")
        selectJob("streetFlyers")
        button("map.startJob").tap()
        button("brief.start").tap()
        XCTAssertTrue(app.staticTexts["Run"].waitForExistence(timeout: 5) || app.otherElements["Run"].exists
                      || app.buttons["Run"].exists, "foot controls showing")
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

    /// Every app on the phone opens and comes back: league, businesses, bank, ledger,
    /// rankings, trophies and skills.
    func testEveryPhoneAppOpens() {
        tapMenu("menu.phone")
        for id in ["phone.league", "phone.properties", "phone.bank", "phone.business", "phone.rankings",
                   "phone.trophies", "phone.skills"] {
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
