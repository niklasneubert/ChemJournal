"""
ner_annotator.py – Validierung der Smart-Extract-Beispiele (6 Create-ML-Klassen)

Prüft pro Beispiel:
  1. tokens und labels vorhanden und gleich lang
  2. nur die Klassen CHEMICAL, MASS, AMOUNT, VOLUME, EQ, NONE
  3. keine leeren Tokens und keine Tokens mit Leerraum am Rand
  4. Mengen-Labels nur auf Zahlen, Einheiten oder Satzzeichen innerhalb der Angabe
     (fängt verschobene Labels ab, z. B. "MASS" auf "Diisopropylamin")
  5. CHEMICAL nie auf reinen Füllwörtern ("in", "und", "the", …)
"""

from __future__ import annotations

import re
from typing import Any, Dict, Tuple

ALLOWED_LABELS = {"CHEMICAL", "MASS", "AMOUNT", "VOLUME", "EQ", "NONE"}

_UNIT_WORDS = {
    "mg", "g", "kg", "µg", "ug", "mmol", "µmol", "umol", "mol", "ml", "µl", "ul", "l",
    "eq", "equiv", "equivalent", "equivalents", "äq", "äquiv", "%", "-", ".", "mol%", "mol-%",
}
_FILLER = {"in", "und", "and", "the", "a", "of", "mit", "with", "von", "zu", "to", "wurde", "wurden", "was", "were"}
_NUMBER = re.compile(r"\d")


def _is_quantity_token(token: str) -> bool:
    t = token.lower().rstrip(".")
    if _NUMBER.search(t):
        return True
    return t in _UNIT_WORDS or token in {".", "%", "-"}


def validate_example(example: Dict[str, Any]) -> Tuple[bool, str]:
    tokens = example.get("tokens", [])
    labels = example.get("labels", [])

    if not tokens or not labels:
        return False, "Leere tokens oder labels"
    if len(tokens) != len(labels):
        return False, f"Längen verschieden: {len(tokens)} tokens vs {len(labels)} labels"

    for i, (tok, lab) in enumerate(zip(tokens, labels)):
        if lab not in ALLOWED_LABELS:
            return False, f"Unbekanntes Label '{lab}' an Position {i}"
        if not tok or tok != tok.strip():
            return False, f"Leeres Token oder Leerraum am Rand an Position {i}: {tok!r}"
        if lab in ("MASS", "AMOUNT", "VOLUME", "EQ"):
            # Benchmark-Stil darf Zahl und Einheit zusammenfassen ("3.50 g", "298.0mg")
            if not all(_is_quantity_token(part) for part in tok.split()):
                return False, f"{lab} auf Nicht-Mengen-Token {tok!r} an Position {i}"
        if lab == "CHEMICAL" and tok.lower() in _FILLER:
            return False, f"CHEMICAL auf Füllwort {tok!r} an Position {i}"
    return True, "OK"
