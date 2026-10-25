// Trainiert den Namensklassifikator für Smart Extract unter Linux und schreibt
// src/shared/smartextract/chemclassifier.js.
//
// Auf dem Mac entscheidet ein Core-ML-Modell (Create ML), welche Wörter Chemikaliennamen sind. Dieses Skript
// trainiert auf denselben Trainingsdaten eine logistische Regression über Wortbausteine (Buchstaben-n-Gramme
// und Wortform). Sie erkennt dadurch auch Namen, die in den Trainingsdaten nicht vorkommen ("Neocuproin").
// Die Schwelle wird auf den Validierungsdaten gewählt – nie auf dem Kontrollset.
//
//   node tools/train-chemclassifier.js ../training/train.jsonl ../training/val.jsonl
const fs = require('fs');
const path = require('path');
const { SmartExtractor } = require('../src/shared/smartextract/extractor.js');
const { features, DIM } = require('../src/shared/smartextract/chemfeatures.js');

const [trainFile, valFile] = process.argv.slice(2);

function load(file) {
  const samples = [];
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    const { tokens, labels } = JSON.parse(line);
    tokens.forEach((tok, i) => {
      for (const sub of SmartExtractor.tokenize(tok, false)) {
        if (!/\p{L}/u.test(sub.text)) continue;
        samples.push({ x: features(sub.text), y: labels[i] === 'CHEMICAL' ? 1 : 0, w: sub.text });
      }
    });
  }
  return samples;
}

const train = load(trainFile);
const val = load(valFile);
console.log(`Training: ${train.length} Wortteile, Validierung: ${val.length}`);

const W = new Float64Array(DIM);
let bias = 0;
const sigmoid = z => 1 / (1 + Math.exp(-z));
const score = x => { let z = bias; for (const f of x) z += W[f]; return z; };

let seed = 42;
const rand = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const order = train.map((_, i) => i);
const lambda = 1e-6;
for (let epoch = 0; epoch < 6; epoch++) {
  for (let i = order.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [order[i], order[j]] = [order[j], order[i]]; }
  const lr = 0.2 / (1 + epoch);
  let loss = 0;
  for (const idx of order) {
    const s = train[idx];
    const p = sigmoid(score(s.x));
    const grad = p - s.y;
    loss += -(s.y ? Math.log(p + 1e-12) : Math.log(1 - p + 1e-12));
    for (const f of s.x) W[f] -= lr * (grad + lambda * W[f]);
    bias -= lr * grad;
  }
  console.log(`Epoche ${epoch + 1}: Verlust ${(loss / order.length).toFixed(4)}`);
}

// Schwelle mit bester F1 auf den Validierungsdaten, bei hoher Präzision (falsche Namen stören mehr als fehlende)
let best = { t: 0.5, f1: 0, p: 0, r: 0 };
for (let t = 0.5; t <= 0.98; t += 0.02) {
  let tp = 0, fp = 0, fn = 0;
  for (const s of val) {
    const pred = sigmoid(score(s.x)) >= t;
    if (pred && s.y) tp++; else if (pred) fp++; else if (s.y) fn++;
  }
  const p = tp / Math.max(1, tp + fp), r = tp / Math.max(1, tp + fn), f1 = (2 * p * r) / Math.max(1e-9, p + r);
  if (p >= 0.97 && f1 > best.f1) best = { t, f1, p, r };
}
console.log(`Schwelle ${best.t.toFixed(2)}: Präzision ${(best.p * 100).toFixed(1)} %, Trefferquote ${(best.r * 100).toFixed(1)} %, F1 ${(best.f1 * 100).toFixed(1)} %`);

// Nur nennenswerte Gewichte speichern
const entries = [];
for (let i = 0; i < DIM; i++) if (Math.abs(W[i]) >= 0.01) entries.push([i, Math.round(W[i] * 1000) / 1000]);
const out = `// Automatisch erzeugt von tools/train-chemclassifier.js – nicht von Hand bearbeiten.
// Logistische Regression über Wortbausteine; erkennt Chemikaliennamen (Ersatz für das Core-ML-Modell).
(function (g) {
  'use strict';
  const ChemClassifier = { bias: ${bias.toFixed(4)}, threshold: ${best.t.toFixed(2)}, weights: new Map(${JSON.stringify(entries)}) };
  const api = { ChemClassifier };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
`;
fs.writeFileSync(path.join(__dirname, '../src/shared/smartextract/chemclassifier.js'), out);
console.log(`${entries.length} Gewichte geschrieben (${(out.length / 1024).toFixed(0)} KB).`);
