//
//  Appearance.swift
//  Folder Crest
//
//  Light, dark, or whatever the system says.
//
//  Applied through `NSApp.appearance` rather than SwiftUI's
//  `.preferredColorScheme`: the modifier only tints the view tree, leaving the
//  menu bar, the open panel and the about window in the system mode — a break
//  you see immediately.
//
//  Note that this has nothing to do with the folder graphic: that one comes
//  from the system and looks the same in either mode.
//

import AppKit
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .system: "Automatic"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.righthalf.filled"
        case .light:  "sun.max"
        case .dark:   "moon"
        }
    }

    private var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil                            // hands control back to macOS
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }
}
