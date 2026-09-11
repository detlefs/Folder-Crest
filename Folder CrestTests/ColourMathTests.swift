//
//  ColourMathTests.swift
//  Folder CrestTests
//
//  Expected values were produced by the Python reference implementation, not
//  re-derived here — these tests exist to catch drift away from it. The two
//  folder colours are the exception: they are measured off the system's own
//  folder icon, so their expected values come from `colorsys` run over the
//  measured pair rather than from a fixture.
//

import Testing
@testable import Folder_Crest

struct ColourMathTests {

    @Test("dividedColour turns the folder's two colours into the engraving colour")
    func centreColour() {
        #expect(dividedColour(FolderGraphic.baseColour, FolderGraphic.iconColour)
                == RGB(222, 219, 220))
    }

    @Test("The inner shadow colour is the centre colour at 90 % value")
    func shadowColour() {
        let expected = RGB(199, 197, 198)
        let centre = dividedColour(FolderGraphic.baseColour, FolderGraphic.iconColour)
        let hsv = rgbIntToHSV(centre)
        let shadow = HSV(hsv.hue, hsv.saturation,
                         hsv.value * Constants.innerShadowColourScalingFactor)
        #expect(hsvToRGBInt(shadow) == expected)
    }

    @Test("rgbToHSV matches colorsys",
          arguments: [
            (RGB(116, 208, 251), HSV(0.5530864198, 0.5378486056, 0.9843137255)),
            (RGB(195, 118, 124), HSV(0.9870129870, 0.3948717949, 0.7647058824)),
            (RGB(255, 0, 0),     HSV(0.0, 1.0, 1.0)),
            (RGB(0, 0, 0),       HSV(0.0, 0.0, 0.0)),
            (RGB(53, 160, 225),  HSV(0.5629844961, 0.7644444444, 0.8823529412)),
            (RGB(225, 224, 221), HSV(0.1250000000, 0.0177777778, 0.8823529412)),
          ])
    func rgbToHSVConversion(colour: RGB, expected: HSV) {
        let hsv = rgbIntToHSV(colour)
        #expect(abs(hsv.hue - expected.hue) < 1e-9)
        #expect(abs(hsv.saturation - expected.saturation) < 1e-9)
        #expect(abs(hsv.value - expected.value) < 1e-9)
    }

    /// A round trip must survive the truncating int conversions, otherwise the
    /// tint LUT drifts a channel at a time.
    @Test func hsvRoundTrip() {
        for red in stride(from: 0, through: 255, by: 17) {
            for green in stride(from: 0, through: 255, by: 51) {
                for blue in stride(from: 0, through: 255, by: 51) {
                    let colour = RGB(red, green, blue)
                    let restored = hsvToRGBInt(rgbIntToHSV(colour))
                    // int() truncation costs at most one unit per channel
                    #expect(abs(restored.red - colour.red) <= 1)
                    #expect(abs(restored.green - colour.green) <= 1)
                    #expect(abs(restored.blue - colour.blue) <= 1)
                }
            }
        }
    }

    @Test("The scale slider hits its endpoints and neutral centre exactly",
          arguments: [(1, 0.1), (8, 0.52), (16, 1.0),
                      (17, 1.0666666667), (24, 1.5333333333), (31, 2.0)])
    func scaleSlider(tick: Int, expected: Double) {
        let scale = interpolateIntToFloatWithMidpoint(
            tick, 1, Constants.iconScaleSliderMax,
            Constants.minimumIconScaleValue, 1.0, Constants.maximumIconScaleValue)
        #expect(abs(scale - expected) < 1e-9)
    }
}
