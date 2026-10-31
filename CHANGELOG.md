# Changelog

🇩🇪 [Deutsche Version](CHANGELOG.de.md)

## 1.1 – 31 October 2026 (macOS and Linux)

The biggest update since 1.0: switch units with one click, purity, marks and tags, a completely new
“Purification & analysis” section with 14 methods, ReShiki as a free drawing program, and much more.

> **Linux:** version 1.1 is now available for Linux too, with the same features and file format
> (see [Linux](#linux) below for the differences). Please update all your computers to 1.1 – older versions
> don't know the new fields (purity, marks, tags, purification & analysis) and would drop them when they save.

### Reagent and yield tables

- **Units with one click:** click the unit in a column header (e.g. “n (mol) ⌄”) to switch between mol/mmol/µmol,
  ml/l/µl and g/kg/mg/µg. The whole column then shows its values in that unit, and you type in it directly. The
  choice is remembered. Values are still stored in mol/ml/g – the file format and all calculations stay the same,
  and “m theor.” follows the chosen unit.
- **Purity:** new column “Purity (%)” (empty = 100 %). n is the amount of the pure substance and drives the
  equivalents; m is the amount to weigh out (m = n · M / purity), V = m / d. Example: NaH 60 % in mineral oil,
  9 mmol → 360 mg. The PDF shows the purity after the name, e.g. “Carbazole (95 %)”.

### Reaction scheme

- **ChemDraw opens in landscape** (A4 landscape, a wide window on the screen ChemJournal is on).
- **Edit drawings again for 7 days:** ChemJournal keeps the drawing behind every imported image. “Edit in ChemDraw”
  or a click on the image reopens it; ⌘S replaces the image.
- **ReShiki as drawing program:** [ReShiki](https://reshiki.com) is free and open source. Choose ChemDraw or ReShiki
  as the default in *Settings › General › Reaction Scheme*; the other one is available from the small + next to
  “Reaction Scheme”. The workflow is the same as with ChemDraw: draw, press ⌘S – the image is imported and the mode
  ends; ⌘D and “Stop” work the same way. A saved drawing always opens in the program it was drawn with.
- **Copy and paste the image:** the “Copy” button on the image puts it on the clipboard; in another experiment,
  “Paste from clipboard” inserts it – and it stays editable in the drawing program. Pasting also works with images
  from other apps and with drawings copied straight from ChemDraw.
- **Fixed:** pressing ⌘S in ChemJournal during a ChemDraw drawing started an import (“Import failed”) instead of
  saving the journal. If you close the drawing in ChemDraw without importing, ChemDraw mode now ends by itself.

### Procedure and observation

- **Bold compound numbers:** “(1)”, “(12)” or “(2a)” appear bold and without parentheses in the preview and the
  PDF, as in publications. Quantities such as “(20 mL)”, “(2 h)” or “(95%)” stay as they are.

### Organising experiments

- **Mark** experiments with a star (in the experiment or by right-clicking it in the sidebar).
- **Your own tags**, each name with a fixed colour: add, remove, rename or delete everywhere.
- **Filter** the sidebar: marked experiments only and/or one tag; a bar shows the active filter.
- The search finds tags, with or without “#”.

### Purification & analysis (replaces “Analysis & data”)

- **Any number of entries per stage**, each with its own form, a “sample” field and linked files (folders for
  NMR raw data too, drag & drop, “Show in Finder”, a warning when a file is missing).
- **14 methods in three groups:**
  - Chromatography & purification: column chromatography (LC), thin-layer chromatography (TLC),
    gas chromatography (GC), recrystallisation, distillation
  - Analysis: NMR, IR, UV/Vis and EPR spectroscopy, mass spectrometry, X-ray diffraction (XRD)
  - Other: melting point, optical rotation, other
- **NMR:** several nuclei/experiments per entry (e.g. one file with ¹H, ¹³C and COSY), frequency, solvent,
  sample mass, temperature, signals, remarks.
- **Calculated values:** mass deviation in ppm (MS), extinction coefficient ε (UV/Vis), recovery in %
  (column, recrystallisation, distillation), specific rotation [α] and optical purity.
- **Suggestions** (⌄) for solvents, ionisation, detection etc.; you can always type your own. A new entry of the
  same method takes over solvent, eluent etc. from the previous one.
- **Collapsed,** every card shows one line as in an experimental section, e.g.
  “¹H-NMR (400 MHz, CDCl₃, 12 mg): δ = 7.95 (d, J = 8.4 Hz, 2H) …” or “[α]D²⁰ = +25.3 (c 1.00, CHCl₃)”; the ⋯ menu
  copies it, duplicates the card or moves it.
- **PDF:** a new “Purification & analysis” section with these lines. The search covers them too (“HRMS”, “CDCl₃” …).
- **Older journals:** previously linked files become entries automatically (the method is guessed from file name
  and description) and are still saved as a plain file list as well.

### Settings and data

- **CAS database:** molar mass and density can be edited right in the table; edited values count as your own and
  take precedence over PubChem.
- **Backups:** daily backups are kept for 30 days (previously also one per month for a year). Manual backups are
  always kept.
- **Drawing program** for reaction schemes (see above).

### Interface and speed

- The toolbar buttons “New” and “Filter” show their names in “Icon and Text” mode (right-click the toolbar).
- The copy button on the reaction image is easy to see in dark mode, too.
- **Faster search:** about 2.5× faster with large journals; the sidebar no longer recomputes the search when
  nothing has changed (e.g. when you select an experiment).

### Linux

Linux 1.1 has all of the above, with these differences:

- **ReShiki is the drawing program** (ChemDraw doesn't exist for Linux): “Draw in ReShiki”, then **Ctrl+S** in
  ReShiki – the image is imported and the mode ends; Ctrl+D and “Stop” work as on macOS, and saved drawings can be
  reopened for 7 days. ChemJournal finds ReShiki on the `PATH`, in `~/.local/bin`, `/opt` or as an AppImage in
  `~/Applications` or `~/Downloads`; otherwise choose it in *Settings › General*.
- Keyboard shortcuts use **Ctrl** instead of ⌘; “Show in Finder” is “Show in file manager”.
- Not on Linux: the ChemDraw-specific items (landscape window, pasting ChemDraw drawings) and the toolbar
  label setting (the Linux toolbar has no “Icon and Text” mode).
- Version 1.1 for Linux was checked on macOS with the same program code (automated tests and an interface test),
  not yet on a Linux computer.

### Compatibility

- macOS 15 (Sequoia) or newer, Apple Silicon and Intel; Linux x86_64 and ARM64 (AppImage or tar.gz).
- Existing journals load unchanged. Older ChemJournal versions (macOS or Linux before 1.1) can open a journal
  edited with 1.1 but drop the new fields when they save.

## 1.0.3 – 26 October 2026

Smart Extract handles real procedures from the literature better (95 new paragraphs from open-access articles,
CC BY 4.0): lists like “1a (0.12 mmol), 2a (0.10 mmol)”, amounts before the name, aliases in brackets, molar mass
and density in the quantity bracket, numbered steps, work-up and products. On 28 paragraphs never looked at during
development, completely correct rows went from 83.0 to 85.7 % (macOS) and from 83.9 to 87.5 % (Linux).

## 1.0.2 – 26 October 2026

Every stage shows its own date. Fixed: the column headers of an empty yield table no longer bunch together.

## 1.0.1 – 26 October 2026

Optional English interface, restore backups with one click, several fixes (ChemDraw import only on ⌘S and from
ChemJournal's own document, wide reaction schemes, search, dark mode, dates).

## 1.0.0 – 25 October 2026

First public release: projects, experiments and stages, reagent tables that calculate themselves, CAS autofill from
PubChem, Smart Extract, formulas, search by chemical, PDF export, version history, daily backups, undo/redo, the same
file format on macOS and Linux.
