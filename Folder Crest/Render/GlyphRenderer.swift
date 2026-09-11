//
//  GlyphRenderer.swift
//  Folder Crest
//
//  Turns text into the grayscale mask the engraving works from: white subject
//  on black, cropped to the same box Pillow produces.
//
//  Pillow measures that box with mixed metrics, verified against the reference
//  on 2026-09-10: **horizontally the advance width** of the laid out line,
//  **vertically the ink extent** of the glyphs. For "A" at 512 pt Bold that is
//  353 × 371, with the ink itself sitting at x = 15...338 — the horizontal side
//  bearings are part of the box, the vertical ones are not.
//
//  Core Text draws the line rather than SwiftUI text so that the glyph to mask
//  step stays under our control, the way Pillow's ImageFont + mask does. AppKit
//  only supplies the font descriptor for the rounded system face.
//

import AppKit
import CoreGraphics
import CoreText
import Foundation

enum GlyphRenderer {

    /// Core Text's own attribute keys, spelled out rather than taken from
    /// AppKit: the line is laid out and drawn by Core Text, not by AppKit.
    private static let fontAttribute = kCTFontAttributeName as NSAttributedString.Key
    private static let colourAttribute =
        kCTForegroundColorAttributeName as NSAttributedString.Key

    /// Builds the icon mask for a piece of text.
    ///
    /// - Returns: A mask with the subject in white on black, or `nil` if the
    ///   text produces no glyphs at all.
    static func mask(text: String, imageSize: Int, weight: SFFont) -> PixelBuffer? {
        guard !text.isEmpty else { return nil }

        let font = weight.roundedSystemFont(size: Double(imageSize) / 2)
        // The colour has to ride on the string: CTLineDraw ignores the
        // context's fill colour and would paint nothing at all
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [
                Self.fontAttribute: font,
                Self.colourAttribute: CGColor(gray: 1, alpha: 1),
            ]))

        // Horizontal: the advance. Vertical: where the outlines actually reach.
        let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

        // FreeType hands Pillow an integer ink box, flooring the bottom edge
        // and ceiling the top one. Rounding the height instead is off by a
        // pixel on about half the glyphs — verified on 2026-09-10.
        let inkBottom = ink.minY.rounded(.down)
        let inkTop = ink.maxY.rounded(.up)

        let width = Int(advance.rounded())
        let height = Int(inkTop - inkBottom)
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width
        var gray = [UInt8](repeating: 0, count: bytesPerRow * height)

        let drawn: Bool = gray.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }

            // The context has y up, so placing the baseline this far above the
            // bottom edge puts the top of the ink exactly on the top edge
            context.textPosition = CGPoint(x: 0, y: -inkBottom)
            CTLineDraw(line, context)
            return true
        }
        guard drawn else { return nil }

        // Widen the single channel into the RGBA buffer the pipeline works in
        var mask = PixelBuffer(width: width, height: height)
        for i in 0..<(width * height) {
            let level = gray[i]
            let base = i * PixelBuffer.bytesPerPixel
            mask.pixels[base] = level
            mask.pixels[base + 1] = level
            mask.pixels[base + 2] = level
            mask.pixels[base + 3] = level
        }
        return mask
    }
}

extension SFFont {

    /// The macOS rounded system face for this weight — SF Rounded ships with
    /// the OS, so nothing has to be bundled or registered.
    ///
    /// Its outlines are the same design as the SF Pro Rounded release the
    /// Python reference uses, but not byte for byte the same cut: about 1.5 %
    /// of the mask pixels differ along the glyph edges, and an occasional ink
    /// box comes out a pixel shorter. Accepted deliberately on 2026-09-11 in
    /// exchange for dropping 55 MB of font files from the bundle.
    func roundedSystemFont(size: Double) -> CTFont {
        let system = NSFont.systemFont(ofSize: size, weight: nsWeight)
        // A missing rounded variant would be an OS without SF Rounded, which
        // no supported macOS is — fall back to the plain system face anyway
        // rather than trade a font substitution for a crash.
        guard let rounded = system.fontDescriptor.withDesign(.rounded) else { return system }
        return CTFontCreateWithFontDescriptor(rounded, size, nil)
    }

    private var nsWeight: NSFont.Weight {
        switch self {
        case .ultralight: .ultraLight
        case .thin:       .thin
        case .light:      .light
        case .regular:    .regular
        case .medium:     .medium
        case .semibold:   .semibold
        case .bold:       .bold
        case .heavy:      .heavy
        case .black:      .black
        }
    }
}

// MARK: - Colour emoji

extension GlyphRenderer {

    /// Draws the text with the system emoji font, keeping the emoji colours.
    ///
    /// Emoji have no glyphs in SF Pro Rounded and carry their own colours, so
    /// they take the second render path: composited on top of the folder
    /// instead of engraved into it.
    ///
    /// - Returns: The emoji, cropped to its ink, or `nil` if the text contains
    ///   nothing the emoji font can draw.
    static func colourEmoji(_ text: String) -> PixelBuffer? {
        guard !text.isEmpty else { return nil }

        let size = Constants.emojiFontSize
        let font = CTFontCreateWithName(Constants.emojiFontName as CFString, size, nil)
        guard hasEmojiGlyph(text, in: font) else { return nil }

        // An empty cascade list keeps Core Text from falling back to a text
        // font for the characters the emoji font cannot draw — the reference
        // draws nothing for those, and so must this
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontCascadeListAttribute: [] as CFArray,
        ] as CFDictionary)
        let emojiFont = CTFontCreateCopyWithAttributes(font, size, nil, descriptor)

        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [Self.fontAttribute: emojiFont]))

        // Generous canvas: the ink is cropped out of it afterwards
        let width = Int(size * 8), height = Int(size * 3)
        var buffer = PixelBuffer(width: width, height: height)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let advance = CTLineGetTypographicBounds(line, nil, nil, nil)

        let drawn: Bool = buffer.pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * PixelBuffer.bytesPerPixel,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }

            context.textPosition = CGPoint(x: (Double(width) - advance) / 2,
                                           y: Double(height) / 2 - ink.midY)
            CTLineDraw(line, context)
            return true
        }
        guard drawn else { return nil }

        unpremultiply(&buffer)
        return cropToInk(buffer)
    }

    /// Whether the emoji font can draw at least one character of the text.
    private static func hasEmojiGlyph(_ text: String, in font: CTFont) -> Bool {
        let characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        return glyphs.contains { $0 != 0 }
    }

    /// The context has to be premultiplied — Core Graphics does not offer a
    /// straight-alpha RGBA bitmap — so the colours are divided back out here.
    private static func unpremultiply(_ buffer: inout PixelBuffer) {
        for i in stride(from: 0, to: buffer.pixels.count, by: PixelBuffer.bytesPerPixel) {
            let alpha = Int(buffer.pixels[i + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0..<3 {
                let value = Int(buffer.pixels[i + channel]) * 255
                buffer.pixels[i + channel] = UInt8(min((value + alpha / 2) / alpha, 255))
            }
        }
    }

    /// Crops away everything fully transparent, as `Image.getbbox` does.
    private static func cropToInk(_ buffer: PixelBuffer) -> PixelBuffer? {
        var minX = buffer.width, minY = buffer.height, maxX = 0, maxY = 0
        for y in 0..<buffer.height {
            for x in 0..<buffer.width where buffer[x, y].alpha > 0 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x + 1); maxY = max(maxY, y + 1)
            }
        }
        guard minX < maxX, minY < maxY else { return nil }

        var cropped = PixelBuffer(width: maxX - minX, height: maxY - minY)
        for y in 0..<cropped.height {
            for x in 0..<cropped.width {
                cropped[x, y] = buffer[minX + x, minY + y]
            }
        }
        return cropped
    }
}
