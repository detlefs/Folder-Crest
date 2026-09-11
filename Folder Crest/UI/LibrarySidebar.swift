//
//  LibrarySidebar.swift
//  Folder Crest
//
//  The saved icons. Adding and removing sit in the footer, right under the list
//  the result appears in — the pattern every macOS source list uses.
//

import SwiftData
import SwiftUI

struct LibrarySidebar: View {
    @Environment(IconStudio.self) private var studio
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedIcon.createdAt, order: .reverse) private var icons: [SavedIcon]

    @Binding var selection: SavedIcon?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(icons) { icon in
                        LibraryRow(icon: icon).tag(icon)
                    }
                } header: {
                    Text("My Icons", comment: "Heading of the saved icons list")
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if icons.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("No saved icons", comment: "Empty state title of the library")
                        } icon: {
                            Image(systemName: "folder")
                        }
                    } description: {
                        Text("Icons you save appear here.",
                             comment: "Empty state description of the library")
                    }
                }
            }

            Divider()
            HStack(spacing: 6) {
                Button {
                    Task { await save() }
                } label: {
                    Label {
                        Text("Save Icon", comment: "Button that adds the current icon to the library")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    remove()
                } label: {
                    Label {
                        Text("Remove Icon", comment: "Button that deletes the selected icon")
                    } icon: {
                        Image(systemName: "minus")
                    }
                }
                .disabled(selection == nil)

                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func save() async {
        let thumbnail = await studio.thumbnailData()
        let icon = SavedIcon(name: suggestedName(), recipe: studio.recipe)
        icon.thumbnail = thumbnail
        context.insert(icon)
        selection = icon
    }

    /// Names the entry after what it shows, falling back to a numbered default.
    private func suggestedName() -> String {
        switch studio.source {
        case .text(let text) where !text.isEmpty:
            return text
        default:
            let base = String(localized: "Icon", comment: "Default name of a saved icon")
            return "\(base) \(icons.count + 1)"
        }
    }

    private func remove() {
        guard let selection else { return }
        context.delete(selection)
        self.selection = nil
    }
}

struct LibraryRow: View {
    let icon: SavedIcon

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let data = icon.thumbnail, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "folder").imageScale(.large)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(icon.name).fontWeight(.medium).lineLimit(1)
                Text(icon.sourceSummary).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
