//
//  ColourMath.swift
//  Folder Crest
//
//  Ports of the colour and interpolation helpers in foldercrest/utilities.py.
//  These have to match Python's `colorsys` exactly, including its truncating
//  int() conversions — the generated icon is compared against the reference
//  pixel by pixel.
//

import Foundation

/// An 8-bit sRGB colour, the unit the reference implementation works in.
struct RGB: Hashable, Sendable {
    var red, green, blue: Int

    init(_ red: Int, _ green: Int, _ blue: Int) {
        self.red = red; self.green = green; self.blue = blue
    }
}

/// A colour in hue/saturation/value, each in 0...1, as `colorsys` produces.
struct HSV: Hashable, Sendable {
    var hue, saturation, value: Double

    init(_ hue: Double, _ saturation: Double, _ value: Double) {
        self.hue = hue; self.saturation = saturation; self.value = value
    }
}

func clamp<T: Comparable>(_ value: T, _ minimum: T, _ maximum: T) -> T {
    min(max(value, minimum), maximum)
}

/// The colour that, multiplied over `start`, yields `final`.
///
/// The engraving draws the icon in this colour so that the multiply blend
/// against the folder produces the intended icon colour.
func dividedColour(_ start: RGB, _ final: RGB) -> RGB {
    func divide(_ start: Int, _ final: Int) -> Int {
        // Python's int() truncates towards zero; Int(_:) does the same
        clamp(Int(255.0 * Double(final) / Double(start)), 0, 255)
    }
    return RGB(divide(start.red, final.red),
               divide(start.green, final.green),
               divide(start.blue, final.blue))
}

/// Port of `colorsys.rgb_to_hsv`, operating on 0...1 components.
func rgbToHSV(_ red: Double, _ green: Double, _ blue: Double) -> HSV {
    let maxComponent = max(red, green, blue)
    let minComponent = min(red, green, blue)
    let range = maxComponent - minComponent

    guard maxComponent != minComponent else { return HSV(0, 0, maxComponent) }

    let saturation = range / maxComponent
    let redDistance = (maxComponent - red) / range
    let greenDistance = (maxComponent - green) / range
    let blueDistance = (maxComponent - blue) / range

    var hue: Double
    if red == maxComponent {
        hue = blueDistance - greenDistance
    } else if green == maxComponent {
        hue = 2.0 + redDistance - blueDistance
    } else {
        hue = 4.0 + greenDistance - redDistance
    }
    hue = (hue / 6.0).truncatingRemainder(dividingBy: 1.0)
    if hue < 0 { hue += 1.0 }   // Python's % always returns a positive result

    return HSV(hue, saturation, maxComponent)
}

/// Port of `colorsys.hsv_to_rgb`, producing 0...1 components.
func hsvToRGB(_ hsv: HSV) -> (red: Double, green: Double, blue: Double) {
    let value = hsv.value
    guard hsv.saturation != 0.0 else { return (value, value, value) }

    let scaled = hsv.hue * 6.0
    let sector = Int(scaled.rounded(.down))
    let fraction = scaled - Double(sector)

    let p = value * (1.0 - hsv.saturation)
    let q = value * (1.0 - hsv.saturation * fraction)
    let t = value * (1.0 - hsv.saturation * (1.0 - fraction))

    switch ((sector % 6) + 6) % 6 {
    case 0:  return (value, t, p)
    case 1:  return (q, value, p)
    case 2:  return (p, value, t)
    case 3:  return (p, q, value)
    case 4:  return (t, p, value)
    default: return (value, p, q)
    }
}

func rgbIntToHSV(_ colour: RGB) -> HSV {
    rgbToHSV(Double(colour.red) / 255, Double(colour.green) / 255, Double(colour.blue) / 255)
}

func hsvToRGBInt(_ hsv: HSV) -> RGB {
    let (red, green, blue) = hsvToRGB(hsv)
    // Python's int() truncates, it does not round
    return RGB(Int(red * 255), Int(green * 255), Int(blue * 255))
}

// MARK: - Slider interpolation

func interpolate(_ value: Double, _ preMin: Double, _ preMax: Double,
                 _ postMin: Double, _ postMax: Double) -> Double {
    ((postMax - postMin) * value + preMax * postMin - preMin * postMax) / (preMax - preMin)
}

/// Maps an integer slider position onto a range with a fixed value at the
/// middle tick, so that the neutral setting is exactly reachable.
func interpolateIntToFloatWithMidpoint(_ value: Int, _ preMin: Int, _ preMax: Int,
                                       _ postMin: Double, _ postMid: Double,
                                       _ postMax: Double) -> Double {
    let preMid = (preMax - preMin) / 2 + 1

    if value == preMid {
        return postMid
    } else if value < preMid {
        return interpolate(Double(value), Double(preMin), Double(preMid), postMin, postMid)
    } else {
        return interpolate(Double(value), Double(preMid), Double(preMax), postMid, postMax)
    }
}
