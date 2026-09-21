//
//  FolderIconWriter.swift
//  Folder Crest
//
//  Writes the generated icon onto a real Finder folder, through the same
//  AppKit call the Python version reaches for via PyObjC.
//

import AppKit
import Foundation

enum FolderIconWriter {

    enum WriteError: LocalizedError {
        case iconDataUnreadable
        case refused(path: String)

        var errorDescription: String? {
            switch self {
            case .iconDataUnreadable:
                String(localized: "The generated icon could not be read.",
                       comment: "Error when the rendered icon cannot be turned into image data")
            case .refused(let path):
                String(localized: "macOS refused to set the icon of “\(path)”.",
                       comment: "Error when NSWorkspace declines to write a folder icon")
            }
        }
    }

    /// Sets the folder's icon.
    ///
    /// Writes one representation per macOS icon size rather than a single large
    /// one, so Finder does not have to downscale for list and column views.
    static func setIcon(_ buffer: PixelBuffer, on folder: URL) throws {
        let image = try iconFamily(from: buffer)

        let workspace = NSWorkspace.shared
        guard workspace.setIcon(image, forFile: folder.path, options: []) else {
            throw WriteError.refused(path: folder.lastPathComponent)
        }
        // Finder usually notices through the filesystem change, but open
        // windows and the icon cache can keep showing the old one
        workspace.noteFileSystemChanged(folder.path)
    }

    /// Removes any custom icon: the `Icon\r` file and the custom-icon flag.
    /// Harmless on a folder that was never customized.
    static func removeCustomIcon(from folder: URL) throws {
        let workspace = NSWorkspace.shared
        guard workspace.setIcon(nil, forFile: folder.path, options: []) else {
            throw WriteError.refused(path: folder.lastPathComponent)
        }
        workspace.noteFileSystemChanged(folder.path)
    }

    private static func iconFamily(from buffer: PixelBuffer) throws -> NSImage {
        let largest = Constants.iconSizes.max() ?? 1024
        let image = NSImage(size: NSSize(width: largest, height: largest))

        for size in Constants.iconSizes {
            let scaled = Resample.resize(buffer, width: size, height: size,
                                         alphaWeighted: true)
            guard let cgImage = try? scaled.cgImage() else {
                throw WriteError.iconDataUnreadable
            }
            let representation = NSBitmapImageRep(cgImage: cgImage)
            representation.size = NSSize(width: size, height: size)
            image.addRepresentation(representation)
        }
        return image
    }

    /// Creates a folder named like Finder's "untitled folder", numbering it up
    /// until the name is free.
    static func makeUniqueFolder(in directory: URL) throws -> URL {
        let base = String(localized: "untitled folder",
                          comment: "Name of a newly created folder, matching Finder's")
        var index = 1
        while true {
            let name = index == 1 ? base : "\(base) \(index)"
            let url = directory.appendingPathComponent(name, isDirectory: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url,
                                                        withIntermediateDirectories: false)
                return url
            }
            index += 1
        }
    }
}
