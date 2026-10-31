# ChemJournal für Linux

Linux-Version des elektronischen Laborjournals **ChemJournal**. Sie sieht aus und funktioniert wie die Mac-App
(`../macos`) und benutzt dasselbe Dateiformat: Journal, `.chemjournal`-Dateien, Versionen und CAS-Datenbank
lassen sich zwischen Mac und Linux austauschen.

## Installieren (für Nutzer)

Fertige Dateien gibt es auf GitHub unter **Releases**:

| Datei | Für |
|---|---|
| `ChemJournal-1.1-x86_64.AppImage` | die meisten Linux-Rechner (Intel/AMD, 64 Bit) |
| `ChemJournal-1.1-arm64.AppImage` | ARM-Rechner (z. B. Raspberry Pi 5, ARM-Laptops) |
| `ChemJournal-1.1-x64.tar.gz`, `…-arm64.tar.gz` | Archiv zum Entpacken, falls AppImages nicht erlaubt sind |
| `SHA256SUMS.txt` | Prüfsummen |

**AppImage:** herunterladen, ausführbar machen und starten – keine Installation nötig:

```bash
chmod +x ChemJournal-1.1-x86_64.AppImage
./ChemJournal-1.1-x86_64.AppImage
```

(Alternativ im Dateimanager: Rechtsklick › Eigenschaften › „Als Programm ausführen“ erlauben, dann doppelklicken.)

**tar.gz:** entpacken und im Ordner `./chemjournal` starten.

Version 1.0 wurde unter Ubuntu 26.04 LTS getestet (ARM64-AppImage direkt, x86_64-Programm über Rosetta in einer VM).
Version 1.1 wurde mit denselben Programmteilen auf macOS geprüft (Tests und Oberflächentest), noch nicht auf einem Linux-Rechner.

## Wo die Daten liegen

| Was | Ort |
|---|---|
| Journal | `~/Dokumente/ChemJournalData.json` (bzw. `~/Documents/…`) + `ChemJournalData.bak.json` |
| Versionen je Ansatz, tägliche Backups, CAS-Datenbank | `~/.local/share/ChemJournal/` |
| Einstellungen | `~/.config/ChemJournal/einstellungen.json` |

In den Einstellungen (Strg+,) lässt sich statt „Nur auf diesem Rechner“ ein **Sync-Ordner** wählen (Nextcloud,
Dropbox, Netzlaufwerk …). Dann liegt alles in `<Ordner>/ChemJournal/`, und Änderungen anderer Rechner werden
automatisch übernommen. Das ist das Gegenstück zu iCloud Drive auf dem Mac.

## Unterschiede zur Mac-Version

- **iCloud Drive** gibt es unter Linux nicht → frei wählbarer Sync-Ordner (siehe oben).
- **ChemDraw** gibt es nicht für Linux → Zeichenprogramm ist [ReShiki](https://reshiki.com) (kostenlos, quelloffen):
  „In ReShiki zeichnen“, in ReShiki Strg+S – das Bild wird übernommen; gespeicherte Zeichnungen lassen sich 7 Tage
  lang wieder öffnen. ChemJournal findet ReShiki im `PATH`, in `~/.local/bin`, `/opt` oder als AppImage in
  `~/Applications` bzw. `~/Downloads`; sonst in den Einstellungen wählen. Daneben wie bisher Drag & Drop, Strg+V und
  „Datei wählen …“ (Bilder und PDFs, z. B. aus ChemSketch, MarvinSketch oder Ketcher).
- **Smart Extract** nutzt statt Core ML einen Namensklassifikator, der auf denselben Trainingsdaten trainiert ist
  (siehe unten). Ergebnis auf dem annotierten Korpus: 100 % (33/33 öffentliche Fälle), wie das Modell auf dem Mac; auf den
  95 Absätzen aus Open-Access-Artikeln (Europe PMC, CC BY 4.0) 99.6 % im Entwicklungsteil und 87.5 % im ungesehenen
  Kontrollset (Mac: 85.7 %).
- Tastenkürzel mit **Strg** statt ⌘.

## Entwickeln und bauen

Voraussetzung: [Node.js](https://nodejs.org) 24 (LTS). Gebaut werden kann auf Linux oder macOS.

```bash
npm install                            # Electron, electron-builder, Preact, htm, pdf.js
node node_modules/electron/install.js  # falls npm das Electron-Installationsskript blockiert hat
npm run vendor                         # Bibliotheken nach src/renderer/vendor kopieren (MathJax aus ../macos)
npm start                              # App starten
npm test                               # Tests
npm run eval                           # Smart Extract gegen das annotierte Korpus prüfen
npm run dist                           # AppImage + tar.gz für x64 und arm64 nach dist/
```

**Ausprobieren ohne das echte Journal:** `CHEMJOURNAL_HOME=/tmp/cj-test npm start` legt alle Daten in diesem Ordner
ab. Wichtig auf einem Mac, auf dem auch die Mac-App läuft – beide würden sonst dieselbe `ChemJournalData.json` nutzen.

### Aufbau

```
src/main/        Hintergrundprozess: Fenster, Menüs, Speichern, Versionen, Backups, CAS-Datenbank, PubChem, PDF
src/renderer/    Oberfläche (Preact + htm, ohne Build-Schritt), Gestaltung nach der SwiftUI-App
src/shared/      Gemeinsame Logik (auch in den Tests): Zahlenformat, Einheiten, Tags, Analytik, CAS, Suche,
                 PDF-Vorlage, Smart Extract
tools/           Smart-Extract-Bewertung, Training des Namensklassifikators, Vendor-Kopie
test/            Tests und das annotierte Korpus (gleich wie macos/Tools/SmartExtractEval)
```

Die Swift-Dateien der Mac-App und ihre Gegenstücke hier tragen gleiche Namen bzw. sind im Dateikopf genannt.
Änderungen an Regeln (Smart Extract, Berechnungen, PDF) bitte in beiden Versionen nachziehen.

### Smart Extract neu trainieren

Normalisierung und Parser sind 1:1 aus Swift übertragen (geprüft an 2.561 Texten). Den Namensklassifikator nach
neuen Trainingsdaten neu erzeugen:

```bash
node tools/train-chemclassifier.js ../training/train.jsonl ../training/val.jsonl
npm run eval
```

Die Schwelle wird nur auf den Validierungsdaten gewählt – das Kontrollset (`test/korpus/kontrollset.json`) dient
ausschließlich der Messung und wird nie zum Nachbessern benutzt.

## Lizenzen der mitgelieferten Bibliotheken

MathJax (Apache 2.0), Preact (MIT), htm (Apache 2.0), pdf.js (Apache 2.0), Electron (MIT) – Lizenztexte in
`src/renderer/vendor/`.
