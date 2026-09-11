//
//  IconRenderer.swift
//  Folder Crest
//
//  The engraving pipeline, ported step for step from
//  `imagetransformations.generate_folder_icon`.
//
//  Three things in the original are easy to read past and change the result:
//    * the mask is pasted onto black using *itself* as the alpha, so what the
//      shadow layer sees is mask², not mask,
//    * `ImageChops.multiply` on RGBA multiplies the alpha channel too — that is
//      what makes the final alpha composite work,
//    * every float to int conversion in Pillow truncates towards zero.
//

import CoreGraphics
import Foundation

enum IconRenderer {

    /// Renders the folder icon. Long running: callers should hand it a
    /// cancellation check so a superseded render stops early.
    static func makeIcon(_ recipe: IconRecipe,
                         isCancelled: () -> Bool = { false }) throws -> PixelBuffer {

        struct Cancelled: Error {}
        func checkpoint() throws { if isCancelled() { throw Cancelled() } }

        let style = recipe.style
        let size = style.size
        let parameters = recipe.engrave

        var folder = try PixelBuffer.folderImage(style)
        increaseShadow(&folder, factor: parameters.folderShadowFactor)
        try checkpoint()

        // Nothing to draw on top
        guard recipe.source.method != .none else {
            return tinted(folder, style: style, tint: recipe.tint)
        }

        // Where the icon goes. The offset shifts the paste, not the box, so
        // moving the icon around never changes its size.
        let box = iconBox(style: style, scale: recipe.scale * parameters.iconBoxScale)
        let offset = (x: Int(Double(size) * recipe.offset.x),
                      y: Int(Double(size) * recipe.offset.y))
        try checkpoint()

        // An image kept in its own colours is pasted on top, not engraved
        if case .image(let image, preserveColours: true) = recipe.source {
            return compositeOriginalColours(folder: folder, image: image, box: box,
                                            offset: offset, style: style, tint: recipe.tint)
        }

        // Emoji have no glyphs in SF Pro Rounded and bring their own colours,
        // so they take the same path as a colour image
        if case .text(let text) = recipe.source, let emoji = GlyphRenderer.colourEmoji(text) {
            try checkpoint()
            return compositeOriginalColours(folder: folder, image: emoji, box: box,
                                            offset: offset, style: style, tint: recipe.tint)
        }
        try checkpoint()

        guard let mask = maskImage(for: recipe) else {
            return tinted(folder, style: style, tint: recipe.tint)
        }
        try checkpoint()

        let formattedMask = fitMask(mask, into: box, offset: offset, canvas: size)
        try checkpoint()

        let engraved = try engrave(folder: folder, mask: formattedMask,
                                   style: style, parameters: parameters,
                                   checkpoint: checkpoint)
        return tinted(engraved, style: style, tint: recipe.tint)
    }

    private static func tinted(_ buffer: PixelBuffer, style: FolderStyle,
                               tint: RGB?) -> PixelBuffer {
        guard let tint else { return buffer }
        var result = buffer
        TintCube.apply(to: &result, base: style.baseColour, tint: tint)
        return result
    }

    /// Pastes the image on top of the folder in its own colours. The tint is
    /// applied to the folder *first*, so it does not recolour the pasted image.
    private static func compositeOriginalColours(
        folder: PixelBuffer, image: PixelBuffer, box: Box,
        offset: (x: Int, y: Int), style: FolderStyle, tint: RGB?) -> PixelBuffer {

        var result = tinted(folder, style: style, tint: tint)

        let ratio = min(box.width / Double(image.width), box.height / Double(image.height))
        let scaled = Resample.resize(image,
                                     width: Int(Double(image.width) * ratio),
                                     height: Int(Double(image.height) * ratio),
                                     alphaWeighted: true)
        guard scaled.width > 0, scaled.height > 0 else { return result }

        let startX = Int(box.x1) + Int((box.width - Double(scaled.width)) / 2) + offset.x
        let startY = Int(box.y1) + Int((box.height - Double(scaled.height)) / 2) + offset.y

        for y in 0..<scaled.height {
            let targetY = startY + y
            guard targetY >= 0, targetY < result.height else { continue }
            for x in 0..<scaled.width {
                let targetX = startX + x
                guard targetX >= 0, targetX < result.width else { continue }
                result[targetX, targetY] = alphaComposite(over: scaled[x, y],
                                                          under: result[targetX, targetY])
            }
        }
        return result
    }

    // MARK: - Steps

    /// Darkens the folder's drop shadow to match the default macOS folders, by
    /// raising the opacity of every partly transparent pixel.
    private static func increaseShadow(_ folder: inout PixelBuffer, factor: Double) {
        for i in stride(from: 3, to: folder.pixels.count, by: PixelBuffer.bytesPerPixel) {
            folder.pixels[i] = UInt8(min(Int(Double(folder.pixels[i]) * factor), 255))
        }
    }

    /// The box the icon is fitted into, scaled from its centre.
    private static func iconBox(style: FolderStyle, scale: Double) -> Box {
        let size = Double(style.size)
        let percentages = style.iconBoxPercentages
        let box = Box(Double(Int(size * percentages.x1)), Double(Int(size * percentages.y1)),
                      Double(Int(size * percentages.x2)), Double(Int(size * percentages.y2)))

        let centre = (x: Double(Int((box.x2 + box.x1) / 2)),
                      y: Double(Int((box.y2 + box.y1) / 2)))

        // Truncation towards zero, as Python's int() does — for the negative
        // top offsets that rounds up, which is not the same as flooring
        let topOffset = (x: Double(Int((box.x1 - centre.x) * scale)),
                         y: Double(Int((box.y1 - centre.y) * scale)))
        let bottomOffset = (x: Double(Int((box.x2 - centre.x) * scale)),
                            y: Double(Int((box.y2 - centre.y) * scale)))

        return Box(max(0, centre.x + topOffset.x),
                   max(0, centre.y + topOffset.y),
                   min(size, centre.x + bottomOffset.x),
                   min(size, centre.y + bottomOffset.y))
    }

    private static func maskImage(for recipe: IconRecipe) -> PixelBuffer? {
        switch recipe.source {
        case .none:
            nil
        case .text(let text):
            GlyphRenderer.mask(text: text, imageSize: recipe.style.size,
                               weight: recipe.fontWeight)
        case .image(let image, _):
            ImageMask.mask(from: image)
        }
    }

    /// Scales the mask into the box and pastes it onto a black canvas.
    ///
    /// The paste uses the mask as its own alpha, exactly as the reference does,
    /// so a grey pixel lands at grey² — that squaring is part of the look, not
    /// an accident.
    private static func fitMask(_ mask: PixelBuffer, into box: Box,
                                offset: (x: Int, y: Int), canvas: Int) -> PixelBuffer {
        var formatted = PixelBuffer(width: canvas, height: canvas)

        let boxWidth = box.width, boxHeight = box.height
        guard boxWidth > 0, boxHeight > 0, mask.width > 0, mask.height > 0 else { return formatted }

        let ratio = min(boxWidth / Double(mask.width), boxHeight / Double(mask.height))
        let scaled = Resample.resize(mask,
                                     width: Int(Double(mask.width) * ratio),
                                     height: Int(Double(mask.height) * ratio))
        guard scaled.width > 0, scaled.height > 0 else { return formatted }

        let startX = Int(box.x1) + Int((boxWidth - Double(scaled.width)) / 2) + offset.x
        let startY = Int(box.y1) + Int((boxHeight - Double(scaled.height)) / 2) + offset.y

        for y in 0..<scaled.height {
            let targetY = startY + y
            guard targetY >= 0, targetY < canvas else { continue }
            for x in 0..<scaled.width {
                let targetX = startX + x
                guard targetX >= 0, targetX < canvas else { continue }

                let level = Int(scaled[x, y].red)
                // Paste over black using the mask as the alpha: level² / 255
                let squared = UInt8(Resample.muldiv255(level, level))
                formatted[targetX, targetY] = RGBA(squared, squared, squared, squared)
            }
        }
        return formatted
    }

    /// Builds the inner shadow and outer highlight layers and combines them
    /// with the folder.
    private static func engrave(folder: PixelBuffer, mask: PixelBuffer,
                                style: FolderStyle, parameters: EngraveParameters,
                                checkpoint: () throws -> Void) throws -> PixelBuffer {
        let size = folder.width

        // The colour that, multiplied over the folder, yields the icon colour
        let centre = dividedColour(style.baseColour, style.iconColour)
        let centreHSV = rgbIntToHSV(centre)
        let shadowColour = hsvToRGBInt(HSV(centreHSV.hue, centreHSV.saturation,
                                           centreHSV.value * parameters.innerShadowValueScale))
        try checkpoint()

        // Inner shadow: the icon colour on the mask, the darker shade off it
        var shadow = PixelBuffer(width: size, height: size)
        for i in 0..<(size * size) {
            let level = Int(mask.pixels[i * PixelBuffer.bytesPerPixel])
            let base = i * PixelBuffer.bytesPerPixel
            shadow.pixels[base] = composite(centre.red, shadowColour.red, level)
            shadow.pixels[base + 1] = composite(centre.green, shadowColour.green, level)
            shadow.pixels[base + 2] = composite(centre.blue, shadowColour.blue, level)
            shadow.pixels[base + 3] = 255
        }
        try checkpoint()

        BoxBlur.blur(&shadow, sigma: parameters.innerShadowBlur)
        shiftDown(&shadow, by: Int((Double(size) * parameters.innerShadowYOffset).rounded(.down)))
        try checkpoint()

        // Outer highlight: a near black wash that is added, not multiplied
        var highlight = PixelBuffer(width: size, height: size)
        for i in 0..<(size * size) {
            let level = Int(mask.pixels[i * PixelBuffer.bytesPerPixel])
            let value = composite(parameters.outerHighlightLevel, 0, level)
            let base = i * PixelBuffer.bytesPerPixel
            highlight.pixels[base] = value
            highlight.pixels[base + 1] = value
            highlight.pixels[base + 2] = value
            highlight.pixels[base + 3] = 255
        }
        try checkpoint()

        BoxBlur.blur(&highlight, sigma: parameters.outerHighlightBlur)
        shiftDown(&highlight, by: Int((Double(size) * parameters.outerHighlightYOffset).rounded(.down)))
        try checkpoint()

        // Combine: the shadow layer over the highlighted folder
        var result = PixelBuffer(width: size, height: size)
        for i in 0..<(size * size) {
            let base = i * PixelBuffer.bytesPerPixel
            let maskLevel = Int(mask.pixels[base])
            let folderAlpha = Int(folder.pixels[base + 3])

            // add(folder, highlight): highlight's alpha was zeroed first, so
            // only the colour channels move and the folder keeps its alpha
            var under = RGBA(0, 0, 0, UInt8(folderAlpha))
            under.red = addClamped(folder.pixels[base], highlight.pixels[base])
            under.green = addClamped(folder.pixels[base + 1], highlight.pixels[base + 1])
            under.blue = addClamped(folder.pixels[base + 2], highlight.pixels[base + 2])

            // multiply(folder, shadow) with the mask as the shadow's alpha —
            // the alpha channel takes part in the multiply
            let over = RGBA(multiply(folder.pixels[base], shadow.pixels[base]),
                            multiply(folder.pixels[base + 1], shadow.pixels[base + 1]),
                            multiply(folder.pixels[base + 2], shadow.pixels[base + 2]),
                            UInt8(Resample.muldiv255(folderAlpha, maskLevel)))

            let combined = alphaComposite(over: over, under: under)
            result.pixels[base] = combined.red
            result.pixels[base + 1] = combined.green
            result.pixels[base + 2] = combined.blue
            result.pixels[base + 3] = combined.alpha
        }
        try checkpoint()

        return result
    }

    // MARK: - Pixel arithmetic

    /// `Image.composite`: `white` where the mask is lit, `black` where it is not.
    @inline(__always)
    private static func composite(_ white: Int, _ black: Int, _ level: Int) -> UInt8 {
        UInt8(Resample.muldiv255(white, level) + Resample.muldiv255(black, 255 - level))
    }

    @inline(__always)
    private static func multiply(_ a: UInt8, _ b: UInt8) -> UInt8 {
        UInt8(Resample.muldiv255(Int(a), Int(b)))
    }

    @inline(__always)
    private static func addClamped(_ a: UInt8, _ b: UInt8) -> UInt8 {
        UInt8(min(Int(a) + Int(b), 255))
    }

    /// Porter-Duff source over, on non-premultiplied 8-bit values.
    private static func alphaComposite(over: RGBA, under: RGBA) -> RGBA {
        let overAlpha = Double(over.alpha) / 255
        let underAlpha = Double(under.alpha) / 255
        let outAlpha = overAlpha + underAlpha * (1 - overAlpha)
        guard outAlpha > 0 else { return RGBA(0, 0, 0, 0) }

        func channel(_ o: UInt8, _ u: UInt8) -> UInt8 {
            let value = (Double(o) * overAlpha + Double(u) * underAlpha * (1 - overAlpha)) / outAlpha
            return UInt8(clamp(value.rounded(), 0, 255))
        }
        return RGBA(channel(over.red, under.red),
                    channel(over.green, under.green),
                    channel(over.blue, under.blue),
                    UInt8((outAlpha * 255).rounded()))
    }

    /// `ImageChops.offset` in the y direction: the image wraps around.
    private static func shiftDown(_ buffer: inout PixelBuffer, by rows: Int) {
        guard rows != 0, buffer.height > 0 else { return }
        let rowBytes = buffer.width * PixelBuffer.bytesPerPixel
        let shift = ((rows % buffer.height) + buffer.height) % buffer.height
        guard shift != 0 else { return }

        var shifted = [UInt8](repeating: 0, count: buffer.pixels.count)
        for y in 0..<buffer.height {
            let source = ((y - shift) + buffer.height) % buffer.height
            let from = source * rowBytes
            shifted.replaceSubrange(y * rowBytes ..< (y + 1) * rowBytes,
                                    with: buffer.pixels[from ..< from + rowBytes])
        }
        buffer.pixels = shifted
    }
}
