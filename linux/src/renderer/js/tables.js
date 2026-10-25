// Ansatzgrößen- und Ausbeute-Tabelle – entspricht ChemicalTableView.swift, YieldTableView.swift, CASStatusIcon.swift.
import { html, CJ, api, useState, useEffect, useRef, newChemical, newYield, formatAbbrev } from './lib.js';
import { Icon } from './icons.js';
import { Sheet, alertOK } from './ui.js';
import { store } from './store.js';

const P = s => CJ.parseDecimal(s);
const f3 = v => CJ.format3(v);
const f4 = v => CJ.format4(v);

// MARK: Berechnungen (1:1 wie in der Mac-App) ---------------------------------------------------------------

/** Rechnet eine Zeile neu, nachdem das Feld `source` geändert wurde. trig = alle Zeilen über die Äquivalente neu rechnen. */
export function calcChemical(chem, source, chemicals) {
  const c = { ...chem };
  const M = P(c.molarMass) ?? 0, d = P(c.density) ?? 0;
  const first = chemicals[0];
  const isRef = !!first && first.id === c.id;
  const refEq = P(first ? first.equivalents : '') ?? 1;
  const baseAmount = (P(first ? first.amount : '') ?? 0) / (refEq > 0 ? refEq : 1);
  const n = P(c.amount), m = P(c.mass), V = P(c.volume), eq = P(c.equivalents);
  let trig = false;
  switch (source) {
    case 'equivalents':
      if (!isRef && eq !== null && baseAmount > 0) {
        const calcN = eq * baseAmount; c.amount = f4(calcN);
        if (M > 0) c.mass = f3(calcN * M);
        if (M > 0 && d > 0) c.volume = f3((calcN * M) / d);
      } else if (isRef) trig = true;
      break;
    case 'amount':
      if (n !== null) {
        if (!isRef && baseAmount > 0) c.equivalents = f4(n / baseAmount); else if (isRef) trig = true;
        if (M > 0) { c.mass = f3(n * M); if (d > 0) c.volume = f3((n * M) / d); }
      }
      break;
    case 'mass':
      if (m !== null && M > 0) {
        const calcN = m / M; c.amount = f4(calcN);
        if (!isRef && baseAmount > 0) c.equivalents = f4(calcN / baseAmount); else if (isRef) trig = true;
        if (d > 0) c.volume = f3(m / d);
      }
      break;
    case 'volume':
      if (V !== null && d > 0) {
        const calcM = V * d; c.mass = f3(calcM);
        if (M > 0) {
          const calcN = calcM / M; c.amount = f4(calcN);
          if (!isRef && baseAmount > 0) c.equivalents = f4(calcN / baseAmount); else if (isRef) trig = true;
        }
      }
      break;
    case 'molarMass':
      if (m !== null && M > 0) {
        const calcN = m / M; c.amount = f4(calcN);
        if (!isRef && baseAmount > 0) c.equivalents = f4(calcN / baseAmount); else if (isRef) trig = true;
        if (d > 0) c.volume = f3(m / d);
      } else if (n !== null && M > 0) {
        c.mass = f3(n * M); if (d > 0) c.volume = f3((n * M) / d);
      }
      break;
    case 'density':
      if (m !== null && d > 0) c.volume = f3(m / d);
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
    const M = P(c.molarMass) ?? 0;
    if (M > 0) { out.mass = f3(newN * M); const d = P(c.density) ?? 0; if (d > 0) out.volume = f3((newN * M) / d); }
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
  return `${e.name ? e.name + ' – ' : ''}lokal gespeichert (${e.source}, ${date})`;
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
    const kept = (row.molarMass || (row.density && d !== null)) ? ' – eigene Werte beibehalten' : '';
    setStatus({ kind: 'found', text: result.title + (result.density == null ? ' (keine Dichte in PubChem)' : '') + kept });
  } else {
    if (r.kind === 'notFound') await api.casMarkChecked(cas);
    const now = getRow();
    if (now.molarMass || now.density) await api.casRecordUser(cas, now.name, now.molarMass, now.density);
    setStatus({ kind: 'failed', text: `${r.message} Eigene Werte werden für diese CAS-Nummer gespeichert.` });
  }
}

async function saveCASValues(row, setStatus) {
  if (!CJ.isValidCAS(row.cas)) return;
  await api.casRecordUser(row.cas, row.name, row.molarMass, row.density);
  const e = store.casEntries.get(CJ.normalizeCAS(row.cas));
  const m = e ? e.molarMass : row.molarMass, d = e ? e.density : row.density;
  setStatus({ kind: 'saved', text: `Als eigene Eingabe gespeichert: M ${m || '–'} g/mol, d ${d || '–'} g/cm³` });
}

export function CASStatusIcon({ status }) {
  switch (status.kind) {
    case 'loading': return html`<span class="cas-status" title="Suche Molmasse und Dichte in PubChem …"><span class="spinner"></span></span>`;
    case 'found': return html`<span class="cas-status green" title=${'Aus PubChem übernommen: ' + status.text}><${Icon} name="checkmark.circle.fill" /></span>`;
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

// MARK: Ansatzgrößen ---------------------------------------------------------------------------------------

export function ChemicalTable({ eid, stage, showSmartExtract, setShowSmartExtract }) {
  const [nameWidth, setNameWidth] = useState(160);
  const [showScale, setShowScale] = useState(false);
  const chemicals = stage.chemicals;
  const setChemicals = fn => store.updateStage(eid, stage.id, s => ({ ...s, chemicals: fn(s.chemicals) }));
  const cols = `${nameWidth}px minmax(40px,0.7fr) minmax(70px,1.3fr) repeat(5, minmax(60px,1fr)) 18px`;

  return html`<div class="table-box">
    <div class="table-head">
      <span class="headline">Ansatzgrößen</span><span class="spacer"></span>
      <button class="tint-button orange" onClick=${() => setShowScale(true)}><${Icon} name="arrow.up.left.and.arrow.down.right" /> Skalieren</button>
      <button class="tint-button purple" onClick=${() => setShowSmartExtract(true)}><${Icon} name="wand" /> Smart Extract</button>
    </div>
    <div class="grid" style=${{ gridTemplateColumns: cols }}>
      <div class="hdr name-col"><span style="flex:1">Name</span><${ResizeHandle} width=${nameWidth} setWidth=${setNameWidth} /></div>
      <div class="hdr">eq</div><div class="hdr">CAS</div><div class="hdr">M (g/mol)</div><div class="hdr">d (g/cm3)</div>
      <div class="hdr">n (mol)</div><div class="hdr">V (ml)</div><div class="hdr">m (g)</div><div class="hdr"></div>
      <div class="rule"></div>
      ${chemicals.map(c => html`<${ChemicalRow} key=${c.id} eid=${eid} sid=${stage.id} chem=${c} setChemicals=${setChemicals} />`)}
    </div>
    <button class="plain-add green" onClick=${() => setChemicals(list => list.concat([newChemical()]))}><${Icon} name="plus" /> Chemikalie hinzufügen</button>
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

function ChemicalRow({ eid, sid, chem, setChemicals }) {
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
    <div class="cell"><${NameField} placeholder="Name" value=${chem.name} onCommit=${v => setChemicals(list => list.map(c => (c.id === chem.id ? { ...c, name: v } : c)))} /></div>
    <div class="cell">${numField('eq', chem.equivalents, v => change('equivalents', v))}</div>
    <div class="cell cas-wrap"><input class="field mono" placeholder="CAS" value=${chem.cas} onInput=${e => onCAS(e.target.value)} /><${CASStatusIcon} status=${status} /></div>
    <div class="cell">${numField('M', chem.molarMass, v => change('molarMass', v), { onBlur: blurSave })}</div>
    <div class="cell">${numField('d', chem.density, v => change('density', v), { onBlur: blurSave })}</div>
    <div class="cell">${numField('n', chem.amount, v => change('amount', v))}</div>
    <div class="cell">${numField('V', chem.volume, v => change('volume', v))}</div>
    <div class="cell">${numField('m', chem.mass, v => change('mass', v))}</div>
    <div class="cell"><button class="icon-button red" title="Zeile löschen" onClick=${() => setChemicals(list => list.filter(c => c.id !== chem.id))}><${Icon} name="trash" /></button></div>
    <div class="rule"></div>`;
}

function ScaleSheet({ onClose, onScale }) {
  const [text, setText] = useState('1.0');
  const apply = () => { const f = P(text); if (f !== null && f > 0) onScale(f); onClose(); };
  return html`<${Sheet} onClose=${onClose} width=${380}>
    <div class="title2" style="font-weight:700">Ansatz skalieren</div>
    <div class="subheadline secondary">Alle Mengen (n, m, V) werden mit dem Faktor multipliziert.</div>
    <div style="display:flex;align-items:center;gap:8px"><span class="headline">Faktor:</span>
      <input class="field" style="width:100px" placeholder="z.B. 0.5" value=${text} onInput=${e => setText(e.target.value)}
        onKeyDown=${e => { if (e.key === 'Enter') apply(); }} ref=${el => el && !el.dataset.f && (el.dataset.f = 1, el.select())} /></div>
    <div class="modal-actions"><button class="btn" onClick=${onClose}>Abbrechen</button><button class="btn prominent-orange" onClick=${apply}>Skalieren</button></div>
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
      if (!rows.length) { await alertOK('Keine Chemikalien gefunden', 'Im Text wurden keine Mengenangaben oder Chemikaliennamen erkannt.'); return; }
      onExtracted(rows);
      onClose();
    }, 30);
  };
  return html`<${Sheet} onClose=${onClose} width=${500} height=${350}>
    <div class="title2" style="font-weight:700">Smart Extract</div>
    <div class="subheadline secondary">Füge hier den Text aus einem Paper ein.</div>
    <textarea class="textarea-field" style="flex:1" value=${text} onInput=${e => setText(e.target.value)} ref=${el => el && !el.dataset.f && (el.dataset.f = 1, el.focus())}></textarea>
    <div class="modal-actions">
      ${busy && html`<span class="spinner"></span><span class="caption secondary">Analysiere…</span>`}
      <span style="flex:1"></span>
      <button class="btn" onClick=${onClose}>Abbrechen</button>
      <button class="btn prominent-purple" disabled=${busy || !text.trim()} onClick=${extract}>Extrahieren</button>
    </div>
  <//>`;
}

// MARK: Ausbeute -------------------------------------------------------------------------------------------

export function YieldTable({ eid, stage }) {
  const [nameWidth, setNameWidth] = useState(160);
  const setYields = fn => store.updateStage(eid, stage.id, s => ({ ...s, yieldProducts: fn(s.yieldProducts) }));
  const cols = `${nameWidth}px minmax(70px,1.3fr) minmax(90px,140px) repeat(5, minmax(60px,1fr)) minmax(60px,0.9fr) minmax(60px,0.9fr) 18px`;
  return html`<div class="table-box">
    <div class="table-head"><span class="headline">Ausbeute (Produkt)</span></div>
    <div class="grid" style=${{ gridTemplateColumns: cols }}>
      <div class="hdr name-col"><span style="flex:1">Produktname</span><${ResizeHandle} width=${nameWidth} setWidth=${setNameWidth} /></div>
      <div class="hdr">CAS</div><div class="hdr">Bezug</div><div class="hdr">M (g/mol)</div><div class="hdr">d (g/cm3)</div>
      <div class="hdr">n (mol)</div><div class="hdr">V (ml)</div><div class="hdr">m (g)</div>
      <div class="hdr secondary">m theor.</div><div class="hdr green">Ausbeute</div><div class="hdr"></div>
      <div class="rule"></div>
      ${stage.yieldProducts.map(y => html`<${YieldRow} key=${y.id} eid=${eid} sid=${stage.id} y=${y} chemicals=${stage.chemicals} setYields=${setYields} />`)}
    </div>
    <button class="plain-add green" onClick=${() => setYields(list => list.concat([newYield()]))}><${Icon} name="plus" /> Produkt hinzufügen</button>
  </div>`;
}

function YieldRow({ eid, sid, y, chemicals, setYields }) {
  const [status, setStatus] = useState({ kind: 'idle' });
  const getRow = () => { const s = store.stage(eid, sid); return s && s.yieldProducts.find(r => r.id === y.id); };
  const change = (field, value) => setYields(list => list.map(r => (r.id === y.id ? calcYield({ ...r, [field]: value }, field) : r)));
  const ref = y.referenceChemicalID ? chemicals.find(c => c.id === y.referenceChemicalID) : null;
  const refN = ref ? P(ref.amount) : null;
  const myN = P(y.amount), M = P(y.molarMass);
  const yieldText = refN !== null && refN > 0 && myN !== null && myN > 0 ? `${((myN / refN) * 100).toFixed(1)} %` : '–';
  const theory = refN !== null && M !== null ? `${f3(refN * M)} g` : '–';
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
    <div class="cell"><${NameField} placeholder="Produktname" value=${y.name} onCommit=${v => setYields(list => list.map(r => (r.id === y.id ? { ...r, name: v } : r)))} /></div>
    <div class="cell cas-wrap"><input class="field mono" placeholder="CAS" value=${y.cas} onInput=${e => onCAS(e.target.value)} /><${CASStatusIcon} status=${status} /></div>
    <div class="cell"><select class="field" value=${y.referenceChemicalID || ''} onChange=${e => setRef(e.target.value)}>
      <option value="">Wählen...</option>
      ${chemicals.filter(c => c.name).map(c => html`<option value=${c.id}>${c.name}</option>`)}
    </select></div>
    <div class="cell">${numField('M', y.molarMass, v => change('molarMass', v), { onBlur: blurSave })}</div>
    <div class="cell">${numField('d', y.density, v => change('density', v), { onBlur: blurSave })}</div>
    <div class="cell">${numField('n', y.amount, v => change('amount', v))}</div>
    <div class="cell">${numField('V', y.volume, v => change('volume', v))}</div>
    <div class="cell">${numField('m', y.mass, v => change('mass', v))}</div>
    <div class="cell theory">${theory}</div>
    <div class="cell yield-value">${yieldText}</div>
    <div class="cell"><button class="icon-button red" title="Zeile löschen" onClick=${() => setYields(list => list.filter(r => r.id !== y.id))}><${Icon} name="trash" /></button></div>
    <div class="rule"></div>`;
}
