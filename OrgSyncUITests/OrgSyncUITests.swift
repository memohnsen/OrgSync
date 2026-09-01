//
//  OrgSyncUITests.swift
//  OrgSyncUITests
//

import XCTest

final class OrgSyncUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset-repo",
            "-ui-testing-skip-onboarding",
            "-ui-testing-unlock-pro",
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["splash.screen"].waitForNonExistence(timeout: 5))
        return app
    }

    @MainActor
    func testPrimaryTabsNavigateToTheirContent() throws {
        let app = launchApp()
        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.navigationBars["Agenda"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["GitHub"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Notes"].tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreatingNoteAddsItToTheNotesList() throws {
        let app = launchApp()
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
    func testGitSettingsAreAvailable() throws {
        let app = launchApp()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.textFields["settings.repositoryURL"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["settings.personalAccessToken"].exists)
    }

    @MainActor
    func testOnboardingGuidesUsersToInboxOrGitHubSetup() throws {
        let onboardingApp = XCUIApplication()
        onboardingApp.launchArguments = ["-ui-testing-reset-repo", "-ui-testing-show-onboarding"]
        onboardingApp.launch()

        XCTAssertTrue(onboardingApp.otherElements["onboarding.screen"].waitForExistence(timeout: 3))
        onboardingApp.buttons["onboarding.next"].tap()
        XCTAssertTrue(onboardingApp.staticTexts["Capture first.\nOrganize later."].waitForExistence(timeout: 2))
        onboardingApp.buttons["onboarding.next"].tap()
        XCTAssertTrue(onboardingApp.buttons["onboarding.connect"].waitForExistence(timeout: 2))
        XCTAssertTrue(onboardingApp.buttons["onboarding.openInbox"].exists)
    }
}
