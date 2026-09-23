import XCTest

/// The Sep 11 batch end to end: a take's card toggles its mixer on tap, the
/// capture wheel floats the grade's character over the record head, tap
/// tempo lives on the metronome, and a deleted take round-trips through
/// Recently Deleted back into the list. Needs the simulator mic (grant with
/// `simctl privacy <udid> grant microphone co.lassidesign.Aufn`).
final class RecentlyDeletedFlowUITests: XCTestCase {
    @MainActor
    func testCardTapWheelCalloutTapTempoAndRestore() throws {
        let app = XCUIApplication()
        app.launch()

        addUIInterruptionMonitor(withDescription: "Microphone") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap(); return true }
            return false
        }

        // Create and open a project.
        let newProject = app.buttons["New Project"].firstMatch
        XCTAssertTrue(newProject.waitForExistence(timeout: 5))
        newProject.tap()
        let card = app.buttons.matching(identifier: "ProjectCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        attach(app, name: "grid")
        card.tap()

        // The wheel's callout describes the highlighted grade over the head.
        let trigger = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Capture mode, '")).firstMatch
        XCTAssertTrue(trigger.waitForExistence(timeout: 5))
        let current = trigger.label.replacingOccurrences(of: "Capture mode, ", with: "")
        trigger.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        let callout = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "\(current): ")).firstMatch
        XCTAssertTrue(callout.waitForExistence(timeout: 5), "callout for \(current)")
        attach(app, name: "wheel-callout")
        // Settling on a DIFFERENT row commits and closes (the same row is a
        // no-op for the picker).
        let other = ["RAW", "TAPE", "WARM", "GLUE"].first { $0 != current }!
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: other)
        XCTAssertTrue(app.buttons["Capture mode, \(other)"].waitForExistence(timeout: 5))
        XCTAssertFalse(callout.exists, "callout leaves with the wheel")

        // Record a take.
        let record = app.buttons["Record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        app.tap()
        let stopRecording = app.buttons["Stop recording"]
        XCTAssertTrue(stopRecording.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        stopRecording.tap()
        let trackName = app.staticTexts["Track 1"]
        XCTAssertTrue(trackName.waitForExistence(timeout: 10))

        // Tapping the card unfolds the mixer; tapping again folds it.
        trackName.tap()
        let volume = app.sliders["Volume for Track 1"]
        XCTAssertTrue(volume.waitForExistence(timeout: 5), "card tap opens the mixer")
        attach(app, name: "mixer-from-card-tap")
        trackName.tap()
        XCTAssertTrue(waitForDisappearance(of: volume), "second card tap closes the mixer")

        // Tap tempo sits in the metronome panel.
        app.buttons["Add"].tap()
        let metronomeItem = app.buttons["Metronome"]
        XCTAssertTrue(metronomeItem.waitForExistence(timeout: 5))
        metronomeItem.tap()
        let metronomeSettings = app.buttons["Metronome settings"]
        XCTAssertTrue(metronomeSettings.waitForExistence(timeout: 5))
        metronomeSettings.tap()
        let tapTempo = app.buttons["Tap tempo"]
        XCTAssertTrue(tapTempo.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            tapTempo.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        let readout = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'BPM · 4/4'")).firstMatch
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        attach(app, name: "tap-tempo")
        metronomeSettings.tap() // fold the panel

        // Swipe the take left past the reveal and confirm; the alert now
        // promises a restore.
        let from = trackName.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: -90, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["You can restore it from Recently Deleted for 30 days."].exists)
        attach(app, name: "delete-alert")
        alert.buttons["Delete Track"].tap()
        XCTAssertTrue(waitForDisappearance(of: trackName), "track leaves the list")

        // Recently Deleted lists it under today; Restore brings it back.
        app.buttons["Settings"].tap()
        let recentlyDeleted = app.buttons["Recently Deleted"]
        XCTAssertTrue(recentlyDeleted.waitForExistence(timeout: 5))
        recentlyDeleted.tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Track 1"].exists)
        XCTAssertTrue(app.buttons["Delete All"].isEnabled)
        attach(app, name: "recently-deleted-feed")
        let restore = app.buttons["Restore Track 1"]
        XCTAssertTrue(restore.exists)
        restore.tap()
        XCTAssertTrue(app.staticTexts["Nothing deleted"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Delete All"].isEnabled)
        attach(app, name: "recently-deleted-empty")

        app.navigationBars.buttons.firstMatch.tap() // back
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Track 1"].waitForExistence(timeout: 5), "restored take is listed again")
        XCTAssertTrue(app.buttons["Mixer for Track 1"].exists)
        attach(app, name: "restored")
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
