//
//  ImageMask.swift
//  Folder Crest
//
//  Turns a dropped image into an engraving mask.
//
//  The reference composites the image onto white, converts to luminance,
//  normalises with a sigmoid, and inverts — so a dark subject on a light or
//  transparent background becomes a white subject on black. The sigmoid is what
//  pushes a photograph towards the two extremes; without it the engraving is
//  mush.
//

import Foundation

enum ImageMask {

    /// Builds the mask: white subject on black.
    static func mask(from image: PixelBuffer) -> PixelBuffer {
        var levels = [UInt8](repeating: 0, count: image.width * image.height)

        // Composite onto white, then take the luminance
        for i in 0..<levels.count {
            let base = i * PixelBuffer.bytesPerPixel
            let alpha = Int(image.pixels[base + 3])
            let red = blendOntoWhite(image.pixels[base], alpha)
            let green = blendOntoWhite(image.pixels[base + 1], alpha)
            let blue = blendOntoWhite(image.pixels[base + 2], alpha)
            levels[i] = luminance(red, green, blue)
        }

        let lookup = normalizeLookup(for: levels)
        var mask = PixelBuffer(width: image.width, height: image.height)
        for i in 0..<levels.count {
            // Invert: the subject is dark, the engraving wants it lit
            let value = 255 - lookup[Int(levels[i])]
            let base = i * PixelBuffer.bytesPerPixel
            mask.pixels[base] = value
            mask.pixels[base + 1] = value
            mask.pixels[base + 2] = value
            mask.pixels[base + 3] = value
        }
        return mask
    }

    /// `paste` with an alpha mask onto a white background.
    @inline(__always)
    private static func blendOntoWhite(_ value: UInt8, _ alpha: Int) -> Int {
        Resample.muldiv255(Int(value), alpha) + Resample.muldiv255(255, 255 - alpha)
    }

    /// Pillow's RGB to L conversion, fixed point and all.
    @inline(__always)
    private static func luminance(_ red: Int, _ green: Int, _ blue: Int) -> UInt8 {
        UInt8(clamp((red * 19595 + green * 38470 + blue * 7471 + 0x8000) >> 16, 0, 255))
    }

    /// Stretches the levels to the full range and pushes them towards the
    /// extremes with a sigmoid. Built as a 256 entry table, which is what
    /// `Image.eval` does — the curve is only ever evaluated per level, never
    /// per pixel.
    private static func normalizeLookup(for levels: [UInt8]) -> [UInt8] {
        guard let lowest = levels.min(), let highest = levels.max() else {
            return (0...255).map { UInt8($0) }
        }
        // A flat image is already "normalised"; the reference catches the
        // division by zero and returns the image untouched
        guard lowest != highest else { return (0...255).map { UInt8($0) } }

        let span = Double(highest) - Double(lowest)
        let steepness = Constants.maskNormalizeSteepness

        return (0...255).map { value in
            let stretched = Double(Int((Double(value) - Double(lowest)) * 255 / span))
            let curved = 255 / (1 + exp(-steepness * (stretched - 127)))
            return UInt8(clamp(curved, 0, 255))
        }
    }
}
