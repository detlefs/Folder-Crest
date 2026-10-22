# TODO — Folder Crest

Offene Punkte der Portierung. Der vollständige Plan, alle Messwerte und die
Begründungen stehen in [PLAN.md](PLAN.md); hier steht nur, was noch zu tun ist.

## Gelöst: Crash beim Start und beim Resizen der Sidebar auf macOS 27

Kein Apple-Bug, sondern App-Code (Issue #6, behoben in `eeb6e6a` am 2026-10-22).
Die drei Buttons in `DestinationRow` (`IconStage.swift`) trugen `.fixedSize()`.
Damit wird ihre Idealbreite zur harten Mindestbreite der Detail-Spalte der
`NavigationSplitView`; `SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`
meldet sie unter macOS 27 während des Constraint-Passes des Fensters immer
wieder neu, bis AppKits Loop-Detector abbricht („more Update Constraints in
Window passes than there are views in the window"). Ersetzt durch
`.layoutPriority(1)`: Die Buttons bleiben ungekürzt, ohne harte Mindestbreite.

So gefunden: Eine Minimal-App mit `NavigationSplitView`, Inspector und denselben
Spaltenbreiten stürzt nicht ab. Danach Spalten und Bestandteile von `IconStage`
per Umgebungsvariable durch Platzhalter ersetzt — nur ohne `DestinationRow`,
und dort nur ohne die `fixedSize`, überlebt die App.

Belegt: Debug-Test 28 Unit- und 14 UI-Tests grün (vorher Absturz beim Start),
Release-Test grün, Fenster-Sweep 880–1600 pt und Divider-Sweeps beider
Split-Views ohne Absturz, manuelles Ziehen auf MacNeo bestätigt.

- [ ] **Manuelles Ziehen der Trennlinien auf dem Haupt-Mac** gegenprüfen, dann
  Issue #6 schließen.

Fallen beim Eingrenzen, für das nächste Mal:

- **Nach einem Absturz hängt der nächste Start im Dialog „Fenster erneut
  öffnen?"** (`promptToIgnorePersistentStateWithCrashHistory`). Ein Prozess,
  der dort steht, sieht wie ein überlebender Start aus. Mit `sample <pid>`
  prüfen, ob `NSAlert runModal` auf dem Hauptthread liegt.
- **`-ApplePersistenceIgnoreState YES` beim Start des Binaries** unterdrückt
  das Fenster der `WindowGroup` ganz — kein Fenster, kein Absturz, nichts
  bewiesen.
- **XCUITest kann die Trennlinien nicht ziehen**: Die Splitter sind 0,5 pt
  breit, nie `isHittable`, und Drags über ihre Koordinaten bewegen nichts.
  Ziehen bleibt Handarbeit.
- **`applicationDidFinishLaunching` findet bei einem frischen Start noch kein
  Fenster** („No window at launch"); `contentMinSize` wird dann nicht gesetzt.
  Nicht behoben.

**Stand 2026-09-13 (1.2, Build 3):** Schritte 0–9, 11, 12 erledigt, 28 Unit-
und 14 UI-Tests grün (Debug wie Release). Offen ist Schritt 10 und das Drumherum.

Normaler Testlauf im Debug — die Debug-Konfiguration steht auf
`SWIFT_OPTIMIZATION_LEVEL = -O`, deshalb ist sie hier nicht mehr langsamer als
Release:

```bash
xcodebuild -project "Folder Crest.xcodeproj" -scheme "Folder Crest" \
  -destination 'platform=macOS' test
```

Der Release-Lauf braucht zusätzlich `ENABLE_TESTABILITY=YES`:

```bash
xcodebuild -project "Folder Crest.xcodeproj" -scheme "Folder Crest" \
  -configuration Release ENABLE_TESTABILITY=YES \
  -destination 'platform=macOS' test
```

Die UI-Tests steuern echte Maus und Tastatur, der Mac ist währenddessen
(~2 min) nicht benutzbar. Nur Unit-Tests, im Hintergrund: an beide Kommandos
`-skip-testing:"Folder CrestUITests"` anhängen.

`ENABLE_TESTABILITY=YES` ist dort nicht optional: die Unit-Tests importieren das
App-Modul mit `@testable`, und ohne Testbarkeit bricht im Release schon deren
Build ab („unable to resolve Swift module dependency to a compatible module:
'Folder_Crest'"). Das gilt auch, wenn nur die UI-Tests laufen sollen —
xcodebuild baut beide Test-Targets.

Dazu muss auf der Maschine der Developer Mode an sein, einmalig mit
`sudo DevToolsSecurity -enable`. Fehlt er, verlangt macOS bei jedem
Testhost-Start eine Passwortbestätigung per Dialog: der Lauf hängt ohne
Ergebnis-Bundle, mit „Unable to obtain a task name port right" im Protokoll,
die UI-Tests mit „Timed out while enabling automation mode".

---

## Blockiert

- [ ] **Schritt 10: CloudKit-Sync.** Braucht ein bezahltes Apple-Developer-Konto.

  Das Modell ist bereits nach CloudKit-Regeln gebaut (Defaults überall,
  keine Unique-Constraints, Enums als `…Raw: Int`). Zu tun, sobald das
  Konto steht:
  1. In `App/Folder_CrestApp.swift` `cloudKitDatabase: .none` → `.automatic`
  2. In Xcode: Signing &amp; Capabilities → iCloud → CloudKit, Container
  iCloud.de.feltedred.Folder-Crest`
  3. Auf zwei Geräten gegenprüfen
  Siehe PLAN.md, Abschnitt 3.

## Entscheidungen, die von dir kommen müssen

Ausführlich in PLAN.md, Abschnitt 9 („Zurückgestellte Fragen").

- [ ] **App-Icon final?** `Folder Crest/new_app_icon.icon` ist eingehängt und baut

  durch. Laut Claude-Memory war das Design am 2026-09-05 noch nicht final
  und wurde deshalb damals zurückgebaut.
- [ ] **Bundle-Identifier.** Aktuell `de.feltedred.Folder-Crest` (von Xcode

  vergeben). Die Python-App hat `de.feltedred.foldercrest`. Soll die native
  App die alte ersetzen, muss sie deren ID tragen — sonst behandelt macOS
  sie als anderes Programm und alle erteilten Berechtigungen fangen bei
  null an.
- [ ] **Schriftschnitte auf Deutsch.** Aktuell typografische Fachbegriffe

  (Ultraleicht, Dünn, Leicht, Normal, Mittel, Halbfett, Fett, Kräftig,
  Schwarz). Alternative: die englischen SF-Pro-Namen stehen lassen.

## Prüfen

- [ ] **Oberfläche visuell ansehen.** Nie kontrolliert worden — dem Terminal

  fehlt die Berechtigung zur Bildschirmaufnahme, Screenshots kommen schwarz
  zurück. Belegt ist nur: startet, läuft, keine Fehler im Log, beendet
  sauber, auf Englisch wie auf Deutsch.
- [ ] **Deutsch im Fenster durchsehen**, besonders auf abgeschnittene

  Beschriftungen im Inspector:
  `"[[ORCA_RICH_MD:4e0e7b84b163fe746d0c7a86e6d19082:inline-html:%3CApp%3E]]/Contents/MacOS/Folder Crest" -AppleLanguages '(de)'`
- [ ] **Drag &amp; Drop von Hand testen**, alle vier Wege: SF Symbol aus der

  SF-Symbols-App, Bilddatei, Ordner, Text/Emoji. Automatisiert ist davon
  nichts — `PasteboardDropView` braucht eine echte Drag-Pasteboard.
- [ ] **Icon auf einen echten Ordner schreiben** und im Finder kontrollieren,

  inklusive der kleinen Grössen in Listen- und Spaltenansicht.

## Repo-Hygiene

- [x] `**.gitignore` anlegen.** Steht im Repo.
- [x] **LICENSE ergänzen** — MIT, wie in den globalen Vorgaben festgelegt.
- [x] **README.md schreiben** (auf Englisch). Steht im Repo.
- [ ] `**Icon\r` ignorieren** — das Finder-Ordnericon liegt ungetrackt im

  Arbeitsverzeichnis.

## Später, bewusst zurückgestellt

- [ ] **„Erweitert"-Tab im Inspector** für die Blur-Radien und Versätze der

  Gravur-Filterkette. `EngraveParameters` ist dafür schon ein eigener Wert
  im Rezept, der Renderer liest ausschliesslich daraus — es fehlen nur die
  Regler. PLAN.md, Abschnitt 6.
- [ ] **UITests-Target entfernen.** Steht leer im Projekt. Bisher nicht

  angefasst, weil das Eingriffe in `project.pbxproj` bedeutet und ein
  ungenutzter Ordner weniger kostet als ein kaputtes Projekt.
- [ ] **Kalibrierung nachziehen, wenn macOS den Ordner neu zeichnet.** Die

  Werte in `FolderGraphic` sind am Systemsymbol von macOS 26 gemessen
  (2026-09-11). Der Test „Die kalibrierten Zahlen beschreiben den
  Systemordner noch" in `BoxBlurTests` schlägt an, sobald das nicht mehr
  stimmt; neu messen lässt es sich mit demselben Verfahren
  (Bounding-Box über Alpha &gt; 8, Mittelfarbe über die Icon-Box, Gravurfarbe
  aus der Differenz zu den Symbolen von Downloads/Dokumente/Programme).

## Manuelle Test-Ergebnisse

- [x] Der Klick auf ein gespeichertes Icon funktioniert nur in einem leeren Bereich, nicht beim Klick auf das Symbol oder einen Text. Das sollte behoben werden.
  - [x] Doppelklick zum Umbenennen sollte ebenfalls auf dem ganzen Feld (Preview, Text, leerer Bereich) funktionieren
- [x] Im Text "SF Symbol, Bild oder Ordner hierher ziehen" soll der Teil "SF Symbol" als Link ausgeführt sein, der entweder die SF Symbols App öffnet (wenn vorhanden) oder im Standardbrowser [https://developer.apple.com/sf-symbols/](https://developer.apple.com/sf-symbols/) öffnet

  Sucht `com.apple.SFSymbols`, dann `com.apple.SFSymbols-beta`. Auf dieser
  Maschine ist `/Applications/SF Symbols.app` eine leere Hülle ohne
  Info.plist — dort öffnet die Beta.
- [x] Da im Readme erwähnte **⇧⌘S** scheint nichts zu tun. Wie soll das funktionieren?

  Sollte „Auf Ordner anwenden" auslösen. Zwei Fehler: der Shortcut am Button
  feuerte nie, und auch der Button selbst scheiterte an der Sandbox („keine
  Berechtigung … Desktop"), weil der Desktop nie durch das Öffnen-Panel ging.
  Jetzt: Befehl im Ablage-Menü (⌘↩), und ohne gewählten Ort fragt die App
  beim Anwenden zuerst nach (Desktop vorausgewählt).
- [x] Im Datei Menü sollen die Punkte zum Speichern in der Library, laden aus der Library, Zurücksetzen und Auf Ordner anwenden stehen, zusammen mit passenden Hotkeys

  In Sammlung sichern ⌘S · Aus Sammlung laden ⌘O (lädt das ausgewählte Icon
  erneut, etwa nach Änderungen) · Alles zurücksetzen ⇧⌘R · Auf Ordner
  anwenden ⌘↩. UI-Test `FileMenuUITests`.
- [x] In der Readme soll erwähnt werden dass das Tool unter Einsatz von KI entstanden ist

- [x] Wenn ich im Textfeld neben einem Buchstaben ein Leerzeichen eingebe, ändert sich die Darstellung zu Schwarz (Ortiginalfarbe), nicht mehr Relief. Warum ist das so (ich vermute es hängt mit dem Emoji-Feature zusammen), bzw. kann es vermieden werden?

  Ja, das Emoji-Feature: „Apple Color Emoji" hat auch Glyphen für Leerzeichen,
  Ziffern, `#` und `*` (Keycap-Basen). Die Prüfung fragte nur die Schrift,
  also galt „A " als Emoji-Text, und Core Text malte das „A" trotz leerer
  Cascade-Liste in einer Textschrift — schwarz, aufgesetzt. Betraf auch eine
  einzelne Ziffer. Jetzt zählen nur echte Emoji (Unicode-Eigenschaft
  `isEmojiPresentation`, VS16 oder Keycap); Buchstaben neben einem Emoji
  bleiben weg wie in der Referenz. Unit-Tests in `GlyphRendererTests`.
- [x] Die "Hitbox" unten beim "-" Minus-Symbol ist sehr klein und schwer zu treffen. Beim "+" ist es leichter

  Ein randloser Button trifft nur auf seinem Glyph, und das Minus ist ein
  dünner Strich. Beide Buttons haben jetzt eine feste Trefferfläche von
  24 × 22 pt.

