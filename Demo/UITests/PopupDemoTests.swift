import XCTest

final class PopupDemoTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["presentRequest"].waitForExistence(timeout: 10))
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing button \(id)", file: file, line: line)
        button.tap()
    }

    private func expectCard(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let title = app.staticTexts.matching(identifier: "requestTitle")
            .matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Missing card \(name)", file: file, line: line)
    }

    private func submitNext(_ mode: String) {
        tap("followUp")
        tap(mode)
    }

    func testPageQueueUsesPriorityThenFIFO() {
        tap("presentRequest")
        expectCard("Request 1")
        submitNext("queue")
        submitNext("Queue high priority")
        submitNext("Queue high priority")
        for name in ["Request 1", "Urgent 3", "Urgent 4", "Request 2"] {
            expectCard(name)
            tap("finishRequest")
        }
        XCTAssertTrue(app.buttons["presentRequest"].isHittable)
    }

    func testWindowGroupLockRejectsAndReleases() {
        tap("Window")
        tap("modePicker")
        tap("groupUnique")
        tap("presentRequest")
        expectCard("Request 1")
        submitNext("queue")
        XCTAssertTrue(app.staticTexts["Request 2 rejected · groupLocked"].waitForExistence(timeout: 5))
        tap("finishRequest")
        tap("presentRequest")
        expectCard("Request 3")
    }

    func testSuspendedPageDraftSurvivesWindowReplacement() {
        tap("openDraft")
        let field = app.textFields["draftText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("First revision\n")
        tap("suspendDraft")
        expectCard("Review 2")
        submitNext("replaceInheritSuspend")
        expectCard("Request 3")
        tap("finishRequest")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "First revision")
        tap("finishDraft")
    }

    func testClearSuspensionAdvancesToWaitingCard() {
        tap("openDraft")
        tap("suspendDraft")
        expectCard("Review 2")
        submitNext("queue")
        submitNext("replaceClearSuspend")
        expectCard("Request 4")
        tap("finishRequest")
        expectCard("Request 3")
        tap("finishRequest")
        XCTAssertFalse(app.textFields["draftText"].exists)
    }

    func testSheetWindowToastPreservesTypingAndTimesOut() {
        tap("openSheet")
        let field = app.textFields["sheetText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("one")
        tap("sheetSave")
        let banner = app.descendants(matching: .any)["savedBanner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 3))
        field.typeText("two")
        XCTAssertEqual(field.value as? String, "onetwo")
        let ended = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: banner)
        XCTAssertEqual(XCTWaiter.wait(for: [ended], timeout: 6), .completed)
    }

    func testUnderlyingPageCardSurvivesSheet() {
        tap("openSheet")
        tap("underlyingCard")
        tap("closeSheet")
        expectCard("Page card 1")
        tap("finishRequest")
    }

    func testPassThroughAndDismissDeliversOneBackgroundTap() {
        tap("Open interaction lab")
        tap("Background")
        tap("passThroughAndDismiss")
        tap("Show touch sample")
        tap("Content taps: 0")
        XCTAssertTrue(app.buttons["Content taps: 1"].exists)
        tap("backgroundCounter")
        XCTAssertEqual(app.buttons["backgroundCounter"].label, "Background taps: 1")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.buttons["Content taps: 1"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 4), .completed)
    }

    func testChangingBoundItemKeepsReplacementOpen() {
        tap("Open interaction lab")
        tap("Present item binding")
        XCTAssertTrue(app.staticTexts["Item 1"].waitForExistence(timeout: 5))
        tap("Switch item")
        XCTAssertTrue(app.staticTexts["Item 2"].waitForExistence(timeout: 5))
        tap("Close")
        tap("Present item binding")
        XCTAssertTrue(app.staticTexts["Item 3"].waitForExistence(timeout: 5))
    }
}
