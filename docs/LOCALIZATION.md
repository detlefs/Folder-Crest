# Localization

All user-facing text lives in a single String Catalog, `Folder Crest/Localizable.xcstrings`. To add a language:

1. Open `Folder Crest.xcodeproj` in Xcode, select the project, go to **Info → Localizations** and add the language with **+**.
2. Open `Localizable.xcstrings`, select the new language and translate every entry. Mark entries as reviewed once they are done.
3. Build and run the app with the new language and check that no text is cut off. In Xcode, set **Product → Scheme → Edit Scheme → Run → Options → App Language**, or from the command line (replace `fr` with the language code):

   ```bash
   xcodebuild -project "Folder Crest.xcodeproj" -scheme "Folder Crest" \
     -destination 'platform=macOS' -derivedDataPath build build
   open -n "build/Build/Products/Debug/Folder Crest.app" --args -AppleLanguages "(fr)"
   ```
4. Add the language to the list in `README.md` under **Usage** and open a pull request.
