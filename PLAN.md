# Umsetzungsplan: Folder Crest (Swift/SwiftUI)

Portierung von FolderCrest 3.0 (Python/PySide6/Pillow) nach nativem macOS.
Referenz: `~/Developer/Github/FolderCrest/New-features`, Branch `detlefs/New-features`.

Ziel-Toolchain: Xcode 26.5, Swift 6.3, Deployment Target macOS 26.0, arm64.

---

## 0. Was ich in der Referenz gefunden habe

Die Pipeline in `imagetransformations.generate_folder_icon` ist in Wahrheit
**reine 8-Bit-Pixelarithmetik auf sRGB** — kein einziger Schritt braucht mehr als
Puffer-Operationen plus zwei Gaussian Blurs. Die Reihenfolge, exakt:

| # | Schritt | Detail, das leicht übersehen wird |
| :-- | :--- | :--- |
| 1 | Basisbild laden | Alpha × 1.7, auf 255 geklemmt (`_increased_shadow`) |
| 2 | Bounding Box | `icon_box_percentages` × 1024, dann `scaled_box(box, scale × 0.84)`, auf Canvas geklemmt |
| 3 | Offset | `int(1024 × icon_offset)` — verschiebt das **Einfügen**, nicht die Box, damit Bewegen nie die Größe ändert |
| 4a | Bild + Originalfarben | Tönung zuerst auf den Ordner, dann Bild aufsetzen |
| 4b | Emoji erkannt | gleicher Pfad wie 4a |
| 5 | Maske erzeugen | Text: SF Pro Rounded @ 512 pt, weiß auf schwarz · Bild: weißer Hintergrund, Sigmoid-Normalisierung (`steepness 0.18`), invertiert |
| 6 | Maske einpassen | `paste(img, box, img)` — **die Maske ist ihre eigene Alpha**, das Ergebnis ist `mask²/255`, nicht `mask` |
| 7 | Mittelfarbe | `divided_colour(base, icon)` = `clamp(255 × icon / base)` |
| 8 | Innerer Schatten | Mischfarbe → Blur σ=3 → 3 px nach unten → `putalpha(mask)` (ungequadrat!) → `multiply(folder, shadow)` |
| 9 | Äußeres Highlight | `#131313`-Maske → Blur σ=6 → 8 px nach unten → `putalpha(0)` → `add(folder, highlight)` |
| 10 | Kombinieren | `alpha_composite(highlight_insert, shadow_insert)` |
| 11 | Tönung | 3D-LUT der **Kantenlänge 4** in HSV: `h += Δh mod 1`, `s ×= f_s`, `v ×= f_v` |

Zwei Fallen, die eine naive Portierung sofort sichtbar falsch machen:

* **Schritt 6** quadriert die Maske. Übersieht man das, wird die Gravur zu weich.
* **Schritt 8**: `ImageChops.multiply` auf RGBA multipliziert **auch den Alphakanal**.
  Das Ergebnis-Alpha ist `folder_a × mask / 255` — genau deshalb funktioniert das
  spätere `alpha_composite` überhaupt.

### Gemessen, nicht geraten: die Blur-Semantik

Pillows `GaussianBlur(radius)` behandelt `radius` als **Standardabweichung σ**,
nicht als Kernelradius. Sprungantwort, gemessen mit Pillow 12.3.0 an einer
Kante:

```
radius=3   d=-3: 0.2118   (σ=3: 0.1587,  σ=1: 0.0013)
radius=3   d=+3: 0.8745   (σ=3: 0.8413,  σ=1: 0.9987)
radius=6   d=-6: 0.1882   (σ=6: 0.1587,  σ=2: 0.0013)
```

Also σ ≈ radius, und leicht breiter als eine echte Gauß-Kurve, weil Pillow drei
Box-Blurs stapelt. `CIGaussianBlur.inputRadius` folgt einer anderen Konvention
(≈ 3σ) und ist nicht dokumentiert festgeschrieben.

Die vier Ordner-PNGs tragen `sRGB IEC61966-2.1` — Pillow ignoriert das Profil und
rechnet auf rohen Bytes. Ein sRGB-Bitmapkontext in Core Graphics macht dieselbe
Rechnung ohne Konvertierung, Bitgleichheit ist erreichbar.

---

## 1. Entschieden am 2026-09-10: CPU-Pipeline statt Core Image

Der Prompt sagt „Core-Image-Filterkette 1:1 nachbauen". Stattdessen eine
CPU-Pipeline über RGBA8-Puffer (Accelerate/vImage + Core Graphics), aus drei
nachprüfbaren Gründen:

1. Core Image rechnet standardmäßig in **linearem** Arbeitsfarbraum. `CIMultiplyBlendMode`
   auf linearen Werten ist nicht `ImageChops.multiply` auf sRGB-Bytes. Man müsste
   `CIContext(options: [.workingColorSpace: NSNull()])` erzwingen — dann ist von
   „nativ Core Image" ohnehin nur noch die Filterhülle übrig.
2. `CIGaussianBlur` hat die falsche Radius-Konvention (s. o.) und keine
   zugesicherte Kernel-Form. Pillows 3-Pass-Boxblur ist dagegen ~30 Zeilen
   (`vImageBoxConvolve_ARGB8888`, drei Durchgänge, Boxbreite aus σ nach
   `BoxBlur.c`) und liefert **exakt** dieselben Zahlen.
3. 1024² sind 1 M Pixel; die ganze Kette sind ca. 8 volle Puffer-Durchläufe.
   Der GPU-Vorteil von Core Image zahlt sich hier nicht aus, die Debugbarkeit
   einer CPU-Kette schon. **Gemessen am 2026-09-10:** beide Blurs zusammen
   79 ms auf 1024² (Schritt 2, s. u.) — mehr als anfangs geschätzt, mit
   Debounce und Task-Abbruch aber unkritisch.

Die Tönung bleibt trotzdem 1:1 als 4³-LUT — Pillows `Color3DLUT` und ein
`CIColorCube` interpolieren beide trilinear, hier wäre Core Image sogar
deckungsgleich. Ich würde sie der Einheitlichkeit halber trotzdem auf der CPU
rechnen.

Damit bleibt der Parity-Test in seiner strengen Form: `maxChannelDelta ≤ 1`,
also Bitgleichheit gegen die Python-Referenz. Mit Core Image wären Toleranzen
nötig gewesen.

---

## 2. Zielarchitektur

Drei Schichten, die sich nicht kennen: `Render` weiß nichts von SwiftUI,
`Model` weiß nichts von Core Graphics, `UI` ruft nur `IconRenderer`.

```
Folder Crest/
  App/
    Folder_CrestApp.swift        @main, ModelContainer (CloudKit), Commands
    IconStudio.swift             @Observable — hält Recipe + laufenden Render-Task
  Model/
    Constants.swift              1:1 aus constants.py, mit den Originalkommentaren
    FolderStyle.swift            enum + filename/displayName/size/iconBox/previewCrop/baseColour/iconColour
    IconRecipe.swift             struct Hashable: style, source, scale, offset, tint, weight, preserveColours
    IconSource.swift             enum: none / text(String) / image(CGImage, preserveColours: Bool)
    EngraveParameters.swift      innerBlur, innerYOffset, outerBlur, outerYOffset, shadowScale
    SavedIcon.swift              @Model für SwiftData/CloudKit
    Appearance.swift             enum system/light/dark + Anwendung auf NSApp
  Render/
    PixelBuffer.swift            RGBA8 (non-premultiplied), CGImage ⇄ Puffer, Un-/Premultiply via vImage
    BoxBlur.swift                Pillow-kompatibler 3-Pass-Boxblur
    ColourMath.swift             rgb↔hsv, dividedColour, clamp — Ports aus utilities.py
    TintCube.swift               4³-HSV-LUT + trilineare Anwendung
    MaskBuilder.swift            Text/Bild → L-Maske inkl. Sigmoid-Normalisierung
    GlyphRenderer.swift          Core Text: SF Pro Rounded + Apple Color Emoji
    VectorRenderer.swift         SVG (SF Symbol) → CGImage, auf Tintenrahmen beschnitten
    IconRenderer.swift           makeIcon(_ recipe:) — die Kette aus Abschnitt 0
    FolderIconWriter.swift       NSImage-Familie 16…1024 + NSWorkspace.setIcon + noteFileSystemChanged
  UI/
    MainView.swift               NavigationSplitView + .inspector + .toolbar
    LibrarySidebar.swift         gespeicherte Icons (@Query)
    FolderCanvas.swift           großes Icon, Drop-Ziel, Preview-Crop
    SourceStrip.swift            kleine Quellvorschau + Textfeld
    Inspector/IconTab.swift      Größe, Versatz H/V, Textstärke, Originalfarben
    Inspector/ColourTab.swift    Tint-Palette + eigene Farbe
    AppearanceMenu.swift         Sonne/Mond-Umschalter in der Toolbar
    PasteboardDropView.swift     NSViewRepresentable — der einzige AppKit-Umweg
  Resources/
    Localizable.xcstrings        String Catalog, Quellsprache en, dazu de
    InfoPlist.xcstrings          lokalisierte Bundle-Strings
    Folders/{big_sur_light,big_sur_dark,catalina,tahoe}.png
    Fonts/SF-Pro-Rounded-*.otf   Stand 2023, unverändert übernommen
Folder CrestTests/
  ParityTests.swift              Pixelvergleich gegen die Python-Referenz
  Fixtures/*.png
Scripts/
  make_fixtures.py               erzeugt die Fixtures aus der Referenz-Implementierung
```

### Views ↔ bisherige Komponenten

| Python (PySide6) | Swift |
| :--- | :--- |
| `FolderStyleDropdown` | `Picker` in der Toolbar |
| `CentreFolderIconContainer` + Spinner | `FolderCanvas` (`Image` + `ProgressView`, gleiches 250-ms-Delay) |
| `PositionSliders` (Slider um die Vorschau) | Inspector-Tab „Icon", zwei `Slider` |
| `ScaleThicknessSliders` | Inspector-Tab „Icon", `Slider` + `Picker` für die Schriftstärke |
| `ColourPalette` (Radiobuttons) | Inspector-Tab „Ordnerfarbe": Kreisraster, letzter Kreis = Farbrad, öffnet `ColorPicker` |
| `SetIconTextPanel` | `SourceStrip` unter dem Icon |
| `SetLocationPanel` | Zielzeile unten in der Mitte („Neuer Ordner in …" / gezogener Ordner) |
| `SaveIconPanel` | Aufgeteilt: „Auf Ordner anwenden" + „Alles zurücksetzen" in der Zielzeile · „+" in der Seitenleisten-Fußzeile (neu) |
| `AboutPanel` | Standard-`about`-Fenster (`.commands`) |
| — (neu) | `AppearanceMenu` in der Toolbar: Automatisch / Hell / Dunkel |
| `FolderGeneratorWorker` + `TaskExitedException` | `Task` + `Task.checkCancellation()` |

Die nummerierten Instruktions-Panels 1–3 fallen ersatzlos weg; die
Sidebar/Inspector-Aufteilung aus dem Prompt ersetzt sie. `PANEL{1,2,3}_COLOUR`
werden damit unbenutzt und wandern nicht mit.

### Wo die Aktionen sitzen

Der erste Entwurf hatte einen einzigen Knopf „Ordner-Icon sichern" oben rechts
in der Toolbar. Das war aus zwei Gründen falsch, und der zweite ist der
schwerere:

1. Er stand maximal weit von der Seitenleiste entfernt, in der das Ergebnis
   auftaucht.
2. **Er trug zwei verschiedene Aktionen unter einer Beschriftung.** Die App hat
   zwei „Sichern", die nichts miteinander zu tun haben:
   * **Auf Ordner anwenden** — schreibt das Icon per `NSWorkspace.setIcon` auf
     einen echten Finder-Ordner. Objekt ist der Zielordner.
   * **Zur Sammlung sichern** — legt das Rezept in SwiftData ab, es erscheint in
     der Seitenleiste. Objekt ist die Sammlung.

Regel für das Layout, daraus abgeleitet: **jede Aktion steht neben ihrem
Objekt, die Toolbar trägt nur Ansichtssteuerung.**

| Steuerung | Ort | Warum dort |
| :--- | :--- | :--- |
| Seitenleiste ein/aus, Ordnerstil, Erscheinungsbild, Inspector ein/aus | Toolbar | Alles vier ändert nur die Ansicht, nichts davon schreibt etwas |
| `+` / `−` | Fußzeile der Seitenleiste | Das gesicherte Icon erscheint eine Zeile darüber. Das ist das native Source-List-Muster (Finder-Seitenleiste, Mail, Kurzbefehle) |
| „Auf Ordner anwenden" (gefüllt) | Zielzeile unten in der Mitte | Direkt hinter „Neuer Ordner in: Schreibtisch" — der Satz wird dort vollständig |
| „Alles zurücksetzen" | daneben, ungefüllt | Wie im Original neben dem Sichern-Knopf gruppiert |
| „Quelle löschen" | im Bereich „Quelle" | Löscht nur den Drop, nicht die Regler |

Tastaturkürzel: ⌘S sichert zur Sammlung (das erwartet man von ⌘S),
⇧⌘S wendet auf den Ordner an. Beide zusätzlich im Menü „Ablage", damit sie
auffindbar sind.

### Nebenläufigkeit

`IconStudio.recipe` ist `Hashable`. Bei jeder Änderung:

```swift
renderTask?.cancel()
renderTask = Task {
    try? await Task.sleep(for: .milliseconds(40))   // Debounce beim Sliderziehen
    let image = try await IconRenderer.makeIcon(recipe)   // checkCancellation zwischen den Stufen
    guard !Task.isCancelled else { return }
    self.preview = image
}
```

Das ersetzt `QThreadPool` + `uuid_to_wait_for` + `keep_going` komplett — der
zuletzt gestartete Task gewinnt, weil der vorige abgebrochen wurde. `save_when_ready`
wird zu `await renderTask?.value` vor dem Schreiben.

### Drag & Drop

SwiftUI `.onDrop` reicht **nicht**, weil `public.svg-image` eines gezogenen
SF Symbols nur auf der Drag-Pasteboard liegt. In AppKit ist das aber viel
einfacher als der Cocoa-Umweg in der Python-Version: `draggingPasteboard` ist im
`NSDraggingInfo` direkt vorhanden. `PasteboardDropView` (NSView in
`NSViewRepresentable`) prüft in dieser Reihenfolge:

1. `public.svg-image` → `VectorRenderer` → grau? dann Silhouette + Gravur, sonst Originalfarben
2. `public.file-url` → Ordner? Zielordner setzen. Datei? als Bild öffnen
3. Bilddaten (`NSImage.imageTypes`) → Bildpfad
4. `public.utf8-plain-text` → ins Textfeld

`NSImage(data:)` rastert SVG seit macOS 11 selbst — kein SVG-Parser nötig. Als
Rückfallebene liegt auf der Pasteboard zusätzlich
`com.apple.SFSymbols.symbol-identifier` für `NSImage(systemSymbolName:)`.

---

## 3. Datenmodell (SwiftData + CloudKit)

```swift
@Model final class SavedIcon {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var styleRaw: Int = FolderStyle.tahoe.rawValue
    var text: String = ""
    var scale: Double = 1.0
    var offsetX: Double = 0
    var offsetY: Double = 0
    var fontWeightRaw: Int = SFFont.bold.rawValue
    var tintRGB: Int?                                  // nil = keine Tönung
    var preserveColours: Bool = false
    @Attribute(.externalStorage) var sourceImage: Data?   // Original des Drops
    @Attribute(.externalStorage) var thumbnail: Data?     // 256 px PNG für die Sidebar
}
```

CloudKit-Zwänge, die die Feldliste erklären: jede Property braucht einen
Defaultwert oder muss optional sein, `@Attribute(.unique)` ist verboten,
Beziehungen müssen optional sein. Darum kein `enum` als gespeicherter Typ,
sondern `…Raw: Int` mit `computed property` davor.

Gespeichert wird das **Rezept**, nicht das fertige 1024er-Icon — das kostet in
iCloud fast nichts und lässt ein Icon nach einem Stil-Update neu rendern. Nur die
Bildquelle und ein 256-px-Thumbnail liegen als Blob dabei.

Container: `ModelConfiguration(cloudKitDatabase: .automatic)`, Entitlements
`com.apple.developer.icloud-services = CloudKit` +
`iCloud.de.feltedred.foldercrest`. **Das braucht ein Apple-Developer-Konto** —
laut Projektnotiz gibt es aktuell keins. Ohne Konto baut die App weiter, nur
ohne Sync; ich lege das hinter ein Feature-Flag, damit lokal jederzeit gebaut
werden kann.

---

## 4. Reihenfolge der Schritte

Jeder Schritt ist für sich lauffähig und testbar.

| # | Schritt | Fertig, wenn |
| :-- | :--- | :--- |
| 0 | ✅ erledigt: Template wiederhergestellt, `Item`/`ContentView` raus, Assets + Fonts im Bundle, Build Settings korrigiert | App startet leer, Build grün |
| 1 | ✅ erledigt: `Constants.swift`, `FolderStyle.swift`, `ColourMath.swift` | `ColourMathTests` grün, Erwartungswerte aus der Referenz gezogen |
| 2 | ✅ erledigt: `PixelBuffer`, `BoxBlur` | Sprungantwort **identisch** zu Pillow (Abweichung 0), Dekodierung byte-gleich |
| 3 | ✅ erledigt: `IconRenderer` (Text-Gravur), `GlyphRenderer`, `Resample`, Fixture-Vergleich | 66 Testfälle grün, leerer Ordner bit-identisch |
| 4 | ✅ Bild-Maske, Originalfarben, Emoji, Tönung | 27 Fixtures, Tönung max 1, Bildpfade max 2 |
| 5 | ✅ SwiftUI-Grundgerüst: `MainView`, `IconStage`, `InspectorPanel`, `LibrarySidebar` | `NavigationSplitView` + `.inspector`, nur semantische Farben |
| 5b | ✅ `Appearance` + Toolbar-Umschalter über `NSApp.appearance` | in `@AppStorage`, wirkt auf die ganze App |
| 6 | ✅ Task-Abbruch + 40 ms Debounce + `ProgressView` | letzter Task gewinnt, kein Queue-System |
| 7 | ✅ `PasteboardDropView` (SVG-Symbol, Datei, Ordner, Bild, Text) | AppKit-Drop, `NSImage` rastert das SVG selbst |
| 8 | ✅ `FolderIconWriter` + Zielzeile + Zurücksetzen | Icon-Familie 16…1024, Sandbox auf `readwrite` gestellt |
| 9 | ✅ SwiftData lokal: Sidebar, +/− in der Fußzeile, Laden | Rezept wird gesichert, nicht das fertige Bild |
| 10 | ⛔ CloudKit | **blockiert**: braucht ein bezahltes Developer-Konto. Modell und Container sind vorbereitet, es fehlt `cloudKitDatabase: .automatic` plus Entitlement |
| 11 | ✅ App-Icon aus `app_icon.icon` | Xcode erzeugt `Assets.car` + `CFBundleIconName` von selbst, kein `actool` nötig |
| 12 | ✅ String Catalog, 68 Schlüssel, Deutsch vollständig | `de.lproj` im Bundle, Start mit `-AppleLanguages (de)` läuft |

Schritte 3–4 sind die eigentliche Arbeit; 5–9 sind geradlinig.

---

### Build Settings, am 2026-09-10 korrigiert

Das Xcode-Template kam mit drei ungünstigen Vorgaben:

| Einstellung | War | Ist | Warum |
| :--- | :--- | :--- | :--- |
| `SWIFT_VERSION` | 5.0 | 6.0 | Strict Concurrency jetzt, nicht in Schritt 6 nachrüsten |
| `MACOSX_DEPLOYMENT_TARGET` | 26.5 | 26.0 | 26.5 schließt ohne Not das halbe Feld aus |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | MainActor | nonisolated | s. u. |

Die dritte ist die wichtige. Xcode 26 stellt „Approachable Concurrency" so ein,
dass **jeder Typ implizit `@MainActor`** ist. Für eine App, deren Kern eine reine
Rechenpipeline ist, ist das genau verkehrt herum: `ColourMathTests` ließ sich
nicht übersetzen, weil schon `RGB.red` main-actor-isoliert war. Mit
`nonisolated` als Default sind Model und Render frei, und die SwiftUI-Views
bekommen ihre Main-Actor-Isolation weiterhin über das `View`-Protokoll — es
muss also nichts von Hand annotiert werden.

Das UITests-Target bleibt vorerst liegen. Es zu entfernen hieße, im
`project.pbxproj` zu operieren, und das ist mehr Risiko als der ungenutzte
Ordner kostet.

---

## 5. Testkonzept

**Fixtures aus der Wahrheit erzeugen.** `Scripts/make_fixtures.py` läuft mit dem
venv der Referenz und schreibt eine Parametermatrix als PNG nach
`Folder CrestTests/Fixtures/`:

* 4 Stile × Text „A" (Standard) → Grundfall pro Stil
* Tahoe × `scale ∈ {0.1, 1.0, 2.0}`
* Tahoe × `offset ∈ {(0,0), (0.2, -0.1), (-0.27, 0.15)}`
* Tahoe × Schriftstärke `ultralight`, `black`
* Tahoe × Tönung `red`, `white`
* Tahoe × Bild (rotes Quadrat) graviert und in Originalfarben
* Tahoe × Emoji 🐙
* Big Sur Dark × Text + Tönung (der Stil mit abweichender `icon_colour`)

≈ 18 Dateien à ~600 KB. Der Dateiname kodiert das Rezept, der Swift-Test parst
ihn — kein zweiter Ort, an dem die Matrix gepflegt werden muss.

**Vergleich in Swift.** `ParityTests` rendert dasselbe Rezept und prüft je
Fixture:

* `maxChannelDelta ≤ 1` (Rundung), und
* `meanAbsoluteError ≤ 0.2`

Bei Fehlschlag schreibt der Test ein Differenzbild nach
`$TMPDIR/foldercrest-parity/` und nennt den Pfad in der Fehlermeldung —
sonst debuggt man Pixelabweichungen blind.

**Darüber hinaus**, jeweils ein kleiner Test:

* `BoxBlurTests` — Sprungantwort gegen die gemessenen Pillow-Zahlen
* `ColourMathTests` — `dividedColour`, HSV-Roundtrip
* `WriterTests` — `setIcon` auf einen `FileManager`-Temp-Ordner, danach existiert
  `Icon\r`; auf einen nicht existierenden Pfad wirft es (Portierung der
  entsprechenden Blöcke aus `test_icons.py`)
* `SymbolTests` — SVG → CGImage, Graustufenerkennung, Silhouette

Die Fixture-Generierung läuft **nicht** in CI (kein Python dort) — die PNGs
liegen im Repo, `make_fixtures.py` wird nur bei bewusster Änderung neu
angefasst.

---

### Was Schritt 2 an Messungen ergeben hat

**Der Algorithmus ist exakt reproduziert.** Pillows `GaussianBlur` ist kein
Gauß-Kernel, sondern drei erweiterte Boxfilter nach Gwosdek et al. (SSVM 2011).
Zwei Details entscheiden über Byte-Gleichheit, beide gegen Pillow 12.3.0
verifiziert:

* die zwei Pixel direkt außerhalb der ganzzahligen Box tragen den Bruchteil des
  Radius bei,
* **jeder Durchgang wird auf 8 Bit zurückgerundet**, bevor der nächste läuft.

Mit beidem ist die Sprungantwort identisch (Abweichung 0). Ohne die Rundung
driftet sie um eine Einheit. Boxradius: 2.4166666667 für σ=3, 5.4583333333
für σ=6.

**Der Flaschenhals war das Striding, nicht die Rechnung.** Drei Durchgänge über
1024²: horizontal 4,7 ms, vertikal 46,3 ms — Faktor 10, reine Cache-Kosten. Die
vertikale Richtung läuft deshalb als horizontale auf der transponierten Ebene
(`vDSP_mtransD`). Beide Blurs eines Icons: **219 ms → 79 ms**.

Ein Zwischenversuch, die Bereichsprüfung aus der inneren Schleife zu ziehen,
machte es *langsamer* (262 ms) — die Aufteilung ist geblieben, weil sie mit der
Transposition zusammen hilft, aber sie war nicht das Problem. Nächster Hebel,
falls je nötig: alle drei Kanäle gleichzeitig als `SIMD3<Double>`.

**Die Dekodierung ist byte-gleich.** vImage liefert nicht-premultipliziertes
sRGB-RGBA; die geprüften Pixel von `tahoe.png` stimmen mit dem überein, was
Pillow aus derselben Datei liest — inklusive der Schattenpixel mit Alpha 18.

---

### Was Schritt 3 ergeben hat

**Der leere Ordner ist bit-identisch** — alle vier Stile, max. Kanalabweichung
0. Damit sind Dekodierung, Schattenverstärkung und Ausgabe bewiesen; jede
spätere Abweichung liegt an der Gravur, nicht am Fundament.

**Die Maskengeometrie ist exakt reproduziert.** Pillow misst die Textbox mit
gemischten Metriken: **horizontal die Vorschubbreite**, **vertikal die
Tintenausdehnung**, letztere ganzzahlig gefloort/geceilt statt gerundet
(Runden ist bei etwa der Hälfte der Glyphen ein Pixel daneben). Mit diesen drei
Regeln stimmen alle zehn geprüften Boxen aufs Pixel, und bei `A`/Bold und
`Ag`/Bold sogar die Tinten-Bbox innerhalb der Maske.

**Die Skalierung musste nachgebaut werden.** `Image.resize` ist bikubisch und
skaliert den Filterträger mit dem Verkleinerungsfaktor — Core-Graphics-
Interpolation macht etwas anderes. `Resample.swift` folgt Pillows `Resample.c`.

**Was bleibt, ist irreduzibel.** Core Text und FreeType rastern Glyphen
verschieden. Das Differenzbild ist ein ein Pixel breiter Umriss entlang der
Glyphenkante, im Inneren nichts. Gemessen über zwölf Text-Fixtures: schlechteste
Kanalabweichung 47…82, mittlerer Absolutfehler 0,006…1,921. Die Testschwelle
liegt bei 120 / 2,2 — mit Luft, aber unterhalb dessen, was ein Versatz
verursacht.

### Zwei Fallen, die Zeit gekostet haben

**`CTLineDraw` ignoriert die Füllfarbe des Kontexts.** Ohne
`kCTForegroundColorAttributeName` am String malt es nichts, ganz ohne Fehler —
die App rendert dann stillschweigend den leeren Ordner. Der Test
`maskHasInk` steht genau deshalb da.

**Debug-Builds sind hier 100× langsamer.** Ein Fixture-Vergleich dauert im
Debug-Build 35 s, im Release-Build 0,35 s. Die Parity-Tests laufen deshalb mit:

```
xcodebuild -scheme "Folder Crest" -configuration Release \
  ENABLE_TESTABILITY=YES -destination 'platform=macOS' test
```

`ENABLE_TESTABILITY=YES` ist nötig, weil `@testable import` sonst im Release
nicht übersetzt. Als Kommandozeilen-Override, damit das Projekt unangetastet
bleibt.

**Testausgaben landen nicht im xcodebuild-Log.** Der Testhost ist die App, sein
stdout wird nicht durchgereicht — und weil die App sandboxed ist, liegt
`NSTemporaryDirectory()` unter
`~/Library/Containers/de.feltedred.Folder-Crest/Data/tmp/foldercrest-parity/`.
Dort schreibt der Test `metrics.txt` (eine Zeile pro Fixture) und bei
Fehlschlag ein verstärktes Differenzbild.

---

## 6. Filterparameter später einstellbar machen

`EngraveParameters` ist von Anfang an ein eigener Wert im `IconRecipe`, mit den
Defaults aus `constants.py`:

```swift
struct EngraveParameters: Hashable {
    var innerShadowBlur: Double = 3
    var innerShadowYOffset: Double = 0.00293
    var innerShadowValueScale: Double = 0.9
    var outerHighlightBlur: Double = 6
    var outerHighlightYOffset: Double = 0.00782
    var outerHighlightLevel: Double = 0x13 / 255
    var iconBoxScale: Double = 0.84
    var folderShadowFactor: Double = 1.7
    static let `default` = EngraveParameters()
}
```

Der Renderer liest ausschließlich aus dieser Struktur, nie aus globalen
Konstanten. Ein späterer „Erweitert"-Tab im Inspector bindet dann nur noch
Slider daran — kein Umbau der Pipeline. Der Parity-Test fixiert `.default`, damit
die Knöpfe die Referenztreue nicht aufweichen können.

---

## 7. Lokalisierung: Englisch (Quelle) + Deutsch

**Quellsprache ist Englisch**, Deutsch die erste Übersetzung. Beide von Anfang
an, nicht nachgereicht — nachträgliches Lokalisieren heißt, jede View noch
einmal anzufassen.

Technisch ein **String Catalog** (`Localizable.xcstrings`), `knownRegions =
[en, de]`, `developmentRegion = en`. Xcode extrahiert die Strings beim Bauen
selbst; es gibt keinen `lupdate`-Schritt wie in der Qt-Welt und keinen
`CFBundleLocalizations`-Eintrag von Hand — das war ein offener Punkt der
Python-Version und erledigt sich hier.

Regeln fürs Schreiben des Codes:

* In Views `LocalizedStringKey` (also schlicht `Text("Reset")`), außerhalb von
  Views `String(localized:)`. Nie String-Interpolation für zusammengesetzte
  Sätze — Platzhalter (`"Could not set the icon of “\(name)”"`), damit die
  Wortstellung übersetzbar bleibt.
* Jeder String bekommt einen **Kommentar** (`comment:`) mit dem Kontext. Ohne
  ihn ist „Scale" beim Übersetzen nicht von „Maßstab" zu unterscheiden.
* Zahlen und Prozente über `.formatted(.percent)` / `Measurement`, nie von Hand
  zusammengesetzt — Deutsch will „100 %" mit geschütztem Leerzeichen.

Was leicht vergessen wird und deshalb hier steht:

| Ort | Anmerkung |
| :--- | :--- |
| `FolderStyle.displayName` | „macOS Big Sur – Light mode" usw. sind UI-Text, gehören in den Katalog. Produktnamen (`macOS`, `Big Sur`, `Tahoe`) bleiben unübersetzt |
| `TintColour`-Namen | Nur als Bedienungshilfen-Label und Tooltip sichtbar, aber vorhanden — „Melon" → „Melone" |
| Fehlermeldungen aus `FolderIconWriter` | Kommen aus dem Model, also `String(localized:)`, nicht `LocalizedStringKey` |
| `"untitled folder"` | Der Name des neu erzeugten Ordners. Finder nennt ihn auf Deutsch „unbenannter Ordner" — mitlokalisieren, sonst fällt es sofort auf |
| Menüs, `.commands`, About-Fenster | Über `InfoPlist.xcstrings`; der App-Name „Folder Crest" bleibt in beiden Sprachen gleich |

Apple Style Guide, konkret angewandt:

* Englisch: **Title-style capitalization** für Schaltflächen und Menütitel
  („Apply to Folder"), sentence style für Hinweistexte
* Deutsch: nur das erste Wort groß („Auf Ordner anwenden"), Sie-frei formuliert
* **„sichern"**, nicht „speichern" — Apple-Terminologie auf dem Mac. Ebenso
  „Bedienungshilfen", „Schreibtisch", „Ordner"
* SF Symbols, macOS, iCloud bleiben als Produktnamen in beiden Sprachen stehen
* Auslassungspunkte (…, ein Zeichen) nur, wenn ein weiterer Dialog folgt

Prüfen lässt sich das ohne Übersetzer: Schema-Option **„Show non-localized
strings"** meldet vergessene Strings zur Laufzeit, und ein zweites Schema mit
`-AppleLanguages (de)` startet die App direkt auf Deutsch.

---

## 8. Erscheinungsbild: Hell / Dunkel / Automatisch

Drei Zustände, gespeichert in `@AppStorage("appearance")`:

```swift
enum Appearance: String, CaseIterable {
    case system, light, dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil                                  // folgt dem System
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }
    var symbol: String {
        switch self {
        case .system: "circle.righthalf.filled"
        case .light:  "sun.max"
        case .dark:   "moon"
        }
    }
}
```

Angewandt wird es über **`NSApp.appearance`**, nicht über
`.preferredColorScheme`. Der SwiftUI-Modifier färbt nur den View-Baum ein;
Menüleiste, Öffnen-Dialog und das About-Fenster blieben sonst im Systemmodus —
ein sofort sichtbarer Bruch. `nil` gibt die Kontrolle ans System zurück, damit
ist „Automatisch" gratis und folgt auch dem Tag/Nacht-Wechsel zur Laufzeit.

**Bedienelement**: ein `Menu` in der Toolbar, dessen Label das Symbol des
aktuellen Zustands zeigt (Sonne / Mond / halbgefüllter Kreis), mit den drei
Einträgen „Automatisch", „Hell", „Dunkel". Ein reiner Zwei-Wege-Umschalter
Sonne↔Mond hätte keinen Platz für „Automatisch", und genau das ist der
Standardzustand.

Konsequenzen fürs Übrige, damit nichts verwechselt wird:

* **Der Renderer ist davon nicht betroffen.** `FolderStyle.big_sur_light` und
  `…_dark` sind *Ordnerstile* (zwei verschiedene macOS-Grafiken), **nicht** das
  Erscheinungsbild der App. Sie bleiben absichtlich entkoppelt: man will unter
  Umständen im dunklen Fenster ein helles Ordner-Icon bauen.
* **Die Tint-Palette darf nicht mitschalten.** Die zehn `TintColour`-Werte sind
  feste RGB-Werte, die im erzeugten Icon landen. Sie kommen als
  `Color(.sRGB, red:…)` in den Code, nicht als Asset-Catalog-Farbe mit
  Dark-Variante.
* **Die restliche Oberfläche** benutzt ausschließlich semantische Farben und
  Materialien (`.background`, `Color.primary`, `.regularMaterial`), dann stimmen
  beide Modi ohne zweite Palette.
* **Die Vorschaufläche** hinter dem großen Icon braucht einen expliziten,
  neutralen Hintergrund (`.background.secondary`): der Ordner bringt seinen
  eigenen weichen Schatten mit, der auf reinem Schwarz verschwindet und auf
  reinem Weiß zu hart wirkt.

Test: eine SwiftUI-Preview je Modus plus ein Startversuch mit erzwungenem
`.darkAqua` — mehr ist hier nicht sinnvoll automatisierbar.

---

### Was die Schritte 4 bis 12 ergeben haben

**Pillow resampled RGBA alpha-gewichtet.** Das war die letzte grosse Abweichung:
ein Bild in Originalfarben lag um bis zu 64 Einheiten daneben, weil ich die
Farbkanäle gerade skalierte und dabei Schwarz aus den transparenten Pixeln
einblutete. Nachgewiesen mit einem Streifen aus halb deckendem Rot und halb
*transparentem Blau* — Pillow lässt kein Blau durch und liefert vollständig
transparente Ausgabepixel als Null. Mit Premultiplizieren vor und Zurückrechnen
nach dem Resampling: max 64 → **max 2**. Die Textmaske ist davon ausgenommen,
sie ist auf der Python-Seite ein einkanaliges Bild.

**Der 4³-LUT trifft exakt.** Tönung auf dem leeren Ordner: max 1. Die grobe
Kantenlänge 4 ist Teil des Aussehens, nicht ein Implementierungsdetail.

**Drei Toleranzstufen**, jede aus Messwerten statt aus Gefühl:

| Stufe | Grenze | Wofür | Gemessen |
| :--- | :--- | :--- | :--- |
| exakt | max 1, Ø 0,2 | ohne Resampling: leerer Ordner, Tönung | max 0…1 |
| resampled | max 3, Ø 0,05 | Bildpfade | max 2 |
| Glyphen | max 120, Ø 2,2 | Text und Emoji | max 36…82 |

Die mittlere Stufe existiert, weil Pillow im 8.22-Festkommaformat resampled und
diese Portierung in `Double` — pro Durchgang eine Einheit.

**Das App-Icon war einfacher als in der Python-Version.** `app_icon.icon` ins
Zielverzeichnis, `ASSETCATALOG_COMPILER_APPICON_NAME = app_icon`, fertig: Xcode
erzeugt `Assets.car` und setzt `CFBundleIconName` selbst. Der `actool`-Aufruf
aus der Icon-Composer-Notiz wird nicht gebraucht.

**Sandbox.** `ENABLE_USER_SELECTED_FILES` stand auf `readonly`; ein Ordner-Icon
zu schreiben braucht `readwrite`. Gezogene Ordner und über den Öffnen-Dialog
gewählte Orte sind damit abgedeckt.

**Nicht visuell geprüft.** Die App startet, läuft, protokolliert keine Fehler
und beendet sauber — auf Englisch wie auf Deutsch. Wie sie *aussieht*, konnte
ich nicht kontrollieren: dem Terminal fehlt die Berechtigung zur
Bildschirmaufnahme, jeder Screenshot kommt schwarz zurück.

---

## 9. Offene Punkte / Risiken

1. ~~Core Image vs. CPU-Pipeline~~ — entschieden, siehe Abschnitt 1.
2. **CloudKit ohne Developer-Konto.** (weiterhin offen) Sync ist ohne bezahlte Mitgliedschaft
   nicht baubar. Vorschlag: Schritte 0–9 durchziehen, 10 als eigener Branch,
   sobald das Konto steht.
3. **Textmetriken PIL vs. Core Text.** PILs `anchor="mm"` misst über
   Ascender/Descender, `CTLineGetImageBounds` liefert den Tintenrahmen. Da die
   Maske anschließend seitenverhältnistreu in die Box skaliert wird, wirkt sich
   der Unterschied nur als leichte Skalenabweichung aus. Erst messen (Schritt 3),
   dann ggf. mit `CTFontGetAscent/Descent` nachziehen — nicht vorab
   verkomplizieren.
4. **Mehrzeiliger Text / `spacing = size/8`** ist in der Referenz vorhanden, aber
   über die UI (einzeiliges Feld, 25 Zeichen) nicht erreichbar. Ich bilde es
   nicht nach; das TODO der Referenz nennt Mehrzeiligkeit ohnehin als offen.
5. **Mitgelieferte Fonts, 37 MB.** Bleiben laut Prompt beim Stand 2023, damit die
   Metriken stimmen. Der Umstieg auf `/System/Library/Fonts/SFNSRounded.ttf`
   steht im TODO der Referenz und würde die Parity-Tests brechen — separates
   Thema, nicht Teil der Portierung.
6. **`is_greyscale` über alle Pixel** ist in Python O(n) mit Python-Schleife;
   in Swift trivial, aber bei 1024² lieber über vImage-Histogramm. Kleinigkeit.

---

### Zurückgestellte Fragen

Gesammelt statt unterwegs gestellt, keine blockiert etwas ausser der ersten:

1. **CloudKit** — braucht das bezahlte Developer-Konto. Willst du es anschaffen,
   oder bleibt die Sammlung vorerst lokal? Der Code ist vorbereitet.
2. **App-Icon** — laut Claude-Memory war das Design am 2026-09-05 „noch nicht
   final" und wurde deshalb damals zurückgebaut. Ich habe `app_icon.icon` jetzt
   eingehängt, weil PROMPT.md es nennt. Ist es inzwischen final?
3. **Bundle-Identifier** — Xcode hat `de.feltedred.Folder-Crest` vergeben, die
   Python-App hat `de.feltedred.foldercrest`. Als eigenständige native App ist
   eine eigene ID plausibel; wenn sie die alte ersetzen soll, müsste sie
   dieselbe tragen.
4. **Schriftschnitte auf Deutsch** — ich habe die typografischen Fachbegriffe
   genommen (Fett, Halbfett, Kräftig, Schwarz). Manche bevorzugen die
   englischen Namen, weil SF Pro sie so führt.
5. **„Engraved" → „Relief"** — dein Wort aus PROMPT.md, nicht „Graviert".
6. **Mitgelieferte Schriften, 37 MB** — bleiben laut Prompt beim Stand 2023.
   Das TODO der Referenz will stattdessen `/System/Library/Fonts/SFNSRounded.ttf`.
   Das würde die Parity-Tests brechen und ist ein eigenes Thema.
7. **UITests-Target** — steht leer im Projekt. Entfernen hiesse, im
   `project.pbxproj` zu operieren; bisher nicht angefasst.

---

## 10. Was ausdrücklich nicht mitkommt

* Die nummerierten Instruktions-Panels und `PANEL*_COLOUR`
* `waitingspinnerwidget.py` (ersetzt durch `ProgressView`)
* Der Cocoa-Umweg über `NSPasteboard.pasteboardWithName_` — in AppKit
  überflüssig, die Drag-Pasteboard kommt direkt mit dem Drop
* PyInstaller/`main.spec`, DMG-Bau, Gatekeeper-Anleitung — mit Xcode-Signierung
  hinfällig
* Der `actool`/`Assets.car`/`CFBundleIconName`-Umweg fürs App-Icon; Xcode
  verarbeitet `.icon` direkt

---

Mockup der Oberfläche: `mockup.svg`.
