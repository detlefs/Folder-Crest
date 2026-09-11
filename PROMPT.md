# Prompt: FolderCrest nach natives macOS Swift/SwiftUI portieren. Neuer Name: Folder Crest (mit Leerzeichen)

Du bekommst Zugriff auf das Repository FolderCrest unter /Users/detlef/Developer/Github/FolderCrest/New-features (Branch `New-features`) als **Referenz**. Es ist die aktuelle Python/PySide6-Implementierung von FolderCrest, einer macOS-App, die benutzerdefinierte Ordner-Icons generiert (Text/Emoji/SF Symbol/Bild wird in ein natives macOS-Ordner-Icon "eingraviert" oder als Farbbild aufgesetzt, inkl. Tönung).

## Ziel

Setze die App (gleiche Funktionalität, angepasstes UI-Layout, gleiches visuelle Ergebnis der generierten Icons) als native macOS-App in Swift/SwiftUI (oder AppKit, wo SwiftUI keine Entsprechung bietet) neu um. Kein Python, kein PySide6/Qt, keine PIL-Abhängigkeit — stattdessen Core Graphics / Core Image / SF Symbols nativ.

Zusätzliche gewünschte Features: Die erstellten Icons können abgespeichert werden (SwiftData oder Code Data, was besser geeignet ist) und über CloudKit synchronisiert werden. In der UI gibt es einen Bereich, ein ein- und ausklappbares Panel auf der linken Seite, mit der Liste der gespeicherten/synchronisierten Icons.

Das neue Icon ist zentral im Hauptfenster dargestellt. Darunter, ebenfalls direkt Hauptfenster, wird eine kleinere Vorschau des gedroppten SF Symbol, Grafik, Emoji, oder Text angezeigt. Das Textfeld zum Eingeben von Emoji und Text ist ebenfall hier.  
 "Eigenschaften" des neu generierten Icons, wie horiz./vert. Versatz, Größe, Originalfarbe/Relief werden in einem ein- und ausklappbaren Panel auf der rechten Seite angezeigt und bearbeitet. In einem weiteren Tab des rechten Panels wird die Farbe des Ordnersymbols angezeigt und bearbeitet.

Das UI-Layout der neuen App soll sich  an den aktuellen Apple Styleguide halten ([https://support.apple.com/de-de/guide/applestyleguide/welcome/web)](https://support.apple.com/de-de/guide/applestyleguide/welcome/web) und die Referenz-UI dementsprechend anpassen.

**Wichtig: Nicht sofort selbst implementieren.** Lies das Repo, verstehe die Logik vollständig, und lege dann einen Umsetzungsplan vor (Architektur, Dateistruktur, Reihenfolge der Schritte), bevor du Code schreibst.

Zeichne auch einen Mockup der UI in SVG, der Mockup kann einfach gehaltenh sein und muss keine MacOS Styles verwenden.

## Wo was liegt (Referenz)

- `foldercrest/constants.py` — alle Konstanten: Folder-Styles (Tahoe/Big Sur/Catalina), Farbpalette, Slider-Wertebereiche, Icon-Box-Geometrie pro Style. **Diese Zahlen 1:1 übernehmen**, sie sind empirisch kalibriert (Kommentare erklären warum).
- `foldercrest/imagetransformations.py` — Kernlogik der Icon-Generierung: Bounding-Box-Berechnung, Masken-Erzeugung aus Text/SF-Font/Bild, Engraving-Effekt (Multiply-Filter + Inner-Shadow + Outer-Highlight via Gaussian Blur), Emoji-Rendering (eigene Farben, kein Masking), Tönung per HSV-Verschiebung.
- `foldercrest/threadsafefoldergeneration.py` — Icon-Generierung läuft in eigenem Thread/Queue, abbrechbar (`TaskExitedException`), damit die UI beim Ziehen der Slider nicht blockiert.
- `foldercrest/utilities.py` — Farbkonvertierungen, Icon-Anwendung auf einen echten Finder-Ordner (setIcon via `NSWorkspace`/Resource Fork-Äquivalent).
- `foldercrest/ui/screens/mainwindow.py` — Hauptfenster-Layout (3 Panels: Style wählen, Icon konfigurieren, Ort/Speichern).
- `foldercrest/ui/components/composite/` — zusammengesetzte UI-Bausteine (Farbpalette, Style-Dropdown, Positions-Slider, Skalierungs/Dicke-Slider, Icon-Text-Panel, Speicherort-Panel).
- `foldercrest/ui/components/` — atomare UI-Bausteine (Radiobuttons, Slider, Labels).
- `assets/` — Basis-Ordnerbilder pro Style (PNG, 1024px) + SF-Pro-Rounded-Fonts.
- `icon_src/app_icon.icon` — App-Icon (Icon Composer Format, siehe Memory zu Icon-Composer-Build).
- `test_icons.py` — einziger vorhandener Test, zeigt erwartete Icon-Generierungs-Aufrufe.

## Bekannte Probleme &amp; Lösungsansätze (kurz)

1. **Font-Rendering-Unterschiede (PIL vs. Core Text).** PIL rendert Glyphen anders als Core Text (Metriken, Anti-Aliasing). → Core Text/`CTFont` direkt für die SF-Pro-Rounded-Fonts nutzen, nicht `NSFont` mit SwiftUI-Text, um volle Kontrolle über Glyph-zu-Maske-Rendering zu behalten (analog zu PILs `ImageFont`+Maske).
2. **Multiply-Blend + Gaussian-Blur-Kette 1:1 nachbilden.** Der Engraving-Look entsteht aus mehreren gestapelten Filtern (Inner Shadow, Outer Highlight, Multiply) mit exakten Offsets/Blur-Radien aus `constants.py`. → Core Image Filter-Kette (`CIMultiplyBlendMode`, `CIGaussianBlur`) 1:1 mit denselben Prozentwerten, relativ zur Foldergröße, nachbauen. In einer späteren Version könnte es möglich sein,  Parameter der gestapelten Filter in der UI anzupassen. Das sollte eingeplant werden.
3. **Emoji sind farbig und dürfen nicht maskiert werden**, SF-Symbole/Text schon (Graustufen-Maske). → Zwei Renderpfade beibehalten wie im Original: Emoji als farbiges Bild kompositieren, Text/SF-Symbol als Maske durchs Multiply.
4. **Drag &amp; Drop von Bildern/Emoji aus Fremd-Apps.** Qt-Pasteboard-Handling ist anders als AppKit. → `NSItemProvider`/`NSPasteboard` direkt nutzen, kein SwiftUI-`.onDrop` allein — für Bilder und Text/Emoji unterschiedliche UTType-Handler registrieren.
5. **Icon auf echten Finder-Ordner anwenden.** Erfolgt aktuell über eine Icon-Resource-Datei + `NSWorkspace.setIcon`. → Gleicher API-Aufruf in Swift (`NSWorkspace.shared.setIcon(_:forFile:options:)`), keine Neuerfindung nötig.
6. **Lange Berechnung blockiert UI beim Slider-Ziehen.** Python löst das mit Worker-Thread + Abbruch-Exception. → In Swift: Berechnung in `Task` mit Cancellation-Check (`Task.checkCancellation()`), letzter angestoßener Task gewinnt (debounce), kein eigenes Queue-System nötig.
7. **App-Icon-Format.** `.icon`-Datei ist Icon-Composer-Format, nicht direkt für ältere Xcode-Versionen. Build-Weg dokumentiert unter `icon-composer-build` — bei Bedarf im Zweiten Gehirn nachschlagen, nicht neu herausfinden.
8. **Fonts sind Stand 2023 mitgeliefert** (siehe `assets/fonts`) — bei Bundle-Fonts in Swift (`CTFontManagerRegisterFontsForURL` oder als Asset Catalog) denselben Versionsstand verwenden, sonst weichen Metriken/Look leicht ab.

## Vorgehen

1. Lies den kompletten Code in den oben genannten Dateien.
2. Leg einen Plan vor: Zielarchitektur (SwiftUI-Views ↔ bisherige composite-Komponenten), Kern-Renderpipeline (Core Image/Core Graphics), Datenmodell für Style/Slider-Zustände, Testkonzept (Pixel-Vergleich generierter Icons gegen die Python-Referenz für alle vier Styles).
3. Warte auf Rückmeldung/Freigabe des Plans, bevor du mit der Implementierung beginnst.

## Nicht tun

- Keine Qt/PySide-Abhängigkeiten importieren oder nachbilden wollen — komplett native AppKit/SwiftUI-Äquivalente verwenden.
- Keine Funktionalität hinzufügen, die im Original nicht existiert, außer der unter Ziel beschriebenen.
- Keine Icon-Geometrie/Farbwerte neu erfinden — exakt aus `constants.py` übernehmen.

