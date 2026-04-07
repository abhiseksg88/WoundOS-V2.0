import XCTest

final class WoundOSV2UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify tab bar exists
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].exists)
        XCTAssertTrue(app.tabBars.buttons["Patients"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    func testNavigateToPatients() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Patients"].tap()
        XCTAssertTrue(app.navigationBars["Patients"].exists)
    }

    func testNavigateToSettings() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }
}
