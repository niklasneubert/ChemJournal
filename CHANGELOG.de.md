# Änderungen

🇬🇧 [English version](CHANGELOG.md)

## Noch nicht veröffentlicht (macOS und Linux)

- **Gekoppelte Methoden GC-MS und LC-MS** in „Aufreinigung & Analytik“ (Gruppe Analytik), jeweils mit eigenem Formular:
  GC-MS mit Säule, Temperaturprogramm, Trägergas, Ionisierung (EI/CI/FI), Massenbereich, Retentionszeiten, Reinheit und
  m/z-Signalen; LC-MS mit Säule, Eluent/Gradient, Fluss, Ionisierung (ESI/APCI/APPI), Modus, Retentionszeiten, Ion,
  m/z gefunden und Reinheit. Neue Symbole (Chromatogramm-Peak mit Massenspektrum). Ältere Dateilisten mit „GC-MS“ bzw.
  „LC-MS“ im Dateinamen werden der passenden Methode zugeordnet.
- **Behoben (macOS):** Der abgelöste Taschenrechner war im dunklen Modus von ChemJournal hell – er folgt jetzt der
  Einstellung *Darstellung › Erscheinungsbild*.
- **Behoben (macOS):** Beim leichten Scrollen wurde der Titel eines Ansatzes an der Unterkante der Symbolleiste hart
  abgeschnitten. Der Inhalt gleitet jetzt weich unter die Symbolleiste.

## 1.2.1 – 3. November 2026 (macOS und Linux)

### Taschenrechner

- **Neu in der Symbolleiste:** ein kleiner Taschenrechner für + − × ÷, Klammern, Potenz, Wurzel, Prozent und
  Vorzeichenwechsel – mit Punkt-vor-Strich und Zwischenergebnis schon während der Eingabe.
- **Rechnung bearbeiten:** In die Rechnungszeile klicken, mit ← → den Cursor bewegen, mit der Löschtaste Zeichen
  entfernen; Ziffern und Rechenzeichen landen an der Cursorposition. Nach „=“ bleibt die Aufgabe stehen und lässt sich
  ändern, das Ergebnis rechnet sofort mit. Return rechnet, eingetipptes `*` und `/` werden zu × und ÷.
- **Frei schwebend:** Den Rechner am Rand wegziehen – er löst sich als kleines Fenster mit Schließen-Knopf und bleibt
  offen, bis man ihn schließt. Unter Linux schwebt er innerhalb des ChemJournal-Fensters.
- **Dezimaltrennzeichen** Punkt (Standard) oder Komma: *Einstellungen › Allgemein › Taschenrechner*. Beim Tippen
  gelten Punkt und Komma immer als Dezimalzeichen.

### Tags

- **21 statt 11 Farben:** zehn neue, gut unterscheidbare Farben (Gold, Limette, Fuchsia, Oliv, Koralle, Marine,
  Schiefer, Waldgrün, Weinrot, Lavendel), jeweils mit eigenem Ton für hellen und dunklen Modus. Ein Tag hat auf Mac
  und Linux dieselbe Farbe. Durch die größere Auswahl bekommen bestehende Tags einmalig eine neue Farbe.

### Symbole

- **Neu gezeichnete Symbole** für die Analytik und Aufreinigung, die zeigen, wie die Methode bzw. ihr Spektrum
  aussieht: Säule mit Banden, DC-Platte, Chromatogramm (GC), Kristalle, Destille, NMR-Multipletts, IR-Banden,
  UV/Vis-Absorptionsbanden, MS-Strichspektrum, EPR-Ableitungssignal, Bragg-Reflexion (XRD) und [α] im Drehpfeil
  (Drehwert); dazu neue Symbole für „Skalieren“ und den Taschenrechner.

### Behoben

- **Namensspalte breiter/schmaler ziehen** (Ansatzgrößen und Ausbeute): Auf dem Mac sprang die Trennlinie beim Ziehen
  hin und her, statt dem Mauszeiger zu folgen. Jetzt läuft sie gleichmäßig mit; unter Linux wird beim Ziehen
  höchstens einmal pro Bild neu gezeichnet.

### Kompatibilität

- Gleiches Dateiformat wie 1.2. Die Einstellung für den Taschenrechner gilt je Computer.

## 1.2 – 2. November 2026 (macOS und Linux)

### Aufreinigung & Analytik

- **Reihenfolge per Ziehen:** Den farbigen Streifen links an einer Karte gedrückt halten und die Karte an die
  gewünschte Stelle ziehen.
- **Einträge unterordnen:** Eine Karte nach rechts ziehen – oder ⋯ › „Unterordnen unter“ – ordnet sie unter einen
  anderen Eintrag (z. B. DC und Säule unter das ¹H-NMR des Produkts). Untergeordnete Einträge sind eingerückt,
  werden mit dem übergeordneten Eintrag eingeklappt und wandern beim Verschieben mit. Nach links ziehen oder
  „Herauslösen“ macht das rückgängig. Ältere Versionen zeigen solche Einträge einfach wieder untereinander.
- **Behoben:** „Hinzufügen“ hat Werte und Probe vom letzten Eintrag derselben Methode übernommen. Neue Einträge sind
  jetzt immer leer.

### Smart Extract

- Genauer bei Supporting Informations: Zusammensetzungen in der Mengenklammer („97 % (w/w) A, 3 % B, 157 mg“),
  Ausbeuten in Klammern, „0.20 mmol scale“, Vorschrift-Kürzel (GPA–GPH), Fällen/Anreiben/Ansäuern, NMR-Proben und
  Aliquots, Silbentrennung nach Lokanten. An 334 von Hand geprüften SI-Absätzen: 87.8 % → 93.3 % richtige Zeilen,
  deutlich weniger falsche Zusatzzeilen; die Kontrollsets bleiben unverändert.

### Sonstiges

- Neues App-Symbol.

### Kompatibilität

- Gleiches Dateiformat wie 1.1. Version 1.1 kann mit 1.2 bearbeitete Journale öffnen; untergeordnete Einträge
  stehen dann einfach untereinander, und Speichern mit 1.1 hebt die Unterordnung auf (die Einträge selbst bleiben).

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
