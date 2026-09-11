//
//  FolderGraphic.swift
//  Folder Crest
//
//  The folder the icon is engraved into is the one the running system uses —
//  `NSWorkspace.icon(for: .folder)`, not a picture of a folder shipped with the
//  app. Older macOS versions are therefore no longer on offer: the app draws
//  what the Finder draws, and nothing else.
//
//  The numbers below are calibrated against that graphic, measured on
//  macOS 26 on 2026-09-11. They replace the per-version values ported from the
//  Python reference (foldercrest/constants.py, FolderStyle).
//

import Foundation

enum FolderGraphic {

    /// Size of the folder in pixels (one dimension only, because square). The
    /// system icon carries a representation at exactly this size.
    static let size = 1024

    /// Rect, in percentages of the folder size, containing the region to draw
    /// the icon into: (x1, y1, x2, y2).
    ///
    /// Derived from the reference's Tahoe box by measuring the front flap of
    /// both graphics and keeping the box's position within it: the system icon
    /// sits three pixels further right and two lower than the bundled PNG did.
    static let iconBoxPercentages = Box(0.0695, 0.2826, 0.9286, 0.7679)

    /// Minimum rect, in percentages, containing the folder — used to crop the
    /// blank space away when showing the preview. Measured as the bounding box
    /// of everything with an alpha above 8, drop shadow included.
    static let previewCropPercentages = Box(0, 0.1221, 1.0, 0.8926)

    /// The average colour of the folder where the icon is to be drawn, over the
    /// opaque centre of the front flap.
    static let baseColour = RGB(93, 192, 236)

    /// The average colour of the engraving in the system's own folder icons,
    /// measured by diffing the icons of Downloads, Documents and Applications
    /// against the plain folder: RGB(82,166,204), (81,166,204), (79,164,203).
    static let iconColour = RGB(81, 165, 204)
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
