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
                .frame(minWidth: 900, minHeight: 620)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) {}
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

/// Closing the window quits: there is one window and nothing to keep running
/// behind it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Drops "Show Tab Bar" and friends from the View menu. The app shows one
    /// document in one window; a second tab of it would have nothing to show.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
