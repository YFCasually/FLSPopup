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
        XCTAssertTrue(button.exists || button.waitForExistence(timeout: 5), "Missing button \(id)", file: file, line: line)
        button.tap()
    }

    private func expectCard(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let title = app.staticTexts.matching(identifier: "requestTitle")
            .matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(title.exists || title.waitForExistence(timeout: 5), "Missing card \(name)\n\(app.debugDescription)", file: file, line: line)
    }

    private func expectGone(_ element: XCUIElement, timeout: TimeInterval = 5,
                            file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed, file: file, line: line)
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
        expectGone(app.staticTexts["requestTitle"])
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

    func testSuspendedPageDraftSurvivesWindowReplacement() throws {
        tap("openDraft")
        let field = app.textFields["draftText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("First revision\n")
        let history = app.scrollViews["draftHistory"]
        let firstRevision = history.staticTexts["Revision 1"]
        XCTAssertTrue(firstRevision.isHittable)
        history.swipeUp()
        XCTAssertFalse(firstRevision.isHittable)
        let visible = history.staticTexts.allElementsBoundByIndex.first {
            $0.isHittable && $0.label.hasPrefix("Revision ") && $0.label != "Revision 1"
        }
        let anchor = try XCTUnwrap(visible)
        let revision = anchor.label
        let offset = anchor.frame.midY - history.frame.minY
        tap("suspendDraft")
        expectCard("Review 2")
        submitNext("replaceInheritSuspend")
        expectCard("Request 3")
        tap("finishRequest")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "First revision")
        let restored = history.staticTexts[revision]
        XCTAssertTrue(restored.isHittable)
        XCTAssertEqual(restored.frame.midY - history.frame.minY, offset, accuracy: 2)
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
        expectGone(banner, timeout: 6)
    }

    func testWindowInputPanelReturnsKeyboardToSheet() {
        tap("openSheet")
        let sheet = app.textFields["sheetText"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.tap()
        app.typeText("one")
        XCTAssertEqual(sheet.value as? String, "one")

        tap("Window input panel")
        let panel = app.textFields["draftText"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("draft")
        XCTAssertEqual(panel.value as? String, "draft")
        XCTAssertTrue(app.buttons["finishDraft"].isHittable)
        tap("finishDraft")
        expectGone(panel)

        // Sending to the application exercises the restored first responder.
        app.typeText("two")
        XCTAssertEqual(sheet.value as? String, "onetwo")
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
        tap("backgroundPicker")
        tap("passThroughAndDismiss")
        tap("Show touch sample")
        tap("Content taps: 0")
        XCTAssertTrue(app.buttons["Content taps: 1"].exists)
        tap("backgroundCounter")
        XCTAssertEqual(app.buttons["backgroundCounter"].label, "Background taps: 1")
        expectGone(app.buttons["Content taps: 1"])
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

extension PopupDemoTests {
    func testBackgroundPoliciesOnBothHosts() {
        tap("Open interaction lab")
        var contentTaps = 0
        var backgroundTaps = 0

        for host in ["Page", "Window"] {
            tap(host)
            for policy in ["block", "dismiss", "passThrough", "passThroughAndDismiss"] {
                tap("backgroundPicker")
                tap(policy)
                let counter = app.buttons["backgroundCounter"]
                let position = counter.frame
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let backgroundPoint = origin.withOffset(CGVector(dx: position.midX, dy: position.midY))
                tap("Show touch sample")
                tap("Content taps: \(contentTaps)")
                contentTaps += 1
                let content = app.buttons["Content taps: \(contentTaps)"]
                XCTAssertTrue(content.exists, "\(host) / \(policy)")
                backgroundPoint.tap()
                if policy == "dismiss" || policy == "passThroughAndDismiss" {
                    expectGone(content)
                } else {
                    XCTAssertTrue(content.isHittable, "\(host) / \(policy)")
                    tap("Close")
                    expectGone(content)
                }
                if policy == "passThrough" || policy == "passThroughAndDismiss" { backgroundTaps += 1 }
                XCTAssertEqual(counter.label, "Background taps: \(backgroundTaps)", "\(host) / \(policy)")
            }
        }
    }
}
