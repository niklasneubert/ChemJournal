// Erzeugt src/shared/smartextract/chemlexicon.js aus den Smart-Extract-Trainingsdaten des Mac-Projekts.
//
// Auf dem Mac entscheidet ein Core-ML-Modell, welche Wörter Chemikaliennamen sind. Unter Linux gibt es kein
// Core ML; stattdessen sammelt dieses Skript alle Wortteile, die in den Trainingsdaten (fast) immer als
// CHEMICAL markiert sind. Aufruf:
//   node tools/build-chemlexicon.js ../training/train.jsonl ../training/val.jsonl
const fs = require('fs');
const path = require('path');
const { SmartExtractor } = require('../src/shared/smartextract/extractor.js');

const counts = new Map();   // Wortteil → { chem, other }
for (const file of process.argv.slice(2)) {
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    const { tokens, labels } = JSON.parse(line);
    tokens.forEach((tok, i) => {
      for (const sub of SmartExtractor.tokenize(tok, false)) {
        const key = sub.text.toLowerCase();
        const c = counts.get(key) || { chem: 0, other: 0 };
        if (labels[i] === 'CHEMICAL') c.chem++; else c.other++;
        counts.set(key, c);
      }
    });
  }
}

const { Vocabulary, Units, isCompoundLabel } = SmartExtractor;
const words = [...counts.entries()]
  .filter(([w, c]) => c.chem >= 2 && c.chem / (c.chem + c.other) >= 0.9)
  .map(([w]) => w)
  .filter(w => Array.from(w).length >= 3 && /\p{L}/u.test(w))
  .filter(w => !Vocabulary.stopwords.has(w) && !Units.quantity(w, '') && !Units.isIgnoredUnit(w) && !isCompoundLabel(w))
  .sort();

const out = `// Automatisch erzeugt von tools/build-chemlexicon.js – nicht von Hand bearbeiten.
// ${words.length} Wortteile, die in den Smart-Extract-Trainingsdaten (fast) immer Chemikaliennamen sind.
(function (g) {
  'use strict';
  const ChemLexicon = new Set(${JSON.stringify(words)});
  const api = { ChemLexicon };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
`;
fs.writeFileSync(path.join(__dirname, '../src/shared/smartextract/chemlexicon.js'), out);
console.log(`${words.length} Wortteile geschrieben.`);
