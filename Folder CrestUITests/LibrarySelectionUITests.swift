//
//  LibrarySelectionUITests.swift
//  Folder CrestUITests
//
//  A saved row has to answer to clicks on all of it — thumbnail, name and the
//  empty rest. A gesture on the row once claimed the clicks on its content and
//  left only the empty part selectable, which no unit test can see.
//
//  `-ui-testing` puts the library in memory, so this never touches the real one.
//

import XCTest

final class LibrarySelectionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWholeRowSelectsLoadsAndRenames() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-ui-testing"]
        app.launch()

        let source = app.textFields["Text or Emoji"]
        XCTAssertTrue(source.waitForExistence(timeout: 10), "no text field")

        save(app, text: "AAA", as: "First")
        save(app, text: "BBB", as: "Second")
        XCTAssertEqual(source.value as? String, "BBB")

        // A click on the name selects the row and loads its icon.
        app.staticTexts["First"].click()
        XCTAssertTrue(waitForValue("AAA", in: source), "a click on the name did not load the icon")

        // A click on the thumbnail does the same.
        thumbnail(of: app.staticTexts["Second"]).click()
        XCTAssertTrue(waitForValue("BBB", in: source), "a click on the thumbnail did not load the icon")

        // File ▸ Load from Library brings the selected icon back after an edit.
        source.click()
        source.typeKey("a", modifierFlags: .command)
        source.typeText("ZZZ")
        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(waitForValue("BBB", in: source), "⌘O did not reload the selected icon")

        // A double click on the thumbnail starts a rename.
        thumbnail(of: app.staticTexts["First"]).doubleClick()
        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "a double click on the thumbnail did not start a rename")
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Renamed\r")
        XCTAssertTrue(app.staticTexts["Renamed"].waitForExistence(timeout: 5), "the rename did not stick")
    }

    /// Types a source, saves it with ⌘S and names the new row.
    @MainActor
    private func save(_ app: XCUIApplication, text: String, as name: String) {
        let source = app.textFields["Text or Emoji"]
        source.click()
        source.typeKey("a", modifierFlags: .command)
        source.typeText(text)
        app.typeKey("s", modifierFlags: .command)

        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "⌘S did not save an icon")
        field.typeKey("a", modifierFlags: .command)
        field.typeText("\(name)\r")
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5), "the name did not stick")
    }

    /// The thumbnail sits left of the name, 36 points wide with 10 between.
    @MainActor
    private func thumbnail(of name: XCUIElement) -> XCUICoordinate {
        name.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: -28, dy: 6))
    }

    private func waitForValue(_ value: String, in element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)],
                              timeout: 5) == .completed
    }
}
