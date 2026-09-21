//
//  FileMenuUITests.swift
//  Folder CrestUITests
//
//  The File menu carries the window's actions with their shortcuts, and the
//  hint under the preview links to SF Symbols. A shortcut on a button inside
//  the window never fired, so both are checked through real key presses and
//  clicks.
//

import XCTest

final class FileMenuUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-ui-testing"]
        app.launch()
        return app
    }

    @MainActor
    func testFileMenuOffersTheWindowActions() throws {
        let app = launch()

        let file = app.menuBarItems["File"]
        XCTAssertTrue(file.waitForExistence(timeout: 10), "no File menu")
        file.click()

        for title in ["Save to Library", "Load from Library", "Reset All", "Apply to Folder"] {
            XCTAssertTrue(app.menuItems[title].exists, "the File menu has no \(title)")
        }
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Nothing was chosen yet, so applying asks where the folder goes — the
    /// sandbox would refuse the Desktop default otherwise. The default icon
    /// has nothing to apply to a new folder, so the icon gets some text first.
    @MainActor
    func testApplyShortcutAsksForTheLocation() throws {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "no window")

        let source = app.textFields["Text or Emoji"]
        XCTAssertTrue(source.waitForExistence(timeout: 10), "no text field")
        source.click()
        source.typeText("A")

        app.typeKey(.return, modifierFlags: .command)

        // The panel's Cancel shows up twice, once as a Touch Bar button that
        // cannot be clicked — Escape dismisses it without picking either
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "⌘↩ did not open the folder chooser")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "the folder chooser did not close")
        XCTAssertFalse(app.sheets.firstMatch.exists, "cancelling still reported an error")
    }

    /// The runner's sandbox can neither look up nor control SF Symbols, so the
    /// proof is that the click reached the link: something else came to the
    /// front. SF Symbols, or the browser without it, stays open afterwards.
    @MainActor
    func testSFSymbolLinkOpensSomething() throws {
        let app = launch()
        let link = app.links["SF Symbol"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "the hint has no SF Symbol link")
        link.click()

        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 15),
                      "clicking the link did not open anything")
    }
}
