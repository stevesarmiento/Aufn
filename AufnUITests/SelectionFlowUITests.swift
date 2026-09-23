import XCTest

/// Multi-select on the tracks page, driven through the metronome row (no mic
/// needed): a right swipe selects, the transport becomes the action bar, and
/// Delete / Cancel restore the record head.
final class SelectionFlowUITests: XCTestCase {
    @MainActor
    func testSelectMetronomeThenCancelAndDeleteFromActionBar() throws {
        let app = XCUIApplication()
        app.launch()

        let newProject = app.buttons["New Project"].firstMatch
        XCTAssertTrue(newProject.waitForExistence(timeout: 5))
        newProject.tap()
        let projectRow = app.buttons.matching(identifier: "ProjectCard").firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5))
        projectRow.tap()

        let add = app.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let metronomeItem = app.buttons["Metronome"]
        XCTAssertTrue(metronomeItem.waitForExistence(timeout: 5))
        metronomeItem.tap()
        let metronomeSettings = app.buttons["Metronome settings"]
        XCTAssertTrue(metronomeSettings.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record"].exists)

        // A vertical drag that starts on a card must not be swallowed by the
        // row: nothing selects and the transport stays as it was.
        let metronomeRow = app.staticTexts["Metronome"].firstMatch
        XCTAssertTrue(metronomeRow.waitForExistence(timeout: 5))
        let top = metronomeRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 200)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertFalse(app.buttons["Cancel selection"].exists)
        XCTAssertTrue(app.buttons["Record"].exists)

        // Swipe the row right. A slow press-and-drag so the finger actually
        // travels past the reveal (a flick's short travel wouldn't commit).
        swipeRightToSelect(app.staticTexts["Metronome"].firstMatch)

        let cancel = app.buttons["Cancel selection"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete selected"].exists)
        XCTAssertFalse(app.buttons["Export selected"].isEnabled)  // metronome is not audio
        XCTAssertTrue(app.staticTexts["1 Selected"].exists)           // title carries the count
        XCTAssertFalse(app.buttons["Record"].exists)               // the head is Delete now
        attach(app, name: "selection-bar")

        // Cancel restores the transport and keeps the row.
        cancel.tap()
        XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: 5))
        XCTAssertTrue(metronomeSettings.exists)

        // Swipe left past the reveal: the alert asks directly (no resting
        // open state); Cancel closes the row without removing anything.
        let row = app.staticTexts["Metronome"].firstMatch
        let from = row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: -90, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        attach(app, name: "delete-alert-from-swipe")
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(metronomeSettings.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)

        // Select again and delete through the bar's confirmation.
        swipeRightToSelect(app.staticTexts["Metronome"].firstMatch)
        let deleteSelected = app.buttons["Delete selected"]
        XCTAssertTrue(deleteSelected.waitForExistence(timeout: 5))
        deleteSelected.tap()
        let confirm = app.buttons["Remove Metronome"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.firstMatch.exists, "Delete confirms through an alert, not an action sheet")
        attach(app, name: "delete-alert")
        confirm.tap()
        XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: 5))
        XCTAssertFalse(metronomeSettings.exists)
    }

    @MainActor
    private func swipeRightToSelect(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 160, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
