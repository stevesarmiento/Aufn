import XCTest

/// Drives the real app in the simulator: create a project, record a take
/// (simulator mic = the Mac's input), overdub a second take, verify both
/// tracks appear. Run with mic permission pre-granted via
/// `simctl privacy <udid> grant microphone co.lassidesign.Aufn`.
final class RecordFlowUITests: XCTestCase {
    @MainActor
    func testRecordOverdubAndTrackListing() throws {
        let app = XCUIApplication()
        app.launch()

        // Auto-accept the mic permission alert if it appears anyway.
        addUIInterruptionMonitor(withDescription: "Microphone") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap(); return true }
            return false
        }

        // Create and open a project.
        let newProject = app.buttons["New Project"].firstMatch
        XCTAssertTrue(newProject.waitForExistence(timeout: 5))
        newProject.tap()
        let projectRow = app.cells.firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5))
        projectRow.tap()

        // Record take 1.
        let record = app.buttons["Record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        app.tap() // deliver any pending interruption monitor

        let stopRecording = app.buttons["Stop recording"]
        XCTAssertTrue(stopRecording.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        stopRecording.tap()

        XCTAssertTrue(app.staticTexts["Track 1"].waitForExistence(timeout: 10))

        // Overdub take 2 while track 1 plays underneath.
        record.tap()
        XCTAssertTrue(stopRecording.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        stopRecording.tap()

        XCTAssertTrue(app.staticTexts["Track 2"].waitForExistence(timeout: 10))

        // Per-track mixer expands to reveal volume/pan.
        let mixer = app.buttons["Mixer for Track 1"]
        XCTAssertTrue(mixer.waitForExistence(timeout: 5))
        mixer.tap()
        XCTAssertTrue(app.sliders["Volume for Track 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["Pan for Track 1"].exists)

        // Aggregate mix waveform appears once tracks exist.
        XCTAssertTrue(app.otherElements["MixWaveform"].waitForExistence(timeout: 5))

        // Playback starts; mute/solo toggle live without breaking transport.
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        let muteTrack1 = app.buttons["Mute Track 1"]
        XCTAssertTrue(muteTrack1.exists)
        muteTrack1.tap()
        XCTAssertTrue(app.buttons["Solo Track 2"].exists, "Track list intact after live mute")
        app.buttons["Solo Track 1"].tap()
        muteTrack1.tap() // restore

        // Auto-stop still fires with all players scheduled (muted or not).
        XCTAssertTrue(play.waitForExistence(timeout: 15), "Playback should auto-stop after tracks finish")
    }
}
