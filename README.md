# Folder Crest

A native macOS app that puts a crest on your folders: text, emoji, an SF Symbol or any image, engraved into the macOS folder icon or placed on top in its own colors - with an optional tint for the whole folder.

<a href="https://github.com/detlefs/Folder-Crest/blob/master/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green"></a>
<a href="https://github.com/detlefs/Folder-Crest/releases/latest"><img alt="GitHub Release" src="https://img.shields.io/github/v/release/detlefs/Folder-Crest"></a>
<a href="https://github.com/detlefs/Folder-Crest/actions/workflows/build.yml"><img alt="GitHub Actions Workflow Status" src="https://img.shields.io/github/actions/workflow/status/detlefs/Folder-Crest/build.yml"></a>

## Install

- macOS 26 Tahoe or later on Apple silicon (arm64 only, no Intel build).
- [Download the latest release](https://github.com/detlefs/Folder-Crest/releases/latest).
- Optional: the [SF Symbols](https://developer.apple.com/sf-symbols/) app and the [SF Pro fonts](https://developer.apple.com/fonts/), needed only if you want to drag SF Symbols onto icons.

To build from source: Xcode 26.5, then open `Folder Crest.xcodeproj` and run the **Folder Crest** scheme, or

```bash
xcodebuild -project "Folder Crest.xcodeproj" -scheme "Folder Crest" \
  -destination 'platform=macOS' build
```

Run the tests with `test` instead of `build`. The UI tests drive the real mouse and keyboard, so the Mac is not usable while they run; add `-skip-testing:"Folder CrestUITests"` to run only the unit tests.

## Usage

- Drag text, an emoji, an SF Symbol, or an image file onto the main area to add a symbol to the icon.
- Adjust size, offset, and rendering (engraved or original colors) in the Icon inspector.
- Pick a folder tint in the Folder Color inspector.
- Drop a folder onto the preview and click **Apply to Folder**, or create a new folder with the icon.
- Save an icon to the sidebar library with **⌘S**; it stores the recipe, not the image, so it re-renders at full resolution.
- Localized in English and German (see [docs/LOCALIZATION.md](docs/LOCALIZATION.md) to add a language).

## Limitations

- **System folder color** - Folder Crest writes each icon as a finished image. If you later change the system folder color (System Settings → Appearance → Folder color), folders modified by Folder Crest keep their color. Folder Crest itself picks up the new color as its default after a restart or after Reset All.

## How it works

Folder Crest is written in Swift and SwiftUI. Icons are rendered on the CPU from the system's folder graphic using Core Graphics, Core Text and vImage; the library is kept in SwiftData. The app has no third-party dependencies.

## Contributing

Pull requests are welcome - bug fixes, new features and translations alike. For larger changes, please open an issue first to discuss the idea.

1. Fork the repository and create a branch from `master`.
2. Make your changes and run the tests (see [Install](#install)).
3. Commit with a short, descriptive message and open a pull request against `master`, describing what you changed and why.

## License

[MIT](LICENSE)
