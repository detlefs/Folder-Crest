#!/usr/bin/env swift

// Builds the README carousel: a row of folder icons where two tiles at a time
// flip around their horizontal or vertical axis and turn into the next icon.
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
let holdSeconds = 1.25
let flipFrames = 12
let flipFrameSeconds = 1.0 / 30
// Tiles that flip together; one pass through the list replaces the whole row
let flipPairs = [(0, 4), (2, 5), (1, 3)]
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

/// One frame of the strip. Slots in `flipping` are mid-flip at `progress` (0...1):
/// the old icon shrinks to an edge, the new one grows back from it.
func drawFrame(
    current: [CGImage], next: [CGImage], flipping: [Int] = [], progress: Double = 0
) -> CGImage {
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
        let rect = CGRect(x: column * tile, y: 0, width: tile, height: tile)
        guard let pairIndex = flipping.firstIndex(of: column) else {
            context.draw(current[column], in: rect)
            continue
        }
        // Ease in and out; the edge-on moment sits at progress 0.5
        let scale = abs(cos(Double.pi * (0.5 - 0.5 * cos(Double.pi * progress))))
        let icon = progress < 0.5 ? current[column] : next[column]
        let horizontal = pairIndex % 2 == 0
        context.draw(icon, in: rect.insetBy(
            dx: horizontal ? rect.width * (1 - scale) / 2 : 0,
            dy: horizontal ? 0 : rect.height * (1 - scale) / 2))
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

// Each full pass shifts the row by `columns`, so it repeats after this many passes
func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int { b == 0 ? a : greatestCommonDivisor(b, a % b) }
let passes = icons.count / greatestCommonDivisor(icons.count, columns)
let flipCount = passes * flipPairs.count
let frameCount = flipCount * flipFrames

try? FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL, UTType.png.identifier as CFString, frameCount, nil) else {
    fail("could not write to '\(output.path)'")
}
CGImageDestinationSetProperties(destination, [
    kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
] as CFDictionary)

func addFrame(_ image: CGImage, seconds: Double) {
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: seconds]
    ] as CFDictionary)
}

var row = Array(icons[0..<columns])
for step in 0..<flipCount {
    let pass = step / flipPairs.count
    let (a, b) = flipPairs[step % flipPairs.count]
    var next = row
    for slot in [a, b] {
        next[slot] = icons[((pass + 1) * columns + slot) % icons.count]
    }
    addFrame(drawFrame(current: row, next: next), seconds: holdSeconds)
    for frame in 1..<flipFrames {  // the last one would repeat the next hold frame
        let image = drawFrame(current: row, next: next, flipping: [a, b],
                              progress: Double(frame) / Double(flipFrames))
        addFrame(image, seconds: flipFrameSeconds)
    }
    row = next
}
guard CGImageDestinationFinalize(destination) else {
    fail("could not finalise '\(output.path)'")
}

let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
let duration = Double(flipCount) * (holdSeconds + Double(flipFrames - 1) * flipFrameSeconds)
print("\(output.path): \(frameCount) frames of \(icons.count) icons, "
      + "\(String(format: "%.1f", duration))s, \(size / 1024) KiB")
