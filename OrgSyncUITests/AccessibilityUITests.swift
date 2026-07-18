//
//  AccessibilityUITests.swift
//  OrgSyncUITests
//
//  Regression coverage for the accessibility contract of the primary app
//  workflows. These tests intentionally exercise labels and stable identifiers
//  rather than relying on the visual arrangement of controls.
//

import XCTest

final class AccessibilityUITests: XCTestCase {
    @MainActor
    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-repo"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    func testSplashAnnouncesTheAppBrand() throws {
        let app = launch(extraArguments: ["-ui-testing-hold-splash"])
        let title = app.staticTexts["OrgSync"]

        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertTrue(title.elementType == .staticText)
        XCTAssertTrue(app.staticTexts["Your notes, in sync."].exists)
    }

    @MainActor
    func testNotesToolbarControlsHaveStableAccessibleNames() throws {
        let app = launch()
        let add = app.buttons["notes.add"]
        let sort = app.buttons["notes.sort"]

        XCTAssertTrue(add.waitForExistence(timeout: 2))
        XCTAssertEqual(add.label, "Add")
        XCTAssertTrue(sort.exists)
        XCTAssertEqual(sort.label, "Sort notes")
    }

    @MainActor
    func testAgendaScopeIsAccessible() throws {
        let app = launch()
        app.tabBars.buttons["Agenda"].tap()

        let scope = app.segmentedControls["agenda.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 2))
        XCTAssertEqual(scope.label, "Agenda View")
        XCTAssertTrue(scope.buttons["Today"].exists)
        XCTAssertTrue(scope.buttons["Upcoming"].exists)
        XCTAssertTrue(scope.buttons["All TODOs"].exists)
    }

    @MainActor
    func testSettingsInputsAndSyncControlsHaveAccessibleNames() throws {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()

        let repositoryURL = app.textFields["settings.repositoryURL"]
        let branch = app.textFields["settings.branch"]
        let token = app.secureTextFields["settings.personalAccessToken"]
        XCTAssertTrue(repositoryURL.waitForExistence(timeout: 2))
        XCTAssertEqual(repositoryURL.label, "Repository URL")
        XCTAssertEqual(branch.label, "Branch")
        XCTAssertEqual(token.label, "Personal Access Token")

        app.swipeUp()
        let autoSync = app.switches["settings.autoSync"]
        let pullOnOpen = app.switches["settings.pullOnOpen"]
        let pushOnClose = app.switches["settings.pushOnClose"]
        XCTAssertTrue(autoSync.waitForExistence(timeout: 2))
        XCTAssertEqual(autoSync.label, "Auto-Sync")
        XCTAssertEqual(pullOnOpen.label, "Pull on Open")
        XCTAssertEqual(pushOnClose.label, "Commit & Push on Close")
    }

    @MainActor
    func testSourceEditorHasAnAccessibleIdentity() throws {
        let app = launch()
        let note = app.buttons["note.row.inbox.org"]
        XCTAssertTrue(note.waitForExistence(timeout: 2))
        note.tap()

        let edit = app.buttons["note.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        edit.tap()

        let editor = app.textViews["note.sourceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertEqual(editor.label, "Org source editor")
    }

    @MainActor
    func testPrimaryControlsRemainAvailableAtAccessibilityTextSize() throws {
        let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])

        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["notes.add"].exists)
        XCTAssertTrue(app.tabBars.buttons["Agenda"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }
}
