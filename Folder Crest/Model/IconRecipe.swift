//
//  IconRecipe.swift
//  Folder Crest
//
//  Everything the renderer needs, and nothing it does not. Hashable so the UI
//  can tell whether a change actually requires a new render.
//

import CoreGraphics
import Foundation

/// What gets put on top of the folder.
enum IconSource: Hashable, Sendable {
    case none
    case text(String)
    /// A dropped image or SF Symbol. `preserveColours` pastes it in its own
    /// colours instead of engraving it.
    case image(PixelBuffer, preserveColours: Bool)

    var method: IconGenerationMethod {
        switch self {
        case .none:  .none
        case .text:  .text
        case .image: .image
        }
    }
}

/// The stacked filters that produce the engraved look. Split out from the
/// constants so a later "Advanced" inspector tab can bind sliders to them
/// without the renderer changing; the parity tests pin `.default`.
struct EngraveParameters: Hashable, Sendable {
    var innerShadowBlur = Constants.innerShadowBlur
    var innerShadowYOffset = Constants.innerShadowYOffset
    var innerShadowValueScale = Constants.innerShadowColourScalingFactor
    var outerHighlightBlur = Constants.outerHighlightBlur
    var outerHighlightYOffset = Constants.outerHighlightYOffset
    var outerHighlightLevel = Constants.outerHighlightLevel
    var iconBoxScale = Constants.iconBoxScalingFactor
    var folderShadowFactor = Constants.folderShadowIncreaseFactor

    static let `default` = EngraveParameters()
}

struct IconRecipe: Hashable, Sendable {
    var source = IconSource.none
    var scale = 1.0
    /// Offset from the centre, as a fraction of the folder size.
    var offset = CGPoint.zero
    var tint: RGB?
    var fontWeight = SFFont.default
    var engrave = EngraveParameters.default
}
