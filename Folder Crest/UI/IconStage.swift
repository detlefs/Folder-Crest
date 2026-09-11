//
//  IconStage.swift
//  Folder Crest
//
//  The middle column: the icon, the source below it, and the destination row.
//

import AppKit
import SwiftUI

struct IconStage: View {
    @Environment(IconStudio.self) private var studio

    var body: some View {
        VStack(spacing: 0) {
            FolderCanvas()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)

            Divider()
            SourceStrip()
                .padding(24)

            Divider()
            DestinationRow()
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        // An explicit ground: the folder graphic brings its own soft shadow,
        // which disappears on pure black and looks harsh on pure white
        .background(.background.secondary)
    }
}

// MARK: - The icon itself

struct FolderCanvas: View {
    @Environment(IconStudio.self) private var studio

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                .foregroundStyle(.quaternary)

            if let preview = studio.preview {
                Image(preview, scale: 1, label: Text("Folder icon preview",
                                                     comment: "Accessibility label of the large preview"))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(24)
            }

            VStack {
                Spacer()
                Text("Drag an SF Symbol, image, or folder here",
                     comment: "Hint under the large folder preview")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }

            if studio.isRendering {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                            .padding(12)
                    }
                }
            }

            DropTarget()
        }
    }
}

/// The pasteboard-backed drop area, laid over the preview.
struct DropTarget: View {
    @Environment(IconStudio.self) private var studio

    var body: some View {
        PasteboardDropView { item in
            switch item {
            case .image(let buffer, let preserveColours):
                studio.setDroppedImage(buffer, preserveColours: preserveColours)
            case .folder(let url):
                studio.existingFolder = url
            case .text(let text):
                studio.text = String(text.prefix(Constants.maximumIconTextLength))
            }
        }
    }
}

// MARK: - Source

struct SourceStrip: View {
    @Environment(IconStudio.self) private var studio

    var body: some View {
        @Bindable var studio = studio

        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary)
                    }
                    .overlay {
                        if let source = studio.sourcePreview {
                            Image(source, scale: 1, label: Text("Source preview",
                                                                comment: "Accessibility label of the small source preview"))
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .padding(10)
                        }
                    }
                    .frame(width: 96, height: 96)

                Text("Source", comment: "Caption of the small source preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Text or Emoji", comment: "Label of the icon text field")
                    .font(.callout)

                TextField(text: $studio.text) {
                    Text("Text or Emoji", comment: "Label of the icon text field")
                }
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .onChange(of: studio.text) { _, new in
                    if new.count > Constants.maximumIconTextLength {
                        studio.text = String(new.prefix(Constants.maximumIconTextLength))
                    }
                }

                Text("Up to \(Constants.maximumIconTextLength) characters. A drop replaces the text.",
                     comment: "Hint under the icon text field")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    studio.clearSource()
                } label: {
                    Text("Clear Source", comment: "Button that removes the dropped image or typed text")
                }
                .disabled(!studio.hasSource)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Destination

struct DestinationRow: View {
    @Environment(IconStudio.self) private var studio
    @State private var isApplying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if studio.existingFolder != nil {
                    Text("Change folder", comment: "Label when a dropped folder is the target")
                        .font(.callout)
                } else {
                    Text("New folder in", comment: "Label before the folder the new folder is created in")
                        .font(.callout)
                }
                Text(studio.destinationName).fontWeight(.semibold)

                Button {
                    chooseLocation()
                } label: {
                    Text("Change…", comment: "Button that opens the folder chooser")
                }
                .controlSize(.small)

                Spacer()

                Button {
                    studio.reset()
                } label: {
                    Text("Reset All", comment: "Button that resets every setting")
                }

                Button {
                    isApplying = true
                    Task {
                        await studio.applyToFolder()
                        isApplying = false
                    }
                } label: {
                    Text("Apply to Folder", comment: "Primary button that writes the icon onto a folder")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
                .disabled(isApplying)
            }

            Text("A dropped folder replaces the target and gets its icon set directly.",
                 comment: "Hint under the destination row")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = studio.newFolderLocation
        guard panel.runModal() == .OK, let url = panel.url else { return }
        studio.newFolderLocation = url
        studio.existingFolder = nil
    }
}

#Preview {
    IconStage()
        .environment(IconStudio())
        .frame(width: 520, height: 640)
}
