//
//  LibraryRenameUITests.swift
//  Folder CrestUITests
//
//  Renaming a saved icon is three pieces of state working together — the row
//  that swaps its label for a text field, the focus that lands in it, and the
//  commit on Return. Only a real click chain proves they still line up.
//
//  `-ui-testing` puts the library in memory, so this never touches the real one.
//

import XCTest

final class LibraryRenameUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSavedIconCanBeRenamed() throws {
        let app = XCUIApplication()
        // Pin the language: the labels used below are the English ones
        app.launchArguments += ["-AppleLanguages", "(en)", "-ui-testing"]
        app.launch()

        app.buttons["Save Icon"].click()

        // A freshly saved row opens straight into its name field.
        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10),
                      "saving did not open the name field")
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Renamed On Save\r")

        let renamed = app.staticTexts["Renamed On Save"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 5),
                      "the typed name did not stick")

        // A double click starts the same edit again.
        renamed.doubleClick()
        let second = app.textFields["Name"]
        XCTAssertTrue(second.waitForExistence(timeout: 5),
                      "a double click did not start a rename")
        second.typeKey("a", modifierFlags: .command)
        second.typeText("Renamed Again\r")

        XCTAssertTrue(app.staticTexts["Renamed Again"].waitForExistence(timeout: 5),
                      "the second rename did not stick")
        XCTAssertFalse(app.staticTexts["Renamed On Save"].exists,
                       "the old name is still in the list")
    }
}
