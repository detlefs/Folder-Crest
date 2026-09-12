#!/usr/bin/env swift

// Draws the DMG window background with the first launch instructions.
//
// Writes dmg_build/dmg_background.png and dmg_background@2x.png. The layout
// has to leave the lower third empty: that is where the disk image places the
// app and the Applications link.
//
// Usage: Scripts/make-dmg-background.swift [output directory]

import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}

// Logical size of the background; the DMG window is 600x500
let width = 600.0
let height = 450.0
// Icons sit at y=333 with icon size 110, so everything below this is theirs
let textBottom = 250.0

let background = NSColor.white
let accent = NSColor(srgbRed: 255 / 255, green: 133 / 255, blue: 178 / 255, alpha: 1)
let textColour = NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
let hintColour = NSColor(srgbRed: 110 / 255, green: 110 / 255, blue: 115 / 255, alpha: 1)

let title = "First launch on macOS"
let steps = [
    "Drag Folder Crest onto Applications below",
    "Open it once — macOS blocks it, click “Done”",
    "System Settings › Privacy & Security",
    "Scroll to the bottom, click “Open Anyway”",
]
let hints = [
    "The entry only shows up after step 2 and expires after about an hour.",
    "macOS Sonoma and older: right-click the app › Open › Open.",
]
let dragLabel = "Drag over!"

/// The rounded system face; the bundled SF Pro Rounded files are not needed,
/// the system carries the same design.
func font(_ size: Double, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded),
          let rounded = NSFont(descriptor: descriptor, size: size) else { return base }
    return rounded
}

func drawBackground(scale: Double) -> NSBitmapImageRep {
    func s(_ value: Double) -> Double { value * scale }

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(s(width)), pixelsHigh: Int(s(height)),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
    ) else {
        fail("could not allocate the \(Int(scale))x bitmap")
    }

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fail("could not draw into the \(Int(scale))x bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    background.setFill()
    NSRect(x: 0, y: 0, width: s(width), height: s(height)).fill()

    // Everything below measures from the top edge, the bitmap's origin is at
    // the bottom left
    func draw(_ text: String, _ face: NSFont, x: Double, top: Double, colour: NSColor) {
        let string = NSAttributedString(
            string: text, attributes: [.font: face, .foregroundColor: colour])
        string.draw(at: NSPoint(x: x, y: s(height) - top - string.size().height))
    }

    func centred(_ text: String, _ face: NSFont, top: Double, colour: NSColor) {
        let measured = NSAttributedString(string: text, attributes: [.font: face]).size().width
        if measured > s(width) - s(24) {
            fail("'\(text)' is too wide for the background")
        }
        draw(text, face, x: (s(width) - measured) / 2, top: top, colour: colour)
    }

    centred(title, font(s(28), .bold), top: s(26), colour: accent)

    let numberFont = font(s(17), .bold)
    let stepFont = font(s(17), .regular)
    var y = s(80)
    for (index, step) in steps.enumerated() {
        draw("\(index + 1).", numberFont, x: s(38), top: y, colour: accent)
        let measured = NSAttributedString(string: step, attributes: [.font: stepFont]).size().width
        if measured > s(width) - s(90) {
            fail("step \(index + 1) is too wide for the background")
        }
        draw(step, stepFont, x: s(66), top: y, colour: textColour)
        y += s(29)
    }

    y += s(8)
    let hintFont = font(s(12), .regular)
    for hint in hints {
        centred(hint, hintFont, top: y, colour: hintColour)
        y += s(18)
    }

    if y > s(textBottom) {
        fail("text reaches \(Int(y / scale)) px, the icons start at \(Int(textBottom)) px")
    }

    // Sits between the app and the Applications link, both at y=333
    centred(dragLabel, font(s(18), .semibold), top: s(340), colour: textColour)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                 ? CommandLine.arguments[1] : "dmg_build")
do {
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
} catch {
    fail("could not create '\(outDir.path)': \(error.localizedDescription)")
}

for (scale, name) in [(1.0, "dmg_background.png"), (2.0, "dmg_background@2x.png")] {
    guard let data = drawBackground(scale: scale).representation(using: .png, properties: [:]) else {
        fail("could not encode \(name)")
    }
    let out = outDir.appendingPathComponent(name)
    do {
        try data.write(to: out, options: .atomic)
    } catch {
        fail("could not write '\(out.path)': \(error.localizedDescription)")
    }
    print(out.path)
}
