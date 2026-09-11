//
//  Resample.swift
//  Folder Crest
//
//  Pillow-compatible bicubic resampling.
//
//  `Image.resize` defaults to bicubic, and Pillow scales the filter support by
//  the downscale factor, so shrinking averages over the whole source region
//  instead of point-sampling four neighbours. Core Graphics interpolation does
//  something else entirely, which is why this is reimplemented rather than
//  handed to a context.
//
//  Structure follows Pillow's Resample.c: coefficients per output pixel,
//  normalised to sum to one, a horizontal pass and then a vertical one, with
//  the result rounded back to 8 bits in between.
//

import Foundation

enum Resample {

    /// Pillow's bicubic kernel, Catmull-Rom with a = -0.5, support 2.
    private static let support = 2.0

    private static func kernel(_ x: Double) -> Double {
        let a = -0.5
        let x = abs(x)
        if x < 1.0 { return ((a + 2.0) * x - (a + 3.0)) * x * x + 1 }
        if x < 2.0 { return (((x - 5) * x + 8) * x - 4) * a }
        return 0.0
    }

    private struct Coefficients {
        var start: [Int]
        var weights: [[Double]]
    }

    private static func coefficients(inSize: Int, outSize: Int) -> Coefficients {
        let scale = Double(inSize) / Double(outSize)
        // Shrinking widens the filter, so every source pixel contributes
        let filterScale = max(scale, 1.0)
        let support = Self.support * filterScale

        var start = [Int](repeating: 0, count: outSize)
        var weights = [[Double]](repeating: [], count: outSize)

        for out in 0..<outSize {
            let centre = (Double(out) + 0.5) * scale
            let from = max(Int(centre - support + 0.5), 0)
            let to = min(Int(centre + support + 0.5), inSize)

            var row = [Double]()
            row.reserveCapacity(to - from)
            var total = 0.0
            for index in from..<to {
                let weight = kernel((Double(index) - centre + 0.5) / filterScale)
                row.append(weight)
                total += weight
            }
            if total != 0 {
                for i in row.indices { row[i] /= total }
            }

            start[out] = from
            weights[out] = row
        }
        return Coefficients(start: start, weights: weights)
    }

    /// Resizes with the same arithmetic Pillow uses, including the rounding
    /// between the two passes.
    ///
    /// - Parameter alphaWeighted: Weight the colour channels by alpha while
    ///   resampling. Pillow does this for RGBA images — verified 2026-09-10:
    ///   scaling a half opaque-red, half transparent-blue strip bleeds no blue
    ///   at all, and fully transparent output pixels come back as zero. Leave
    ///   it off for an engraving mask, which is a single channel image on the
    ///   Python side and carries no alpha to weight by.
    static func resize(_ source: PixelBuffer, width: Int, height: Int,
                       alphaWeighted: Bool = false) -> PixelBuffer {
        guard width > 0, height > 0 else { return PixelBuffer(width: 0, height: 0) }
        guard width != source.width || height != source.height else { return source }

        var working = source
        if alphaWeighted { premultiply(&working) }

        let horizontal = resizeHorizontally(working, to: width)
        var result = resizeVertically(horizontal, to: height)

        if alphaWeighted { unpremultiply(&result) }
        return result
    }

    private static func premultiply(_ buffer: inout PixelBuffer) {
        for i in stride(from: 0, to: buffer.pixels.count, by: PixelBuffer.bytesPerPixel) {
            let alpha = Int(buffer.pixels[i + 3])
            guard alpha < 255 else { continue }
            for channel in 0..<3 {
                buffer.pixels[i + channel] =
                    UInt8(muldiv255(Int(buffer.pixels[i + channel]), alpha))
            }
        }
    }

    private static func unpremultiply(_ buffer: inout PixelBuffer) {
        for i in stride(from: 0, to: buffer.pixels.count, by: PixelBuffer.bytesPerPixel) {
            let alpha = Int(buffer.pixels[i + 3])
            guard alpha > 0, alpha < 255 else {
                if alpha == 0 {
                    buffer.pixels[i] = 0; buffer.pixels[i + 1] = 0; buffer.pixels[i + 2] = 0
                }
                continue
            }
            for channel in 0..<3 {
                let value = Int(buffer.pixels[i + channel]) * 255
                buffer.pixels[i + channel] = UInt8(min((value + alpha / 2) / alpha, 255))
            }
        }
    }

    /// Pillow's `MULDIV255`: `a * b / 255` without a division.
    @inline(__always)
    static func muldiv255(_ a: Int, _ b: Int) -> Int {
        let temp = a * b + 128
        return ((temp >> 8) + temp) >> 8
    }

    private static func resizeHorizontally(_ source: PixelBuffer, to width: Int) -> PixelBuffer {
        guard width != source.width else { return source }

        let coefficients = coefficients(inSize: source.width, outSize: width)
        var result = PixelBuffer(width: width, height: source.height)
        let bytes = PixelBuffer.bytesPerPixel

        source.pixels.withUnsafeBufferPointer { input in
            result.pixels.withUnsafeMutableBufferPointer { output in
                for y in 0..<source.height {
                    let sourceRow = y * source.width * bytes
                    let targetRow = y * width * bytes
                    for x in 0..<width {
                        let from = coefficients.start[x]
                        let weights = coefficients.weights[x]
                        for channel in 0..<bytes {
                            var sum = 0.0
                            for (i, weight) in weights.enumerated() {
                                sum += weight * Double(input[sourceRow + (from + i) * bytes + channel])
                            }
                            output[targetRow + x * bytes + channel] = clip8(sum)
                        }
                    }
                }
            }
        }
        return result
    }

    private static func resizeVertically(_ source: PixelBuffer, to height: Int) -> PixelBuffer {
        guard height != source.height else { return source }

        let coefficients = coefficients(inSize: source.height, outSize: height)
        var result = PixelBuffer(width: source.width, height: height)
        let bytes = PixelBuffer.bytesPerPixel
        let rowBytes = source.width * bytes

        source.pixels.withUnsafeBufferPointer { input in
            result.pixels.withUnsafeMutableBufferPointer { output in
                for y in 0..<height {
                    let from = coefficients.start[y]
                    let weights = coefficients.weights[y]
                    for x in 0..<source.width {
                        for channel in 0..<bytes {
                            var sum = 0.0
                            for (i, weight) in weights.enumerated() {
                                sum += weight * Double(input[(from + i) * rowBytes + x * bytes + channel])
                            }
                            output[y * rowBytes + x * bytes + channel] = clip8(sum)
                        }
                    }
                }
            }
        }
        return result
    }

    @inline(__always)
    private static func clip8(_ value: Double) -> UInt8 {
        let rounded = value.rounded()
        if rounded <= 0 { return 0 }
        if rounded >= 255 { return 255 }
        return UInt8(rounded)
    }
}
