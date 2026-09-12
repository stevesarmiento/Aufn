import XCTest

/// Capture-mode wheel + record: switching grades between takes (and after
/// playback) must never surface an "Audio Error" alert, and each take must
/// land as a track. Fails with the alert's text at the first point one shows.
final class CaptureModeFlowUITests: XCTestCase {
    @MainActor
    func testWheelThenRecordSequences() throws {
        let app = XCUIApplication()
        app.launch()
        let newProject = app.buttons["New Project"].firstMatch
        XCTAssertTrue(newProject.waitForExistence(timeout: 5))
        newProject.tap()
        let card = app.buttons.matching(identifier: "ProjectCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: 5))

        // 1. Record on whatever mode is stored, stop.
        recordTake(app, step: "first take", expectTrack: "Track 1")
        // 2. Switch mode, record.
        pickDifferent(app, preferring: "WARM")
        recordTake(app, step: "take after one switch", expectTrack: "Track 2")
        // 3. Switch twice quickly, record.
        pickDifferent(app, preferring: "GLUE")
        pickDifferent(app, preferring: "TAPE")
        recordTake(app, step: "take after two switches", expectTrack: "Track 3")
        // 4. Play, stop, switch, record.
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        app.buttons["Stop"].tap()
        XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: 5))
        pickDifferent(app, preferring: "WARM")
        recordTake(app, step: "take after playback and switch", expectTrack: "Track 4")
    }

    /// Picks a mode that differs from the current one (the mode persists
    /// across launches, so a fixed target can be a no-op). Returns the label picked.
    @MainActor
    @discardableResult
    private func pickDifferent(_ app: XCUIApplication, preferring wanted: String) -> String {
        let trigger = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Capture mode, '")).firstMatch
        XCTAssertTrue(trigger.waitForExistence(timeout: 5), "trigger")
        let current = trigger.label.replacingOccurrences(of: "Capture mode, ", with: "")
        let all = ["RAW", "TAPE", "WARM", "GLUE"]
        let to = wanted != current ? wanted : all.first { $0 != current }!
        trigger.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        wheel.adjust(toPickerWheelValue: to)
        if !app.buttons["Capture mode, \(to)"].waitForExistence(timeout: 5) {
            let wheelValue = app.pickerWheels.firstMatch.exists ? String(describing: app.pickerWheels.firstMatch.value ?? "nil") : "no wheel"
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "pick-\(to)-failed"; shot.lifetime = .keepAlways; add(shot)
            XCTFail("PICK \(current)->\(to) did not commit. wheel=\(wheelValue)")
        }
        checkAlert(app, step: "after picking \(to)")
        return to
    }

    @MainActor
    private func recordTake(_ app: XCUIApplication, step: String, expectTrack: String) {
        app.buttons["Record"].tap()
        Thread.sleep(forTimeInterval: 2.5)
        checkAlert(app, step: step)
        let stop = app.buttons["Stop recording"]
        XCTAssertTrue(stop.exists, "\(step): should be recording")
        stop.tap()
        checkAlert(app, step: "\(step) (after stop)")
        XCTAssertTrue(app.staticTexts[expectTrack].waitForExistence(timeout: 10), "\(step): \(expectTrack)")
    }

    @MainActor
    private func checkAlert(_ app: XCUIApplication, step: String) {
        let alert = app.alerts.firstMatch
        guard alert.exists else { return }
        let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "alert-\(step)"; shot.lifetime = .keepAlways; add(shot)
        XCTFail("ALERT at [\(step)]: \(text)")
        alert.buttons.firstMatch.tap()
    }
}
