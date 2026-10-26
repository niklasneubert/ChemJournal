// Tests der gemeinsamen Bausteine – entsprechen den Swift-Tests der Mac-App.  Aufruf: npm test
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { format3, format4, parseDecimal } = require('../src/shared/numberformat');
const { normalizeCAS, isValidCAS } = require('../src/shared/casnumber');
const { applySmartFormatting } = require('../src/shared/smartformat');
const { JournalSearch, nameMatches, synonymGroups } = require('../src/shared/search');
const { PubChem } = require('../src/shared/pubchem');
const { nameHTML, previewHTML } = require('../src/shared/pdfhtml');
const { SmartExtractor } = require('../src/shared/smartextract/extractor');
const { normalizeSynthesisText } = require('../src/shared/smartextract/normalizer');

test('Zahlenformat wie auf dem Mac', () => {
  assert.strictEqual(format3(6.55), '6.55');
  assert.strictEqual(format3(1234.5678), '1234.568');
  assert.strictEqual(format4(0.0465), '0.0465');
  assert.strictEqual(format4(0.000115), '0.000115');
  assert.strictEqual(format3(0.0298), '0.0298');
  assert.strictEqual(format3(0), '0');
  assert.strictEqual(parseDecimal('6,55'), 6.55);
  assert.strictEqual(parseDecimal('.5'), 0.5);
  assert.strictEqual(parseDecimal('1e5'), null);
  assert.strictEqual(parseDecimal(''), null);
});

test('CAS-Prüfziffer', () => {
  for (const cas of ['109-99-9', '75-09-2', '7681-65-4', '109-72-8']) assert.ok(isValidCAS(cas), cas);
  assert.strictEqual(normalizeCAS('109‑99‑9'), '109-99-9');
  assert.ok(!isValidCAS('109-72-9'));
  for (const g of synonymGroups) assert.ok(isValidCAS(g.cas), g.cas);
});

test('Smarte Formatierung', () => {
  assert.strictEqual(applySmartFormatting('\\ce{H2O}'), 'H₂O');
  assert.strictEqual(applySmartFormatting('Verbindung (12)'), 'Verbindung 𝟏𝟐');
});

test('Suche: n-BuLi findet Synonyme und CAS', () => {
  const exp = (title, chemicals) => ({ title, summary: '', stages: [{ title: 'Stufe 1', summary: '', procedure: '', observation: '', sourceURL: '', chemicals: chemicals.map(([name, cas]) => ({ name, cas })), yieldProducts: [] }] });
  const a = exp('A', [['n-Butyllithium (2.5 M in Hexan)', '']]), b = exp('B', [['BuLi', '']]), c = exp('C', [['', '109-72-8']]), d = exp('D', [['LDA', '4111-54-0']]);
  const s = JournalSearch('n-BuLi', [{ experiments: [a, b, c, d] }]);
  assert.ok(s.hits(a) && s.hits(b) && s.hits(c));
  assert.strictEqual(s.hits(d), null);
  assert.ok(nameMatches('THF (abs.)', new Set(['thf'])));
  assert.ok(!nameMatches('CuBr2', new Set(['br2'])));
});

test('PubChem-Dichte aus Freitext', () => {
  assert.strictEqual(PubChem.parseDensity(['0.8833 g/cu cm at 25 °C', '0.89 at 20 °C']), 0.8833);
  assert.strictEqual(PubChem.parseDensity(['1.3266 at 20 °C/4 °C', '1.3255 g/cu cm at 25 °C']), 1.3255);
  assert.strictEqual(PubChem.parseDensity(['Saturated vapor density: 0.01 lb/cu ft']), null);
});

test('PDF: Namen bleiben Text, Summenformeln tiefgestellt', () => {
  assert.strictEqual(nameHTML('Propionsäure 1'), 'Propionsäure 1');
  assert.strictEqual(nameHTML('CH2Cl2'), 'CH<sub>2</sub>Cl<sub>2</sub>');
  assert.strictEqual(nameHTML('CuSO4·5H2O'), 'CuSO<sub>4</sub>·5H<sub>2</sub>O');
  assert.strictEqual(previewHTML('mit \\ce{H2O}'), 'mit $\\ce{H2O}$');
});

test('Smart Extract: Normalisierung und Fallbeispiel', () => {
  assert.strictEqual(normalizeSynthesisText('abgekühltund18.6 ml'), 'abgekühlt und 18.6 ml');
  const rows = SmartExtractor.extract('In einem 250 mL Rundkolben wurden 6.55 ml (46.5 mmol, 0.95 eq) Diisopropylamin vorgelegt.');
  assert.strictEqual(rows.length, 1);
  assert.deepStrictEqual([rows[0].name, rows[0].volume, rows[0].amount, rows[0].equivalents], ['Diisopropylamin', '6.55', '0.0465', '0.95']);
});

test('Smart Extract: echtes Korpus (Mindestquote 99 %)', () => {
  const { execFileSync } = require('child_process');
  const out = execFileSync(process.execPath, [path.join(__dirname, '../tools/eval-smartextract.js'), '--min', '99'], { encoding: 'utf8' });
  assert.match(out, /Gesamt: .*komplett richtig/);
});

test('Speichern im Mac-Format, Versionen und Backup', () => {
  const { JournalPersistence, pathsFor } = require('../src/main/storage');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cj-'));
  const paths = {
    dataDirectory: dir, supportDirectory: dir, journalFile: path.join(dir, 'ChemJournalData.json'),
    versionsDirectory: path.join(dir, 'Versionen'), backupsDirectory: path.join(dir, 'Backups'), casDatabaseFile: path.join(dir, 'CAS-Datenbank.json'),
  };
  const p = new JournalPersistence(paths);
  // Datei, wie sie die Mac-App schreibt (Datum = Sekunden seit 2001, Bild = Base64, ohne referenceChemicalID)
  const mac = [{ id: 'A1B2C3D4-0000-0000-0000-000000000001', title: 'P', isExpanded: true, experiments: [{ id: 'A1B2C3D4-0000-0000-0000-000000000002', title: 'E', summary: '', createdAt: 782934000.5, updatedAt: 782934000.5,
    stages: [{ id: 'A1B2C3D4-0000-0000-0000-000000000003', title: 'Stufe 1', sourceURL: '', summary: '', procedure: '', observation: '', isExpanded: true, createdAt: 782934000.5, analysisFiles: [],
      chemicals: [{ id: 'A1B2C3D4-0000-0000-0000-000000000004', name: 'THF', equivalents: '', cas: '109-99-9', molarMass: '72.11', density: '0.8833', amount: '', volume: '10', mass: '' }],
      yieldProducts: [{ id: 'A1B2C3D4-0000-0000-0000-000000000005', name: 'X', cas: '', molarMass: '', density: '', amount: '', volume: '', mass: '' }] }] }] }];
  fs.writeFileSync(paths.journalFile, JSON.stringify(mac));
  const loaded = p.load();
  assert.strictEqual(loaded.kind, 'loaded');
  assert.deepStrictEqual(loaded.projects, mac);
  loaded.projects[0].experiments[0].title = 'Geändert';
  assert.ok(p.save(loaded.projects, true));
  assert.strictEqual(JSON.parse(fs.readFileSync(paths.journalFile, 'utf8'))[0].experiments[0].title, 'Geändert');
  assert.ok(fs.existsSync(path.join(dir, 'ChemJournalData.bak.json')));
  assert.strictEqual(p.history.backups().length, 1);
  const versions = p.history.versions('A1B2C3D4-0000-0000-0000-000000000002');
  assert.ok(versions.length >= 1);
  const snap = p.history.loadSnapshot(versions[0]);
  assert.strictEqual(snap.experiment.title, 'Geändert');
  assert.strictEqual(snap.experiment.createdAt, 782934000);   // ISO-Datum ohne Millisekunden wie in der Mac-App
  assert.ok(typeof pathsFor === 'function');
});

test('Beschädigte Datei: Backup wird geladen, Original gesichert', () => {
  const { JournalPersistence } = require('../src/main/storage');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cj-'));
  const paths = { dataDirectory: dir, supportDirectory: dir, journalFile: path.join(dir, 'ChemJournalData.json'), versionsDirectory: path.join(dir, 'V'), backupsDirectory: path.join(dir, 'B'), casDatabaseFile: path.join(dir, 'c.json') };
  fs.writeFileSync(path.join(dir, 'ChemJournalData.bak.json'), JSON.stringify([{ id: 'X', title: 'Backup', isExpanded: true, experiments: [] }]));
  fs.writeFileSync(paths.journalFile, '{kaputt');
  const r = new JournalPersistence(paths).load();
  assert.strictEqual(r.kind, 'recovered');
  assert.strictEqual(r.projects[0].title, 'Backup');
  assert.ok(fs.readdirSync(dir).some(f => f.startsWith('ChemJournalData.defekt-')));
});

test('Sprache: Deutsch als Standard, Englisch umschaltbar, Platzhalter', () => {
  const i18n = require('../src/shared/i18n');
  assert.strictEqual(i18n.getLanguage(), 'de');
  assert.strictEqual(i18n.t('Neuer Ansatz'), 'Neuer Ansatz');
  i18n.setLanguage('en');
  assert.strictEqual(i18n.t('Neuer Ansatz'), 'New Experiment');
  assert.strictEqual(i18n.t('Seite {0} von {1}', 2, 5), 'Page 2 of 5');
  assert.strictEqual(i18n.t('Nicht im Wörterbuch'), 'Nicht im Wörterbuch');
  // Jeder Platzhalter des deutschen Texts kommt auch in der Übersetzung vor
  for (const [de, en] of Object.entries(i18n.EN)) {
    for (const ph of de.match(/\{\d+\}/g) || []) assert.ok(en.includes(ph), `${de} → ${en}`);
  }
  i18n.setLanguage('de');
});

test('Backup zurückspielen: Sicherung des aktuellen Stands vorher', () => {
  const { JournalPersistence } = require('../src/main/storage');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cj-'));
  const paths = {
    dataDirectory: dir, supportDirectory: dir, journalFile: path.join(dir, 'ChemJournalData.json'),
    versionsDirectory: path.join(dir, 'Versionen'), backupsDirectory: path.join(dir, 'Backups'), casDatabaseFile: path.join(dir, 'CAS-Datenbank.json'),
  };
  const p = new JournalPersistence(paths);
  p.load();
  const project = title => [{ id: 'A1B2C3D4-0000-0000-0000-00000000000A', title, isExpanded: true, experiments: [] }];
  p.save(project('Alt'));
  const backup = p.history.manualBackup(paths.journalFile);
  p.save(project('Neu'));
  const safety = p.history.safetyBackup(paths.journalFile);
  assert.ok(path.basename(safety).startsWith('ChemJournal-vor-Wiederherstellen-'));
  assert.strictEqual(JSON.parse(fs.readFileSync(safety, 'utf8'))[0].title, 'Neu');
  assert.strictEqual(JSON.parse(fs.readFileSync(backup, 'utf8'))[0].title, 'Alt');
});
