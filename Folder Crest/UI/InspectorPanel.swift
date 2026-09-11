//
//  InspectorPanel.swift
//  Folder Crest
//
//  The right hand panel: how the icon sits on the folder, and what colour the
//  folder is.
//

import AppKit
import SwiftUI

struct InspectorPanel: View {
    private enum Tab: Hashable { case icon, colour }
    @State private var tab = Tab.icon

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $tab) {
                Text("Icon", comment: "Inspector tab for the icon's placement").tag(Tab.icon)
                Text("Folder Color", comment: "Inspector tab for the folder tint").tag(Tab.colour)
            } label: {
                Text("Inspector", comment: "Label of the inspector tab picker")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            ScrollView {
                switch tab {
                case .icon:   IconTab()
                case .colour: ColourTab()
                }
            }
        }
    }
}

struct IconTab: View {
    @Environment(IconStudio.self) private var studio

    var body: some View {
        @Bindable var studio = studio

        VStack(alignment: .leading, spacing: 22) {
            TickSlider(title: Text("Size", comment: "Slider for the icon scale"),
                       value: $studio.scaleTick,
                       maximum: Constants.iconScaleSliderMax,
                       reading: studio.scale.formatted(.percent.precision(.fractionLength(0))))

            TickSlider(title: Text("Horizontal Offset", comment: "Slider for the sideways icon offset"),
                       value: $studio.offsetXTick,
                       maximum: Constants.iconOffsetSliderMax,
                       reading: offsetReading(studio.offsetXTick))

            TickSlider(title: Text("Vertical Offset", comment: "Slider for the vertical icon offset"),
                       value: $studio.offsetYTick,
                       maximum: Constants.iconOffsetSliderMax,
                       reading: offsetReading(studio.offsetYTick))

            VStack(alignment: .leading, spacing: 6) {
                Text("Text Weight", comment: "Picker for the font weight of engraved text")
                    .font(.callout)
                Picker(selection: $studio.fontWeight) {
                    ForEach(SFFont.allCases, id: \.self) { weight in
                        Text(weight.label).tag(weight)
                    }
                } label: {
                    Text("Text Weight", comment: "Picker for the font weight of engraved text")
                }
                .labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("RENDERING", comment: "Section heading in the inspector")
                    .font(.caption).foregroundStyle(.secondary)

                Picker(selection: $studio.preserveColours) {
                    Text("Engraved", comment: "Rendering mode: cut into the folder").tag(false)
                    Text("Original Colors", comment: "Rendering mode: pasted in its own colours").tag(true)
                } label: {
                    Text("Rendering", comment: "Label of the rendering mode picker")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!studio.canPreserveColours)

                Text("Original colors apply only to dropped images and multicolor symbols.",
                     comment: "Hint under the rendering mode picker")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    private func offsetReading(_ tick: Int) -> String {
        let middle = IconStudio.middleTick(of: Constants.iconOffsetSliderMax)
        return (tick - middle).formatted(.number.sign(strategy: .automatic))
    }
}

/// A slider over integer ticks with its label and current reading above it.
struct TickSlider: View {
    let title: Text
    @Binding var value: Int
    let maximum: Int
    let reading: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                title.font(.callout)
                Spacer()
                Text(reading).font(.callout).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { Double(value) },
                                  set: { value = Int($0.rounded()) }),
                   in: 1...Double(maximum), step: 1) {
                title
            }
            .labelsHidden()
        }
    }
}

struct ColourTab: View {
    @Environment(IconStudio.self) private var studio
    @State private var panel = ColourPanel()

    private let columns = [GridItem(.adaptive(minimum: 34), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, spacing: 10) {
                NoTintSwatch(isSelected: studio.tint == nil) { studio.tint = nil }

                ForEach(TintColour.allCases, id: \.self) { tint in
                    ColourSwatch(colour: tint.rgb.color,
                                 isSelected: studio.tint == tint.rgb,
                                 label: tint.label) {
                        studio.tint = tint.rgb
                    }
                }

                // The wheel is a way in to the colour picker, not a tint of its
                // own, so it is drawn in full saturation rather than in the
                // muted folder palette
                ColourWheelSwatch(isSelected: isCustomSelected) {
                    panel.show(initial: studio.tint ?? TintColour.teal.rgb) { colour in
                        studio.tint = colour
                    }
                }
            }

            Text("The tint shifts hue, saturation, and brightness across the whole folder.",
                 comment: "Hint under the tint palette")
                .font(.caption).foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding()
    }

    private var isCustomSelected: Bool {
        guard let tint = studio.tint else { return false }
        return !TintColour.allCases.contains { $0.rgb == tint }
    }
}

private struct ColourSwatch: View {
    let colour: Color
    let isSelected: Bool
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(colour)
                .overlay { Circle().strokeBorder(.separator) }
                .overlay { if isSelected { Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-3) } }
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

private struct NoTintSwatch: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(.background)
                .overlay { Circle().strokeBorder(.separator) }
                .overlay {
                    Path { path in
                        path.move(to: CGPoint(x: 6, y: 22))
                        path.addLine(to: CGPoint(x: 22, y: 6))
                    }
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                .overlay { if isSelected { Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-3) } }
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(Text("No tint", comment: "Tooltip of the swatch that removes the folder tint"))
        .accessibilityLabel(Text("No tint", comment: "Tooltip of the swatch that removes the folder tint"))
    }
}

/// Drives the shared colour panel.
///
/// SwiftUI's `ColorPicker` cannot be given the look of a swatch: hiding its own
/// control behind the wheel left the wheel's button taking the clicks, so the
/// panel never opened. The panel underneath it is public API, so the wheel just
/// opens it directly.
@MainActor
@Observable
final class ColourPanel: NSObject {
    private var onChange: ((RGB) -> Void)?

    func show(initial: RGB, onChange: @escaping (RGB) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(initial.color)
        panel.setTarget(self)
        panel.setAction(#selector(colourChanged))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func colourChanged(_ sender: NSColorPanel) {
        onChange?(sender.color.rgb)
    }
}

private struct ColourWheelSwatch: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(AngularGradient(colors: Self.wheel, center: .center))
                .overlay { Circle().strokeBorder(.separator) }
                .overlay { if isSelected { Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-3) } }
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(Text("Custom Color", comment: "Label of the custom tint colour picker"))
        .accessibilityLabel(Text("Custom Color", comment: "Label of the custom tint colour picker"))
    }

    private static let wheel: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12)
        .map { Color(hue: $0, saturation: 0.85, brightness: 1.0) }
}

// MARK: - Small helpers

extension RGB {
    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255,
              blue: Double(blue) / 255)
    }
}

extension NSColor {
    var rgb: RGB {
        let resolved = usingColorSpace(.sRGB) ?? .black
        return RGB(Int((resolved.redComponent * 255).rounded()),
                   Int((resolved.greenComponent * 255).rounded()),
                   Int((resolved.blueComponent * 255).rounded()))
    }
}

extension TintColour {
    var label: LocalizedStringKey {
        switch self {
        case .red: "Red"
        case .melon: "Melon"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .teal: "Teal"
        case .lightblue: "Light Blue"
        case .purple: "Purple"
        case .cream: "Cream"
        case .white: "White"
        }
    }
}

extension SFFont {
    var label: LocalizedStringKey {
        switch self {
        case .ultralight: "Ultralight"
        case .thin: "Thin"
        case .light: "Light"
        case .regular: "Regular"
        case .medium: "Medium"
        case .semibold: "Semibold"
        case .bold: "Bold"
        case .heavy: "Heavy"
        case .black: "Black"
        }
    }
}
