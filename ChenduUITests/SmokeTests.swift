import XCTest

/// Launch → list → open issue → tap a margin note → add a reader note → play audio → my notes.
/// Runs against the live site. On a network that needs a proxy, pass it through the test runner:
/// `TEST_RUNNER_CHENDU_PROXY=127.0.0.1:6789 xcodebuild test …`
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var shotIndex = 0

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemoryStore"]
        let env = ProcessInfo.processInfo.environment
        if let proxy = env["CHENDU_PROXY"] { app.launchEnvironment["CHENDU_PROXY"] = proxy }
    }

    func testReadingFlow() throws {
        app.launch()

        let firstIssue = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'issue-'")).firstMatch
        XCTAssertTrue(firstIssue.waitForExistence(timeout: 45), "issue list did not load")
        shot("01-issue-list")

        firstIssue.tap()
        let title = app.staticTexts["issueTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 45), "issue did not open")
        shot("02-reader")

        let note = app.descendants(matching: .any)["note-1"]
        if !note.waitForExistence(timeout: 10) {
            print("TREE-DUMP-BEGIN\n\(app.debugDescription)\nTREE-DUMP-END")
        }
        XCTAssertTrue(note.exists, "annotated phrase not exposed")
        note.tap()
        let card = app.descendants(matching: .any)["annotationCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "margin note did not open")
        shot("03-margin-note")

        let para = app.descendants(matching: .any)["para-0"]
        XCTAssertTrue(para.waitForExistence(timeout: 5))
        para.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.12)).press(forDuration: 1.2)
        let addNote = app.descendants(matching: .any).matching(NSPredicate(format: "label == '加笔记' OR identifier == 'addNoteAction'")).firstMatch
        if !addNote.waitForExistence(timeout: 5) {
            shot("debug-edit-menu")
            print("TREE2-BEGIN\n\(app.debugDescription)\nTREE2-END")
        }
        XCTAssertTrue(addNote.exists, "edit menu has no 加笔记")
        shot("04-edit-menu")
        addNote.tap()

        let editor = app.textViews["noteTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "note editor did not appear")
        editor.tap()
        editor.typeText("smoke test note 练习")
        shot("05-note-editor")
        app.buttons["saveNote"].tap()
        let userCard = app.descendants(matching: .any)["userNoteCard"]
        XCTAssertTrue(userCard.waitForExistence(timeout: 5), "saved note not shown")
        shot("06-user-note")

        let play = app.buttons["playNormal"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        for _ in 0..<12 where !play.isHittable { app.swipeUp() }
        play.tap()
        let pause = app.buttons["miniPlayPause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10), "player bar did not appear")
        let playing = NSPredicate(format: "label == '暂停'")
        expectation(for: playing, evaluatedWith: pause)
        waitForExpectations(timeout: 90)
        let elapsed = app.staticTexts["elapsedTime"]
        let advanced = NSPredicate(format: "label != '0:00'")
        expectation(for: advanced, evaluatedWith: elapsed)
        waitForExpectations(timeout: 20)
        shot("07-audio-playing")

        app.tabBars.buttons["我的笔记"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["myNoteRow"].waitForExistence(timeout: 5), "note missing from 我的笔记")
        shot("08-my-notes")
    }

    private func shot(_ name: String) {
        shotIndex += 1
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
