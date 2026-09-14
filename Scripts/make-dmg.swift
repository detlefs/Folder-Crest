#!/usr/bin/env swift

// Builds Folder Crest in Release and packs it into a disk image with the
// drag-to-Applications layout.
//
// The app is signed ad hoc: without a Developer ID it would not pass
// Gatekeeper on another Mac anyway, and CI has no certificate. The background
// explains the "Open Anyway" route.
//
// Needs appdmg (https://github.com/LinusU/node-appdmg); falls back to npx.
//
// Usage: Scripts/make-dmg.swift
// Output: dmg_build/Folder Crest <version>.dmg

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}

func log(_ message: String) {
    print("==> \(message)")
}

/// Runs a command found on PATH, passing its output through; stops the script
/// when it fails.
func run(_ arguments: [String], quiet: Bool = false) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    if quiet {
        process.standardOutput = FileHandle.nullDevice
    }
    do {
        try process.run()
    } catch {
        fail("could not start \(arguments[0]): \(error.localizedDescription)")
    }
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        fail("\(arguments[0]) exited with \(process.terminationStatus)")
    }
}

func onPath(_ tool: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [tool]
    process.standardOutput = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
guard FileManager.default.changeCurrentDirectoryPath(root.path) else {
    fail("could not change to '\(root.path)'")
}

let out = "dmg_build"
let appPath = "DerivedData/Build/Products/Release/Folder Crest.app"
let app = "\(out)/\(appPath)"

log("Building Release")
run([
    "xcodebuild", "-project", "Folder Crest.xcodeproj", "-scheme", "Folder Crest",
    "-configuration", "Release", "-destination", "generic/platform=macOS",
    "-derivedDataPath", "\(out)/DerivedData",
    "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=",
    "-quiet", "build",
])

guard FileManager.default.fileExists(atPath: app) else {
    fail("no app bundle at '\(app)'")
}
run(["codesign", "--verify", "--strict", app])

let infoURL = URL(fileURLWithPath: "\(app)/Contents/Info.plist")
guard let info = NSDictionary(contentsOf: infoURL),
      let version = info["CFBundleShortVersionString"] as? String else {
    fail("no version in '\(infoURL.path)'")
}
let dmg = "\(out)/Folder Crest \(version).dmg"

log("Drawing background")
run(["swift", "Scripts/make-dmg-background.swift", out], quiet: true)

// Positions match the background: icons at y=333, text above y=250
let spec: [String: Any] = [
    "title": "Folder Crest",
    "icon-size": 110,
    "window": ["size": ["width": 600, "height": 500]],
    "background": "dmg_background.png",
    "contents": [
        ["x": 487, "y": 333, "type": "link", "path": "/Applications"],
        ["x": 113, "y": 333, "type": "file", "path": appPath],
    ],
]
let specURL = URL(fileURLWithPath: "\(out)/appdmg.json")
do {
    try JSONSerialization.data(withJSONObject: spec, options: .prettyPrinted).write(to: specURL)
} catch {
    fail("could not write '\(specURL.path)': \(error.localizedDescription)")
}

log("Packing \(dmg)")
if FileManager.default.fileExists(atPath: dmg) {
    do {
        try FileManager.default.removeItem(atPath: dmg)
    } catch {
        fail("could not remove the old '\(dmg)': \(error.localizedDescription)")
    }
}
let appdmg = onPath("appdmg") ? ["appdmg"] : ["npx", "--yes", "appdmg@0.6.6"]
run(appdmg + [specURL.path, dmg])
run(["hdiutil", "verify", dmg], quiet: true)

print(dmg)
