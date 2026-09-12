#!/usr/bin/env swift

// Builds the README carousel: a row of folder icons that swaps every 1.25s.
// Keeps the alpha channel, so it is written as an APNG, not a GIF.
//
// Usage: Scripts/make-icon-carousel.swift [source directory] [output.png]
//
// The source directory holds one subfolder per icon, each with the
// <name>_1024.png that Scripts/export-icon.swift writes.

import AppKit
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}

let tile = 120
let columns = 6
let frameSeconds = 1.25
let sourceSize = 1024  // which per-size PNG to downscale from

let arguments = CommandLine.arguments
let source = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "readme_assets/_new")
let output = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "readme_assets/carousel.png")

func iconPaths() -> [URL] {
    guard let entries = try? FileManager.default.contentsOfDirectory(
        at: source, includingPropertiesForKeys: [.isDirectoryKey]) else {
        fail("could not read '\(source.path)'")
    }
    let folders = entries
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    let icons = folders.map {
        $0.appendingPathComponent("\($0.lastPathComponent)_\(sourceSize).png")
    }
    for icon in icons where !FileManager.default.fileExists(atPath: icon.path) {
        fail("missing \(icon.path)")
    }
    if icons.count < columns {
        fail("need at least \(columns) icons, found \(icons.count)")
    }
    return icons
}

/// One tile-sized frame of the strip, drawn from the icons starting at `offset`
func drawFrame(icons: [CGImage], offset: Int) -> CGImage {
    guard let context = CGContext(
        data: nil, width: tile * columns, height: tile,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("could not allocate the frame bitmap")
    }
    context.interpolationQuality = .high
    for column in 0..<columns {
        let icon = icons[(offset + column) % icons.count]
        context.draw(icon, in: CGRect(x: column * tile, y: 0, width: tile, height: tile))
    }
    guard let image = context.makeImage() else { fail("could not render a frame") }
    return image
}

let paths = iconPaths()
let icons: [CGImage] = paths.map { path in
    guard let source = CGImageSourceCreateWithURL(path as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("could not read \(path.path)")
    }
    return image
}

// Shifting by `columns` each frame, the row repeats after this many frames
func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int { b == 0 ? a : greatestCommonDivisor(b, a % b) }
let frameCount = icons.count / greatestCommonDivisor(icons.count, columns)

try? FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL, UTType.png.identifier as CFString, frameCount, nil) else {
    fail("could not write to '\(output.path)'")
}
CGImageDestinationSetProperties(destination, [
    kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
] as CFDictionary)

for frame in 0..<frameCount {
    CGImageDestinationAddImage(destination, drawFrame(icons: icons, offset: frame * columns), [
        kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: frameSeconds]
    ] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else {
    fail("could not finalise '\(output.path)'")
}

let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
print("\(output.path): \(frameCount) frames of \(icons.count) icons, "
      + "\(String(format: "%.1f", Double(frameCount) * frameSeconds))s, \(size / 1024) KiB")
