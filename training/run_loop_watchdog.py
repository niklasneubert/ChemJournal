#!/usr/bin/env python3
"""
run_loop_watchdog.py – Erzeugt, prüft und speichert den Smart-Extract-Datensatz.

Aufruf (im Projektordner):
    python3 run_loop_watchdog.py                 # 8000 Training / 1000 Validierung / 1000 Test
    python3 run_loop_watchdog.py --dry-run       # nur erzeugen und prüfen, nichts schreiben
    python3 run_loop_watchdog.py --seed 42 --legacy-share 0.25

Schritte
  1. Hashes der goldenen Benchmarks merken (testdaten_1.json, testdaten_NEU.json – werden nie geschrieben).
  2. Splits erzeugen (dataset_builder.SmartExtractDatasetBuilder); Test nutzt eigene, ungesehene Namen.
  3. Jedes Beispiel validieren (ner_annotator.validate_example); fehlerhafte Beispiele brechen den Lauf ab.
  4. Leakage prüfen: kein Beispiel darf einem Benchmark-Satz entsprechen; Splits teilen keine Texte.
  5. Schreiben: Create-ML-Dateien (nur tokens/labels) und Root-Dateien mit Metadaten, Bericht, Status.
  6. Benchmark-Hashes erneut prüfen.

Unterschiede zur alten Version: Die alte Version hat nur einmal generiert und gespeichert (kein Loop,
kein Watchdog), den Status nie geladen, keine Leakage-Prüfung gemacht und doppelte Spalten
(`labels` und `ner_tags`) geschrieben.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
from collections import Counter
from pathlib import Path

from dataset_builder import LABELS, SmartExtractDatasetBuilder
from ner_annotator import validate_example

ROOT = Path(__file__).resolve().parent
CREATE_ML_DIR = ROOT / "createml"
GOLDEN = [CREATE_ML_DIR / "testdaten_1.json", CREATE_ML_DIR / "testdaten_NEU.json"]
TRAIN_CREATEML = CREATE_ML_DIR / "trainingsdaten_NEU.json"
VAL_CREATEML = CREATE_ML_DIR / "validationdata_NEU.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_key(tokens: list[str]) -> str:
    """Vergleichsschlüssel unabhängig vom Token-Stil."""
    return re.sub(r"\s+", "", "".join(tokens)).lower()


def write_json(path: Path, data) -> None:
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)


def write_jsonl(path: Path, data) -> None:
    with path.open("w", encoding="utf-8") as f:
        for item in data:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--train", type=int, default=8000)
    ap.add_argument("--val", type=int, default=1000)
    ap.add_argument("--test", type=int, default=1000)
    ap.add_argument("--seed", type=int, default=1337)
    ap.add_argument("--legacy-share", type=float, default=0.2, help="Anteil im Token-Stil der Benchmarks")
    ap.add_argument("--de-ratio", type=float, default=0.5)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--out", type=Path, help="Alles in diesen Ordner schreiben statt ins Projekt (zum Ausprobieren)")
    args = ap.parse_args()
    out_root = args.out or ROOT
    out_createml = args.out or CREATE_ML_DIR
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)

    golden_before = {p.name: sha256(p) for p in GOLDEN if p.exists()}
    golden_keys = set()
    for p in GOLDEN:
        if p.exists():
            golden_keys |= {text_key(x["tokens"]) for x in json.loads(p.read_text(encoding="utf-8"))}

    t0 = time.time()
    builder = SmartExtractDatasetBuilder(seed=args.seed, legacy_share=args.legacy_share)
    splits = {}
    removed = Counter()
    taken: set[str] = set(golden_keys)
    for name, count in (("train", args.train), ("val", args.val), ("test", args.test)):
        print(f"Erzeuge {name}: {count} Beispiele …", flush=True)
        reserve = max(50, count // 50)
        items = []
        for x in builder.build_split(name, count + reserve, de_ratio=args.de_ratio):
            key = text_key(x["tokens"])
            if key in taken:
                # Kurze Standardsätze ("Gewaschen wurde mit 5 mL THF.") können zufällig doppelt vorkommen
                removed[name] += 1
                continue
            taken.add(key)
            items.append(x)
        if len(items) < count:
            print(f"FEHLER: zu wenige eindeutige Beispiele für {name}")
            return 1
        splits[name] = items[:count]

    # Validierung
    for name, items in splits.items():
        for item in items:
            ok, msg = validate_example(item)
            if not ok:
                print(f"FEHLER in {name}: {msg}\n  {item['raw_text']}")
                return 1
    # Leakage
    keys = {name: {text_key(x["tokens"]) for x in items} for name, items in splits.items()}
    leaks = {name: len(k & golden_keys) for name, k in keys.items()}
    overlaps = {"train∩val": len(keys["train"] & keys["val"]), "train∩test": len(keys["train"] & keys["test"]),
                "val∩test": len(keys["val"] & keys["test"])}
    if any(leaks.values()) or any(overlaps.values()):
        print(f"FEHLER: Leakage {leaks} / Überschneidung {overlaps}")
        return 1

    all_items = splits["train"] + splits["val"] + splits["test"]
    label_counts = Counter(l for x in all_items for l in x["labels"])
    total_tokens = sum(label_counts.values())
    langs = Counter(x["language"] for x in all_items)
    styles = Counter(x["tokenization"] for x in all_items)
    frames = Counter(f for x in all_items for f in x["frames"])
    print(f"OK: {len(all_items)} Beispiele, {total_tokens} Tokens, {dict(langs)}, {dict(styles)} "
          f"in {time.time() - t0:.0f} s")
    print(f"   Entfernt wegen Überschneidung mit Benchmark/anderem Split: {dict(removed)}")
    print(f"   Statistik: {builder.stats.generated} erzeugt, {builder.stats.duplicates} Duplikate, "
          f"{builder.stats.normalizer_changed} durch Normalisierung verändert, "
          f"{builder.stats.boundary_conflicts} Token-Konflikte (verworfen)")
    if args.dry_run:
        return 0

    # Create ML: nur die beiden Spalten, die das Projekt erwartet
    write_json(out_createml / TRAIN_CREATEML.name, [{"tokens": x["tokens"], "labels": x["labels"]} for x in splits["train"]])
    write_json(out_createml / VAL_CREATEML.name, [{"tokens": x["tokens"], "labels": x["labels"]} for x in splits["val"]])
    # Root-Dateien mit Metadaten (test.json dient in Create ML als zusätzliches Testset)
    for name, items in (("train", splits["train"]), ("val", splits["val"]), ("test", splits["test"]),
                        ("dataset_master", all_items)):
        write_json(out_root / f"{name}.json", items)
        write_jsonl(out_root / f"{name}.jsonl", items)

    state = {
        "collected_count": len(all_items), "train": len(splits["train"]), "val": len(splits["val"]),
        "test": len(splits["test"]), "status": "completed", "seed": args.seed, "legacy_share": args.legacy_share,
        "de_count": langs["de"], "en_count": langs["en"], "classes": list(LABELS), "last_updated": time.time(),
    }
    write_json(out_root / "agent_state.json", state)

    rows = "\n".join(f"| `{l}` | {label_counts[l]:,} | {label_counts[l] / total_tokens * 100:.1f} % |" for l in LABELS)
    frame_rows = "\n".join(f"| `{f}` | {c:,} |" for f, c in frames.most_common())
    report = f"""# Smart Extract – Datensatzbericht

Erzeugt mit `python3 run_loop_watchdog.py --seed {args.seed} --legacy-share {args.legacy_share}`.

## Umfang
| Split | Beispiele | Datei |
|---|---|---|
| Training | {len(splits['train']):,} | `trainingsdaten_NEU.json`, `train.json` |
| Validierung | {len(splits['val']):,} | `validationdata_NEU.json`, `val.json` |
| Test (eigene, ungesehene Chemikaliennamen) | {len(splits['test']):,} | `test.json` |

- Sprachen: Deutsch {langs['de']:,}, Englisch {langs['en']:,}
- Tokenisierung: wie NLTagger in der App {styles['nl']:,}, Benchmark-Stil {styles['legacy']:,}
- Tokens gesamt: {total_tokens:,} (Ø {total_tokens / len(all_items):.1f} pro Beispiel)

## Prüfungen
- Validierung (`ner_annotator.py`): alle Beispiele bestanden
- Text unverändert durch `normalizeSynthesisText`: ja ({builder.stats.normalizer_changed} Abweichungen verworfen)
- Tokens mit Labelgrenze im Inneren: {builder.stats.boundary_conflicts} (verworfen)
- Überschneidung mit `testdaten_1.json`/`testdaten_NEU.json`: {sum(leaks.values())} (vorab entfernt: {sum(removed.values())} Kollisionen kurzer Standardsätze)
- Überschneidung zwischen den Splits: {sum(overlaps.values())}
- Benchmarks unverändert (SHA-256): {', '.join(f'{k} {v[:12]}…' for k, v in golden_before.items())}

## Klassenverteilung
| Klasse | Tokens | Anteil |
|---|---|---|
{rows}

## Satzbausteine
| Baustein | Vorkommen |
|---|---|
{frame_rows}

## Label-Policy
Siehe Docstring in `dataset_builder.py`. Kurz: Aufarbeitung, Reinigung und Produktangaben sind komplett
`NONE`; Konzentrationen, Trägerlösemittel ("2.5 M in hexanes"), Temperaturen, Zeiten und Kolbenvolumina
sind `NONE`; mol% ist `EQ`. `testdaten_NEU.json` labelt einige Waschsätze ("Die organische Phase wurde mit
X mL Y gewaschen", "washed with") abweichend als VOLUME/CHEMICAL.
"""
    (out_root / "dataset_report.md").write_text(report, encoding="utf-8")

    golden_after = {p.name: sha256(p) for p in GOLDEN if p.exists()}
    if golden_after != golden_before:
        print("FEHLER: Benchmark-Datei wurde verändert!")
        return 1
    print(f"Geschrieben: {TRAIN_CREATEML.name}, {VAL_CREATEML.name}, train/val/test/dataset_master (.json/.jsonl), "
          f"agent_state.json, dataset_report.md. Benchmarks unverändert.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
