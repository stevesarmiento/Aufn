import XCTest

/// Drives the toolbar pill and the workspace settings: + adds the metronome
/// (and disables itself once added), the ellipsis opens the full-screen
/// settings sheet, and rows push sub-pages (sample rate, microphone, export).
final class WorkspaceFlowUITests: XCTestCase {
    @MainActor
    func testAddMenuAndWorkspaceSettings() throws {
        let app = XCUIApplication()
        app.launch()

        // Create and open a project.
        let newProject = app.buttons["New Project"].firstMatch
        XCTAssertTrue(newProject.waitForExistence(timeout: 5))
        newProject.tap()
        let projectRow = app.buttons.matching(identifier: "ProjectCard").firstMatch
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5))
        projectRow.tap()

        // + menu adds the metronome row.
        let add = app.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        attach(app, name: "toolbar")
        add.tap()
        let metronomeItem = app.buttons["Metronome"]
        XCTAssertTrue(metronomeItem.waitForExistence(timeout: 5))
        metronomeItem.tap()
        XCTAssertTrue(app.buttons["Metronome settings"].waitForExistence(timeout: 5))

        // The settings root: inline master volume plus the three links.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Sample Rate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["Master volume"].exists)
        XCTAssertTrue(app.switches["Repeat Playback"].exists)
        XCTAssertTrue(app.buttons["Microphone"].exists)
        XCTAssertTrue(app.buttons["Export"].exists)   // toolbar share button
        attach(app, name: "settings-root")

        // Export is a toolbar action, disabled with no tracks.
        XCTAssertFalse(app.buttons["Export"].isEnabled)

        // Microphone pushes one page holding input device AND mic position.
        app.buttons["Microphone"].tap()
        XCTAssertTrue(app.buttons["Input device, Auto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Mic position, Auto"].exists)
        attach(app, name: "microphone-page")
        app.navigationBars.buttons.firstMatch.tap() // back

        // Sample rate pushes its picker.
        XCTAssertTrue(app.buttons["Sample Rate"].waitForExistence(timeout: 5))
        app.buttons["Sample Rate"].tap()
        XCTAssertTrue(app.buttons["Sample rate, G+ — 48 kHz"].waitForExistence(timeout: 5))
        attach(app, name: "sample-rate-page")
        app.navigationBars.buttons.firstMatch.tap() // back

        // Close returns to the project.
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
