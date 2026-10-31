// Version 1.1: Einheiten, Reinheit, Tags, Aufreinigung & Analytik, Zeichnungen – gleiche Ergebnisse wie die Mac-App.
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const i18n = require('../src/shared/i18n');
const { Analysis } = require('../src/shared/analysis');
const { Tags } = require('../src/shared/tags');
const { Units, purityFraction, massToWeigh, pureAmount } = require('../src/shared/units');
const { normalizeStage, normalizeExperiment, experimentToISO, experimentFromISO } = require('../src/main/model');
const { previewHTML, containsCompoundNumbers, generatePDFHTML } = require('../src/shared/pdfhtml');
const { JournalSearch } = require('../src/shared/search');
const { DrawingStore, ReShikiBridge, containsReShikiDrawing, EMPTY_RSK, LIFETIME_MS } = require('../src/main/drawing');
const { JournalHistory, dayString } = require('../src/main/history');

i18n.setLanguage('de');
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'cj11-'));

test('Einheiten: Anzeige und Rückrechnung (wie UnitConversionTests auf dem Mac)', () => {
  assert.strictEqual(Units.display('0.0015', Units.unit('amount', 'mmol'), 'amount'), '1.5');
  assert.strictEqual(Units.display('0.000115', Units.unit('amount', 'µmol'), 'amount'), '115');
  assert.strictEqual(Units.display('0.0123', Units.unit('mass', 'mg'), 'mass'), '12.3');
  assert.strictEqual(Units.display('0.025', Units.unit('volume', 'µl'), 'volume'), '25');
  assert.strictEqual(Units.toBase('12.34', Units.unit('mass', 'mg')), '0.01234');
  assert.strictEqual(Units.toBase('0.1', Units.unit('amount', 'µmol')), '0.0000001');
  assert.strictEqual(Units.toBase('abc', Units.unit('mass', 'mg')), 'abc');
  assert.strictEqual(Units.unit('mass', 'unbekannt').symbol, 'g');
});

test('Reinheit: Laborblatt (Carbazol 95 %, Nitril 98 %, NaH 60 %)', () => {
  assert.strictEqual(Math.round(massToWeigh({ molarMass: '167.21', purity: '95' }, 0.0065) * 1000), 1144);
  assert.strictEqual(Math.round(massToWeigh({ molarMass: '193.08', purity: '98' }, 0.001) * 1000), 197);
  assert.strictEqual(Math.round(massToWeigh({ molarMass: '24', purity: '60' }, 0.009) * 1000), 360);
  assert.ok(Math.abs(pureAmount({ molarMass: '24', purity: '60' }, 0.36) - 0.009) < 1e-12);
  assert.strictEqual(purityFraction({ purity: '' }), 1);
  assert.strictEqual(purityFraction({ purity: '150' }), 1);
});

test('Tags: bereinigen, Dubletten, umbenennen, löschen, Farben wie auf dem Mac', () => {
  assert.strictEqual(Tags.clean('  #Photo   katalyse '), 'Photo katalyse');
  assert.strictEqual(Tags.clean('#'), null);
  const e = Tags.addTag({ tags: [] }, 'Scale-up');
  assert.strictEqual(Tags.addTag(e, 'scale-UP'), null);
  let projects = [{ experiments: [{ tags: ['Scale-up', 'NMR'] }, { tags: ['scale-up'] }, { tags: ['Grosser Ansatz', 'Scale-up'] }] }];
  assert.deepStrictEqual(Tags.all(projects), ['Grosser Ansatz', 'NMR', 'Scale-up']);
  projects = Tags.rename(projects, 'SCALE-UP', 'Grosser Ansatz');
  assert.deepStrictEqual(projects[0].experiments.map(x => x.tags), [['Grosser Ansatz', 'NMR'], ['Grosser Ansatz'], ['Grosser Ansatz']]);
  projects = Tags.remove(projects, 'grosser ansatz');
  assert.deepStrictEqual(projects[0].experiments.map(x => x.tags), [['NMR'], [], []]);
  assert.deepStrictEqual(['Photokatalyse', 'Kreuzkupplung', 'TADF', 'Scale-up'].map(Tags.color), ['orange', 'red', 'cyan', 'blue']);
});

test('Aufreinigung & Analytik: Zeilen wie im Experimentalteil (identisch zur Mac-App)', () => {
  const nmr = { method: 'nmr', values: { nucleus: '¹H', frequency: '400', solvent: 'CDCl₃', sampleMass: '12', data: '7.26 (d, J = 8.0 Hz, 2H)' } };
  assert.strictEqual(Analysis.summary(nmr), '¹H-NMR (400 MHz, CDCl₃, 12 mg): δ = 7.26 (d, J = 8.0 Hz, 2H)');
  assert.strictEqual(Analysis.heading({ method: 'nmr', values: { nucleus: '¹H, ¹³C{¹H}, HSQC' } }), '¹H/¹³C{¹H}-NMR, HSQC');
  const ms = { method: 'ms', values: { kind: 'HRMS', ionization: 'ESI', ion: '[M+H]⁺', formula: 'C20H13F4N2', mzCalc: '345.1015', mzFound: '345.1012' } };
  assert.strictEqual(Analysis.summary(ms), 'HRMS (ESI): m/z [M+H]⁺ ber. für C20H13F4N2: 345.1015, gef.: 345.1012 (Δ = −0.9 ppm)');
  assert.strictEqual(Analysis.results({ method: 'column', values: { crudeMass: '250', isolatedMass: '180' } })[0].value, '72 %');
  assert.strictEqual(Analysis.results({ method: 'uvVis', values: { concentration: '1e-5', absorbance: '0.45' } })[0].value, 'ε = 45 000 L·mol⁻¹·cm⁻¹');
  const rot = { method: 'opticalRotation', values: { measured: '+0.253', concentration: '1.00', pathLength: '1', wavelength: '589 nm (Na-D)', temperature: '20', solvent: 'CHCl₃', literature: '+26.0' } };
  assert.strictEqual(Analysis.summary(rot), 'Drehwert: [α]D²⁰ = +25.3 (c 1.00, CHCl₃); Literatur: +26.0; optische Reinheit 97 %');
  assert.strictEqual(Analysis.summary({ method: 'opticalRotation', values: { specific: '−12.4', wavelength: '546 nm (Hg)', temperature: '25' } }), 'Drehwert: [α]₅₄₆²⁵ = −12.4');
  const epr = { method: 'epr', values: { technique: 'CW-EPR', band: 'X-Band (~9.5 GHz)', frequency: '9.48', power: '2', modAmp: '0.2', modFreq: '100', temperature: '77',
    sampleState: 'gefrorene Lösung', solvent: 'Toluol', gValues: '2.0034', hyperfine: 'A(¹⁴N) = 42 MHz', simulation: 'EasySpin' } };
  assert.strictEqual(Analysis.summary(epr), 'CW-EPR (X-Band, 9.48 GHz, 2 mW, Mod. 0.2 mT/100 kHz, 77 K, gefrorene Lösung, Toluol): g = 2.0034; A(¹⁴N) = 42 MHz; Simulation: EasySpin');
  assert.strictEqual(Analysis.heading({ method: 'xrd', values: { kind: 'Pulver (PXRD)' } }), 'PXRD');
  assert.ok(!Analysis.fields('tlc').some(f => f.key === 'plate'));
  for (const m of Analysis.METHODS) {
    const keys = Analysis.fields(m).map(f => f.key);
    assert.strictEqual(new Set(keys).size, keys.length, m);
    assert.ok(Analysis.inherited(m).every(k => keys.includes(k)), m);
  }
  assert.strictEqual(Analysis.groupTitle(Analysis.GROUPS[0]), 'Chromatographie & Aufreinigung');
});

test('Ältere Dateien: Dateiliste wird zu Einträgen, Liste wird weiter mitgeschrieben; unbekannte Methode → Sonstiges', () => {
  const s = normalizeStage({ title: 'S', analysisFiles: [
    { filePath: '/x/NK12_1H.fid', description: '1H NMR CDCl3' }, { filePath: '/x/NK12_13C.pdf', description: '' },
    { filePath: '/x/hrms_esi.pdf', description: 'HRMS' }, { filePath: '/x/foto.jpg', description: 'Kristalle' }] });
  assert.deepStrictEqual(s.analyses.map(a => Analysis.heading(a)), ['¹H-NMR', '¹³C{¹H}-NMR', 'HRMS', 'Sonstiges']);
  assert.strictEqual(s.analysisFiles.length, 4);
  assert.strictEqual(normalizeStage({ title: 'S', analyses: [{ method: 'raman', values: { notes: 'x' } }] }).analyses[0].method, 'other');
  const e = normalizeExperiment({ title: 'Alt', stages: [] });
  assert.strictEqual(e.isMarked, false);
  assert.deepStrictEqual(e.tags, []);
  // Versionen speichern alle Datumswerte als ISO-Text (wie Swift .iso8601) – auch die der Einträge
  const withEntry = normalizeExperiment({ title: 'V', stages: [{ title: 'S', analyses: [{ method: 'nmr', createdAt: 782934000 }] }] });
  const iso = experimentToISO(withEntry);
  assert.strictEqual(typeof iso.stages[0].analyses[0].createdAt, 'string');
  assert.strictEqual(experimentFromISO(iso).stages[0].analyses[0].createdAt, 782934000);
});

test('Vorschau und PDF: fette Verbindungsnummern, Reinheit, Aufreinigung & Analytik', () => {
  assert.strictEqual(previewHTML('Carbazol (1) und Nitril (2a) ergaben (12).', true), 'Carbazol <b>1</b> und Nitril <b>2a</b> ergaben <b>12</b>.');
  assert.strictEqual(previewHTML('$f(1)$ und \\ce{A (1)} mit (3)', true), '$f(1)$ und $\\ce{A (1)}$ mit <b>3</b>');
  assert.ok(!containsCompoundNumbers('THF (5 mL), 2 h (95%), (1.5 mmol), (4R), (1234)'));
  assert.strictEqual(previewHTML('Produkt (1)'), 'Produkt (1)');
  const exp = normalizeExperiment({ title: 'A', stages: [{ title: 'S', procedure: 'Carbazol (1)',
    chemicals: [{ name: 'Carbazol', purity: '95' }], analyses: [{ method: 'nmr', sample: 'Produkt 3', values: { nucleus: '¹H', solvent: 'CDCl₃' } }] }] });
  const html = generatePDFHTML([exp], 'P', s => new Date(Date.UTC(2001, 0, 1) + s * 1000));
  assert.ok(html.includes('Carbazol (95 %)'));
  assert.ok(html.includes('Carbazol <b>1</b>'));
  assert.ok(html.includes('<b>¹H-NMR</b> – Produkt 3 (CDCl₃)'));
  assert.ok(html.includes('Aufreinigung &amp; Analytik') || html.includes('Aufreinigung & Analytik'));
});

test('Suche findet Tags (auch mit #) und Inhalte aus Aufreinigung & Analytik', () => {
  const projects = [{ experiments: [
    normalizeExperiment({ title: 'Suzuki', tags: ['Scale-up'], stages: [{ title: 'S', analyses: [{ method: 'column', values: { eluent: 'PE/EtOAc 10:1' } }] }] }),
    normalizeExperiment({ title: 'Heck', stages: [] })] }];
  for (const q of ['scale', '#scale-up', '#Scale', 'etoac', 'säulenchromatographie']) {
    const s = JournalSearch(q, projects);
    assert.notStrictEqual(s.hits(projects[0].experiments[0]), null, q);
    assert.strictEqual(s.hits(projects[0].experiments[1]), null, q);
  }
});

test('Zeichnungen 7 Tage aufheben, nach Bild zuordnen, abgelaufene löschen', () => {
  const store = new DrawingStore(tmp());
  const image = Buffer.from([1, 2, 3, 4]);
  const rsk = Buffer.from('{"version":29,"atoms":[{"id":1}],"bonds":[]}');
  store.save(rsk, image, 'reShiki');
  const found = store.find(image);
  assert.strictEqual(found.app, 'reShiki');
  assert.ok(Math.abs(found.expires - Date.now() - LIFETIME_MS) < 60000);
  assert.strictEqual(store.find(Buffer.from([9])), null);
  assert.strictEqual(store.find(image, Date.now() + LIFETIME_MS + 1000), null);
  store.purgeExpired(Date.now() + LIFETIME_MS + 1000);
  assert.strictEqual(fs.readdirSync(store.directory).length, 0);
  assert.ok(containsReShikiDrawing(rsk));
  assert.ok(!containsReShikiDrawing(Buffer.from(EMPTY_RSK)));
});

test('ReShiki-Ablauf mit einem Ersatzprogramm: öffnen, Sichern bemerken, rendern, beenden', async () => {
  const dir = tmp();
  // Ersatz für "reshiki": öffnet nichts, rendert ein festes PNG (wie --cli render)
  const png = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082', 'hex');
  fs.writeFileSync(path.join(dir, 'bild.png'), png);
  const fake = path.join(dir, 'reshiki');
  fs.writeFileSync(fake, `#!/bin/sh\nif [ "$1" = "--cli" ]; then cp "${path.join(dir, 'bild.png')}" "$5"; exit 0; fi\nsleep 30\n`, { mode: 0o755 });
  const events = [];
  const bridge = new ReShikiBridge(() => fake, ev => events.push(ev));
  assert.deepStrictEqual(bridge.open(null), { ok: true });
  assert.deepStrictEqual(await bridge.render(), { error: 'empty' });   // leere Zeichnung → wie ChemDraw: Meldung
  await new Promise(r => setTimeout(r, 50));
  fs.writeFileSync(bridge.file, '{"version":29,"atoms":[{"id":1}],"bonds":[]}');   // „Strg+S in ReShiki“
  await new Promise(r => setTimeout(r, 1600));
  assert.ok(events.includes('reshiki:changed'));
  const r = await bridge.render();
  assert.ok(r.png.equals(png));
  bridge.stop(true);
  assert.strictEqual(bridge.active, false);
  assert.deepStrictEqual(new ReShikiBridge(() => null, () => {}).open(null), { error: 'notFound' });
});

test('Tägliche Backups bleiben 30 Tage, manuelle bleiben immer', () => {
  const dir = tmp();
  const h = new JournalHistory(path.join(dir, 'Versionen'), path.join(dir, 'Backups'));
  const journal = path.join(dir, 'ChemJournalData.json');
  fs.writeFileSync(journal, '[]');
  const start = new Date(2027, 0, 10, 12);
  h.manualBackup(journal, start);
  for (let day = 0; day < 45; day++) h.dailyBackup(journal, new Date(start.getTime() + day * 86400000));
  const names = h.backups().map(b => path.basename(b.url));
  const daily = names.filter(n => !n.includes('manuell'));
  assert.strictEqual(daily.length, 31);
  assert.ok(names.some(n => n.includes('manuell')));
  assert.ok(daily.includes(`ChemJournal-${dayString(new Date(start.getTime() + 44 * 86400000))}.json`));
  assert.ok(!daily.includes(`ChemJournal-${dayString(new Date(start.getTime() + 13 * 86400000))}.json`));
});
