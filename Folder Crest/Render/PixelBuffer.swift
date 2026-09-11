//
//  PixelBuffer.swift
//  Folder Crest
//
//  The unit the whole render pipeline works in: tightly packed 8-bit RGBA in
//  sRGB, with *non-premultiplied* alpha — the same bytes Pillow sees, which is
//  what makes a pixel-exact comparison against the Python reference possible.
//

import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum RenderError: Error, CustomStringConvertible {
    case resourceMissing(String)
    case imageDecodingFailed

    var description: String {
        switch self {
        case .resourceMissing(let name): "Bundled resource “\(name)” is missing"
        case .imageDecodingFailed:       "The image data could not be decoded"
        }
    }
}

struct PixelBuffer: Hashable, Sendable {
    let width: Int
    let height: Int
    /// Row-major RGBA, four bytes per pixel, no row padding.
    var pixels: [UInt8]

    static let bytesPerPixel = 4

    /// Equality compares every byte, which is what a recipe change has to know.
    /// Hashing does not: the dimensions separate the cases that matter, and
    /// digesting megabytes on every lookup would not.
    func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(pixels.count)
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * Self.bytesPerPixel)
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * Self.bytesPerPixel)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Byte offset of a pixel's red channel.
    @inline(__always)
    func offset(x: Int, y: Int) -> Int {
        (y * width + x) * Self.bytesPerPixel
    }

    subscript(x: Int, y: Int) -> RGBA {
        get {
            let i = offset(x: x, y: y)
            return RGBA(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
        }
        set {
            let i = offset(x: x, y: y)
            pixels[i] = newValue.red
            pixels[i + 1] = newValue.green
            pixels[i + 2] = newValue.blue
            pixels[i + 3] = newValue.alpha
        }
    }
}

struct RGBA: Hashable, Sendable {
    var red, green, blue, alpha: UInt8

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8, _ alpha: UInt8) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
}

// MARK: - Core Graphics bridge

extension PixelBuffer {

    /// sRGB, 8 bits per channel, alpha last and *not* premultiplied. vImage
    /// converts into this layout whatever the decoder handed us, so a source
    /// PNG that arrives premultiplied is unpremultiplied here rather than
    /// silently changing the numbers later.
    /// Computed rather than stored: `vImage_CGImageFormat` is not `Sendable`,
    /// and building it costs nothing next to decoding an image.
    private static var format: vImage_CGImageFormat {
        vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            renderingIntent: .defaultIntent)!
    }

    init(cgImage: CGImage) throws {
        var source = try vImage_Buffer(cgImage: cgImage, format: Self.format)
        defer { source.free() }

        let width = Int(source.width)
        let height = Int(source.height)
        let rowBytes = width * Self.bytesPerPixel

        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        pixels.withUnsafeMutableBytes { destination in
            // vImage pads rows for alignment; copy row by row to pack them
            for row in 0..<height {
                let from = source.data.advanced(by: row * source.rowBytes)
                let to = destination.baseAddress!.advanced(by: row * rowBytes)
                to.copyMemory(from: from, byteCount: rowBytes)
            }
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    func cgImage() throws -> CGImage {
        var buffer = try vImage_Buffer(width: width, height: height, bitsPerPixel: 32)
        defer { buffer.free() }

        let rowBytes = width * Self.bytesPerPixel
        pixels.withUnsafeBytes { source in
            for row in 0..<height {
                let from = source.baseAddress!.advanced(by: row * rowBytes)
                let to = buffer.data.advanced(by: row * buffer.rowBytes)
                to.copyMemory(from: from, byteCount: rowBytes)
            }
        }
        return try buffer.createCGImage(format: Self.format)
    }

    /// Loads one of the bundled macOS folder graphics.
    static func folderImage(_ style: FolderStyle) throws -> PixelBuffer {
        guard let url = Bundle.main.url(forResource: style.filename, withExtension: "png")
                ?? Bundle.main.url(forResource: style.filename, withExtension: "png",
                                   subdirectory: "Folders")
        else { throw RenderError.resourceMissing("\(style.filename).png") }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw RenderError.imageDecodingFailed }

        return try PixelBuffer(cgImage: image)
    }
}

// MARK: - PNG

extension PixelBuffer {

    /// PNG data, for storing a dropped image alongside its recipe.
    func pngData() -> Data? {
        guard let image = try? cgImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    init?(pngData: Data) {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let buffer = try? PixelBuffer(cgImage: image)
        else { return nil }
        self = buffer
    }

    /// Crops away the blank space around the folder, so the preview does not
    /// float in a sea of margin.
    func cropped(to percentages: Box) -> PixelBuffer {
        let x1 = max(0, Int(Double(width) * percentages.x1))
        let y1 = max(0, Int(Double(height) * percentages.y1))
        let x2 = min(width, Int(Double(width) * percentages.x2))
        let y2 = min(height, Int(Double(height) * percentages.y2))
        guard x2 > x1, y2 > y1 else { return self }

        var result = PixelBuffer(width: x2 - x1, height: y2 - y1)
        for y in 0..<result.height {
            for x in 0..<result.width {
                result[x, y] = self[x1 + x, y1 + y]
            }
        }
        return result
    }
}
