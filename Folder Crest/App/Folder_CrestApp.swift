//
//  Folder_CrestApp.swift
//  Folder Crest
//

import AppKit
import SwiftData
import SwiftUI

@main
struct Folder_CrestApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @State private var studio = IconStudio()

    /// The library lives in SwiftData.
    ///
    /// CloudKit is switched off until the app has an iCloud entitlement, which
    /// needs a paid developer account — see `PLAN.md`. Turning it on is one
    /// argument here; the model was written to CloudKit's rules from the start
    /// (defaults everywhere, no unique constraints), so nothing else changes.
    ///
    /// Under `-ui-testing` the store is thrown away again, so a UI test can
    /// save and rename icons without leaving them in the real library.
    private let container: ModelContainer = {
        let isUITest = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isUITest,
                                               cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: SavedIcon.self, configurations: configuration)
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(studio)
        }
        .defaultSize(width: 1100, height: 720)
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) {}
            FileCommands(studio: studio)
            CommandGroup(replacing: .appInfo) {
                Button {
                    NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
                } label: {
                    Text("About Folder Crest",
                         comment: "Application menu entry that opens the about panel")
                }
            }
        }
    }

    /// The standard about panel already shows the name, the version and the
    /// copyright from the Info.plist. This adds the licence and the site under
    /// it. Written in code rather than as a `Credits.html`, because the panel
    /// imports HTML with a fixed black text colour that turns unreadable in
    /// dark mode.
    private static var credits: NSAttributedString {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        let style: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centred,
        ]

        let licence = String(localized: "Released under the MIT License.",
                             comment: "Licence line in the about panel")
        let text = NSMutableAttributedString(string: licence + "\n", attributes: style)
        text.append(NSAttributedString(
            string: "www.feltedred.de",
            attributes: style.merging([.link: URL(string: "https://www.feltedred.de")!]) { _, new in new }))
        return text
    }
}

/// The window's actions in the File menu. Menu key equivalents fire wherever
/// focus is; a shortcut on a button deep in the window did not.
struct FileCommands: Commands {
    let studio: IconStudio
    @FocusedValue(\.library) private var library

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button {
                library?.save()
            } label: {
                Text("Save to Library", comment: "File menu entry that adds the current icon to the library")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(library == nil)

            Button {
                library?.load?()
            } label: {
                Text("Load from Library", comment: "File menu entry that loads the selected library icon again")
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(library?.load == nil)

            Divider()

            Button {
                studio.reset()
            } label: {
                Text("Reset All", comment: "Button that resets every setting")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button {
                Task { await studio.applyToFolder() }
            } label: {
                Text("Apply to Folder", comment: "Primary button that writes the icon onto a folder")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!studio.canApply)
        }
    }
}

/// Closing the window quits: there is one window and nothing to keep running
/// behind it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Drops "Show Tab Bar" and friends from the View menu. The app shows one
    /// document in one window; a second tab of it would have nothing to show.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    /// The window minimum belongs to the window, not to a `frame` around the
    /// scene content: a minimum imposed on the `NavigationSplitView` has to be
    /// redistributed over its columns mid-layout, which makes a split view
    /// child report a new minimum size during the window's constraint update
    /// pass. macOS 27 throws on that re-entrancy and the app aborts.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let window = NSApp.windows.first else {
            NSLog("No window at launch; window minimum size not applied.")
            return
        }
        window.contentMinSize = NSSize(width: 900, height: 620)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
