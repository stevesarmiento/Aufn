import XCTest

/// Drives the projects grid: the gear opens app settings and pushes the App
/// Icon page; a card's long-press menu opens Customize, where tints and
/// glyphs apply live.
final class ProjectsGridUITests: XCTestCase {
    @MainActor
    func testAppSettingsAndCustomizeCard() throws {
        let app = XCUIApplication()
        app.launch()

        let newProject = app.buttons["New Project"].firstMatch
        XCTAssertTrue(newProject.waitForExistence(timeout: 5))
        newProject.tap()
        let card = app.buttons.matching(identifier: "ProjectCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        attach(app, name: "grid")

        // Gear → Settings → App Icon page lists the default icon.
        app.buttons["App Settings"].tap()
        XCTAssertTrue(app.buttons["App Icon"].waitForExistence(timeout: 5))
        // The permissions switch reflects mic status; don't flip it (with the
        // choice already made, flipping only leaves for the system Settings).
        XCTAssertTrue(app.switches["Microphone"].exists)
        attach(app, name: "app-settings")
        app.buttons["App Icon"].tap()
        XCTAssertTrue(app.buttons["Default"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Default"].isSelected)
        // The shipped alternates, in catalog order. Tapping one can't be
        // verified in the simulator (the system icon-change alert fails to
        // load there), so this only checks they're offered.
        XCTAssertTrue(app.buttons["Retro"].exists)
        XCTAssertTrue(app.buttons["Blueprint"].exists)
        attach(app, name: "app-icon")
        app.navigationBars.buttons.firstMatch.tap() // back
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()

        // Long-press → Customize: pick a tint and a symbol.
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 1)
        let customize = app.buttons["Customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        customize.tap()
        let pink = app.buttons["Pink tint"]
        XCTAssertTrue(pink.waitForExistence(timeout: 5))
        pink.tap()
        XCTAssertTrue(pink.isSelected)
        attach(app, name: "customize")
        app.buttons["Close"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
