# Smart Extract – Bewertung mit echten Vorschriften

Prüft die Smart-Extract-Funktion der App gegen Synthesevorschriften aus echten Supporting Informations,
Artikeln und Abschlussarbeiten, deren richtige Ansatzgrößen-Tabelle von Hand eingetragen wurde.
Das Werkzeug kompiliert dafür direkt die Smart-Extract-Quellen aus `ChemJournal/Services/SmartExtract/`,
testet also immer genau den Code, der in der App läuft.

## Aufruf

```bash
Tools/SmartExtractEval/run.sh
```

| Option | Wirkung |
|---|---|
| *(keine)* | mit dem Modell mit der höchsten Nummer im App-Ordner |
| `--model 14` | mit „Smart Extract for ChemJournal 14“ (sucht im App- und im Training-Ordner) |
| `--no-model` | nur die Regeln, ohne Modell |
| `--case beng_2` | nur ein Fall, mit vollständiger Ist-Tabelle |
| `-v` | alle Fälle mit Details |
| `--min 98` | Exit-Code 1, wenn weniger als 98 % der Pflichtzeilen stimmen |

Die erste Ausführung baut das Werkzeug und kompiliert das Modell (einige Sekunden); danach geht es schnell.
Gebaute Dateien liegen im temporären Verzeichnis, nicht im Projekt.

## Ausgabe

```
✘ beng_0  [Molecules 2024, 29, 1715 (CC BY 4.0)]  6/7
   ≠ p-methoxyphenol: soll m=0.182 n=0.0015 V=– eq=– | ist m=0.182 n=0.0015 V=5 eq=–
   ✗ fehlt: CH2Cl2  (soll m=– n=– V=5.0 eq=–)
   + zu viel: "water" m=– n=– V=200 eq=–
```

- **✗ fehlt** – Pflichtzeile wurde nicht gefunden.
- **≠** – Name gefunden, aber mindestens ein Wert falsch oder zusätzlich.
- **+ zu viel** – Zeile mit Mengen, die nicht in die Tabelle gehört (z. B. Aufarbeitung).
- **nur Name** – Zeilen ohne Mengen (z. B. „in THF gelöst“); zählen nicht als Fehler.

„Komplett richtig“ heißt: Name passt und alle vier Werte (m, n, V, eq) stimmen auf 2 % genau,
und es gibt keinen Wert, der nicht im Soll steht.

## Korpus

| Datei | Inhalt |
|---|---|
| `Korpus/korpus.json` | 20 Absätze, 90 Pflichtzeilen. An diesen Fällen wurde Smart Extract verbessert. |
| `Korpus/kontrollset.json` | 13 Absätze, 56 Pflichtzeilen. Nur zum Messen – nie daran nachbessern. |
| `Korpus/korpus_europepmc.json` | 67 Absätze, 280 Pflichtzeilen aus 2024/25 erschienenen Open-Access-Artikeln (CC BY 4.0, über Europe PMC), davon 7 aus SI-PDFs. An diesen Fällen wurde Smart Extract am 26.10.2026 robuster gemacht. |
| `Korpus/kontrollset_europepmc.json` | 28 Absätze, 112 Pflichtzeilen aus *anderen* Artikeln derselben Suche. Während der Arbeit nie im Detail angesehen, nur als Gesamtzahl gemessen. |

Stand 23.10.2026 mit Modell 15: `korpus.json` und `kontrollset.json` 100 % (33/33 Fälle).

Öffentlich enthalten sind nur frei lizenzierte Texte: Molecules-Artikel unter CC BY 4.0 und eigene
Praktikumsprotokolle (Quelle steht je Fall im Feld `quelle`). Das vollständige Korpus (58 Fälle, zusätzlich
Supporting Informations von Verlagen und Abschlussarbeiten) bleibt aus Urheberrechtsgründen privat; auch dort
erreicht Smart Extract 100 %. Die Texte sind so belassen, wie
PDFKit bzw. der Browser sie beim Kopieren liefert – inklusive der Artefakte, um die es geht.

### Europe-PMC-Korpus (26.10.2026)

Ausgewählt per Europe-PMC-Suche nach Open-Access-Artikeln mit Lizenz CC BY und experimentellem Teil
(Molecules, J. Org. Chem., ACS Omega, ChemistryOpen, Chem. Eur. J., RSC Adv., Beilstein J. Org. Chem., Front. Chem.,
Chem. Sci., Org. Lett.); Volltext als JATS-XML, SI-PDFs über die Supplementary-Files-Schnittstelle. Aufgeteilt
**nach Artikel**: Kein Artikel des Kontrollsets kommt im Entwicklungsteil vor. Die Quelle (Zeitschrift, Jahr, PMCID,
DOI) steht je Fall im Feld `quelle`.

| Kontrollset (ungesehen) | vorher (v1.0.2) | nachher |
|---|---|---|
| Mac, Modell 15 | 83.0 % richtige Zeilen, 12/28 Fälle fehlerfrei, 13 falsche Zusatzzeilen | 85.7 %, 19/28, 6 |
| Linux (Klassifikator) | 83.9 %, 12/28, 12 | 87.5 %, 20/28, 4 |

## Neuen Fall hinzufügen

1. Text besorgen. Für PDFs: `swift Tools/SmartExtractEval/pdf_text.swift "Datei.pdf" > text.txt`,
   dann den Absatz herauskopieren (Artefakte nicht korrigieren).
2. Eintrag in `korpus.json` ergänzen:

```json
{
  "id": "mein_fall",
  "quelle": "Org. Lett. SI (lokale Datei)",
  "text": "To a solution of benzaldehyde (1.06 g, 10.0 mmol, 1.0 equiv) in THF (20 mL) was added …",
  "soll": [
    {"namen": ["benzaldehyde"], "m": 1.06, "n": 0.01, "eq": 1},
    {"namen": ["THF"], "V": 20},
    {"namen": ["HCl", "1M HCl"], "V": 3, "optional": true}
  ]
}
```

Einheiten wie in der App-Tabelle: **m in g, n in mol, V in ml, eq dimensionslos** (mol% als Bruchteil, 5 mol% = 0.05).
Nur Werte angeben, die im Text stehen – nicht ausrechnen. `namen` darf mehrere Schreibweisen enthalten;
ein Teilstring genügt („BINOL 62b“ passt zu „monosubstituiertem BINOL 62b“).

### Annotationsregeln

- In die Tabelle gehören Edukte, Reagenzien, Katalysatoren, Additive und Reaktionslösemittel mit Mengenangabe.
- Nicht in die Tabelle: Aufarbeitung (Quench, Extraktion, Waschen, Trocknen, Säule), Produkte und Ausbeuten,
  Kolbenvolumina, Trägerlösemittel einer Reagenzlösung („2.5 M in hexanes“).
- Bei „a solution of X in S (1.43 M, 9.8 mL)“ gehört das Volumen zu X.
- Grenzfälle (Quench-Reagenz im Reaktionssatz, Molsieb) als `"optional": true` markieren.
- Wenn du einen Fall zur Fehlersuche nutzt, kommt er nach `korpus.json`. `kontrollset.json` nur ergänzen,
  nie daran nachbessern – sonst misst es nicht mehr, wie gut Smart Extract mit *neuen* Texten zurechtkommt.
