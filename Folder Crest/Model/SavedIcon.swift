//
//  SavedIcon.swift
//  Folder Crest
//
//  What the library keeps: the *recipe*, not the finished 1024 px icon. That
//  costs almost nothing to sync and lets an icon be re-rendered when the
//  system's folder graphic changes. Only the dropped source image and a small
//  thumbnail are stored as blobs.
//
//  Every property has a default value and none is unique, because that is what
//  CloudKit requires of a SwiftData model. Enums are stored as their raw value
//  for the same reason.
//

import Foundation
import SwiftData

@Model
final class SavedIcon {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now

    var text: String = ""
    var scale: Double = 1.0
    var offsetX: Double = 0
    var offsetY: Double = 0
    var fontWeightRaw: Int = SFFont.default.rawValue
    /// Packed 0xRRGGBB, or nil for no tint.
    var tintRGB: Int?
    var preserveColours: Bool = false

    @Attribute(.externalStorage) var sourceImage: Data?
    @Attribute(.externalStorage) var thumbnail: Data?

    init(name: String = "", recipe: IconRecipe) {
        self.name = name
        self.scale = recipe.scale
        self.offsetX = recipe.offset.x
        self.offsetY = recipe.offset.y
        self.fontWeightRaw = recipe.fontWeight.rawValue
        self.tintRGB = recipe.tint.map { $0.packed }

        switch recipe.source {
        case .none:
            break
        case .text(let value):
            self.text = value
        case .image(let buffer, let preserve):
            self.preserveColours = preserve
            self.sourceImage = buffer.pngData()
        }
    }

    var fontWeight: SFFont { SFFont(rawValue: fontWeightRaw) ?? .default }

    /// Rebuilds the recipe this entry was saved from.
    var recipe: IconRecipe {
        var recipe = IconRecipe()
        recipe.scale = scale
        recipe.offset = CGPoint(x: offsetX, y: offsetY)
        recipe.fontWeight = fontWeight
        recipe.tint = tintRGB.map(RGB.init(packed:))

        if let data = sourceImage, let buffer = PixelBuffer(pngData: data) {
            recipe.source = .image(buffer, preserveColours: preserveColours)
        } else if !text.isEmpty {
            recipe.source = .text(text)
        }
        return recipe
    }

    /// A short description of the source, for the sidebar's second line.
    var sourceSummary: String {
        if sourceImage != nil {
            return preserveColours
                ? String(localized: "Image · Original colors",
                         comment: "Sidebar subtitle for an image kept in its own colours")
                : String(localized: "Image", comment: "Sidebar subtitle for an engraved image")
        }
        if !text.isEmpty { return text }
        return String(localized: "Plain folder",
                      comment: "Sidebar subtitle for a folder with no icon on it")
    }
}

extension RGB {
    var packed: Int { (red << 16) | (green << 8) | blue }

    init(packed: Int) {
        self.init((packed >> 16) & 0xFF, (packed >> 8) & 0xFF, packed & 0xFF)
    }
}
