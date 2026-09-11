//
//  RenderTests.swift
//  Folder CrestTests
//
//  The pipeline used to be pinned against PNG fixtures rendered by the Python
//  reference. That ended on 2026-09-11, when the folder graphic started coming
//  from the running system: the reference engraves a bundled Big Sur era PNG,
//  so every fixture compared two different folders and no tolerance could tell
//  a real regression from that.
//
//  What is left is what can be asserted without a second implementation: the
//  engraving lands inside the icon box, it scales, it tints, and a colour image
//  keeps its colours. The arithmetic underneath is still pinned pixel by pixel
//  in BoxBlurTests, ColourMathTests and GlyphRendererTests.
//

import CoreGraphics
import Testing
@testable import Folder_Crest

struct RenderTests {

    /// Pixels inside the icon box that the engraving changed.
    static func engravedPixels(_ recipe: IconRecipe) throws -> Int {
        let plain = try IconRenderer.makeIcon(IconRecipe())
        let icon = try IconRenderer.makeIcon(recipe)
        let box = FolderGraphic.iconBoxPercentages
        let size = FolderGraphic.size

        var changed = 0
        for y in Int(Double(size) * box.y1)..<Int(Double(size) * box.y2) {
            for x in Int(Double(size) * box.x1)..<Int(Double(size) * box.x2)
            where icon[x, y] != plain[x, y] {
                changed += 1
            }
        }
        return changed
    }

    @Test("A plain folder is the system graphic with a deepened shadow")
    func plainFolder() throws {
        let icon = try IconRenderer.makeIcon(IconRecipe())
        let folder = try PixelBuffer.folderImage()

        #expect(icon.width == FolderGraphic.size)
        #expect(icon.height == FolderGraphic.size)
        #expect(icon[512, 512] == folder[512, 512])   // opaque pixels are untouched

        // The shadow is the only difference: partly transparent gets more so
        let shadowY = Int(Double(FolderGraphic.size) * 0.88)
        #expect(icon[512, shadowY].alpha >= folder[512, shadowY].alpha)
    }

    @Test("Text is engraved inside the icon box")
    func textEngraving() throws {
        let changed = try Self.engravedPixels(IconRecipe(source: .text("A")))
        #expect(changed > 10_000)
    }

    @Test("A larger scale engraves more of the box")
    func scaling() throws {
        let small = try Self.engravedPixels(IconRecipe(source: .text("A"), scale: 0.5))
        let large = try Self.engravedPixels(IconRecipe(source: .text("A"), scale: 2.0))
        #expect(large > small)
    }

    @Test("An offset moves the engraving without resizing it")
    func offset() throws {
        let centred = try IconRenderer.makeIcon(IconRecipe(source: .text("A")))
        let moved = try IconRenderer.makeIcon(
            IconRecipe(source: .text("A"), offset: CGPoint(x: 0.2, y: 0)))
        #expect(centred != moved)

        let shift = Int(Double(FolderGraphic.size) * 0.2)
        let y = FolderGraphic.size / 2
        var matches = 0
        for x in 300..<600 where centred[x, y] == moved[x + shift, y] { matches += 1 }
        #expect(matches == 300)
    }

    @Test("A tint recolours the folder")
    func tinting() throws {
        let plain = try IconRenderer.makeIcon(IconRecipe())
        let red = try IconRenderer.makeIcon(IconRecipe(tint: TintColour.red.rgb))

        #expect(plain[512, 512].blue > plain[512, 512].red)
        #expect(red[512, 512].red > red[512, 512].blue)
        #expect(red[0, 0].alpha == 0)   // the empty corner stays empty
    }

    @Test("An image kept in its own colours is pasted, not engraved")
    func originalColours() throws {
        var image = PixelBuffer(width: 100, height: 100)
        for y in 0..<100 {
            for x in 0..<100 { image[x, y] = RGBA(255, 0, 0, 255) }
        }
        let icon = try IconRenderer.makeIcon(
            IconRecipe(source: .image(image, preserveColours: true)))

        // The paste is centred in the icon box, so its middle carries the
        // image's own red rather than a shade of the folder's blue
        let box = FolderGraphic.iconBoxPercentages
        let centre = (x: Int(Double(FolderGraphic.size) * (box.x1 + box.x2) / 2),
                      y: Int(Double(FolderGraphic.size) * (box.y1 + box.y2) / 2))
        #expect(icon[centre.x, centre.y] == RGBA(255, 0, 0, 255))
    }

    @Test("An emoji keeps its own colours too")
    func emoji() throws {
        let changed = try Self.engravedPixels(IconRecipe(source: .text("\u{1F419}")))
        #expect(changed > 10_000)
    }
}
