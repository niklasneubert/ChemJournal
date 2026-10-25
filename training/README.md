# Smart Extract – training data

The sentences used to train the "is this a chemical name?" model are **synthetic**: `dataset_builder.py` combines
sentence templates (German and English) with chemical names, quantities and units and labels every token as
`CHEMICAL`, `MASS`, `AMOUNT`, `VOLUME`, `EQ` or `NONE`. No text from papers or theses is included.

| File | Content |
|---|---|
| `train.jsonl` / `val.jsonl` / `test.jsonl` | 8,000 / 1,000 / 1,000 labelled examples |
| `createml/testdaten_1.json`, `createml/testdaten_NEU.json` | hand-written benchmark sets (never modified by the scripts) |
| `dataset_report.md` | statistics of the current data set |

Regenerate (macOS, needs `swiftc` because tokens are produced with the same normaliser as the app):

```bash
cd training
python3 run_loop_watchdog.py --seed 1337 --legacy-share 0.2
```

The Create ML model in the macOS app is trained from the generated `createml/trainingsdaten_NEU.json`; the Linux
classifier from `train.jsonl` (`node ../linux/tools/train-chemclassifier.js train.jsonl val.jsonl`).
