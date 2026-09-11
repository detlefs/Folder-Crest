//
//  AboutAndTabsUITests.swift
//  Folder CrestUITests
//
//  Two pieces of menu bar state that no unit test can see: the tab entries the
//  system adds to the View menu unless told not to, and what the standard
//  about panel ends up showing.
//

import XCTest

final class AboutAndTabsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Pin the language: the menu titles used below are the English ones
        app.launchArguments += ["-AppleLanguages", "(en)", "-ui-testing"]
        app.launch()
        return app
    }

    @MainActor
    func testViewMenuOffersNoTabs() throws {
        let app = launch()

        let view = app.menuBarItems["View"]
        XCTAssertTrue(view.waitForExistence(timeout: 10), "no View menu")
        view.click()

        let items = app.menuItems.allElementsBoundByIndex.map(\.title)
        XCTAssertFalse(items.isEmpty, "the View menu came up empty")
        for title in ["Show Tab Bar", "Hide Tab Bar", "Show All Tabs", "Move Tab to New Window"] {
            XCTAssertFalse(items.contains(title), "the View menu still offers \(title)")
        }
    }

    @MainActor
    func testAboutPanelShowsTheLicenceAndTheSite() throws {
        let app = launch()

        app.menuBarItems.element(boundBy: 1).click()   // the application menu
        app.menuItems["About Folder Crest"].click()

        // The standard about panel is a dialog without a title of its own.
        let panel = app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "the about panel did not open")

        // Name, version and copyright are labels; the credits are a text view.
        let text = (panel.staticTexts.allElementsBoundByIndex
                    + panel.textViews.allElementsBoundByIndex)
            .compactMap { $0.value as? String }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("Copyright © 2026 Detlef Schneider"),
                      "no copyright in the about panel — got:\n\(text)")
        XCTAssertTrue(text.contains("MIT License"),
                      "no licence in the about panel — got:\n\(text)")
        XCTAssertTrue(panel.links["www.feltedred.de"].exists,
                      "no clickable site link in the about panel — got:\n\(text)")
    }
}
