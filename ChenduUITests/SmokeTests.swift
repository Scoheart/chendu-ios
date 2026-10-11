import XCTest

final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemoryStore", "-forceSignedOut"]
    }

    func testLoginScreen() {
        app.launch()
        XCTAssertTrue(app.textFields["loginEmail"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'issue-'")).firstMatch.exists)
    }
}
