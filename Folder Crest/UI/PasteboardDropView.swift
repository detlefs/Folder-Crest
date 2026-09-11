//
//  PasteboardDropView.swift
//  Folder Crest
//
//  Drop handling, straight on NSPasteboard.
//
//  SwiftUI's `.onDrop` is not enough: a symbol dragged out of the SF Symbols
//  app carries its vector artwork as `public.svg-image`, and that flavour never
//  reaches an `NSItemProvider`. In AppKit it is simply there on the dragging
//  pasteboard — which makes this *less* work than the Cocoa detour the Python
//  version needs, not more.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What a drop turned out to be.
enum DroppedItem {
    /// An image or a monochrome symbol, ready to engrave or paste.
    case image(PixelBuffer, preserveColours: Bool)
    /// A folder: the target to change, not an icon.
    case folder(URL)
    /// Text or emoji for the icon field.
    case text(String)
}

struct PasteboardDropView: NSViewRepresentable {
    var onDrop: (DroppedItem) -> Void

    func makeNSView(context: Context) -> DropReceiver {
        let view = DropReceiver()
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ view: DropReceiver, context: Context) {
        view.onDrop = onDrop
    }
}

final class DropReceiver: NSView {
    var onDrop: ((DroppedItem) -> Void)?

    /// Highlighted while a drag hovers, so the window says it will accept it.
    private(set) var isTargeted = false {
        didSet { needsDisplay = true }
    }

    private static let svgType = NSPasteboard.PasteboardType("public.svg-image")

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([
            Self.svgType, .fileURL, .png, .tiff, .string,
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isTargeted = false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        isTargeted = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isTargeted = false
        guard let item = Self.read(sender.draggingPasteboard) else { return false }
        onDrop?(item)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isTargeted else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                xRadius: 12, yRadius: 12)
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    /// Reads a drop, most specific flavour first.
    static func read(_ pasteboard: NSPasteboard) -> DroppedItem? {
        // An SF Symbol: its vector artwork, in the colours of the rendering
        // mode chosen in the SF Symbols app
        if let svg = pasteboard.data(forType: svgType),
           let symbol = VectorRenderer.render(svg: svg, longestSide: Constants.symbolRenderSize) {
            // A symbol carrying colours goes on top of the folder, a
            // monochrome one is engraved like anything else — and engraving
            // works on brightness, so a white symbol needs its silhouette
            let colourful = !symbol.isGreyscale
            return .image(colourful ? symbol : symbol.blackSilhouette,
                          preserveColours: colourful)
        }

        if let url = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return .folder(url) }
                if let image = NSImage(contentsOf: url), let buffer = image.pixelBuffer {
                    return .image(buffer, preserveColours: false)
                }
            }
        }

        if let image = NSImage(pasteboard: pasteboard), let buffer = image.pixelBuffer {
            return .image(buffer, preserveColours: false)
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text)
        }
        return nil
    }
}

// MARK: - Helpers

extension NSImage {
    var pixelBuffer: PixelBuffer? {
        var rect = CGRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &rect, context: nil, hints: nil)
        else { return nil }
        return try? PixelBuffer(cgImage: cgImage)
    }
}

extension PixelBuffer {
    /// Whether every visible pixel is a shade of grey.
    var isGreyscale: Bool {
        for i in stride(from: 0, to: pixels.count, by: Self.bytesPerPixel) {
            guard pixels[i + 3] > 0 else { continue }
            if pixels[i] != pixels[i + 1] || pixels[i] != pixels[i + 2] { return false }
        }
        return true
    }

    /// The same shape, in black. A monochrome symbol may come in any colour,
    /// white included — and engraving reads brightness, so a white symbol
    /// would engrave nothing at all.
    var blackSilhouette: PixelBuffer {
        var result = self
        for i in stride(from: 0, to: result.pixels.count, by: Self.bytesPerPixel) {
            result.pixels[i] = 0
            result.pixels[i + 1] = 0
            result.pixels[i + 2] = 0
        }
        return result
    }
}

/// Rasterises the SVG macOS puts on the drag pasteboard for an SF Symbol.
enum VectorRenderer {
    static func render(svg: Data, longestSide: Int) -> PixelBuffer? {
        // NSImage reads SVG itself; there is no need for a parser
        guard let image = NSImage(data: svg), image.size.width > 0, image.size.height > 0
        else { return nil }

        let scale = Double(longestSide) / max(image.size.width, image.size.height)
        let size = NSSize(width: (image.size.width * scale).rounded(),
                          height: (image.size.height * scale).rounded())

        let scaled = NSImage(size: size)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        scaled.unlockFocus()

        return scaled.pixelBuffer?.croppedToInk()
    }
}

extension PixelBuffer {
    /// Trims fully transparent edges, as `Image.getbbox` does.
    func croppedToInk() -> PixelBuffer? {
        var minX = width, minY = height, maxX = 0, maxY = 0
        for y in 0..<height {
            for x in 0..<width where self[x, y].alpha > 0 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x + 1); maxY = max(maxY, y + 1)
            }
        }
        guard minX < maxX, minY < maxY else { return nil }

        var result = PixelBuffer(width: maxX - minX, height: maxY - minY)
        for y in 0..<result.height {
            for x in 0..<result.width { result[x, y] = self[minX + x, minY + y] }
        }
        return result
    }
}
