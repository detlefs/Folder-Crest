#!/usr/bin/env swift

// Exports the custom icon of a folder as PNG files, one per icon size.
//
// Usage: Scripts/export-icon.swift <folder> <destination directory>

import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fail("usage: export-icon.swift <folder> <destination directory>")
}

// NSWorkspace needs an absolute path; given a relative one it silently hands
// back the generic document icon
let folder = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let destination = URL(fileURLWithPath: arguments[2])

var isDirectory: ObjCBool = false
guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
      isDirectory.boolValue else {
    fail("'\(folder.path)' is not a folder")
}

// A custom icon lives in an 'Icon\r' file; without it macOS would hand us the
// generic folder icon, which is not what the user asked to export
guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("Icon\r").path) else {
    fail("'\(folder.path)' has no custom icon")
}

let icon = NSWorkspace.shared.icon(forFile: folder.path)
guard let tiff = icon.tiffRepresentation else {
    fail("macOS returned no bitmap data for '\(folder.path)'")
}

do {
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
} catch {
    fail("could not create '\(destination.path)': \(error.localizedDescription)")
}

// The icon's own representations are not bitmaps; the TIFF detour turns every
// size into an NSBitmapImageRep, with duplicates for the retina variants that
// render identically
let name = folder.lastPathComponent
var seen = Set<Int>()
var written: [String] = []

for case let rep as NSBitmapImageRep in NSBitmapImageRep.imageReps(with: tiff) {
    guard seen.insert(rep.pixelsWide).inserted else { continue }
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fail("could not encode the \(rep.pixelsWide)px icon as PNG")
    }
    let out = destination.appendingPathComponent("\(name)_\(rep.pixelsWide).png")
    do {
        try data.write(to: out, options: .atomic)
    } catch {
        fail("could not write '\(out.path)': \(error.localizedDescription)")
    }
    written.append(out.path)
}

guard !written.isEmpty else {
    fail("the icon of '\(folder.path)' has no bitmap representation")
}
written.forEach { print($0) }
