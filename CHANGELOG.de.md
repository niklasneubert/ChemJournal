# Änderungen

🇬🇧 [English version](CHANGELOG.md)

## 1.1 – 31. Oktober 2026 (macOS und Linux)

Die größte Aktualisierung seit 1.0: Einheiten per Klick, Reinheit, Markierungen und Tags, ein komplett neuer
Bereich „Aufreinigung & Analytik“ mit 14 Methoden, ReShiki als freies Zeichenprogramm und vieles mehr.

> **Linux:** Version 1.1 gibt es jetzt auch für Linux, mit denselben Funktionen und demselben Dateiformat
> (Unterschiede siehe [Linux](#linux) unten). Bitte alle Rechner auf 1.1 aktualisieren – ältere Versionen kennen
> die neuen Felder (Reinheit, Markierungen, Tags, Aufreinigung & Analytik) nicht und würden sie beim Speichern verwerfen.

### Ansatzgrößen und Ausbeute

- **Einheiten per Klick:** Ein Klick auf die Einheit im Spaltenkopf (z. B. „n (mol) ⌄“) wechselt zwischen
  mol/mmol/µmol, ml/l/µl und g/kg/mg/µg. Die ganze Spalte zeigt dann die Werte in dieser Einheit, und du tippst
  auch direkt in ihr. Die Wahl bleibt nach einem Neustart erhalten. Gespeichert wird weiter in mol/ml/g – das
  Dateiformat und alle Rechnungen bleiben gleich, „m theor.“ rechnet mit.
- **Reinheit:** neue Spalte „Reinheit (%)“ (leer = 100 %). n ist die Stoffmenge des reinen Stoffes, daraus folgen
  die Äquivalente; m ist die einzuwiegende Menge (m = n · M / Reinheit), V = m / d. Beispiel: NaH 60 % in
  Mineralöl, 9 mmol → 360 mg. Im PDF steht die Reinheit hinter dem Namen, z. B. „Carbazol (95 %)“.

### Reaktionsgleichung

- **ChemDraw öffnet im Querformat** (A4 quer, breites Fenster auf dem Bildschirm von ChemJournal).
- **Zeichnungen 7 Tage lang erneut bearbeiten:** ChemJournal hebt zu jedem importierten Bild die Zeichnung selbst
  auf. Mit „In ChemDraw bearbeiten“ oder einem Klick auf das Bild öffnet sie sich wieder; ⌘S ersetzt das Bild.
- **ReShiki als Zeichenprogramm:** [ReShiki](https://reshiki.com) ist kostenlos und quelloffen. In
  *Einstellungen › Allgemein › Reaktionsgleichung* wählst du ChemDraw oder ReShiki als Standard; das andere Programm
  erreichst du über das kleine + neben „Reaktionsgleichung“. Der Ablauf ist derselbe wie bei ChemDraw: zeichnen,
  ⌘S – das Bild wird übernommen, der Modus endet; ⌘D und „Beenden“ funktionieren ebenso. Eine gespeicherte
  Zeichnung öffnet sich immer in dem Programm, mit dem sie entstanden ist.
- **Bild kopieren und einfügen:** Der Knopf „Kopieren“ am Bild legt es in die Zwischenablage; in einem anderen
  Ansatz setzt „Aus Zwischenablage einfügen“ es ein – und es bleibt dort im Zeichenprogramm bearbeitbar. Einfügen
  geht auch mit Bildern aus anderen Programmen und mit direkt aus ChemDraw kopierten Zeichnungen.
- **Behoben:** ⌘S in ChemJournal löste während einer ChemDraw-Zeichnung einen Import aus („Import fehlgeschlagen“),
  statt das Journal zu speichern. Wird die Zeichnung in ChemDraw ohne Import geschlossen, endet der ChemDraw-Modus
  jetzt von selbst.

### Vorgehen und Beobachtung

- **Verbindungsnummern fett:** „(1)“, „(12)“ oder „(2a)“ erscheinen in der Vorschau und im PDF fett und ohne
  Klammern, wie in Veröffentlichungen. Mengen wie „(20 mL)“, „(2 h)“ oder „(95%)“ bleiben unverändert.

### Ansätze ordnen

- **Markieren:** Stern-Knopf im Ansatz oder per Rechtsklick in der Seitenleiste.
- **Eigene Tags** mit fester Farbe je Name: hinzufügen, entfernen, überall umbenennen oder löschen.
- **Filter** in der Seitenleiste: nur markierte Ansätze und/oder ein Tag; eine Leiste zeigt den aktiven Filter.
- Die Suche findet Tags, auch mit „#“.

### Aufreinigung & Analytik (ersetzt „Analyse & Daten“)

- **Beliebig viele Einträge pro Stufe**, jeder mit eigenem Formular, Feld „Probe“ und verknüpften Dateien
  (auch Ordner für NMR-Rohdaten, per Drag & Drop, „Im Finder zeigen“, Hinweis bei fehlender Datei).
- **14 Methoden in drei Gruppen:**
  - Chromatographie & Aufreinigung: Säulenchromatographie (LC), Dünnschichtchromatographie (DC),
    Gaschromatographie (GC), Umkristallisation, Destillation
  - Analytik: NMR-, IR-, UV/Vis- und EPR-Spektroskopie, Massenspektrometrie, Röntgenbeugung (XRD)
  - Weitere: Schmelzpunkt, Drehwert, Sonstiges
- **NMR:** mehrere Kerne/Experimente pro Eintrag (z. B. eine Datei mit ¹H, ¹³C und COSY), Frequenz, Lösungsmittel,
  Probenmasse, Temperatur, Signale, Anmerkungen.
- **Berechnete Werte:** Massenabweichung in ppm (MS), Extinktionskoeffizient ε (UV/Vis), Wiederfindung in %
  (Säule, Umkristallisation, Destillation), spezifischer Drehwert [α] und optische Reinheit.
- **Vorschläge** (⌄) für Lösungsmittel, Ionisierung, Detektion usw.; eigene Eingaben sind immer möglich. Ein neuer
  Eintrag derselben Methode übernimmt Lösungsmittel, Eluent usw. vom vorigen.
- **Eingeklappt** zeigt jede Karte eine Zeile wie in einer Experimentalbeschreibung, z. B.
  „¹H-NMR (400 MHz, CDCl₃, 12 mg): δ = 7.95 (d, J = 8.4 Hz, 2H) …“ oder „[α]D²⁰ = +25.3 (c 1.00, CHCl₃)“; über ⋯
  lässt sie sich kopieren, die Karte duplizieren oder verschieben.
- **PDF:** neuer Abschnitt „Aufreinigung & Analytik“ mit diesen Zeilen. Die Suche findet auch hier („Kieselgel“, „HRMS“ …).
- **Ältere Journale:** Bisher verknüpfte Dateien werden automatisch zu Einträgen (die Methode wird aus Dateiname und
  Beschreibung erraten) und zusätzlich weiter als einfache Dateiliste gespeichert.

### Einstellungen und Daten

- **CAS-Datenbank:** Molmasse und Dichte lassen sich direkt in der Tabelle ändern; geänderte Werte gelten als eigene
  Eingabe und haben Vorrang vor PubChem.
- **Backups:** tägliche Backups bleiben 30 Tage (bisher zusätzlich eines pro Monat für ein Jahr). Manuelle Backups
  bleiben immer.
- **Zeichenprogramm** für Reaktionsgleichungen wählbar (siehe oben).

### Oberfläche und Geschwindigkeit

- Die Knöpfe „Neu“ und „Filter“ in der Symbolleiste zeigen bei „Symbol und Text“ (Rechtsklick auf die Symbolleiste)
  ihren Namen.
- Der Kopieren-Knopf am Reaktionsbild ist auch im Dunkelmodus gut sichtbar.
- **Suche schneller:** bei großen Journalen etwa 2,5-mal schneller; die Seitenleiste rechnet die Suche nicht mehr neu,
  wenn sich nichts geändert hat (z. B. beim Auswählen eines Ansatzes).

### Linux

Linux 1.1 hat alles oben Genannte, mit diesen Unterschieden:

- **Zeichenprogramm ist ReShiki** (ChemDraw gibt es nicht für Linux): „In ReShiki zeichnen“, dann in ReShiki
  **Strg+S** – das Bild wird übernommen und der Modus endet; Strg+D und „Beenden“ funktionieren wie auf dem Mac,
  gespeicherte Zeichnungen lassen sich 7 Tage lang wieder öffnen. ChemJournal findet ReShiki im `PATH`, in
  `~/.local/bin`, `/opt` oder als AppImage in `~/Applications` bzw. `~/Downloads`; sonst unter
  *Einstellungen › Allgemein* wählen.
- Tastenkürzel mit **Strg** statt ⌘; „Im Finder zeigen“ heißt „Im Dateimanager zeigen“.
- Nicht unter Linux: die ChemDraw-eigenen Punkte (Querformat-Fenster, Einfügen von ChemDraw-Zeichnungen) und die
  Beschriftung der Symbolleiste (die Linux-Symbolleiste hat keinen Modus „Symbol und Text“).
- Die Linux-Version 1.1 wurde mit demselben Programmcode auf macOS geprüft (automatische Tests und Oberflächentest),
  noch nicht auf einem Linux-Rechner.

### Kompatibilität

- macOS 15 (Sequoia) oder neuer, Apple-Chip und Intel; Linux x86_64 und ARM64 (AppImage oder tar.gz).
- Bestehende Journale laden unverändert. Ältere ChemJournal-Versionen (macOS oder Linux vor 1.1) können ein mit 1.1
  bearbeitetes Journal öffnen, verwerfen beim Speichern aber die neuen Felder.

## 1.0.3 – 26. Oktober 2026

Smart Extract kommt mit echten Vorschriften aus der Literatur besser zurecht (95 neue Absätze aus
Open-Access-Artikeln, CC BY 4.0): Listen wie „1a (0.12 mmol), 2a (0.10 mmol)“, Mengen vor dem Namen, Aliase in
Klammern, Molmasse und Dichte in der Mengenklammer, nummerierte Schritte, Aufarbeitung und Produkte. Auf 28 nie
angesehenen Absätzen stieg der Anteil komplett richtiger Zeilen von 83,0 auf 85,7 % (macOS) bzw. 83,9 auf 87,5 % (Linux).

## 1.0.2 – 26. Oktober 2026

Jede Stufe zeigt ihr eigenes Datum. Behoben: Spaltenköpfe einer leeren Ausbeute-Tabelle rücken nicht mehr zusammen.

## 1.0.1 – 26. Oktober 2026

Oberfläche optional auf Englisch, Backups per Klick zurückspielen, mehrere Korrekturen (ChemDraw-Import nur bei ⌘S
und aus dem eigenen Dokument, breite Reaktionsgleichungen, Suche, Dunkelmodus, Datumsangaben).

## 1.0.0 – 25. Oktober 2026

Erste öffentliche Version: Projekte, Ansätze und Stufen, rechnende Ansatzgrößen, CAS-Autofill aus PubChem,
Smart Extract, Formeln, Suche nach Chemikalien, PDF-Export, Versionsverlauf, tägliche Backups, Rückgängig/Wiederholen,
gleiches Dateiformat auf macOS und Linux.
