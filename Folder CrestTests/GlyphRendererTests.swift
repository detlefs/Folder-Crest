//
//  GlyphRendererTests.swift
//  Folder CrestTests
//
//  The mask box has to match Pillow's exactly — everything downstream scales
//  the mask into the icon box, so a different box means a different size.
//  Expected values captured from the reference on 2026-09-10.
//

import Testing
@testable import Folder_Crest

struct GlyphRendererTests {

    static let boxes: [(text: String, weight: SFFont, width: Int, height: Int)] = [
        ("A",  .bold, 353, 371), ("A",  .ultralight, 300, 369),
        ("W",  .bold, 494, 371), ("W",  .ultralight, 444, 369),
        ("Ag", .bold, 647, 468), ("Ag", .ultralight, 558, 458),
        ("8",  .bold, 334, 377), ("8",  .ultralight, 295, 371),
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
