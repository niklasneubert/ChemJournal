// Ansatzgrößen- und Ausbeute-Tabelle – entspricht ChemicalTableView.swift, YieldTableView.swift, CASStatusIcon.swift.
import { html, CJ, api, t, useState, useEffect, useRef, newChemical, newYield, formatAbbrev, stored, remember } from './lib.js';
import { Icon } from './icons.js';
import { Sheet, alertOK, openMenuAt } from './ui.js';
import { store } from './store.js';

const P = s => CJ.parseDecimal(s);
const f3 = v => CJ.format3(v);
const f4 = v => CJ.format4(v);

// MARK: Berechnungen (1:1 wie in der Mac-App) ---------------------------------------------------------------

/** Rechnet eine Zeile neu, nachdem das Feld `source` geändert wurde. trig = alle Zeilen über die Äquivalente neu rechnen.
 *  Reinheit: n ist die Stoffmenge des reinen Stoffes; m und V sind die abzumessende Menge (m = n · M / Reinheit). */
export function calcChemical(chem, source, chemicals) {
  const c = { ...chem };
  const d = P(c.density) ?? 0;
  const first = chemicals[0];
  const isRef = !!first && first.id === c.id;
  const refEq = P(first ? first.equivalents : '') ?? 1;
  const baseAmount = (P(first ? first.amount : '') ?? 0) / (refEq > 0 ? refEq : 1);
  const n = P(c.amount), m = P(c.mass), V = P(c.volume), eq = P(c.equivalents);
  const M = P(c.molarMass) ?? 0;
  let trig = false;
  /** Aus der Stoffmenge: Masse und Volumen des Reagenzes */
  const setMassAndVolume = amount => {
    const mass = CJ.massToWeigh(c, amount);
    if (mass === null) return;
    c.mass = f3(mass);
    if (d > 0) c.volume = f3(mass / d);
  };
  /** Aus der abgewogenen Masse: Stoffmenge (und Äquivalente) des reinen Stoffes */
  const setAmount = mass => {
    const calcN = CJ.pureAmount(c, mass);
    if (calcN === null) return;
    c.amount = f4(calcN);
    if (!isRef && baseAmount > 0) c.equivalents = f4(calcN / baseAmount); else if (isRef) trig = true;
  };
  switch (source) {
    case 'equivalents':
      if (!isRef && eq !== null && baseAmount > 0) { const calcN = eq * baseAmount; c.amount = f4(calcN); setMassAndVolume(calcN); }
      else if (isRef) trig = true;
      break;
    case 'amount':
      if (n !== null) {
        if (!isRef && baseAmount > 0) c.equivalents = f4(n / baseAmount); else if (isRef) trig = true;
        setMassAndVolume(n);
      }
      break;
    case 'mass':
      if (m !== null) { setAmount(m); if (d > 0) c.volume = f3(m / d); }
      break;
    case 'volume':
      if (V !== null && d > 0) { const calcM = V * d; c.mass = f3(calcM); setAmount(calcM); }
      break;
    case 'molarMass':
      if (m !== null && M > 0) { setAmount(m); if (d > 0) c.volume = f3(m / d); }
      else if (n !== null) setMassAndVolume(n);
      break;
    case 'density':
      if (m !== null && d > 0) c.volume = f3(m / d);
      break;
    // Reinheit geändert: die benötigte Stoffmenge bleibt, abzuwiegende Menge passt sich an
    case 'purity':
      if (n !== null) setMassAndVolume(n); else if (m !== null) setAmount(m);
      break;
    default: break;
  }
  return { chem: c, trig };
}

/** Rechnet alle Zeilen über ihre Äquivalente aus der ersten Zeile (Leit-Reaktand) neu. */
export function triggerGlobalUpdate(chemicals) {
  if (chemicals.length <= 1) return chemicals;
  const refN = P(chemicals[0].amount) ?? 0;
  const refEq = P(chemicals[0].equivalents) ?? 1;
  const baseAmount = refN / (refEq > 0 ? refEq : 1);
  if (!(baseAmount > 0)) return chemicals;
  return chemicals.map((c, i) => {
    if (i === 0) return c;
    const eq = P(c.equivalents) ?? 0;
    if (!(eq > 0)) return c;
    const out = { ...c };
    const newN = eq * baseAmount; out.amount = f4(newN);
    // Reinheit: für n mol reinen Stoff muss mehr abgewogen werden (m = n · M / Reinheit)
    const mass = CJ.massToWeigh(c, newN);
    if (mass !== null) { out.mass = f3(mass); const d = P(c.density) ?? 0; if (d > 0) out.volume = f3(mass / d); }
    return out;
  });
}

/** Ein Feld einer Chemikalie ändern und alles Abhängige nachrechnen. */
function changeChemical(chemicals, id, field, value, forceCalc = true) {
  const old = chemicals;
  let list = chemicals.map(c => (c.id === id ? { ...c, [field]: value } : c));
  if (forceCalc) {
    const row = list.find(c => c.id === id);
    const { chem, trig } = calcChemical(row, field, list);
    list = list.map(c => (c.id === id ? chem : c));
    if (trig) list = triggerGlobalUpdate(list);
  }
  // wie .onChange(of: chemicals.first?.amount / equivalents) in der Mac-App
  if (old[0] && list[0] && (old[0].amount !== list[0].amount || old[0].equivalents !== list[0].equivalents)) list = triggerGlobalUpdate(list);
  return list;
}

export function calcYield(y, source) {
  const c = { ...y };
  const M = P(c.molarMass) ?? 0, d = P(c.density) ?? 0;
  const n = P(c.amount), m = P(c.mass), V = P(c.volume);
  switch (source) {
    case 'amount': if (n !== null && M > 0) { c.mass = f3(n * M); if (d > 0) c.volume = f3((n * M) / d); } break;
    case 'mass': if (m !== null && M > 0) { c.amount = f4(m / M); if (d > 0) c.volume = f3(m / d); } break;
    case 'volume': if (V !== null && d > 0) { const calcM = V * d; c.mass = f3(calcM); if (M > 0) c.amount = f4(calcM / M); } break;
    case 'molarMass':
      if (m !== null && M > 0) { c.amount = f4(m / M); if (d > 0) c.volume = f3(m / d); }
      else if (n !== null && M > 0) { c.mass = f3(n * M); if (d > 0) c.volume = f3((n * M) / d); }
      break;
    case 'density': if (m !== null && d > 0) c.volume = f3(m / d); break;
    default: break;
  }
  return c;
}

// MARK: CAS-Autofill -------------------------------------------------------------------------------------

function savedInfo(e) {
  const date = formatAbbrev(new Date(e.updatedAt));
  return t('{0}lokal gespeichert ({1}, {2})', e.name ? e.name + ' – ' : '', t(e.source), date);
}

/**
 * CAS-Nummer geändert:
 * 1. In der lokalen CAS-Datenbank → Werte sofort eintragen (offline).
 * 2. Sonst PubChem fragen → nur leere Felder füllen (eigene Werte bleiben) → Ergebnis speichern.
 */
function casChanged(rawCAS, getRow, setStatus, apply) {
  const cas = CJ.normalizeCAS(rawCAS);
  if (!cas) { setStatus({ kind: 'idle' }); return; }
  const saved = store.casEntries.get(cas);
  if (saved && (saved.molarMass || saved.density)) {
    apply(saved.molarMass || null, saved.density || null);
    setStatus({ kind: 'saved', text: savedInfo(saved) });
    if ((!saved.molarMass || !saved.density) && !saved.pubChemChecked) lookup(cas, getRow, setStatus, apply);
    return;
  }
  lookup(cas, getRow, setStatus, apply);
}

async function lookup(cas, getRow, setStatus, apply) {
  setStatus({ kind: 'loading' });
  const r = await api.pubChemLookup(cas);
  const row = getRow();
  if (!row || CJ.normalizeCAS(row.cas) !== cas) return;   // inzwischen andere CAS
  if (r.ok) {
    const result = r.result;
    const m = f3(result.molarMass), d = result.density == null ? null : f4(result.density);
    apply(row.molarMass ? null : m, row.density ? null : d);
    await api.casRecordPubChem(cas, result);
    if (row.molarMass || row.density) { const now = getRow(); await api.casRecordUser(cas, now.name, now.molarMass, now.density); }
    const kept = (row.molarMass || (row.density && d !== null)) ? t(' – eigene Werte beibehalten') : '';
    setStatus({ kind: 'found', text: result.title + (result.density == null ? t(' (keine Dichte in PubChem)') : '') + kept });
  } else {
    if (r.kind === 'notFound') await api.casMarkChecked(cas);
    const now = getRow();
    if (now.molarMass || now.density) await api.casRecordUser(cas, now.name, now.molarMass, now.density);
    setStatus({ kind: 'failed', text: t(r.message) + t(' Eigene Werte werden für diese CAS-Nummer gespeichert.') });
  }
}

async function saveCASValues(row, setStatus) {
  if (!CJ.isValidCAS(row.cas)) return;
  await api.casRecordUser(row.cas, row.name, row.molarMass, row.density);
  const e = store.casEntries.get(CJ.normalizeCAS(row.cas));
  const m = e ? e.molarMass : row.molarMass, d = e ? e.density : row.density;
  setStatus({ kind: 'saved', text: t('Als eigene Eingabe gespeichert: M {0} g/mol, d {1} g/cm³', m || '–', d || '–') });
}

export function CASStatusIcon({ status }) {
  switch (status.kind) {
    case 'loading': return html`<span class="cas-status" title=${t('Suche Molmasse und Dichte in PubChem …')}><span class="spinner"></span></span>`;
    case 'found': return html`<span class="cas-status green" title=${t('Aus PubChem übernommen: {0}', status.text)}><${Icon} name="checkmark.circle.fill" /></span>`;
    case 'saved': return html`<span class="cas-status gray" title=${status.text}><${Icon} name="checkmark.circle.fill" /></span>`;
    case 'failed': return html`<span class="cas-status orange" title=${status.text}><${Icon} name="exclamationmark.triangle.fill" /></span>`;
    default: return null;
  }
}

// MARK: Bausteine ------------------------------------------------------------------------------------------

/** Name mit „Smarter Formatierung“ beim Verlassen des Feldes ("\ce{H2O}" → H₂O, "(12)" → fett). */
function NameField({ value, placeholder, onCommit }) {
  const [temp, setTemp] = useState(value);
  const focused = useRef(false);
  useEffect(() => { if (!focused.current) setTemp(value); }, [value]);
  // Immer den Feldinhalt nehmen – der zuletzt gezeichnete Zustand kann einen Tastendruck hinterher sein
  const commit = el => { const f = CJ.applySmartFormatting(el.value); el.value = f; setTemp(f); if (f !== value) onCommit(f); };
  return html`<input class="field" placeholder=${placeholder} value=${temp}
    onInput=${e => setTemp(e.target.value)}
    onFocus=${() => { focused.current = true; }}
    onBlur=${e => { focused.current = false; commit(e.target); }}
    onKeyDown=${e => { if (e.key === 'Enter') commit(e.target); }} />`;
}

function ResizeHandle({ width, setWidth }) {
  const onDown = e => {
    e.preventDefault();
    const startX = e.clientX, startW = width;
    const move = ev => setWidth(Math.max(80, startW + ev.clientX - startX));
    const up = () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up); document.body.style.cursor = ''; };
    window.addEventListener('mousemove', move);
    window.addEventListener('mouseup', up);
    document.body.style.cursor = 'col-resize';
  };
  return html`<div class="resize-handle" onMouseDown=${onDown}></div>`;
}

const numField = (placeholder, value, onInput, extra = {}) => html`<input class="field mono" placeholder=${placeholder} value=${value}
  onInput=${e => onInput(e.target.value)} ...${extra} />`;

// MARK: Einheiten (wie UnitColumns.swift) ------------------------------------------------------------------

/** Gewählte Anzeigeeinheiten einer Tabelle, gemerkt wie @AppStorage ("unit.reagents.amount" …). */
function useUnits(table) {
  const read = kind => CJ.Units.unit(kind, stored(`unit.${table}.${kind}`, CJ.Units.baseUnit(kind).symbol));
  const [units, setUnits] = useState(() => ({ amount: read('amount'), volume: read('volume'), mass: read('mass') }));
  const choose = (kind, symbol) => { remember(`unit.${table}.${kind}`, symbol); setUnits(u => ({ ...u, [kind]: CJ.Units.unit(kind, symbol) })); };
  return [units, choose];
}

/** Spaltenkopf wie "n (mol)": Ein Klick auf die Einheit zeigt die anderen Einheiten; die gewählte gilt für die ganze Spalte. */
function UnitHeader({ symbol, kind, unit, onChoose }) {
  const open = e => openMenuAt(e.currentTarget, CJ.Units.units(kind).map(u => ({
    label: u.symbol, icon: u.symbol === unit.symbol ? 'checkmark' : null, action: () => onChoose(kind, u.symbol),
  })));
  return html`<div class="hdr">${symbol}<button class="unit-menu" title=${t('Klicken, um die Einheit der Spalte zu wechseln')} onClick=${open}>
    (${unit.symbol})<${Icon} name="chevron.down" /></button></div>`;
}

/** Mengenfeld: zeigt den gespeicherten Wert (mol/ml/g) in der gewählten Einheit und rechnet Eingaben zurück.
 *  Während des Tippens bleibt der Text, wie er ist ("12." wird nicht zu "12"). */
function UnitField({ placeholder, value, unit, kind, onChange, extra = {} }) {
  const [editing, setEditing] = useState(null);
  if (CJ.Units.isBase(unit)) return numField(placeholder, value, onChange, extra);
  const shown = editing !== null ? editing : CJ.Units.display(value, unit, kind);
  return html`<input class="field mono" placeholder=${placeholder} value=${shown}
    onFocus=${e => setEditing(e.target.value)}
    onInput=${e => { setEditing(e.target.value); onChange(CJ.Units.toBase(e.target.value, unit)); }}
    onBlur=${e => { setEditing(null); if (extra.onBlur) extra.onBlur(e); }} />`;
}

// MARK: Ansatzgrößen ---------------------------------------------------------------------------------------

export function ChemicalTable({ eid, stage, showSmartExtract, setShowSmartExtract }) {
  const [nameWidth, setNameWidth] = useState(160);
  const [showScale, setShowScale] = useState(false);
  const [units, chooseUnit] = useUnits('reagents');
  const chemicals = stage.chemicals;
  const setChemicals = fn => store.updateStage(eid, stage.id, s => ({ ...s, chemicals: fn(s.chemicals) }));
  const cols = `${nameWidth}px minmax(40px,0.7fr) minmax(70px,1.3fr) repeat(3, minmax(60px,1fr)) repeat(3, minmax(72px,1fr)) 18px`;

  return html`<div class="table-box">
    <div class="table-head">
      <span class="headline">${t('Ansatzgrößen')}</span><span class="spacer"></span>
      <button class="tint-button orange" onClick=${() => setShowScale(true)}><${Icon} name="arrow.up.left.and.arrow.down.right" /> ${t('Skalieren')}</button>
      <button class="tint-button purple" onClick=${() => setShowSmartExtract(true)}><${Icon} name="wand" /> Smart Extract</button>
    </div>
    <div class="grid" style=${{ gridTemplateColumns: cols }}>
      <div class="hdr name-col"><span style="flex:1">${t('Name')}</span><${ResizeHandle} width=${nameWidth} setWidth=${setNameWidth} /></div>
      <div class="hdr">eq</div><div class="hdr">CAS</div><div class="hdr">M (g/mol)</div><div class="hdr">d (g/cm3)</div>
      <div class="hdr" title=${t('Gehalt des Reagenzes, z. B. 95 oder 60 (NaH in Mineralöl). Leer = 100 %. n bleibt die Stoffmenge des reinen Stoffes, m und V sind die abzumessende Menge.')}>${t('Reinheit (%)')}</div>
      <${UnitHeader} symbol="n" kind="amount" unit=${units.amount} onChoose=${chooseUnit} />
      <${UnitHeader} symbol="V" kind="volume" unit=${units.volume} onChoose=${chooseUnit} />
      <${UnitHeader} symbol="m" kind="mass" unit=${units.mass} onChoose=${chooseUnit} /><div class="hdr"></div>
      <div class="rule"></div>
      ${chemicals.map(c => html`<${ChemicalRow} key=${c.id} eid=${eid} sid=${stage.id} chem=${c} units=${units} setChemicals=${setChemicals} />`)}
    </div>
    <button class="plain-add green" onClick=${() => setChemicals(list => list.concat([newChemical()]))}><${Icon} name="plus" /> ${t('Chemikalie hinzufügen')}</button>
    ${showScale && html`<${ScaleSheet} onClose=${() => setShowScale(false)} onScale=${factor => setChemicals(list => list.map(c => {
      const o = { ...c };
      const n = P(c.amount), m = P(c.mass), v = P(c.volume);
      if (n !== null) o.amount = f4(n * factor);
      if (m !== null) o.mass = f3(m * factor);
      if (v !== null) o.volume = f3(v * factor);
      return o;
    }))} />`}
    ${showSmartExtract && html`<${SmartExtractSheet} onClose=${() => setShowSmartExtract(false)}
      onExtracted=${rows => setChemicals(list => list.concat(rows))} />`}
  </div>`;
}

function ChemicalRow({ eid, sid, chem, units, setChemicals }) {
  const [status, setStatus] = useState({ kind: 'idle' });
  const getRow = () => { const s = store.stage(eid, sid); return s && s.chemicals.find(c => c.id === chem.id); };
  const change = (field, value) => setChemicals(list => changeChemical(list, chem.id, field, value));
  const onCAS = value => {
    setChemicals(list => list.map(c => (c.id === chem.id ? { ...c, cas: value } : c)));
    casChanged(value, getRow, setStatus, (m, d) => {
      const row = getRow();
      if (!row) return;
      if (m !== null && row.molarMass !== m) change('molarMass', m);
      const row2 = getRow();
      if (d !== null && row2 && row2.density !== d) change('density', d);
    });
  };
  const blurSave = () => { const r = getRow(); if (r) saveCASValues(r, setStatus); };
  return html`
    <div class="cell"><${NameField} placeholder=${t('Name')} value=${chem.name} onCommit=${v => setChemicals(list => list.map(c => (c.id === chem.id ? { ...c, name: v } : c)))} /></div>
    <div class="cell">${numField('eq', chem.equivalents, v => change('equivalents', v))}</div>
    <div class="cell cas-wrap"><input class="field mono" placeholder="CAS" value=${chem.cas} onInput=${e => onCAS(e.target.value)} /><${CASStatusIcon} status=${status} /></div>
    <div class="cell">${numField('M', chem.molarMass, v => change('molarMass', v), { onBlur: blurSave })}</div>
    <div class="cell">${numField('d', chem.density, v => change('density', v), { onBlur: blurSave })}</div>
    <div class="cell">${numField('100', chem.purity || '', v => change('purity', v))}</div>
    <div class="cell"><${UnitField} placeholder="n" value=${chem.amount} unit=${units.amount} kind="amount" onChange=${v => change('amount', v)} /></div>
    <div class="cell"><${UnitField} placeholder="V" value=${chem.volume} unit=${units.volume} kind="volume" onChange=${v => change('volume', v)} /></div>
    <div class="cell"><${UnitField} placeholder="m" value=${chem.mass} unit=${units.mass} kind="mass" onChange=${v => change('mass', v)} /></div>
    <div class="cell"><button class="icon-button red" title=${t('Zeile löschen')} onClick=${() => setChemicals(list => list.filter(c => c.id !== chem.id))}><${Icon} name="trash" /></button></div>
    <div class="rule"></div>`;
}

function ScaleSheet({ onClose, onScale }) {
  const [text, setText] = useState('1.0');
  const apply = () => { const f = P(text); if (f !== null && f > 0) onScale(f); onClose(); };
  return html`<${Sheet} onClose=${onClose} width=${380}>
    <div class="title2" style="font-weight:700">${t('Ansatz skalieren')}</div>
    <div class="subheadline secondary">${t('Alle Mengen (n, m, V) werden mit dem Faktor multipliziert.')}</div>
    <div style="display:flex;align-items:center;gap:8px"><span class="headline">${t('Faktor:')}</span>
      <input class="field" style="width:100px" placeholder=${t('z.B. 0.5')} value=${text} onInput=${e => setText(e.target.value)}
        onKeyDown=${e => { if (e.key === 'Enter') apply(); }} ref=${el => el && !el.dataset.f && (el.dataset.f = 1, el.select())} /></div>
    <div class="modal-actions"><button class="btn" onClick=${onClose}>${t('Abbrechen')}</button><button class="btn prominent-orange" onClick=${apply}>${t('Skalieren')}</button></div>
  <//>`;
}

function SmartExtractSheet({ onClose, onExtracted }) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const extract = () => {
    setBusy(true);
    // Kurz warten, damit die Fortschrittsanzeige sichtbar wird; die Extraktion selbst läuft lokal
    setTimeout(async () => {
      const rows = CJ.SmartExtractor.extract(text);
      setBusy(false);
      if (!rows.length) { await alertOK(t('Keine Chemikalien gefunden'), t('Im Text wurden keine Mengenangaben oder Chemikaliennamen erkannt.')); return; }
      onExtracted(rows);
      onClose();
    }, 30);
  };
  return html`<${Sheet} onClose=${onClose} width=${500} height=${350}>
    <div class="title2" style="font-weight:700">Smart Extract</div>
    <div class="subheadline secondary">${t('Füge hier die Versuchsvorschrift aus einem Paper oder einer SI ein. Die Auswertung läuft komplett auf deinem Rechner.')}</div>
    <textarea class="textarea-field" style="flex:1" value=${text} onInput=${e => setText(e.target.value)} ref=${el => el && !el.dataset.f && (el.dataset.f = 1, el.focus())}></textarea>
    <div class="modal-actions">
      ${busy && html`<span class="spinner"></span><span class="caption secondary">${t('Analysiere…')}</span>`}
      <span style="flex:1"></span>
      <button class="btn" onClick=${onClose}>${t('Abbrechen')}</button>
      <button class="btn prominent-purple" disabled=${busy || !text.trim()} onClick=${extract}>${t('Extrahieren')}</button>
    </div>
  <//>`;
}

// MARK: Ausbeute -------------------------------------------------------------------------------------------

export function YieldTable({ eid, stage }) {
  const [nameWidth, setNameWidth] = useState(160);
  const [units, chooseUnit] = useUnits('yield');
  const setYields = fn => store.updateStage(eid, stage.id, s => ({ ...s, yieldProducts: fn(s.yieldProducts) }));
  const cols = `${nameWidth}px minmax(70px,1.3fr) minmax(90px,140px) repeat(5, minmax(60px,1fr)) minmax(60px,0.9fr) minmax(60px,0.9fr) 18px`;
  return html`<div class="table-box">
    <div class="table-head"><span class="headline">${t('Ausbeute (Produkt)')}</span></div>
    <div class="grid" style=${{ gridTemplateColumns: cols }}>
      <div class="hdr name-col"><span style="flex:1">${t('Produktname')}</span><${ResizeHandle} width=${nameWidth} setWidth=${setNameWidth} /></div>
      <div class="hdr">CAS</div><div class="hdr">${t('Bezug')}</div><div class="hdr">M (g/mol)</div><div class="hdr">d (g/cm3)</div>
      <${UnitHeader} symbol="n" kind="amount" unit=${units.amount} onChoose=${chooseUnit} />
      <${UnitHeader} symbol="V" kind="volume" unit=${units.volume} onChoose=${chooseUnit} />
      <${UnitHeader} symbol="m" kind="mass" unit=${units.mass} onChoose=${chooseUnit} />
      <div class="hdr secondary">${t('m theor.')}</div><div class="hdr green">${t('Ausbeute')}</div><div class="hdr"></div>
      <div class="rule"></div>
      ${stage.yieldProducts.map(y => html`<${YieldRow} key=${y.id} eid=${eid} sid=${stage.id} y=${y} units=${units} chemicals=${stage.chemicals} setYields=${setYields} />`)}
    </div>
    <button class="plain-add green" onClick=${() => setYields(list => list.concat([newYield()]))}><${Icon} name="plus" /> ${t('Produkt hinzufügen')}</button>
  </div>`;
}

function YieldRow({ eid, sid, y, units, chemicals, setYields }) {
  const [status, setStatus] = useState({ kind: 'idle' });
  const getRow = () => { const s = store.stage(eid, sid); return s && s.yieldProducts.find(r => r.id === y.id); };
  const change = (field, value) => setYields(list => list.map(r => (r.id === y.id ? calcYield({ ...r, [field]: value }, field) : r)));
  const ref = y.referenceChemicalID ? chemicals.find(c => c.id === y.referenceChemicalID) : null;
  const refN = ref ? P(ref.amount) : null;
  const myN = P(y.amount), M = P(y.molarMass);
  const yieldText = refN !== null && refN > 0 && myN !== null && myN > 0 ? `${((myN / refN) * 100).toFixed(1)} %` : '–';
  const theory = refN !== null && M !== null ? `${CJ.Units.format((refN * M) / units.mass.factor, 'mass')} ${units.mass.symbol}` : '–';
  const onCAS = value => {
    setYields(list => list.map(r => (r.id === y.id ? { ...r, cas: value } : r)));
    casChanged(value, getRow, setStatus, (m, d) => {
      const row = getRow();
      if (row && m !== null && row.molarMass !== m) change('molarMass', m);
      const row2 = getRow();
      if (row2 && d !== null && row2.density !== d) change('density', d);
    });
  };
  const blurSave = () => { const r = getRow(); if (r) saveCASValues(r, setStatus); };
  const setRef = id => setYields(list => list.map(r => {
    if (r.id !== y.id) return r;
    const o = { ...r };
    if (id) o.referenceChemicalID = id; else delete o.referenceChemicalID;
    return o;
  }));
  return html`
    <div class="cell"><${NameField} placeholder=${t('Produktname')} value=${y.name} onCommit=${v => setYields(list => list.map(r => (r.id === y.id ? { ...r, name: v } : r)))} /></div>
    <div class="cell cas-wrap"><input class="field mono" placeholder="CAS" value=${y.cas} onInput=${e => onCAS(e.target.value)} /><${CASStatusIcon} status=${status} /></div>
    <div class="cell"><select class="field" value=${y.referenceChemicalID || ''} onChange=${e => setRef(e.target.value)}>
      <option value="">${t('Wählen...')}</option>
      ${chemicals.filter(c => c.name).map(c => html`<option value=${c.id}>${c.name}</option>`)}
    </select></div>
    <div class="cell">${numField('M', y.molarMass, v => change('molarMass', v), { onBlur: blurSave })}</div>
    <div class="cell">${numField('d', y.density, v => change('density', v), { onBlur: blurSave })}</div>
    <div class="cell"><${UnitField} placeholder="n" value=${y.amount} unit=${units.amount} kind="amount" onChange=${v => change('amount', v)} /></div>
    <div class="cell"><${UnitField} placeholder="V" value=${y.volume} unit=${units.volume} kind="volume" onChange=${v => change('volume', v)} /></div>
    <div class="cell"><${UnitField} placeholder="m" value=${y.mass} unit=${units.mass} kind="mass" onChange=${v => change('mass', v)} /></div>
    <div class="cell theory">${theory}</div>
    <div class="cell yield-value">${yieldText}</div>
    <div class="cell"><button class="icon-button red" title=${t('Zeile löschen')} onClick=${() => setYields(list => list.filter(r => r.id !== y.id))}><${Icon} name="trash" /></button></div>
    <div class="rule"></div>`;
}
