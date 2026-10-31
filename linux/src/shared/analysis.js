// Aufreinigung & Analytik einer Stufe – entspricht Models/AnalysisModels.swift.
// Beliebig viele Einträge pro Stufe, jeder mit einer Methode (NMR, IR, Säule, …), eigenen Feldern (als Text in
// `values`) und verknüpften Dateien. Gleiches Dateiformat wie auf dem Mac.
(function (g) {
  'use strict';
  const node = typeof module === 'object' && module.exports;
  const { parseDecimal } = node ? require('./numberformat.js') : g.CJ;
  const { t } = node ? require('./i18n.js') : g.CJ;

  const GROUPS = ['purification', 'spectroscopy', 'other'];
  const GROUP_TITLES = { purification: 'Chromatographie & Aufreinigung', spectroscopy: 'Analytik', other: 'Weitere' };
  // Reihenfolge wie auf dem Mac (bestimmt auch die Reihenfolge im Menü)
  const METHODS = ['nmr', 'ir', 'uvVis', 'ms', 'epr', 'xrd', 'column', 'tlc', 'gc', 'recrystallization', 'distillation', 'meltingPoint', 'opticalRotation', 'other'];
  const GROUP_OF = { nmr: 'spectroscopy', ir: 'spectroscopy', uvVis: 'spectroscopy', ms: 'spectroscopy', epr: 'spectroscopy', xrd: 'spectroscopy',
    column: 'purification', tlc: 'purification', gc: 'purification', recrystallization: 'purification', distillation: 'purification',
    meltingPoint: 'other', opticalRotation: 'other', other: 'other' };
  const TITLES = { nmr: 'NMR-Spektroskopie', ir: 'IR-Spektroskopie', uvVis: 'UV/Vis-Spektroskopie', ms: 'Massenspektrometrie', epr: 'EPR-Spektroskopie',
    xrd: 'Röntgenbeugung (XRD)', column: 'Säulenchromatographie (LC)', tlc: 'Dünnschichtchromatographie (DC)', gc: 'Gaschromatographie (GC)',
    recrystallization: 'Umkristallisation', distillation: 'Destillation', meltingPoint: 'Schmelzpunkt', opticalRotation: 'Drehwert', other: 'Sonstiges' };
  const SHORT = { nmr: 'NMR', ir: 'IR', uvVis: 'UV/Vis', ms: 'MS', epr: 'EPR', xrd: 'XRD', tlc: 'DC', gc: 'GC' };
  const SYMBOLS = { nmr: 'waveform.path.ecg', ir: 'waveform', uvVis: 'rainbow', ms: 'chart.bar.xaxis', epr: 'dot.radiowaves', xrd: 'circle.hexagongrid',
    column: 'line.3.horizontal.decrease', tlc: 'rectangle.split.1x2', gc: 'chart.xyaxis.line', recrystallization: 'snowflake', distillation: 'flame',
    meltingPoint: 'thermometer', opticalRotation: 'dial', other: 'doc.text' };

  const title = m => t(TITLES[m] || TITLES.other);
  const shortTitle = m => (m === 'tlc' ? t('DC') : SHORT[m] || title(m));
  const groupTitle = grp => t(GROUP_TITLES[grp]);
  const methodsIn = grp => METHODS.filter(m => GROUP_OF[m] === grp);

  const NMR_SOLVENTS = ['CDCl₃', 'DMSO-d₆', 'CD₃OD', 'C₆D₆', 'CD₂Cl₂', 'Aceton-d₆', 'CD₃CN', 'D₂O', 'THF-d₈', 'Toluol-d₈'];
  const NMR_EXPERIMENTS = ['¹H', '¹³C{¹H}', '¹⁹F', '³¹P{¹H}', '¹¹B', '²⁹Si', 'DEPT-135', 'COSY', 'HSQC', 'HMBC', 'NOESY'];
  const TWO_D = new Set(['DEPT-135', 'COSY', 'HSQC', 'HMBC', 'NOESY']);
  const SOLVENTS = ['MeCN', 'MeOH', 'EtOH', 'CH₂Cl₂', 'CHCl₃', 'THF', 'Toluol', 'DMSO', 'H₂O', 'Cyclohexan', 'n-Hexan'];

  // Feld: { key, label, kind: 'text'|'number'|'choice'|'multiChoice'|'multiline', unit?, options? }
  const text = (key, label) => ({ key, label, kind: 'text' });
  const number = (key, label, unit = '') => ({ key, label, kind: 'number', unit });
  const choice = (key, label, options) => ({ key, label, kind: 'choice', options });
  const multiline = (key, label) => ({ key, label, kind: 'multiline' });

  /** Felder einer Methode (Beschriftungen übersetzt). */
  function fields(m) {
    const notes = multiline('notes', t('Bemerkungen'));
    switch (m) {
      case 'nmr': return [
        { key: 'nucleus', label: t('Kerne / Experimente'), kind: 'multiChoice', options: NMR_EXPERIMENTS },
        number('frequency', t('Frequenz'), 'MHz'), choice('solvent', t('Lösungsmittel'), NMR_SOLVENTS),
        number('sampleMass', t('Probenmasse'), 'mg'), number('temperature', t('Temperatur'), '°C'),
        multiline('data', t('Signale (δ in ppm)')), multiline('notes', t('Anmerkungen'))];
      case 'ir': return [
        choice('technique', t('Messmethode'), ['ATR', t('KBr-Pressling'), 'Film', t('Lösung'), 'Nujol']),
        multiline('data', t('Banden ṽ (cm⁻¹)'))];
      case 'uvVis': return [
        choice('solvent', t('Lösungsmittel'), SOLVENTS), number('concentration', t('Konzentration c'), 'mol/L'),
        number('pathLength', t('Schichtdicke d'), 'cm'), number('lambdaMax', 'λmax', 'nm'), number('absorbance', t('Absorbanz A bei λmax')),
        multiline('data', t('Weitere Banden'))];
      case 'ms': return [
        choice('kind', t('Art'), ['HRMS', 'LRMS']),
        choice('ionization', t('Ionisierung'), ['ESI', 'APCI', 'EI', 'CI', 'MALDI', 'APPI', 'FD', 'GC-MS (EI)', 'LC-MS (ESI)']),
        choice('polarity', t('Modus'), [t('positiv'), t('negativ')]), text('formula', t('Summenformel')),
        choice('ion', 'Ion', ['[M+H]⁺', '[M+Na]⁺', '[M+K]⁺', '[M+NH₄]⁺', '[M]⁺', '[M]⁺•', '[M−H]⁻', '[M+Cl]⁻', '[M+HCOO]⁻']),
        number('mzCalc', t('m/z berechnet')), number('mzFound', t('m/z gefunden')), multiline('data', t('Weitere Signale'))];
      case 'epr': return [
        choice('technique', t('Methode'), ['CW-EPR', t('Puls-EPR (ESE)'), 'ENDOR', 'HYSCORE', 'ESEEM', 'DEER/PELDOR', t('Spin-Trapping')]),
        choice('band', t('Frequenzband'), ['X-Band (~9.5 GHz)', 'Q-Band (~34 GHz)', 'W-Band (~94 GHz)', 'S-Band (~3 GHz)', 'L-Band (~1 GHz)']),
        number('frequency', t('Mikrowellenfrequenz'), 'GHz'), number('power', t('Mikrowellenleistung'), 'mW'),
        number('modAmp', t('Modulationsamplitude'), 'mT'), number('modFreq', t('Modulationsfrequenz'), 'kHz'),
        number('temperature', t('Temperatur'), 'K'),
        choice('sampleState', t('Probenzustand'), [t('Lösung'), t('gefrorene Lösung'), t('Feststoff/Pulver'), t('Einkristall')]),
        choice('solvent', t('Lösungsmittel / Matrix'), SOLVENTS), number('concentration', t('Konzentration'), 'mM'),
        text('field', t('Feldbereich (Mitte / Sweep)')), number('scans', t('Scans')), text('gValues', t('g-Faktoren')),
        text('hyperfine', t('Hyperfeinkopplung A (MHz, mit Kern)')), text('zfs', t('Nullfeldaufspaltung D, E')),
        choice('simulation', t('Simulation'), ['EasySpin', 'SimFonia', 'Bruker Xenon']),
        multiline('data', t('Weitere Ergebnisse')), multiline('notes', t('Anmerkungen'))];
      case 'xrd': return [
        choice('kind', t('Art'), [t('Einkristall (SC-XRD)'), t('Pulver (PXRD)')]),
        choice('radiation', t('Strahlung'), ['Mo Kα (0.71073 Å)', 'Cu Kα (1.54184 Å)', 'Ga Kα (1.34139 Å)', 'Ag Kα (0.56087 Å)', 'Synchrotron']),
        number('temperature', t('Temperatur'), 'K'),
        choice('crystalSystem', t('Kristallsystem'), ['triklin', 'monoklin', 'orthorhombisch', 'tetragonal', 'trigonal', 'hexagonal', 'kubisch'].map(x => t(x))),
        text('spaceGroup', t('Raumgruppe')), text('cell', t('Zellparameter')), text('rFactors', 'R1 / wR2'), text('ccdc', t('CCDC-Nummer')),
        text('twoTheta', t('2θ-Bereich')), text('crystal', t('Kristall')), notes];
      case 'column': return [
        choice('stationaryPhase', t('Stationäre Phase'), [t('Kieselgel 60 (40–63 µm)'), t('Kieselgel 60 (63–200 µm)'), t('Al₂O₃ neutral'),
          t('Al₂O₃ basisch'), t('Al₂O₃ sauer'), 'C18 (Reversed Phase)', 'Florisil']),
        text('eluent', t('Eluent')), number('diameter', t('Säulendurchmesser'), 'cm'), number('height', t('Füllhöhe'), 'cm'),
        number('crudeMass', t('Rohprodukt'), 'mg'), number('isolatedMass', t('Isoliert'), 'mg'), text('rf', t('Rf (Produkt)')),
        text('fractions', t('Produktfraktionen')), notes];
      case 'tlc': return [
        text('eluent', t('Eluent')),
        choice('detection', t('Detektion'), ['UV 254 nm', 'UV 365 nm', 'KMnO₄', 'Vanillin', t('Anisaldehyd'), 'CAM', 'Ninhydrin', t('Iod'), t('Bromkresolgrün')]),
        text('rf', t('Rf-Werte')), notes];
      case 'gc': return [
        text('column', t('Säule')), text('program', t('Temperaturprogramm')), text('carrier', t('Trägergas / Fluss')),
        choice('detector', t('Detektor'), ['FID', 'MS', t('WLD (TCD)'), 'ECD']), text('retention', t('Retentionszeit(en)')),
        number('purity', t('Reinheit / Umsatz'), '%'), notes];
      case 'recrystallization': return [
        choice('solvent', t('Lösungsmittel'), SOLVENTS), number('volume', t('Volumen'), 'mL'), number('crudeMass', t('Rohprodukt'), 'mg'),
        number('crystalMass', t('Kristalle'), 'mg'), text('conditions', t('Bedingungen')), text('appearance', t('Aussehen')),
        number('meltingPoint', t('Smp.'), '°C'), notes];
      case 'distillation': return [
        choice('technique', t('Art'), [t('einfach'), t('fraktioniert'), t('Vakuum'), t('Kugelrohr'), t('Wasserdampf')]),
        number('pressure', t('Druck'), 'mbar'), number('boilingPoint', t('Siedepunkt (Kopf)'), '°C'), number('bathTemp', t('Badtemperatur'), '°C'),
        number('crudeMass', t('Einsatz'), 'mg'), number('distillateMass', t('Destillat'), 'mg'), notes];
      case 'meltingPoint': return [
        number('found', t('Smp. gefunden'), '°C'), number('literature', t('Smp. Literatur'), '°C'),
        choice('method', t('Methode'), [t('Kapillare'), t('Kofler-Heizbank'), 'DSC']), notes];
      case 'opticalRotation': return [
        number('measured', t('Gemessener Drehwinkel α'), '°'), text('specific', t('Spezifischer Drehwert [α] (falls abgelesen)')),
        choice('wavelength', t('Wellenlänge'), ['589 nm (Na-D)', '578 nm (Hg)', '546 nm (Hg)', '436 nm (Hg)', '405 nm (Hg)', '365 nm (Hg)']),
        number('temperature', t('Temperatur'), '°C'), choice('solvent', t('Lösungsmittel'), SOLVENTS),
        number('concentration', t('Konzentration c'), 'g/100 mL'), number('pathLength', t('Küvettenlänge l'), 'dm'),
        text('literature', t('Literaturwert [α]')), notes];
      default: return [text('title', t('Bezeichnung')), multiline('notes', t('Ergebnis / Beschreibung'))];
    }
  }

  /** Felder, die ein neuer Eintrag derselben Methode in der Stufe übernimmt. */
  const INHERITED = { nmr: ['solvent', 'sampleMass', 'temperature'], ir: ['technique'], uvVis: ['solvent', 'concentration', 'pathLength'],
    ms: ['kind', 'ionization', 'polarity', 'formula'], epr: ['technique', 'band', 'frequency', 'power', 'modAmp', 'modFreq', 'temperature', 'sampleState', 'solvent'],
    xrd: ['kind', 'radiation', 'temperature'], column: ['stationaryPhase', 'eluent'], tlc: ['eluent', 'detection'],
    gc: ['column', 'program', 'carrier', 'detector'], recrystallization: ['solvent'], distillation: ['technique'], meltingPoint: ['method'],
    opticalRotation: ['wavelength', 'temperature', 'solvent', 'pathLength'], other: [] };

  // MARK: Eintrag

  const uuid = () => (typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : require('crypto').randomUUID()).toUpperCase();
  const REF = Date.UTC(2001, 0, 1);
  const nowRef = () => (Date.now() - REF) / 1000;
  const str = v => (typeof v === 'string' ? v : v == null ? '' : String(v));

  function newEntry(method, values = {}, sample = '', files = []) {
    return { id: uuid(), method: METHODS.includes(method) ? method : 'other', sample, values: { ...values }, files, isExpanded: true, createdAt: nowRef() };
  }

  /** Liest einen Eintrag (auch aus neueren Versionen: unbekannte Methode → „Sonstiges“). */
  function normalizeEntry(e = {}) {
    const values = {};
    if (e.values && typeof e.values === 'object') for (const [k, v] of Object.entries(e.values)) if (typeof v === 'string') values[k] = v;
    return {
      id: str(e.id) || uuid(), method: METHODS.includes(e.method) ? e.method : 'other', sample: str(e.sample), values,
      files: (e.files || []).map(f => ({ id: str(f.id) || uuid(), filePath: str(f.filePath), description: str(f.description) })),
      isExpanded: e.isExpanded !== false, createdAt: typeof e.createdAt === 'number' && Number.isFinite(e.createdAt) ? e.createdAt : nowRef(),
    };
  }

  const value = (e, key) => str(e.values && e.values[key]).trim();
  /** Mehrfachauswahl: "¹H, ¹³C{¹H}" → ["¹H", "¹³C{¹H}"]. */
  const list = text => String(text).split(/[,;]/).map(s => s.trim()).filter(Boolean);

  function heading(e) {
    switch (e.method) {
      case 'nmr': {
        const nuclei = list(value(e, 'nucleus'));
        if (!nuclei.length) return 'NMR';
        const oneD = nuclei.filter(n => !TWO_D.has(n)), twoD = nuclei.filter(n => TWO_D.has(n));
        return (oneD.length ? [oneD.join('/') + '-NMR'] : []).concat(twoD).join(', ');
      }
      case 'epr': {
        const tech = value(e, 'technique');
        if (!tech) return 'EPR';
        return tech.startsWith(t('Puls-EPR')) ? t('Puls-EPR') : tech;
      }
      case 'xrd': {
        const k = value(e, 'kind').toLowerCase();
        return k.includes('pxrd') || k.includes('pulver') || k.includes('powder') ? 'PXRD'
          : (k.includes('sc-xrd') || k.includes('einkristall') || k.includes('single') ? 'SC-XRD' : 'XRD');
      }
      case 'ms': return value(e, 'kind') || 'MS';
      case 'ir': case 'uvVis': return shortTitle(e.method);
      case 'other': return value(e, 'title') || title('other');
      default: return title(e.method);
    }
  }

  function num(e, key) {
    const v = value(e, key).replace(/,/g, '.');
    if (!v) return null;
    const d = parseDecimal(v);
    if (d !== null) return d;
    const x = Number(v);   // "1e-5"
    return Number.isFinite(x) && /^[-+]?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?$/i.test(v) ? x : null;
  }

  const fixed = (v, digits) => Math.abs(v).toFixed(digits);
  const signed = (v, digits) => { const s = fixed(v, digits); return v < 0 ? '−' + s : v > 0 ? '+' + s : s; };
  const grouped = v => new Intl.NumberFormat('de-DE', { maximumSignificantDigits: 3 }).format(v).replace(/\./g, ' ');
  const percent0 = v => `${Math.round(v)} %`;

  /** Zahl mit Vorzeichen, auch "+25.3", "−12,4°". */
  function signedNumber(text) {
    const s = String(text).replace(/−/g, '-').replace(/\+/g, '').replace(/°/g, '').replace(/,/g, '.').trim();
    if (!s) return null;
    const x = Number(s);
    return Number.isFinite(x) ? x : null;
  }
  const rotation = v => signed(v, Math.abs(v) < 10 ? 2 : 1);

  function computedSpecificRotation(e) {
    const alpha = signedNumber(value(e, 'measured')), c = num(e, 'concentration');
    if (alpha === null || c === null || !(c > 0)) return null;
    const l = num(e, 'pathLength') ?? 1;
    return l > 0 ? (100 * alpha) / (l * c) : null;
  }
  const specificRotation = e => signedNumber(value(e, 'specific')) ?? computedSpecificRotation(e);

  /** "[α]D²⁰" – D für die Natrium-D-Linie, sonst die Wellenlänge tiefgestellt; die Temperatur hochgestellt. */
  function rotationSymbol(e) {
    const sub = { 0: '₀', 1: '₁', 2: '₂', 3: '₃', 4: '₄', 5: '₅', 6: '₆', 7: '₇', 8: '₈', 9: '₉' };
    const sup = { 0: '⁰', 1: '¹', 2: '²', 3: '³', 4: '⁴', 5: '⁵', 6: '⁶', 7: '⁷', 8: '⁸', 9: '⁹', '-': '⁻', '.': '·' };
    const wl = value(e, 'wavelength');
    const nm = (wl.match(/^\d+/) || [''])[0];
    const lambda = !wl || nm === '589' || wl.includes('D') ? 'D' : [...nm].map(c => sub[c] || '').join('');
    const temp = [...value(e, 'temperature')].map(c => sup[c] || '').join('');
    return '[α]' + lambda + temp;
  }

  function recovery(e, crudeKey, productKey) {
    const crude = num(e, crudeKey), product = num(e, productKey);
    return crude !== null && product !== null && crude > 0 ? [{ label: t('Wiederfindung'), value: percent0((product / crude) * 100) }] : [];
  }

  /** Berechnete Werte, sobald die nötigen Felder ausgefüllt sind. */
  function results(e) {
    switch (e.method) {
      case 'ms': {
        const calc = num(e, 'mzCalc'), found = num(e, 'mzFound');
        if (calc === null || found === null || !(calc > 0)) return [];
        return [{ label: t('Massenabweichung'), value: `Δ = ${signed(((found - calc) / calc) * 1e6, 1)} ppm` }];
      }
      case 'uvVis': {
        const a = num(e, 'absorbance'), c = num(e, 'concentration');
        if (a === null || c === null || !(c > 0)) return [];
        const d = num(e, 'pathLength') ?? 1;
        return d > 0 ? [{ label: t('Extinktionskoeffizient'), value: `ε = ${grouped(a / (c * d))} L·mol⁻¹·cm⁻¹` }] : [];
      }
      case 'column': return recovery(e, 'crudeMass', 'isolatedMass');
      case 'recrystallization': return recovery(e, 'crudeMass', 'crystalMass');
      case 'distillation': return recovery(e, 'crudeMass', 'distillateMass');
      case 'opticalRotation': {
        const r = [];
        const computed = computedSpecificRotation(e);
        if (!value(e, 'specific') && computed !== null) r.push({ label: t('Spezifischer Drehwert'), value: `[α] = ${rotation(computed)}` });
        const sp = specificRotation(e), lit = signedNumber(value(e, 'literature'));
        if (sp !== null && lit !== null && lit !== 0) r.push({ label: t('Optische Reinheit'), value: percent0((sp / lit) * 100) });
        return r;
      }
      default: return [];
    }
  }

  /** Eine Zeile wie in einer Experimentalbeschreibung: "¹H-NMR (400 MHz, CDCl₃, 12 mg): δ = 7.26 (d, 2H)". */
  function summary(e) {
    const v = k => value(e, k);
    const join = parts => parts.filter(Boolean).join(', ');
    const paren = parts => { const j = join(parts); return j ? ` (${j})` : ''; };
    const withUnit = (k, unit) => (v(k) ? `${v(k)} ${unit}` : '');
    const data = v('data'), notes = v('notes');
    const head = heading(e);
    let line;
    switch (e.method) {
      case 'nmr':
        line = head + paren([withUnit('frequency', 'MHz'), v('solvent'), withUnit('sampleMass', 'mg'), v('temperature') ? `${v('temperature')} °C` : '']);
        if (data) line += ': ' + (data.startsWith('δ') ? data : 'δ = ' + data);
        break;
      case 'ir':
        line = 'IR' + paren([v('technique')]);
        if (data) line += ': ' + (data.startsWith('ṽ') ? data : 'ṽ = ' + data) + (data.includes('cm') ? '' : ' cm⁻¹');
        break;
      case 'uvVis': {
        line = 'UV/Vis' + paren([v('solvent'), v('concentration') ? `c = ${v('concentration')} mol/L` : '', withUnit('pathLength', 'cm')]);
        const parts = [];
        if (v('lambdaMax')) { const r = results(e)[0]; parts.push(`λmax = ${v('lambdaMax')} nm${r ? ` (${r.value})` : ''}`); }
        if (data) parts.push(data);
        if (parts.length) line += ': ' + parts.join('; ');
        break;
      }
      case 'ms': {
        line = head + paren([v('ionization'), v('polarity')]);
        const parts = [];
        if (v('mzCalc') || v('mzFound')) {
          let s = 'm/z';
          if (v('ion')) s += ` ${v('ion')}`;
          if (v('mzCalc')) s += t(' ber.') + (v('formula') ? t(' für {0}', v('formula')) : '') + `: ${v('mzCalc')}`;
          if (v('mzFound')) s += (v('mzCalc') ? ', ' : ': ') + t('gef.: ') + v('mzFound');
          const r = results(e)[0];
          if (r) s += ` (${r.value})`;
          parts.push(s);
        } else if (v('formula')) parts.push(v('formula'));
        if (data) parts.push(data);
        if (parts.length) line += ': ' + parts.join('; ');
        break;
      }
      case 'opticalRotation': {
        line = head;
        const parts = [];
        const sp = specificRotation(e);
        if (sp !== null) {
          const shown = v('specific') || rotation(sp);
          const cond = [v('concentration') ? `c ${v('concentration')}` : '', v('solvent')].filter(Boolean);
          parts.push(`${rotationSymbol(e)} = ${shown}` + (cond.length ? ` (${cond.join(', ')})` : ''));
        } else if (v('measured')) parts.push(`α = ${v('measured')}°`);
        if (v('literature')) parts.push(t('Literatur: {0}', v('literature')));
        const purity = results(e).find(r => r.label === t('Optische Reinheit'));
        if (purity) parts.push(t('optische Reinheit {0}', purity.value));
        if (parts.length) line += ': ' + parts.join('; ');
        break;
      }
      case 'epr': {
        const band = v('band').split(' (')[0];
        let modulation = v('modAmp') ? t('Mod. {0} mT', v('modAmp')) : '';
        if (v('modFreq')) modulation += (modulation ? '/' : t('Mod. ')) + `${v('modFreq')} kHz`;
        line = head + paren([band, withUnit('frequency', 'GHz'), withUnit('power', 'mW'), modulation, withUnit('temperature', 'K'),
          v('sampleState'), v('solvent'), withUnit('concentration', 'mM'), v('scans') ? t('{0} Scans', v('scans')) : '']);
        const parts = [];
        const gv = v('gValues'), a = v('hyperfine'), zfs = v('zfs');
        if (gv) parts.push(gv.toLowerCase().startsWith('g') ? gv : 'g = ' + gv);
        if (a) parts.push(a.startsWith('A') ? a : 'A = ' + a);
        if (zfs) parts.push(zfs.startsWith('D') ? zfs : 'D, E = ' + zfs);
        if (v('field')) parts.push(t('Feld {0}', v('field')));
        if (data) parts.push(data);
        if (v('simulation')) parts.push(t('Simulation: {0}', v('simulation')));
        if (parts.length) line += ': ' + parts.join('; ');
        break;
      }
      default: {
        const skip = e.method === 'other' ? new Set(['title', 'notes']) : new Set(['notes']);
        const parts = fields(e.method).filter(f => !skip.has(f.key) && v(f.key))
          .map(f => `${f.label} ${v(f.key)}${f.unit ? ` ${f.unit}` : ''}`)
          .concat(results(e).map(r => `${r.label} ${r.value}`));
        line = head + (parts.length ? ': ' + parts.join(', ') : '');
      }
    }
    if (notes && e.method !== 'other') line += '. ' + notes;
    if (e.method === 'other' && notes) line += ': ' + notes;
    return line;
  }

  const baseName = p => String(p).split(/[\\/]/).pop();

  /** Volltext für die Suche. */
  function searchText(e) {
    return [title(e.method), heading(e), e.sample || ''].concat(Object.values(e.values || {}))
      .concat((e.files || []).flatMap(f => [f.description, baseName(f.filePath)])).join(' ');
  }

  /** Ordnet eine früher verknüpfte Datei anhand von Beschreibung und Dateiname einer Methode zu. */
  function migrated(file) {
    const txt = (str(file.description) + ' ' + baseName(file.filePath)).toLowerCase();
    const esc = w => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const has = words => words.some(w => new RegExp('(^|[^a-z0-9])' + esc(w) + '([^a-z]|$)').test(txt));
    let entry;
    if (has(['nmr', '1h', '13c', '19f', '31p', '11b', 'cosy', 'hsqc', 'hmbc', 'noesy', 'fid'])) {
      entry = newEntry('nmr');
      const nucleus = has(['13c']) ? '¹³C{¹H}' : has(['19f']) ? '¹⁹F' : has(['31p']) ? '³¹P{¹H}' : has(['11b']) ? '¹¹B' : has(['cosy']) ? 'COSY'
        : has(['hsqc']) ? 'HSQC' : has(['hmbc']) ? 'HMBC' : has(['noesy']) ? 'NOESY' : has(['1h']) ? '¹H' : null;
      if (nucleus) entry.values.nucleus = nucleus;
    } else if (has(['hrms', 'ms', 'esi', 'maldi', 'apci', 'masse', 'mass'])) {
      entry = newEntry('ms');
      if (has(['hrms'])) entry.values.kind = 'HRMS';
    } else if (has(['ir', 'ftir', 'atr'])) entry = newEntry('ir');
    else if (has(['uv', 'uvvis', 'uv-vis', 'absorption'])) entry = newEntry('uvVis');
    else if (has(['gc', 'gcms', 'gc-ms'])) entry = newEntry('gc');
    else if (has(['dc', 'tlc'])) entry = newEntry('tlc');
    else entry = newEntry('other');
    entry.files = [{ id: str(file.id) || uuid(), filePath: str(file.filePath), description: str(file.description) }];
    return entry;
  }

  const api = { Analysis: {
    GROUPS, METHODS, NMR_EXPERIMENTS, groupTitle, methodsIn, title, shortTitle, symbol: m => SYMBOLS[m] || 'doc.text', group: m => GROUP_OF[m],
    fields, inherited: m => INHERITED[m] || [], newEntry, normalizeEntry, value, list, heading, results, summary, searchText, migrated, signedNumber,
  } };
  if (node) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
