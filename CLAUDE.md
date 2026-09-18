# Arbeitsanweisungen für Claude Code

Im [Projektplan.md](http://Projektplan.md)  stehen die Eckdaten des Projekts. Diese Datei sagt nur, **wie hier gearbeitet wird** — lies sie zuerst und die anderen  gezielt nach Bedarf, nicht vorsorglich am Stück.

Beachte auch das zweite Gehirn in Obsidian, lies gezielt die Bereiche 10 Projekte/Folder Crest. Beachte auch die letzten zwei Tageszusammenfassungen, so dass du eine Idee hast, was in den Vortagen passiert ist.

## Projekt in Kürze

Native Swift/SwiftUI-Portierung von FolderCrest (macOS-App, erzeugt Ordner-Icons). Xcode 26.5, Swift 6.3, macOS 26.0 und 27.0, arm64, Branch `master`. Referenz: `~/Developer/Github/FolderCrest/New-features` (Python).

Architektur, Pipeline-Entscheidungen (CPU statt Core Image), Pillow-Fallen, Layoutregeln, Testkonzept und Sandbox stehen in `PLAN.md` — **dort nachlesen.** Beachte dort den Nachtrag vom 2026-09-11 (Parity-Tests und Fixtures sind hinfällig). Referenzen im Repo: [PROMPT.md](PROMPT.md) (Auftrag und Vorgaben), [TODO.md](TODO.md) (offene Punkte — beim Wiederaufnehmen zuerst lesen), [PLAN.md](PLAN.md) (Plan und Messwerte), `mockup.svg` (UI-Entwurf).

## Xcode-Projekt

- Synchronisierte Ordner: Dateien im Zielordner sind automatisch Target-Mitglied. `project.pbxproj` nie von Hand um Dateien erweitern. Alles im Ordner landet auch im Bundle — `Scripts/` liegt deshalb auf Repo-Ebene.
- Debug steht auf `SWIFT_OPTIMIZATION_LEVEL = -O` (mit `-Onone` 50× langsamer). Nicht zurückdrehen; `@_optimize(speed)` bringt nichts.
- Für Xcode-Previews das Scheme `Folder Crest (Preview)` (Konfiguration Preview, `-Onone`) nutzen. Beide Schemes bleiben unter Versionskontrolle.
- Für reproduzierbare Läufe `-derivedDataPath` setzen (Xcode legt sonst eine zweite DerivedData-Ablage an).
- Deployment Target bleibt 26.0. Die Kalibrierung in `FolderGraphic.swift` ist gegen die macOS-26-Grafik vermessen und trägt auch unter macOS 27 (nachgemessen 2026-09-16).
- Nach App-Icon-Wechsel zeigt der Symbolstil „Dunkel" das alte Icon: Icon-Cache, nicht der Build. Erst `xcrun assetutil --info`, dann `touch`, `lsregister -f`, `killall Dock`.

## Build-Vokabular

Das gesagte Stichwort entscheidet, nicht der Umfang der Änderung. Ohne Stichwort bei Codeänderungen der Testbuild.

- **„Schneller Build"** → nur Debug bauen, keine Tests:
`xcodebuild -project "Folder Crest.xcodeproj" -scheme "Folder Crest" -destination 'platform=macOS' build`
- **„Testbuild"** → Debug bauen, nur Unit-Tests:
`… -destination 'platform=macOS' -skip-testing:"Folder CrestUITests" test`
- **„Voller Build"** → Debug-Test mit UI-Tests, dazu Release-Test ohne UI-Tests (`-configuration Release ENABLE_TESTABILITY=YES -skip-testing:"Folder CrestUITests" test`) und ein Release-Build.
- **"DMG Build"** → Erstelle eine DMG. Ein Release-Build wird nur erstellt, wenn notwendig (Code-änderungen, version) 

Regeln dazu:

- UI-Tests steuern echte Maus und Tastatur, der Mac ist \~2 min blockiert. Einzelne UI-Tests (`-only-testing:"Folder CrestUITests/<Klasse>/<Methode>"`) nur, wenn eine Änderung genau einen Klickweg betrifft — vorher ankündigen.
- **Kein Zip:** Nach einem Build das App-Bundle nicht verpacken, nur den Pfad zum Produkt nennen.
- Exit-Code und Testzahlen immer belegen.

## UI-Tests

- Einziger Weg, Klicks zu prüfen (`osascript`/System Events hat keinen Hilfszugriff).
- `app.launchArguments += ["-AppleLanguages", "(en)"]` setzen und gegen englische Labels klicken. Tests, die speichern, brauchen `-ui-testing` (In-Memory-Container), sonst landen Einträge in der echten Library.
- Elemente brauchen `.accessibilityLabel`, `.help()` allein reicht nicht. Das Über-Panel ist ein `dialog` ohne Titel (`app.dialogs.firstMatch`).
- `NSOpenPanel` liefert „Cancel" doppelt — mit Escape schließen. Der Runner ist sandboxed und findet fremde Apps nicht (`app.wait(for: .runningBackground)` prüfen). `.keyboardShortcut` an Buttons feuert nicht, Shortcuts gehören ins Menü (`FileCommands`).

## Release / DMG

`Scripts/make-dmg.swift` baut Release ad-hoc-signiert nach `dmg_build/` und packt mit appdmg. CI: `.github/workflows/build.yml` (Push auf master → Artefakt, Tag `v*` → Upload ins Release). Das Release legt Detlef auf github.com an, Tag `v<Version>-<Build>` (z. B. `v1.2-3`), Tag erst nach dem Push.

## Projektspezifische Regeln

- Sprache: Antworten Deutsch, Code-Kommentare, Commit-Messages, README und Wiki Englisch.
- Nichts committen oder pushen ohne ausdrückliche Aufforderung; vorher `git diff` zeigen und zusammenfassen.
- Lizenz MIT. Keine Secrets in Dateien.
- Erkenntnisse nach Abschluss im zweiten Gehirn (`10 Projekte/Folder Crest`) festhalten.

