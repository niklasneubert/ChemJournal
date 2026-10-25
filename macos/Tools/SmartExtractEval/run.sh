#!/bin/bash
# Prüft Smart Extract gegen die annotierten echten Vorschriften in Korpus/.
#
#   Tools/SmartExtractEval/run.sh                    # mit dem neuesten Modell im App-Ordner
#   Tools/SmartExtractEval/run.sh --no-model         # nur Regeln
#   Tools/SmartExtractEval/run.sh --model 14         # mit "Smart Extract for ChemJournal 14"
#   Tools/SmartExtractEval/run.sh --case beng_2      # ein Fall, mit Ist-Tabelle
#   Tools/SmartExtractEval/run.sh -v                 # alle Fälle mit Details
#   Tools/SmartExtractEval/run.sh --min 98           # Exit-Code 1, wenn weniger als 98 % der Zeilen stimmen
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../../ChemJournal"
BUILD="${TMPDIR:-/tmp}/chemjournal_smartextract_eval"
mkdir -p "$BUILD"

# Modellwahl: Standard ist die höchste Nummer im App-Ordner
MODEL_NR=""
USE_MODEL=1
PASS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-model) USE_MODEL=0; shift ;;
        --model) MODEL_NR="$2"; shift 2 ;;
        *) PASS+=("$1"); shift ;;
    esac
done

# Tool mit den Smart-Extract-Quellen der App bauen (nur wenn sich etwas geändert hat)
SOURCES=("$APP"/Services/SmartExtract/*.swift "$APP/Models/JournalModels.swift" "$APP/Utilities/NumberFormatting.swift" "$HERE/Evaluate.swift")
BIN="$BUILD/evaluate"
if [[ ! -x "$BIN" ]] || [[ -n "$(find "${SOURCES[@]}" -newer "$BIN" 2>/dev/null)" ]]; then
    echo "Baue Bewertungswerkzeug …"
    swiftc -O "${SOURCES[@]}" -o "$BIN"
fi

ARGS=()
if [[ $USE_MODEL -eq 1 ]]; then
    if [[ -z "$MODEL_NR" ]]; then
        MODEL_NR="$(ls "$APP" | sed -n 's/^Smart Extract for ChemJournal \([0-9]*\)\.mlmodel$/\1/p' | sort -n | tail -1)"
    fi
    # Erst im App-Ordner suchen, dann bei den älteren Modellen im Training-Ordner
    MLMODEL="$APP/Smart Extract for ChemJournal $MODEL_NR.mlmodel"
    [[ -f "$MLMODEL" ]] || MLMODEL="$HERE/../../Training model for image classification /Smart Extract for ChemJournal $MODEL_NR.mlmodel"
    COMPILED="$BUILD/Smart Extract for ChemJournal $MODEL_NR.mlmodelc"
    [[ -f "$MLMODEL" ]] || { echo "Modell $MODEL_NR weder im App- noch im Training-Ordner gefunden" >&2; exit 1; }
    if [[ ! -d "$COMPILED" ]] || [[ "$MLMODEL" -nt "$COMPILED" ]]; then
        echo "Kompiliere Modell $MODEL_NR …"
        rm -rf "$COMPILED"
        xcrun coremlcompiler compile "$MLMODEL" "$BUILD" >/dev/null
    fi
    ARGS+=(--model "$COMPILED")
fi

"$BIN" ${ARGS[@]+"${ARGS[@]}"} ${PASS[@]+"${PASS[@]}"} "$HERE/Korpus/korpus.json" "$HERE/Korpus/kontrollset.json"
