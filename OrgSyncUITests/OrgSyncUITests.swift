//
//  OrgSyncUITests.swift
//  OrgSyncUITests
//

import XCTest

final class OrgSyncUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-ui-testing-reset-repo"]
        app.launch()
    }

    @MainActor
    func testPrimaryTabsNavigateToTheirContent() throws {
        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.navigationBars["Agenda"].waitForExistence(timeout: 2))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["GitHub"].exists)

        app.tabBars.buttons["Notes"].tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCreatingNoteAddsItToTheNotesList() throws {
        app.buttons["Add"].tap()
        app.buttons["New Note"].tap()

        let nameField = app.alerts["New Note"].textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("UI Test Note")
        app.alerts["New Note"].buttons["Create"].tap()

        XCTAssertFalse(app.alerts["New Note"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testSyncPreferenceControlsAreAvailable() throws {
        app.tabBars.buttons["Settings"].tap()
        app.swipeUp()
        XCTAssertTrue(app.switches["settings.autoSync"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["settings.pullOnOpen"].exists)
        XCTAssertTrue(app.switches["settings.pushOnClose"].exists)
    }
}
