//
//  TintCube.swift
//  Folder Crest
//
//  The folder tint, as a 3D colour lookup table.
//
//  The reference shifts every pixel by the amount that would move the folder's
//  base colour to the chosen tint — hue by offset, saturation and value by
//  factor — and it does so through a **4×4×4** LUT with trilinear
//  interpolation. That coarseness is not an accident of implementation, it is
//  part of the look: a per-pixel conversion would give visibly different
//  colours. The alpha channel is left alone.
//

import Foundation

enum TintCube {

    /// Edge length of the cube. Pillow's `Color3DLUT.generate(4, …)`.
    static let size = 4

    /// Recolours the buffer so that `base` would land on `tint`.
    static func apply(to buffer: inout PixelBuffer, base: RGB, tint: RGB) {
        let table = makeTable(base: base, tint: tint)

        // Every 8-bit level maps to the same cube position, so the position and
        // its weight are worth precomputing once instead of a million times
        var cell = [Int](repeating: 0, count: 256)
        var fraction = [Double](repeating: 0, count: 256)
        for value in 0..<256 {
            let position = Double(value) * Double(size - 1) / 255
            let lower = min(Int(position), size - 2)
            cell[value] = lower
            fraction[value] = position - Double(lower)
        }

        for i in stride(from: 0, to: buffer.pixels.count, by: PixelBuffer.bytesPerPixel) {
            let r = Int(buffer.pixels[i])
            let g = Int(buffer.pixels[i + 1])
            let b = Int(buffer.pixels[i + 2])

            let colour = interpolate(table: table,
                                     cell: (cell[r], cell[g], cell[b]),
                                     fraction: (fraction[r], fraction[g], fraction[b]))
            buffer.pixels[i] = clip8(colour.red)
            buffer.pixels[i + 1] = clip8(colour.green)
            buffer.pixels[i + 2] = clip8(colour.blue)
            // alpha untouched: the reference generates the LUT with 3 channels
        }
    }

    private struct Entry { var red, green, blue: Double }

    /// Cube entries, ordered as Pillow does: red fastest, then green, then blue.
    private static func makeTable(base: RGB, tint: RGB) -> [Entry] {
        let start = rgbIntToHSV(base)
        let final = rgbIntToHSV(tint)

        let hueOffset = final.hue - start.hue
        let saturationFactor = start.saturation == 0 ? 1 : final.saturation / start.saturation
        let valueFactor = start.value == 0 ? 1 : final.value / start.value

        var table = [Entry]()
        table.reserveCapacity(size * size * size)

        let step = Double(size - 1)
        for blue in 0..<size {
            for green in 0..<size {
                for red in 0..<size {
                    let hsv = rgbToHSV(Double(red) / step, Double(green) / step,
                                       Double(blue) / step)
                    var hue = (hsv.hue + hueOffset).truncatingRemainder(dividingBy: 1.0)
                    if hue < 0 { hue += 1.0 }
                    let shifted = HSV(hue,
                                      clamp(hsv.saturation * saturationFactor, 0.0, 1.0),
                                      clamp(hsv.value * valueFactor, 0.0, 1.0))
                    let (r, g, b) = hsvToRGB(shifted)
                    table.append(Entry(red: r, green: g, blue: b))
                }
            }
        }
        return table
    }

    private static func interpolate(table: [Entry], cell: (Int, Int, Int),
                                    fraction: (Double, Double, Double)) -> Entry {
        @inline(__always)
        func entry(_ dr: Int, _ dg: Int, _ db: Int) -> Entry {
            table[((cell.2 + db) * size + cell.1 + dg) * size + cell.0 + dr]
        }
        @inline(__always)
        func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

        var result = Entry(red: 0, green: 0, blue: 0)
        for channel in 0..<3 {
            func value(_ e: Entry) -> Double {
                channel == 0 ? e.red : channel == 1 ? e.green : e.blue
            }
            let c00 = mix(value(entry(0, 0, 0)), value(entry(1, 0, 0)), fraction.0)
            let c10 = mix(value(entry(0, 1, 0)), value(entry(1, 1, 0)), fraction.0)
            let c01 = mix(value(entry(0, 0, 1)), value(entry(1, 0, 1)), fraction.0)
            let c11 = mix(value(entry(0, 1, 1)), value(entry(1, 1, 1)), fraction.0)

            let c0 = mix(c00, c10, fraction.1)
            let c1 = mix(c01, c11, fraction.1)
            let mixed = mix(c0, c1, fraction.2)

            switch channel {
            case 0: result.red = mixed
            case 1: result.green = mixed
            default: result.blue = mixed
            }
        }
        return result
    }

    @inline(__always)
    private static func clip8(_ value: Double) -> UInt8 {
        UInt8(clamp((value * 255).rounded(), 0, 255))
    }
}
