//
//  Folder_CrestApp.swift
//  Folder Crest
//

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
    private let container: ModelContainer = {
        let configuration = ModelConfiguration(cloudKitDatabase: .none)
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
        }
    }
}

/// Closing the window quits: there is one window and nothing to keep running
/// behind it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
