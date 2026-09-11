//
//  GlyphRendererTests.swift
//  Folder CrestTests
//
//  The mask box decides the size of the engraving — everything downstream
//  scales the mask into the icon box — so it is pinned here per glyph.
//
//  Values captured from the Python reference on 2026-09-10. Two of them moved
//  by a pixel on 2026-09-11, when the renderer swapped the bundled SF Pro
//  Rounded files for the rounded system face: a different cut of the same
//  design rounds the ink box differently at the margins. Marked below.
//

import Testing
@testable import Folder_Crest

struct GlyphRendererTests {

    static let boxes: [(text: String, weight: SFFont, width: Int, height: Int)] = [
        ("A",  .bold, 353, 371), ("A",  .ultralight, 300, 369),
        ("W",  .bold, 494, 371), ("W",  .ultralight, 444, 369),
        ("Ag", .bold, 647, 467), ("Ag", .ultralight, 558, 458),   // Pillow: 468
        ("8",  .bold, 334, 377), ("8",  .ultralight, 294, 372),   // Pillow: 295 × 371
        ("MM", .bold, 884, 371), ("MM", .ultralight, 788, 369),
    ]

    @Test("The mask box matches Pillow", arguments: boxes)
    func maskBox(text: String, weight: SFFont, width: Int, height: Int) throws {
        let mask = try #require(GlyphRenderer.mask(text: text, imageSize: 1024, weight: weight))
        #expect(mask.width == width)
        #expect(mask.height == height)
    }

    /// A mask that comes back all black would engrave nothing at all, and the
    /// folder would silently render as if no text had been typed.
    @Test func maskHasInk() throws {
        let mask = try #require(GlyphRenderer.mask(text: "A", imageSize: 1024, weight: .bold))
        let lit = mask.pixels.filter { $0 > 128 }.count
        #expect(lit > 0, "the mask is empty — nothing would be engraved")

        let coverage = Double(lit) / Double(mask.pixels.count)
        #expect(coverage > 0.2 && coverage < 0.8,
                "an “A” should fill a sizeable part of its box, got \(coverage)")
    }

    @Test func emptyTextHasNoMask() {
        #expect(GlyphRenderer.mask(text: "", imageSize: 1024, weight: .bold) == nil)
    }
}
