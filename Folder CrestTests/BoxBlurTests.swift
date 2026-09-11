//
//  BoxBlurTests.swift
//  Folder CrestTests
//
//  The expected values are Pillow 12.3.0's own output, captured on 2026-09-10.
//  If this test goes red, the generated icons no longer match the reference.
//

import Testing
@testable import Folder_Crest

struct BoxBlurTests {

    @Test("The box radius matches Pillow's derivation from sigma")
    func radius() {
        #expect(abs(BoxBlur.boxRadius(sigma: 3) - 2.4166666667) < 1e-9)
        #expect(abs(BoxBlur.boxRadius(sigma: 6) - 5.4583333333) < 1e-9)
    }

    /// Pillow's step response, sampled at the edge from d = -12 to +12.
    static let stepResponses: [(sigma: Double, expected: [UInt8])] = [
        (3, [0, 0, 0, 0, 1, 3, 8, 18, 32, 54, 81, 111, 144,
             174, 201, 223, 237, 247, 252, 254, 255, 255, 255, 255, 255]),
        (6, [7, 10, 15, 21, 28, 37, 48, 60, 74, 88, 104, 120, 135,
             151, 167, 181, 195, 207, 218, 227, 234, 240, 245, 248, 251]),
    ]

    @Test("The step response is identical to Pillow's",
          arguments: stepResponses)
    func stepResponse(sigma: Double, expected: [UInt8]) {
        let width = 201, height = 3, edge = 100

        var buffer = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let level: UInt8 = x < edge ? 0 : 255
                buffer[x, y] = RGBA(level, level, level, 255)
            }
        }

        BoxBlur.blur(&buffer, sigma: sigma)

        // Sampled in the middle row, where the vertical passes see a flat edge
        let actual = (-12...12).map { buffer[edge + $0, 1].red }
        #expect(actual == expected)
    }

    /// The same edge, rotated. The vertical direction runs on a transposed
    /// plane, so only a horizontal edge proves the transpose is right — a
    /// vertical one leaves every column constant and would pass regardless.
    @Test("A horizontal edge blurs identically to a vertical one",
          arguments: stepResponses)
    func stepResponseRotated(sigma: Double, expected: [UInt8]) {
        let width = 3, height = 201, edge = 100

        var buffer = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let level: UInt8 = y < edge ? 0 : 255
                buffer[x, y] = RGBA(level, level, level, 255)
            }
        }

        BoxBlur.blur(&buffer, sigma: sigma)

        let actual = (-12...12).map { buffer[1, edge + $0].red }
        #expect(actual == expected)
    }

    /// A flat image must survive untouched — catches divisor and edge-clamp
    /// mistakes that a step edge would hide.
    @Test func flatImageIsUnchanged() {
        var buffer = PixelBuffer(width: 64, height: 64)
        for y in 0..<64 {
            for x in 0..<64 { buffer[x, y] = RGBA(200, 100, 50, 255) }
        }

        BoxBlur.blur(&buffer, sigma: 6)

        #expect(buffer[0, 0] == RGBA(200, 100, 50, 255))
        #expect(buffer[32, 32] == RGBA(200, 100, 50, 255))
        #expect(buffer[63, 63] == RGBA(200, 100, 50, 255))
    }

    /// Channels not listed must not be touched.
    @Test func alphaIsLeftAlone() {
        var buffer = PixelBuffer(width: 32, height: 32)
        for y in 0..<32 {
            for x in 0..<32 { buffer[x, y] = RGBA(x < 16 ? 0 : 255, 0, 0, UInt8(x * 8 % 256)) }
        }
        let alphaBefore = (0..<32).map { buffer[$0, 16].alpha }

        BoxBlur.blur(&buffer, sigma: 3, channels: [0])

        #expect((0..<32).map { buffer[$0, 16].alpha } == alphaBefore)
    }
}

struct PixelBufferTests {

    /// Decoding must produce the same bytes Pillow reads out of the PNG —
    /// non-premultiplied sRGB, no colour management in between.
    @Test("The bundled folder graphic decodes to the reference bytes")
    func folderImageMatchesReference() throws {
        let buffer = try PixelBuffer.folderImage(.tahoe)

        #expect(buffer.width == 1024)
        #expect(buffer.height == 1024)

        #expect(buffer[0, 0] == RGBA(0, 0, 0, 0))
        #expect(buffer[512, 512] == RGBA(118, 210, 251, 255))
        #expect(buffer[512, 300] == RGBA(106, 203, 248, 255))
        #expect(buffer[100, 600] == RGBA(115, 210, 251, 255))
        #expect(buffer[1023, 1023] == RGBA(0, 0, 0, 0))
        #expect(buffer[512, 900] == RGBA(0, 0, 0, 18))
    }

    @Test("Every folder style is bundled and square", arguments: FolderStyle.allCases)
    func everyStyleLoads(style: FolderStyle) throws {
        let buffer = try PixelBuffer.folderImage(style)
        #expect(buffer.width == style.size)
        #expect(buffer.height == style.size)
    }

    @Test func cgImageRoundTripKeepsBytes() throws {
        var buffer = PixelBuffer(width: 17, height: 5)   // odd width: catches row padding
        for y in 0..<5 {
            for x in 0..<17 {
                buffer[x, y] = RGBA(UInt8(x * 15), UInt8(y * 50), 7, UInt8(200 + x % 55))
            }
        }

        let restored = try PixelBuffer(cgImage: buffer.cgImage())

        #expect(restored.width == buffer.width)
        #expect(restored.height == buffer.height)
        #expect(restored.pixels == buffer.pixels)
    }
}

struct ResampleTests {

    /// Pillow weights the colour channels by alpha when it resamples an RGBA
    /// image: scaling a strip that is half opaque red and half *transparent
    /// blue* must not bleed any blue into the red. Expected values read out of
    /// Pillow 12.3.0 on 2026-09-10.
    @Test func alphaWeightedResampleDoesNotBleed() {
        var strip = PixelBuffer(width: 20, height: 4)
        for y in 0..<4 {
            for x in 0..<20 {
                strip[x, y] = x < 10 ? RGBA(255, 0, 0, 255) : RGBA(0, 0, 255, 0)
            }
        }

        let scaled = Resample.resize(strip, width: 40, height: 4, alphaWeighted: true)

        let expected: [Int: RGBA] = [
            18: RGBA(255, 0, 0, 255),
            19: RGBA(255, 0, 0, 203),
            20: RGBA(255, 0, 0, 52),
            21: RGBA(0, 0, 0, 0),
        ]
        for (x, want) in expected.sorted(by: { $0.key < $1.key }) {
            let got = scaled[x, 1]
            #expect(got == want, "at x=\(x): got \(got), expected \(want)")
        }
    }

    /// The engraving mask is a single channel image on the Python side, so it
    /// must *not* be alpha weighted — doing so would darken every soft edge.
    @Test func maskResampleIsStraight() {
        var mask = PixelBuffer(width: 8, height: 8)
        for y in 0..<8 {
            for x in 0..<8 {
                let level: UInt8 = x < 4 ? 0 : 255
                mask[x, y] = RGBA(level, level, level, level)
            }
        }

        let scaled = Resample.resize(mask, width: 16, height: 16)

        // All four channels stay equal, which is what "grey in an RGBA buffer"
        // means downstream
        for y in 0..<16 {
            for x in 0..<16 {
                let p = scaled[x, y]
                #expect(p.red == p.alpha && p.red == p.green && p.red == p.blue)
            }
        }
    }
}
