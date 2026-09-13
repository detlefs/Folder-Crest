//
//  LibrarySidebar.swift
//  Folder Crest
//
//  The saved icons. Adding and removing sit in the footer, right under the list
//  the result appears in — the pattern every macOS source list uses. Renaming
//  goes through SwiftUI's own `RenameButton`/`.renameAction` pair, so the
//  context menu entry, its wording and its shortcut come from the system.
//

import SwiftData
import SwiftUI

struct LibrarySidebar: View {
    @Environment(IconStudio.self) private var studio
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedIcon.createdAt, order: .reverse) private var icons: [SavedIcon]

    @Binding var selection: SavedIcon?
    @State private var renaming: UUID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(icons) { icon in
                        LibraryRow(icon: icon,
                                   isRenaming: renaming == icon.id,
                                   endRename: { renaming = nil })
                            .tag(icon)
                    }
                } header: {
                    Text("My Icons", comment: "Heading of the saved icons list")
                }
            }
            // The list's own menu and primary action cover the whole row. A
            // tap gesture on the row would claim clicks on its image and text,
            // and only the empty part of the row would still select.
            .contextMenu(forSelectionType: SavedIcon.self) { selected in
                if let icon = selected.first {
                    RenameButton().renameAction { renaming = icon.id }
                }
            } primaryAction: { selected in
                renaming = selected.first?.id
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
            // A borderless button only hits on its glyph, and the minus is a
            // thin line. A fixed square makes both buttons equally easy to hit.
            .labelStyle(SquareIconLabelStyle())
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .focusedSceneValue(\.library, LibraryCommands(
            save: { Task { await save() } },
            load: selection.map { icon in { studio.load(icon) } }))
    }

    private func save() async {
        let thumbnail = await studio.thumbnailData()
        let icon = SavedIcon(name: suggestedName(), recipe: studio.recipe)
        icon.thumbnail = thumbnail
        context.insert(icon)
        selection = icon
        renaming = icon.id
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

private struct SquareIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Built on the icon-only style, which keeps the title for VoiceOver
        Label(configuration)
            .labelStyle(.iconOnly)
            .frame(width: 24, height: 22)
            .contentShape(.rect)
    }
}

/// What the File menu needs from the library, published by the sidebar.
struct LibraryCommands {
    var save: () -> Void
    /// Nil while nothing is selected.
    var load: (() -> Void)?
}

extension FocusedValues {
    @Entry var library: LibraryCommands?
}

struct LibraryRow: View {
    @Bindable var icon: SavedIcon
    var isRenaming = false
    var endRename: () -> Void = {}

    @FocusState private var nameFocused: Bool
    /// Kept so an emptied field can fall back to the name the row had before.
    @State private var previousName = ""

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
                if isRenaming {
                    TextField(text: $icon.name) {
                        Text("Name", comment: "Label of the field that renames a saved icon")
                    }
                    .textFieldStyle(.plain)
                    .fontWeight(.medium)
                    .focused($nameFocused)
                    .onSubmit(finish)
                    .onExitCommand(perform: finish)
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { finish() }
                    }
                    .task {
                        previousName = icon.name
                        nameFocused = true
                    }
                } else {
                    Text(icon.name).fontWeight(.medium).lineLimit(1)
                }
                Text(icon.sourceSummary).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func finish() {
        if icon.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            icon.name = previousName
        }
        endRename()
    }
}

#Preview {
    @Previewable @State var selection: SavedIcon?
    LibrarySidebar(selection: $selection)
        .environment(IconStudio())
        .modelContainer(for: SavedIcon.self, inMemory: true)
        .frame(width: 240, height: 600)
}
