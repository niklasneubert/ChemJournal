// Prüft Smart Extract gegen die von Hand annotierten echten Vorschriften (gleiches Korpus und gleiche
// Bewertung wie macos/Tools/SmartExtractEval).
//
//   node tools/eval-smartextract.js                  # mit Namensklassifikator (wie die App)
//   node tools/eval-smartextract.js --lexicon        # mit Namenslexikon statt Klassifikator
//   node tools/eval-smartextract.js --no-model       # nur Regeln
//   node tools/eval-smartextract.js --case beng_2    # ein Fall mit Ist-Tabelle
//   node tools/eval-smartextract.js -v               # alle Fälle mit Details
//   node tools/eval-smartextract.js --min 98         # Exit-Code 1 unter 98 % richtigen Zeilen
const fs = require('fs');
const path = require('path');
const { SmartExtractor } = require('../src/shared/smartextract/extractor.js');
const { parseDecimal } = require('../src/shared/numberformat.js');

const args = process.argv.slice(2);
const opt = name => { const i = args.indexOf(name); if (i < 0) return null; const v = args[i + 1]; args.splice(i, 2); return v; };
const flag = name => { const i = args.indexOf(name); if (i < 0) return false; args.splice(i, 1); return true; };
const nameModel = flag('--no-model') ? 'none' : flag('--lexicon') ? 'lexicon' : 'classifier';
const verbose = flag('-v');
const only = opt('--case');
const minQuote = opt('--min');
const files = args.length ? args : ['korpus.json', 'kontrollset.json', 'korpus_europepmc.json', 'kontrollset_europepmc.json'].map(f => path.join(__dirname, '../test/korpus', f));

const key = s => s.toLowerCase().replace(/[\s-]/g, '');
function namePasst(soll, ist) {
  const i = key(ist);
  if (!i) return false;
  return soll.namen.some(n => { const s = key(n); return s === i || (s.length >= 3 && i.includes(s)) || (i.length >= 3 && s.includes(i)); });
}
function wertPasst(soll, ist) {
  const v = parseDecimal(ist);
  if (soll == null && v === null) return true;
  if (soll != null && v !== null) return Math.abs(soll - v) <= Math.max(1e-9, 0.02 * Math.abs(soll));
  return false;
}
const zeilePasst = (s, r) => wertPasst(s.m, r.mass) && wertPasst(s.n, r.amount) && wertPasst(s.V, r.volume) && wertPasst(s.eq, r.equivalents);
const f = v => (v == null ? '–' : String(v));
const bSoll = s => `m=${f(s.m)} n=${f(s.n)} V=${f(s.V)} eq=${f(s.eq)}`;
const fi = v => (v ? v : '–');
const bIst = r => `m=${fi(r.mass)} n=${fi(r.amount)} V=${fi(r.volume)} eq=${fi(r.equivalents)}`;
const hasAny = r => !!(r.equivalents || r.amount || r.volume || r.mass);

const neu = () => ({ pflicht: 0, nameGefunden: 0, richtig: 0, zuViel: 0, nurName: 0, faelleOK: 0, faelle: 0 });
const add = (a, b) => { for (const k of Object.keys(a)) a[k] += b[k]; };
const quote = b => (b.pflicht === 0 ? 100 : (100 * b.richtig) / b.pflicht);
const zus = b => `${b.faelleOK}/${b.faelle} Fälle fehlerfrei | ${b.pflicht} Pflichtzeilen | Name gefunden ${(b.pflicht ? (100 * b.nameGefunden) / b.pflicht : 100).toFixed(1)} % | komplett richtig ${quote(b).toFixed(1)} % | falsche Zusatzzeilen ${b.zuViel} | Zeilen nur mit Name ${b.nurName}`;

function bewerte(fall, ausfuehrlich) {
  const zeilen = SmartExtractor.extract(fall.text, { nameModel });
  const belegt = new Set();
  const meldungen = [];
  const b = neu(); b.faelle = 1;
  const sollListe = fall.soll.filter(s => !s.optional).concat(fall.soll.filter(s => s.optional));
  for (const s of sollListe) {
    const kandidaten = zeilen.map((_, i) => i).filter(i => !belegt.has(i) && namePasst(s, zeilen[i].name));
    const wahl = kandidaten.find(i => zeilePasst(s, zeilen[i])) ?? kandidaten[0];
    if (!s.optional) b.pflicht++;
    if (wahl === undefined) { if (!s.optional) meldungen.push(`   ✗ fehlt: ${s.namen[0]}  (soll ${bSoll(s)})`); continue; }
    belegt.add(wahl);
    const ok = zeilePasst(s, zeilen[wahl]);
    if (!s.optional) { b.nameGefunden++; if (ok) b.richtig++; }
    if (!ok && !s.optional) meldungen.push(`   ≠ ${s.namen[0]}: soll ${bSoll(s)} | ist ${bIst(zeilen[wahl])}`);
  }
  zeilen.forEach((r, i) => {
    if (belegt.has(i)) return;
    if (hasAny(r)) { b.zuViel++; meldungen.push(`   + zu viel: "${r.name}" ${bIst(r)}`); }
    else { b.nurName++; if (ausfuehrlich) meldungen.push(`   · nur Name: "${r.name}"`); }
  });
  const fehlerfrei = b.richtig === b.pflicht && b.zuViel === 0;
  if (fehlerfrei) b.faelleOK = 1;
  if (!fehlerfrei || ausfuehrlich) {
    console.log(`${fehlerfrei ? '✔' : '✘'} ${fall.id}  [${fall.quelle}]  ${b.richtig}/${b.pflicht}`);
    meldungen.forEach(m => console.log(m));
    if (ausfuehrlich) { console.log('   Ist-Tabelle:'); zeilen.forEach(r => console.log(`     ${r.name || '(ohne Name)'}  ${bIst(r)}`)); }
  }
  return b;
}

console.log({ none: 'Modus: nur Regeln', lexicon: 'Modus: Regeln + Namenslexikon', classifier: 'Modus: Regeln + Namensklassifikator (wie Modell auf dem Mac)' }[nameModel]);
const gesamt = neu();
for (const datei of files) {
  const faelle = JSON.parse(fs.readFileSync(datei, 'utf8')).filter(c => !only || c.id === only);
  if (!faelle.length) continue;
  const b = neu();
  console.log(`\n== ${path.basename(datei)}`);
  for (const fall of faelle) add(b, bewerte(fall, verbose || !!only));
  console.log(zus(b));
  add(gesamt, b);
}
if (gesamt.faelle === 0) { console.log('Kein passender Fall gefunden.'); process.exit(1); }
if (files.length > 1 && !only) console.log('\nGesamt: ' + zus(gesamt));
if (minQuote && quote(gesamt) < Number(minQuote)) { console.log(`\nUNTER DER MINDESTQUOTE: ${quote(gesamt).toFixed(1)} % < ${minQuote} %`); process.exit(1); }
