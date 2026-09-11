//
//  ColourWheelUITests.swift
//  Folder CrestUITests
//
//  The colour wheel in the folder colour tab used to sit on top of a hidden
//  `ColorPicker`; its own button swallowed the click, so the wheel applied a
//  tint instead of opening the picker. This drives the real click.
//

import XCTest

final class ColourWheelUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testColourWheelOpensTheColourPanel() throws {
        let app = XCUIApplication()
        // Pin the language: the labels clicked below are the English ones
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()

        app.radioButtons["Folder Color"].click()

        let wheel = app.buttons["Custom Color"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 5), "colour wheel not found")
        wheel.click()

        let panel = app.windows["Colors"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5),
                      "clicking the wheel did not open the colour panel")
    }
}
