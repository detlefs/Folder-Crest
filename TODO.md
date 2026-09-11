# TODO — Folder Crest

Offene Punkte der Portierung. Der vollständige Plan, alle Messwerte und die
Begründungen stehen in [PLAN.md](PLAN.md); hier steht nur, was noch zu tun ist.

**Stand 2026-09-10:** Schritte 0–9, 11, 12 erledigt, 80 Testfälle grün. Offen
ist Schritt 10 und das Drumherum.

Testlauf (muss Release sein, Debug ist hier 100× langsamer):

```bash
xcodebuild -project "Folder Crest.xcodeproj" -scheme "Folder Crest" \
  -configuration Release ENABLE_TESTABILITY=YES \
  -destination 'platform=macOS' test
```

---

## Blockiert

- [ ] **Schritt 10: CloudKit-Sync.** Braucht ein bezahltes Apple-Developer-Konto.
      Das Modell ist bereits nach CloudKit-Regeln gebaut (Defaults überall,
      keine Unique-Constraints, Enums als `…Raw: Int`). Zu tun, sobald das
      Konto steht:
      1. In `App/Folder_CrestApp.swift` `cloudKitDatabase: .none` → `.automatic`
      2. In Xcode: Signing & Capabilities → iCloud → CloudKit, Container
         `iCloud.de.feltedred.Folder-Crest`
      3. Auf zwei Geräten gegenprüfen
      Siehe PLAN.md, Abschnitt 3.

## Entscheidungen, die von dir kommen müssen

Ausführlich in PLAN.md, Abschnitt 9 („Zurückgestellte Fragen").

- [ ] **App-Icon final?** `Folder Crest/app_icon.icon` ist eingehängt und baut
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
      `"<App>/Contents/MacOS/Folder Crest" -AppleLanguages '(de)'`
- [ ] **Drag & Drop von Hand testen**, alle vier Wege: SF Symbol aus der
      SF-Symbols-App, Bilddatei, Ordner, Text/Emoji. Automatisiert ist davon
      nichts — `PasteboardDropView` braucht eine echte Drag-Pasteboard.
- [ ] **Icon auf einen echten Ordner schreiben** und im Finder kontrollieren,
      inklusive der kleinen Grössen in Listen- und Spaltenansicht.

## Repo-Hygiene vor dem ersten Commit

Noch ist nichts committet: 21 Einträge stehen ungetrackt oder geändert im
Arbeitsverzeichnis.

- [ ] **`.gitignore` anlegen**, bevor committet wird. Sonst landen
      `xcuserdata/`, `.DS_Store` und Build-Reste dauerhaft in der Historie.
- [ ] **LICENSE ergänzen** — MIT, wie in den globalen Vorgaben festgelegt.
- [ ] **README.md schreiben** (auf Englisch).
- [ ] Erst danach committen.

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
      (Bounding-Box über Alpha > 8, Mittelfarbe über die Icon-Box, Gravurfarbe
      aus der Differenz zu den Symbolen von Downloads/Dokumente/Programme).
