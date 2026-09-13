//
//  IconStudio.swift
//  Folder Crest
//
//  The state behind the window: the recipe being edited, the rendered preview,
//  and where the icon should end up.
//
//  Rendering an icon takes long enough to be felt, so it runs off the main
//  actor and the previous render is cancelled whenever the recipe changes. The
//  last task started is the one that wins — which is all the Python version's
//  worker queue plus UUID bookkeeping ever achieved.
//

import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class IconStudio {

    // MARK: - Recipe inputs

    var text = "" { didSet { textChanged() } }
    var preserveColours = false { didSet { scheduleRender() } }
    var fontWeight = SFFont.default { didSet { scheduleRender() } }
    var tint: RGB? { didSet { scheduleRender() } }

    /// Slider positions, kept as ticks like the reference so the neutral middle
    /// is exactly reachable.
    var scaleTick = middleTick(of: Constants.iconScaleSliderMax) { didSet { scheduleRender() } }
    var offsetXTick = middleTick(of: Constants.iconOffsetSliderMax) { didSet { scheduleRender() } }
    var offsetYTick = middleTick(of: Constants.iconOffsetSliderMax) { didSet { scheduleRender() } }

    private(set) var droppedImage: PixelBuffer?

    // MARK: - Output

    private(set) var preview: CGImage?
    private(set) var sourcePreview: CGImage?
    private(set) var isRendering = false
    private(set) var isApplying = false
    var lastError: String?

    /// Where a new folder gets created, unless an existing one was dropped.
    private(set) var newFolderLocation = FileManager.default.urls(for: .desktopDirectory,
                                                                  in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser
    /// The sandbox only lets the app write where the user pointed it. The
    /// Desktop default is a suggestion until it went through the open panel.
    private var locationGranted = false
    /// A folder dropped onto the window: its icon is changed directly.
    var existingFolder: URL?

    private var renderTask: Task<Void, Never>?
    private var rendered: PixelBuffer?

    init() {
        scheduleRender()
    }

    // MARK: - Derived state

    static func middleTick(of total: Int) -> Int { (total - 1) / 2 + 1 }

    var scale: Double {
        interpolateIntToFloatWithMidpoint(
            scaleTick, 1, Constants.iconScaleSliderMax,
            Constants.minimumIconScaleValue, 1.0, Constants.maximumIconScaleValue)
    }

    /// The offset in fractions of the folder size. A smaller icon has more room
    /// to move, so the range grows as the scale shrinks — capped, because past
    /// that even a tiny icon leaves the box.
    var offset: CGPoint {
        func value(_ tick: Int, axis: Int) -> Double {
            let limits = axis == 0
                ? (Constants.maximumIconOffsetValue.x, Constants.maximumIconOffsetLimit.x)
                : (Constants.maximumIconOffsetValue.y, Constants.maximumIconOffsetLimit.y)
            let maximum = min(limits.0 / scale, limits.1)
            return interpolateIntToFloatWithMidpoint(
                tick, 1, Constants.iconOffsetSliderMax, -maximum, 0.0, maximum)
        }
        return CGPoint(x: value(offsetXTick, axis: 0), y: value(offsetYTick, axis: 1))
    }

    var source: IconSource {
        if let droppedImage { return .image(droppedImage, preserveColours: preserveColours) }
        if !text.isEmpty { return .text(text) }
        return .none
    }

    var recipe: IconRecipe {
        IconRecipe(source: source, scale: scale, offset: offset,
                   tint: tint, fontWeight: fontWeight)
    }

    /// The original colours choice only means anything for a dropped image.
    var canPreserveColours: Bool { droppedImage != nil }

    var hasSource: Bool {
        if case .none = source { return false }
        return true
    }

    var destinationName: String {
        (existingFolder ?? newFolderLocation).lastPathComponent
    }

    // MARK: - Editing

    private func textChanged() {
        // Typing replaces a dropped image, the way the reference clears the
        // text field when something is dropped
        if !text.isEmpty && droppedImage != nil { droppedImage = nil }
        scheduleRender()
    }

    func setDroppedImage(_ image: PixelBuffer, preserveColours: Bool? = nil) {
        droppedImage = image
        text = ""
        if let preserveColours { self.preserveColours = preserveColours }
        scheduleRender()
    }

    func clearSource() {
        droppedImage = nil
        text = ""
        scheduleRender()
    }

    func reset() {
        text = ""
        droppedImage = nil
        preserveColours = false
        fontWeight = .default
        tint = nil
        scaleTick = Self.middleTick(of: Constants.iconScaleSliderMax)
        offsetXTick = Self.middleTick(of: Constants.iconOffsetSliderMax)
        offsetYTick = Self.middleTick(of: Constants.iconOffsetSliderMax)
        existingFolder = nil
        scheduleRender()
    }

    func load(_ saved: SavedIcon) {
        let recipe = saved.recipe
        scaleTick = Self.tick(forScale: recipe.scale)
        fontWeight = recipe.fontWeight
        tint = recipe.tint
        switch recipe.source {
        case .none:
            text = ""; droppedImage = nil
        case .text(let value):
            droppedImage = nil; text = value
        case .image(let buffer, let preserve):
            text = ""; preserveColours = preserve; droppedImage = buffer
        }
        // The offsets were stored as fractions; find the ticks that reproduce
        // them under the scale that is now set
        offsetXTick = tick(forOffset: recipe.offset.x, axis: 0)
        offsetYTick = tick(forOffset: recipe.offset.y, axis: 1)
        scheduleRender()
    }

    private static func tick(forScale scale: Double) -> Int {
        (1...Constants.iconScaleSliderMax).min {
            let a = interpolateIntToFloatWithMidpoint(
                $0, 1, Constants.iconScaleSliderMax,
                Constants.minimumIconScaleValue, 1.0, Constants.maximumIconScaleValue)
            let b = interpolateIntToFloatWithMidpoint(
                $1, 1, Constants.iconScaleSliderMax,
                Constants.minimumIconScaleValue, 1.0, Constants.maximumIconScaleValue)
            return abs(a - scale) < abs(b - scale)
        } ?? Self.middleTick(of: Constants.iconScaleSliderMax)
    }

    private func tick(forOffset value: Double, axis: Int) -> Int {
        let limits = axis == 0
            ? (Constants.maximumIconOffsetValue.x, Constants.maximumIconOffsetLimit.x)
            : (Constants.maximumIconOffsetValue.y, Constants.maximumIconOffsetLimit.y)
        let maximum = min(limits.0 / scale, limits.1)
        guard maximum > 0 else { return Self.middleTick(of: Constants.iconOffsetSliderMax) }
        return (1...Constants.iconOffsetSliderMax).min {
            let a = interpolateIntToFloatWithMidpoint(
                $0, 1, Constants.iconOffsetSliderMax, -maximum, 0.0, maximum)
            let b = interpolateIntToFloatWithMidpoint(
                $1, 1, Constants.iconOffsetSliderMax, -maximum, 0.0, maximum)
            return abs(a - value) < abs(b - value)
        } ?? Self.middleTick(of: Constants.iconOffsetSliderMax)
    }

    // MARK: - Rendering

    /// Debounce: a slider drag fires a change per pixel, and rendering every
    /// one of them would only ever produce frames nobody sees.
    private static let debounce = Duration.milliseconds(40)

    private func scheduleRender() {
        renderTask?.cancel()
        isRendering = true

        let recipe = self.recipe
        let cropBox = FolderGraphic.previewCropPercentages
        let source = self.source

        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }

            let result = Result {
                try IconRenderer.makeIcon(recipe, isCancelled: { Task.isCancelled })
            }
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let buffer):
                let preview = try? buffer.cropped(to: cropBox).cgImage()
                let sourceImage = Self.sourceThumbnail(for: source, recipe: recipe)
                await self?.finish(buffer: buffer, preview: preview, source: sourceImage)
            case .failure(let error):
                // A cancelled render is not a failure worth showing
                guard !Task.isCancelled else { return }
                await self?.fail(error)
            }
        }
    }

    /// The small preview under the icon: what was dropped or typed, on its own.
    private nonisolated static func sourceThumbnail(for source: IconSource,
                                                    recipe: IconRecipe) -> CGImage? {
        switch source {
        case .none:
            return nil
        case .image(let buffer, _):
            return try? buffer.cgImage()
        case .text(let text):
            if let emoji = GlyphRenderer.colourEmoji(text) { return try? emoji.cgImage() }
            guard var mask = GlyphRenderer.mask(text: text, imageSize: FolderGraphic.size,
                                                weight: recipe.fontWeight) else { return nil }
            // The mask is white on black; show it as a solid shape instead
            for i in stride(from: 0, to: mask.pixels.count, by: PixelBuffer.bytesPerPixel) {
                let level = mask.pixels[i]
                mask.pixels[i] = 0; mask.pixels[i + 1] = 0; mask.pixels[i + 2] = 0
                mask.pixels[i + 3] = level
            }
            return try? mask.cgImage()
        }
    }

    private func finish(buffer: PixelBuffer, preview: CGImage?, source: CGImage?) {
        rendered = buffer
        self.preview = preview
        self.sourcePreview = source
        isRendering = false
    }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        isRendering = false
    }

    // MARK: - Writing

    /// Applies the icon to the target folder, waiting for a render that is
    /// still in flight rather than writing the previous one.
    func applyToFolder() async {
        guard !isApplying else { return }
        if existingFolder == nil && !locationGranted {
            guard chooseLocation() else { return }
        }
        isApplying = true
        defer { isApplying = false }

        await renderTask?.value
        guard let rendered else { return }

        do {
            let target: URL
            if let existingFolder {
                target = existingFolder
            } else {
                target = try FolderIconWriter.makeUniqueFolder(in: newFolderLocation)
            }
            try FolderIconWriter.setIcon(rendered, on: target)
            existingFolder = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Asks where new folders go. Returns false when the panel was cancelled.
    @discardableResult
    func chooseLocation() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = newFolderLocation
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        newFolderLocation = url
        locationGranted = true
        existingFolder = nil
        return true
    }

    /// A thumbnail for the library sidebar.
    func thumbnailData() async -> Data? {
        await renderTask?.value
        guard let rendered else { return nil }
        return Resample.resize(rendered.cropped(to: FolderGraphic.previewCropPercentages),
                               width: 256, height: 256, alphaWeighted: true).pngData()
    }
}
