# Smart Extract – Datensatzbericht

Erzeugt mit `python3 run_loop_watchdog.py --seed 1337 --legacy-share 0.2`.

## Umfang
| Split | Beispiele | Datei |
|---|---|---|
| Training | 8,000 | `trainingsdaten_NEU.json`, `train.json` |
| Validierung | 1,000 | `validationdata_NEU.json`, `val.json` |
| Test (eigene, ungesehene Chemikaliennamen) | 1,000 | `test.json` |

- Sprachen: Deutsch 5,021, Englisch 4,979
- Tokenisierung: wie NLTagger in der App 7,988, Benchmark-Stil 2,012
- Tokens gesamt: 454,255 (Ø 45.4 pro Beispiel)

## Prüfungen
- Validierung (`ner_annotator.py`): alle Beispiele bestanden
- Text unverändert durch `normalizeSynthesisText`: ja (0 Abweichungen verworfen)
- Tokens mit Labelgrenze im Inneren: 0 (verworfen)
- Überschneidung mit `testdaten_1.json`/`testdaten_NEU.json`: 0 (vorab entfernt: 16 Kollisionen kurzer Standardsätze)
- Überschneidung zwischen den Splits: 0
- Benchmarks unverändert (SHA-256): testdaten_1.json 729d91cbf775…, testdaten_NEU.json 85e3db83d3b5…

## Klassenverteilung
| Klasse | Tokens | Anteil |
|---|---|---|
| `CHEMICAL` | 63,852 | 14.1 % |
| `MASS` | 34,742 | 7.6 % |
| `AMOUNT` | 31,011 | 6.8 % |
| `VOLUME` | 26,301 | 5.8 % |
| `EQ` | 44,247 | 9.7 % |
| `NONE` | 254,102 | 55.9 % |

## Satzbausteine
| Baustein | Vorkommen |
|---|---|
| `en_volume_of` | 788 |
| `en_charged` | 768 |
| `en_bare` | 766 |
| `en_solution_treated` | 754 |
| `en_to_solution` | 751 |
| `en_dissolved_treated` | 749 |
| `en_catalyst` | 748 |
| `en_mixture_solvents` | 740 |
| `en_solution_dropwise` | 715 |
| `en_sequential` | 707 |
| `de_aufarbeitung` | 704 |
| `de_bedingungen` | 692 |
| `en_workup` | 670 |
| `de_nummer_als_loesung` | 640 |
| `de_zwei_komponenten` | 627 |
| `de_iod_zink` | 625 |
| `de_versetzt` | 615 |
| `en_conditions` | 603 |
| `de_nummer_direkt` | 592 |
| `de_geloest` | 591 |
| `de_klammerlos` | 576 |
| `de_gemisch_loesemittel` | 573 |
| `de_vorgelegt` | 564 |
| `de_zu_loesung` | 562 |
| `de_direkt_addiert` | 561 |
| `de_loesung_zugetropft` | 559 |
| `de_katalysator` | 529 |

## Label-Policy
Siehe Docstring in `dataset_builder.py`. Kurz: Aufarbeitung, Reinigung und Produktangaben sind komplett
`NONE`; Konzentrationen, Trägerlösemittel ("2.5 M in hexanes"), Temperaturen, Zeiten und Kolbenvolumina
sind `NONE`; mol% ist `EQ`. `testdaten_NEU.json` labelt einige Waschsätze ("Die organische Phase wurde mit
X mL Y gewaschen", "washed with") abweichend als VOLUME/CHEMICAL.
