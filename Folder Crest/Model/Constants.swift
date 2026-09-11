//
//  Constants.swift
//  Folder Crest
//
//  Ported 1:1 from the Python reference (foldercrest/constants.py). The numbers
//  are empirically calibrated — the comments explain why. Do not re-derive them.
//

import Foundation

enum Constants {

    // MARK: - Slider ranges

    static let iconScaleSliderMax = 31
    static let maximumIconScaleValue = 2.0
    static let minimumIconScaleValue = 0.1

    static let iconOffsetSliderMax = 31

    /// Percentage of the folder size the icon can be shifted by: x, y. Further
    /// than this the icon leaves the body of the folder and the engraving looks
    /// wrong. The icon box is much wider than it is high, so there is more room
    /// sideways.
    static let maximumIconOffsetValue = (x: 0.27, y: 0.15)

    /// The offset range is divided by the icon scale, since a small icon has
    /// more room to move. This caps it at the half size of the icon box (~0.87
    /// wide and ~0.49 high), beyond which even a tiny icon leaves the box.
    static let maximumIconOffsetLimit = (x: 0.39, y: 0.22)

    // MARK: - Icon generation

    static let folderShadowIncreaseFactor = 1.7
    static let innerShadowColourScalingFactor = 0.9

    static let innerShadowBlur = 3.0
    /// Percentage of height
    static let innerShadowYOffset = 0.00293
    static let outerHighlightBlur = 6.0
    /// Percentage of height
    static let outerHighlightYOffset = 0.00782

    static let iconBoxScalingFactor = 0.84

    /// Level the outer highlight is drawn at, `#131313` in the reference.
    static let outerHighlightLevel = 0x13

    /// Intensity of the sigmoid curve used to normalize an image mask. Smaller
    /// values lead to less separated colours.
    static let maskNormalizeSteepness = 0.18

    /// Maximum number of characters accepted in the icon text field.
    static let maximumIconTextLength = 25

    // MARK: - Emoji

    /// The only size Apple Color Emoji exposes as a full resolution bitmap strike.
    static let emojiFontSize = 160.0
    static let emojiFontName = "Apple Color Emoji"

    // MARK: - SF Symbols

    /// SF Symbols glyphs live in the plane 16 private use area.
    static let symbolCharacterRange: ClosedRange<UInt32> = 0x100000...0x10FFFD

    /// Symbols are drawn at the size of the largest folder icon.
    static let symbolRenderSize = 1024

    // MARK: - Writing the icon

    /// Sizes macOS keeps in an icon family. Providing all of them avoids Finder
    /// having to downscale the single large icon for list and column views.
    static let iconSizes = [16, 32, 128, 256, 512, 1024]
}

/// Default colour palette for folder tints. Values are 76.5 % of the upstream
/// brightness (`white` at 90 %, so it stays distinguishable from `cream`) —
/// the originals looked washed out on the folder graphic.
enum TintColour: String, CaseIterable {
    case red, melon, orange, yellow, green, teal, lightblue, purple, cream, white

    var rgb: RGB {
        switch self {
        case .red:       RGB(195, 118, 124)
        case .melon:     RGB(195, 140, 136)
        case .orange:    RGB(195, 167, 148)
        case .yellow:    RGB(195, 181, 160)
        case .green:     RGB(173, 184, 156)
        case .teal:      RGB(139, 179, 165)
        case .lightblue: RGB(139, 175, 187)
        case .purple:    RGB(152, 158, 179)
        case .cream:     RGB(195, 192, 184)
        case .white:     RGB(225, 224, 221)
        }
    }
}

/// Weights of the bundled SF Pro Rounded fonts. The raw values match the slider
/// positions of the reference implementation.
enum SFFont: Int, CaseIterable {
    case ultralight = 1, thin, light, regular, medium, semibold, bold, heavy, black

    static let `default` = SFFont.bold

    /// Filename in the bundled fonts folder.
    var filename: String {
        switch self {
        case .ultralight: "SF-Pro-Rounded-Ultralight"
        case .thin:       "SF-Pro-Rounded-Thin"
        case .light:      "SF-Pro-Rounded-Light"
        case .regular:    "SF-Pro-Rounded-Regular"
        case .medium:     "SF-Pro-Rounded-Medium"
        case .semibold:   "SF-Pro-Rounded-Semibold"
        case .bold:       "SF-Pro-Rounded-Bold"
        case .heavy:      "SF-Pro-Rounded-Heavy"
        case .black:      "SF-Pro-Rounded-Black"
        }
    }
}

/// How the icon on top of the folder is produced.
enum IconGenerationMethod {
    case none, image, text
}
