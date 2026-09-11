//
//  FolderStyle.swift
//  Folder Crest
//
//  Ported 1:1 from the Python reference (foldercrest/constants.py, FolderStyle).
//  The geometry percentages are empirically calibrated per macOS folder graphic.
//

import Foundation

/// A macOS folder graphic the icon is engraved into.
///
/// This is the *artwork*, not the appearance of the app: `bigSurLight` and
/// `bigSurDark` are two different folder images, unrelated to whether the app
/// itself runs in light or dark mode.
enum FolderStyle: Int, CaseIterable, Hashable, Sendable {
    case bigSurLight = 0
    case bigSurDark = 1
    case catalina = 2
    case tahoe = 3

    static let `default` = FolderStyle.tahoe

    /// Name of the image in the bundled folders directory.
    var filename: String {
        switch self {
        case .bigSurLight: "big_sur_light"
        case .bigSurDark:  "big_sur_dark"
        case .catalina:    "catalina"
        case .tahoe:       "tahoe"
        }
    }

    /// Untranslated name; the UI resolves this through the string catalog.
    var displayNameKey: String.LocalizationValue {
        switch self {
        case .bigSurLight: "macOS Big Sur – Light mode"
        case .bigSurDark:  "macOS Big Sur – Dark mode"
        case .catalina:    "macOS Catalina"
        case .tahoe:       "macOS Tahoe"
        }
    }

    /// Size of the folder in pixels (one dimension only, because square).
    var size: Int {
        switch self {
        case .bigSurLight, .bigSurDark, .catalina, .tahoe: 1024
        }
    }

    /// Rect, in percentages of the folder size, containing the region to draw
    /// the icon into: (x1, y1, x2, y2).
    var iconBoxPercentages: Box {
        switch self {
        case .bigSurLight, .bigSurDark: Box(0.086, 0.29, 0.914, 0.777)
        case .catalina, .tahoe:         Box(0.0668, 0.281, 0.9332, 0.770)
        }
    }

    /// Minimum rect, in percentages, containing the folder — used to crop the
    /// blank space away when showing the preview.
    var previewCropPercentages: Box {
        switch self {
        case .bigSurLight, .bigSurDark: Box(0, 0.0888, 1.0, 0.9276)
        case .catalina, .tahoe:         Box(0, 0.0972, 1.0, 0.896)
        }
    }

    /// The average colour of the folder where the icon is to be drawn.
    var baseColour: RGB {
        switch self {
        case .bigSurLight: RGB(116, 208, 251)
        case .bigSurDark:  RGB(96, 208, 255)
        case .catalina:    RGB(120, 210, 251)
        case .tahoe:       RGB(120, 210, 251)
        }
    }

    /// The average colour of the icon in default macOS folders.
    var iconColour: RGB {
        switch self {
        case .bigSurLight: RGB(63, 170, 229)
        case .bigSurDark:  RGB(53, 160, 225)
        // ponytail: Catalina and Tahoe inherit Big Sur's value, as upstream
        // does. Measuring the real ones is a separate task — see the reference
        // repo's TODO. Changing them breaks the parity fixtures.
        case .catalina:    RGB(63, 170, 229)
        case .tahoe:       RGB(63, 170, 229)
        }
    }
}

/// A rectangle as (x1, y1, x2, y2), matching the reference's tuple layout.
struct Box: Hashable, Sendable {
    var x1, y1, x2, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    var width: Double { x2 - x1 }
    var height: Double { y2 - y1 }
}
