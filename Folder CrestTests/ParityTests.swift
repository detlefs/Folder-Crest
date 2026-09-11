//
//  ParityTests.swift
//  Folder CrestTests
//
//  Compares the Swift renderer against the Python reference, pixel by pixel.
//  The fixtures in `Fixtures/` were produced by `Scripts/make_fixtures.py`;
//  the filename carries the recipe so the matrix lives in one place only.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import Folder_Crest

struct ParityTests {

    /// Everything that does not go through a glyph rasteriser has to match to
    /// the last unit — the arithmetic is the same arithmetic.
    static let exactTolerance = Tolerance(maxChannelDelta: 1, meanAbsoluteError: 0.2)

    /// Anything that goes through `Resample`. Pillow resamples in 8.22 fixed
    /// point, this does it in `Double`; each of the two passes can land a unit
    /// away. Measured 2026-09-10: max 2, mean ≤ 0.02 across the image fixtures.
    static let resampledTolerance = Tolerance(maxChannelDelta: 3, meanAbsoluteError: 0.05)

    /// Text is rasterised by Core Text here and by FreeType there. The mask
    /// boxes agree to the pixel and so does their placement — the difference
    /// image is a one pixel outline along the glyph edge, nothing in its
    /// interior. That part is irreducible.
    ///
    /// Measured 2026-09-10 across the twelve text fixtures: worst channel
    /// delta 47...82, mean absolute error 0.006...1.921. The thresholds sit
    /// above that with room to spare, but low enough to still catch a
    /// misregistration — a glyph that is missing or a pixel off lights up the
    /// whole body and pushes the mean past 2.5.
    static let glyphTolerance = Tolerance(maxChannelDelta: 120, meanAbsoluteError: 2.2)

    struct Tolerance {
        var maxChannelDelta: Int
        var meanAbsoluteError: Double
    }

    @Test("The plain folder matches the reference exactly",
          arguments: FolderStyle.allCases)
    func plainFolder(style: FolderStyle) throws {
        try compare(recipe: IconRecipe(style: style),
                    fixture: "none_\(style.fixtureName)_scale1_off0-0_bold",
                    tolerance: Self.exactTolerance)
    }

    @Test("Text engraving matches the reference", arguments: textCases)
    func textEngraving(fixture: String, recipe: IconRecipe) throws {
        try compare(recipe: recipe, fixture: fixture, tolerance: Self.glyphTolerance)
    }

    static let textCases: [(fixture: String, recipe: IconRecipe)] = {
        var cases: [(String, IconRecipe)] = []

        for style in FolderStyle.allCases {
            cases.append(("text-A_\(style.fixtureName)_scale1_off0-0_bold",
                          IconRecipe(style: style, source: .text("A"))))
        }
        for scale in [0.1, 1.0, 2.0] {
            cases.append(("text-A_tahoe_scale\(scale)_off0-0_bold",
                          IconRecipe(source: .text("A"), scale: scale)))
        }
        cases.append(("text-A_tahoe_scale1_off0.2--0.1_bold",
                      IconRecipe(source: .text("A"), offset: CGPoint(x: 0.2, y: -0.1))))
        cases.append(("text-A_tahoe_scale1_off-0.27-0.15_bold",
                      IconRecipe(source: .text("A"), offset: CGPoint(x: -0.27, y: 0.15))))
        for weight in [SFFont.ultralight, .black] {
            cases.append(("text-A_tahoe_scale1_off0-0_\(weight.fixtureName)",
                          IconRecipe(source: .text("A"), fontWeight: weight)))
        }
        cases.append(("text-Ag_tahoe_scale1_off0-0_bold", IconRecipe(source: .text("Ag"))))

        return cases.map { (fixture: $0.0, recipe: $0.1) }
    }()

    // MARK: - Step 4 paths

    /// The same deterministic image the fixture generator builds in Python.
    static func testImage() -> PixelBuffer {
        var image = PixelBuffer(width: 200, height: 160)
        for y in 0..<160 {
            for x in 0..<200 where (20..<180).contains(x) && (20..<140).contains(y) {
                image[x, y] = RGBA(UInt8((x * 7) % 256), UInt8((y * 11) % 256),
                                   UInt8((x + y) % 256), 255)
            }
        }
        return image
    }

    @Test("The tint matches the reference", arguments: tintCases)
    func tinting(fixture: String, recipe: IconRecipe, glyphs: Bool) throws {
        try compare(recipe: recipe, fixture: fixture,
                    tolerance: glyphs ? Self.glyphTolerance : Self.exactTolerance)
    }

    static let tintCases: [(fixture: String, recipe: IconRecipe, glyphs: Bool)] = {
        var cases: [(String, IconRecipe, Bool)] = []
        for tint in [TintColour.red, .white, .teal] {
            cases.append(("none_tahoe_scale1_off0-0_bold_tint-\(tint.rawValue)",
                          IconRecipe(tint: tint.rgb), false))
            cases.append(("text-A_tahoe_scale1_off0-0_bold_tint-\(tint.rawValue)",
                          IconRecipe(source: .text("A"), tint: tint.rgb), true))
        }
        return cases.map { (fixture: $0.0, recipe: $0.1, glyphs: $0.2) }
    }()

    @Test("A dropped image matches the reference, engraved and in its own colours",
          arguments: imageCases)
    func droppedImage(fixture: String, recipe: IconRecipe) throws {
        try compare(recipe: recipe, fixture: fixture, tolerance: Self.resampledTolerance)
    }

    static let imageCases: [(fixture: String, recipe: IconRecipe)] = [
        (fixture: "image_tahoe_scale1_off0-0_bold_engraved",
         recipe: IconRecipe(source: .image(testImage(), preserveColours: false))),
        (fixture: "image_tahoe_scale1_off0-0_bold_original",
         recipe: IconRecipe(source: .image(testImage(), preserveColours: true))),
        (fixture: "image_tahoe_scale1_off0-0_bold_original_tint-red",
         recipe: IconRecipe(source: .image(testImage(), preserveColours: true),
                            tint: TintColour.red.rgb)),
    ]

    /// Emoji are rasterised by two different engines, like text — same caveat.
    @Test("Emoji keep their own colours", arguments: [
        ("emoji-octopus_tahoe_scale1_off0-0_bold", "\u{1F419}"),
        ("emoji-folder_tahoe_scale1_off0-0_bold", "\u{1F4C1}"),
    ])
    func emoji(fixture: String, text: String) throws {
        try compare(recipe: IconRecipe(source: .text(text)), fixture: fixture,
                    tolerance: Self.glyphTolerance)
    }

    // MARK: - Comparison

    private func compare(recipe: IconRecipe, fixture: String,
                         tolerance: Tolerance) throws {
        let expected = try Self.loadFixture(fixture)
        let actual = try IconRenderer.makeIcon(recipe)

        #expect(actual.width == expected.width)
        #expect(actual.height == expected.height)
        guard actual.width == expected.width, actual.height == expected.height else { return }

        var worst = 0
        var worstAt = (x: 0, y: 0)
        var total = 0

        for i in 0..<actual.pixels.count {
            let delta = abs(Int(actual.pixels[i]) - Int(expected.pixels[i]))
            total += delta
            if delta > worst {
                worst = delta
                let pixel = i / PixelBuffer.bytesPerPixel
                worstAt = (pixel % actual.width, pixel / actual.width)
            }
        }
        let mean = Double(total) / Double(actual.pixels.count)

        // One line per case, so a run says how close every fixture is rather
        // than only which ones tripped the threshold. A file, not stdout:
        // xcodebuild does not forward the test host's console.
        let mine = actual[worstAt.x, worstAt.y]
        let theirs = expected[worstAt.x, worstAt.y]
        Self.report(String(format: "%-44s  max %3d  mean %6.3f  at (%d,%d) mine=%d,%d,%d,%d theirs=%d,%d,%d,%d",
                           (fixture as NSString).utf8String!, worst, mean,
                           worstAt.x, worstAt.y,
                           Int(mine.red), Int(mine.green), Int(mine.blue), Int(mine.alpha),
                           Int(theirs.red), Int(theirs.green), Int(theirs.blue), Int(theirs.alpha)))

        let acceptable = worst <= tolerance.maxChannelDelta
            && mean <= tolerance.meanAbsoluteError
        if !acceptable {
            let path = try Self.writeDifference(actual: actual, expected: expected,
                                                name: fixture)
            Issue.record("""
                \(fixture): worst channel delta \(worst) at \
                (\(worstAt.x), \(worstAt.y)), mean absolute error \
                \(String(format: "%.3f", mean)).
                Allowed: delta \(tolerance.maxChannelDelta), mean \
                \(tolerance.meanAbsoluteError).
                Difference image: \(path)
                """)
        }
    }

    /// The fixtures ship with the *test* bundle, not the app, and the tests run
    /// inside the app as their host — so `Bundle.main` is the wrong one.
    private static let fixtureBundle = Bundle(for: FixtureBundleAnchor.self)

    /// Appends a line to `$TMPDIR/foldercrest-parity/metrics.txt`.
    private static func report(_ line: String) {
        let url = reportDirectory.appendingPathComponent("metrics.txt")
        try? FileManager.default.createDirectory(at: reportDirectory,
                                                 withIntermediateDirectories: true)
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static let reportDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("foldercrest-parity")

    private static func loadFixture(_ name: String) throws -> PixelBuffer {
        guard let url = fixtureBundle.url(forResource: name, withExtension: "png")
                ?? fixtureBundle.url(forResource: name, withExtension: "png",
                                     subdirectory: "Fixtures")
        else { throw RenderError.resourceMissing("\(name).png") }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw RenderError.imageDecodingFailed }

        return try PixelBuffer(cgImage: image)
    }

    /// Writes an amplified difference image, because debugging a pixel
    /// mismatch by reading numbers off a failure message does not work.
    private static func writeDifference(actual: PixelBuffer, expected: PixelBuffer,
                                        name: String) throws -> String {
        var difference = PixelBuffer(width: actual.width, height: actual.height)
        for i in stride(from: 0, to: actual.pixels.count, by: PixelBuffer.bytesPerPixel) {
            var worst = 0
            for channel in 0..<4 {
                worst = max(worst, abs(Int(actual.pixels[i + channel])
                                       - Int(expected.pixels[i + channel])))
            }
            let level = UInt8(min(worst * 8, 255))
            difference.pixels[i] = level
            difference.pixels[i + 1] = level
            difference.pixels[i + 2] = level
            difference.pixels[i + 3] = 255
        }

        let directory = reportDirectory
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).diff.png")

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return "could not be written" }
        CGImageDestinationAddImage(destination, try difference.cgImage(), nil)
        CGImageDestinationFinalize(destination)

        return url.path
    }
}

/// Only exists so `Bundle(for:)` can find the test bundle.
private final class FixtureBundleAnchor {}

// MARK: - Fixture naming

extension FolderStyle {
    /// Matches the Python enum member names the fixture generator uses.
    var fixtureName: String {
        switch self {
        case .bigSurLight: "big_sur_light"
        case .bigSurDark:  "big_sur_dark"
        case .catalina:    "catalina"
        case .tahoe:       "tahoe"
        }
    }
}

extension SFFont {
    var fixtureName: String { String(describing: self) }
}
