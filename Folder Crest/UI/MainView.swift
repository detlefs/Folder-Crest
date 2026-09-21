//
//  MainView.swift
//  Folder Crest
//
//  Sidebar (the library), the icon in the middle, inspector on the right.
//
//  Every action sits next to the thing it acts on: adding to the library is at
//  the foot of the library, applying to a folder is next to the folder that is
//  named. The toolbar carries view controls only.
//

import SwiftData
import SwiftUI

struct MainView: View {
    @Environment(IconStudio.self) private var studio
    @Environment(\.modelContext) private var context

    @AppStorage("appearance") private var appearance = Appearance.system
    @State private var inspectorShown = true
    @State private var selection: SavedIcon?

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            IconStage()
                .inspector(isPresented: $inspectorShown) {
                    InspectorPanel()
                        .inspectorColumnWidth(min: 260, ideal: 290, max: 360)
                }
        }
        .toolbar {
            ToolbarItem {
                AppearanceMenu(appearance: $appearance)
            }
            ToolbarItem {
                Button {
                    inspectorShown.toggle()
                } label: {
                    Label {
                        Text("Inspector", comment: "Toolbar button that shows or hides the inspector")
                    } icon: {
                        Image(systemName: "sidebar.trailing")
                    }
                }
            }
        }
        .onAppear { appearance.apply() }
        .onChange(of: appearance) { _, new in new.apply() }
        .onChange(of: selection) { _, new in
            if let new { studio.load(new) }
        }
        .alert(Text("Something went wrong", comment: "Title of the generic error alert"),
               isPresented: Binding(get: { studio.lastError != nil },
                                    set: { if !$0 { studio.lastError = nil } })) {
            Button("OK") { studio.lastError = nil }
        } message: {
            Text(studio.lastError ?? "")
        }
        .confirmationDialog(
            Text("Remove the custom icon from “\(studio.destinationName)”?",
                 comment: "Title of the confirmation before a folder's custom icon is removed"),
            isPresented: Binding(get: { studio.confirmingRemoval },
                                 set: { studio.confirmingRemoval = $0 }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                studio.removeCustomIcon()
            } label: {
                Text("Remove", comment: "Destructive button that removes a folder's custom icon")
            }
        } message: {
            Text("The folder returns to the default macOS icon. This also removes icons set by other tools.",
                 comment: "Message of the confirmation before a folder's custom icon is removed")
        }
    }
}

struct AppearanceMenu: View {
    @Binding var appearance: Appearance

    var body: some View {
        Menu {
            Picker(selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Label(option.label, systemImage: option.symbol).tag(option)
                }
            } label: {
                Text("Appearance", comment: "Label of the light/dark mode picker")
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text("Appearance", comment: "Label of the light/dark mode picker")
            } icon: {
                Image(systemName: appearance.symbol)
            }
        }
    }
}

#Preview {
    MainView()
        .environment(IconStudio())
        .modelContainer(for: SavedIcon.self, inMemory: true)
        .frame(width: 1000, height: 680)
}
