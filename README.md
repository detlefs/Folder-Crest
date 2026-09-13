# Folder Crest

A native macOS app that puts a crest on your folders: text, emoji, an SF Symbol
or any image, engraved into the macOS folder icon or placed on top in its own
colours — with an optional tint for the whole folder.

![Folder icons made with Folder Crest](readme_assets/carousel.png)

## Features

### Sources

- **Text** — up to 25 characters, set in SF Rounded in one of nine weights,
  from Ultralight to Black.
- **Emoji** — typed or pasted into the text field, drawn in full colour. When
  the text mixes emoji and letters, only the emoji are drawn.
- **SF Symbols** — drag a symbol straight out of the
  [SF Symbols](https://developer.apple.com/sf-symbols/) app. Monochrome symbols
  are engraved, multicolour symbols keep their colours.
- **Images** — drop an image file or image data from any app.

### Rendering

- **Engraved** — the source is cut into the folder with an inner shadow and a
  soft highlight, matching the look of the system's own folder icons
  (Downloads, Documents, Applications).
- **Original Colors** — dropped images and multicolour symbols can be placed on
  the folder as they are instead.
- **Size and position** — sliders for scale (10 % to 200 %) and horizontal and
  vertical offset. The offset range grows as the icon shrinks, so a small icon
  can move further without leaving the folder.

### Folder colour

- Ten muted tints tuned for the folder graphic: red, melon, orange, yellow,
  green, teal, light blue, purple, cream and white.
- Any other colour through the system colour panel.
- The tint shifts hue, saturation and brightness across the whole folder, not
  just a colour overlay.

### Applying the icon

- **New folder** — creates an "untitled folder" with the icon in a location of
  your choice. The first time, the app asks where (Desktop preselected), since
  the sandbox only lets it write where you pointed it.
- **Existing folder** — drop a folder onto the preview to make it the target;
  **Apply to Folder** then changes its icon instead of creating a new folder.
- Writes every icon size macOS uses (16 to 1024 px), so the icon stays sharp in
  list and column view too.
- Live preview while editing; **Reset All** returns to a plain folder.

### Library

- Save the current icon with **+** or **⌘S**.
- Saved icons appear in the sidebar with a thumbnail. Click one to load it
  back into the editor, rename it by double-click or context menu, remove it
  with **−**.
- The library stores the recipe, not the finished image, so icons can be
  re-rendered at any time.

### File menu

| Command           | Shortcut | What it does                                   |
| :---------------- | :------- | :--------------------------------------------- |
| Save to Library   | ⌘S       | Adds the current icon to the library           |
| Load from Library | ⌘O       | Loads the selected library icon again          |
| Reset All         | ⇧⌘R      | Returns to a plain folder                      |
| Apply to Folder   | ⌘↩       | Writes the icon onto the target folder         |

### App

- Light, dark or automatic appearance, selectable from the toolbar.
- Collapsible inspector.
- Localised in English and German.

## Requirements

- macOS 26 Tahoe or later (universal build, tested on Apple silicon)
- Xcode 26.5 to build from source
- Optional, for dragging in symbols: the
  [SF Symbols](https://developer.apple.com/sf-symbols/) app. It may also need the SF Pro font installed system wide — a freshly installed SF Symbols app will tell you so. Download the fonts from [Apple Fonts](https://developer.apple.com/fonts/).

## Building

Open `Folder Crest.xcodeproj` in Xcode and run the **Folder Crest** scheme, or
from the command line:

```bash
xcodebuild -project "Folder Crest.xcodeproj" -scheme "Folder Crest" \
  -destination 'platform=macOS' build
```

Run the tests with `test` instead of `build`. The UI tests drive the real mouse
and keyboard, so the Mac is not usable while they run; add
`-skip-testing:"Folder CrestUITests"` to run only the unit tests.

## How it works

Folder Crest is written in Swift and SwiftUI. Icons are rendered on the CPU
from the system's folder graphic using Core Graphics, Core Text and vImage; the
library is kept in SwiftData. The app has no third-party dependencies.

## About this project

Folder Crest was built with the help of AI: large parts of the code, the tests
and the documentation were written together with
[Claude Code](https://claude.com/claude-code).

## Licence

Released under the [MIT License](LICENSE).
