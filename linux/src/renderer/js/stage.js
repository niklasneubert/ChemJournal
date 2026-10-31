// Stufe eines Ansatzes – entspricht StageView.swift, ReactionImageView.swift, AnalysisSectionView.swift.
import { html, CJ, api, t, useState, useRef, useEffect, useLayoutEffect, uuid, nowRef, refToDate, formatLong, formatAbbrevTime } from './lib.js';
import { Icon } from './icons.js';
import { ask, openContextMenu, openMenuAt, alertOK } from './ui.js';
import { store } from './store.js';
import { LaTeXEditor } from './latex.js';
import { ChemicalTable, YieldTable } from './tables.js';

function extractURL(text) {
  const clean = text.trim();
  const lower = clean.toLowerCase();
  if (lower.startsWith('http')) return clean;
  if (lower.startsWith('doi:')) return 'https://doi.org/' + clean.slice(4).trim();
  if (lower.startsWith('10.')) return 'https://doi.org/' + clean;
  return null;
}

export function StageView({ eid, stage, onDelete, onDuplicate }) {
  const [editingSource, setEditingSource] = useState(false);
  const [showSmartExtract, setShowSmartExtract] = useState(false);
  const update = fn => store.updateStage(eid, stage.id, fn);
  const set = (field, value) => update(s => ({ ...s, [field]: value }));
  const url = extractURL(stage.sourceURL);

  const textMenu = field => e => openContextMenu(e, [
    { label: t('Smarte Formatierung anwenden'), icon: 'textformat.subscript', action: () => set(field, CJ.applySmartFormatting(store.stage(eid, stage.id)[field])) },
    'separator',
    { label: t('Smart Extract öffnen'), icon: 'wand', action: () => setShowSmartExtract(true) },
  ]);

  const confirmDelete = async () => {
    const i = await ask({
      title: t('Stufe löschen?'), message: t('Alle Daten dieser Stufe werden gelöscht. Mit Strg+Z lässt sich das rückgängig machen.'),
      buttons: [{ label: t('Stufe löschen'), role: 'destructive' }, { label: t('Abbrechen'), role: 'cancel' }],
    });
    if (i === 0) onDelete();
  };

  return html`<div class="stage-card">
    <div class="stage-header">
      <button class=${'disclosure' + (stage.isExpanded ? ' open' : '')} onClick=${() => set('isExpanded', !stage.isExpanded)}><${Icon} name="chevron.right" /></button>
      <input class="plain-field" placeholder=${t('Stufenname')} value=${stage.title} onInput=${e => set('title', e.target.value)} />
      <span class="stage-date caption secondary" title=${t('Stufe angelegt am {0}', formatAbbrevTime(refToDate(stage.createdAt)))}><${Icon} name="calendar" />${formatLong(refToDate(stage.createdAt))}</span>
      <button class="icon-button blue" title=${t('Stufe duplizieren')} onClick=${onDuplicate}><${Icon} name="doc.on.doc" /></button>
      <button class="icon-button red" title=${t('Stufe löschen')} onClick=${confirmDelete}><${Icon} name="trash" /></button>
    </div>
    ${stage.isExpanded && html`<div class="stage-body">
      <div class="source-row">
        <span class="headline">${t('Quelle:')}</span>
        ${!editingSource && url
          ? html`<a title=${url} onClick=${() => api.openExternal(url)}>${stage.sourceURL}</a><span style="flex:1"></span>
              <button class="icon-button gray" title=${t('Bearbeiten')} onClick=${() => setEditingSource(true)}><${Icon} name="pencil" /></button>`
          : html`<input class="field" placeholder=${t('DOI, URL oder Buch...')} value=${stage.sourceURL}
              onInput=${e => set('sourceURL', e.target.value)} onKeyDown=${e => { if (e.key === 'Enter') setEditingSource(false); }} />
              ${url && html`<button class="icon-button green" title=${t('Fertig')} onClick=${() => setEditingSource(false)}><${Icon} name="checkmark.circle.fill" /></button>`}`}
      </div>
      <${LaTeXEditor} title=${t('Zusammenfassung')} value=${stage.summary} onChange=${v => set('summary', v)} onContextMenu=${textMenu('summary')} />
      <${ReactionImage} data=${stage.reactionImageData} onChange=${v => update(s => { const o = { ...s }; if (v) o.reactionImageData = v; else delete o.reactionImageData; return o; })} />
      <${ChemicalTable} eid=${eid} stage=${stage} showSmartExtract=${showSmartExtract} setShowSmartExtract=${setShowSmartExtract} />
      <${LaTeXEditor} title=${t('Vorgehen')} value=${stage.procedure} onChange=${v => set('procedure', v)} onContextMenu=${textMenu('procedure')} boldCompoundNumbers=${true} />
      <${LaTeXEditor} title=${t('Beobachtung')} value=${stage.observation} onChange=${v => set('observation', v)} onContextMenu=${textMenu('observation')} boldCompoundNumbers=${true} />
      <${YieldTable} eid=${eid} stage=${stage} />
      <${AnalysisSection} entries=${stage.analyses || []} onChange=${fn => update(s => ({ ...s, analyses: fn(s.analyses || []) }))} />
    </div>`}
  </div>`;
}

// MARK: Reaktionsgleichung ------------------------------------------------------------------------------

const MIME = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', webp: 'image/webp', bmp: 'image/bmp', svg: 'image/svg+xml' };

function sniffMime(base64) {
  const head = atob(base64.slice(0, 24));
  if (head.startsWith('\x89PNG')) return 'image/png';
  if (head.startsWith('\xFF\xD8')) return 'image/jpeg';
  if (head.startsWith('GIF8')) return 'image/gif';
  if (head.startsWith('RIFF')) return 'image/webp';
  if (head.startsWith('BM')) return 'image/bmp';
  if (head.includes('<svg') || head.startsWith('<?xml')) return 'image/svg+xml';
  return 'image/png';
}

async function bytesToBase64(bytes) {
  return new Promise(resolve => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(',')[1]);
    reader.readAsDataURL(new Blob([bytes]));
  });
}

/** Erste PDF-Seite als PNG (für ChemDraw-/ChemSketch-Exporte). */
async function pdfFirstPagePNG(bytes) {
  const pdfjs = await import('../vendor/pdf.min.mjs');
  pdfjs.GlobalWorkerOptions.workerSrc = new URL('../vendor/pdf.worker.min.mjs', import.meta.url).href;
  const doc = await pdfjs.getDocument({ data: bytes }).promise;
  const page = await doc.getPage(1);
  const viewport = page.getViewport({ scale: 2 });
  const canvas = document.createElement('canvas');
  canvas.width = Math.ceil(viewport.width); canvas.height = Math.ceil(viewport.height);
  await page.render({ canvasContext: canvas.getContext('2d'), viewport, canvas }).promise;
  return canvas.toDataURL('image/png').split(',')[1];
}

async function fileToImageBase64(name, bytes) {
  if (/\.pdf$/i.test(name) || (bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46)) return pdfFirstPagePNG(bytes);
  return bytesToBase64(bytes);
}

function ReactionImage({ data, onChange }) {
  const [hovering, setHovering] = useState(false);
  const [saved, setSaved] = useState(null);          // gespeicherte ReShiki-Zeichnung zum Bild: { expires, app }
  const [active, setActive] = useState(false);       // ReShiki-Modus (wie ChemDraw auf dem Mac)
  const [importing, setImporting] = useState(false);
  const [copied, setCopied] = useState(false);
  const depth = useRef(0);
  const activeRef = useRef(false);
  activeRef.current = active;

  const refreshSaved = () => { if (data) api.drawingFind(data).then(setSaved); else setSaved(null); };
  useEffect(refreshSaved, [data]);
  const canEdit = !!saved && !active && !importing;
  const editHelp = saved ? t('Zeichnung in {0} öffnen und bearbeiten (möglich bis {1})', 'ReShiki', formatAbbrevTime(new Date(saved.expires))) : '';

  const importFile = async (name, bytes) => {
    try {
      const b64 = await fileToImageBase64(name, bytes);
      if (b64) onChange(b64);
    } catch (e) {
      alertOK(t('Import fehlgeschlagen'), t('Die Datei konnte nicht als Bild gelesen werden.'));
    }
  };

  const onDrop = async e => {
    e.preventDefault();
    depth.current = 0;
    setHovering(false);
    const file = e.dataTransfer.files && e.dataTransfer.files[0];
    if (file) { await importFile(file.name, new Uint8Array(await file.arrayBuffer())); return; }
    const item = [...e.dataTransfer.items].find(i => i.type.startsWith('image/'));
    if (item) { const f = item.getAsFile(); if (f) await importFile('bild', new Uint8Array(await f.arrayBuffer())); }
  };

  // Zwischenablage: eigene Bytes zuerst (dann bleibt die gespeicherte Zeichnung zugeordnet), sonst jedes Bild
  const pasteFromClipboard = async () => {
    const b64 = await api.clipboardReadImage();
    if (b64) { onChange(b64); return; }
    try {
      const items = await navigator.clipboard.read();
      for (const item of items) {
        const type = item.types.find(x => x.startsWith('image/'));
        if (type) { const blob = await item.getType(type); await importFile('bild', new Uint8Array(await blob.arrayBuffer())); return; }
      }
    } catch (e) { /* kein Zugriff */ }
    alertOK(t('Kein Bild in der Zwischenablage'), t('Kopiere ein Reaktionsbild (z. B. aus einem anderen Ansatz) oder eine Zeichnung aus deinem Strukturprogramm und versuche es erneut.'));
  };

  const copyImage = async () => {
    if (!data) return;
    await api.clipboardWriteImage(data);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  const chooseFile = async () => {
    const f = await api.chooseImage();
    if (f) await importFile(f.name, Uint8Array.from(atob(f.base64), c => c.charCodeAt(0)));
  };

  const remove = () => onChange(null);

  // MARK: ReShiki

  const startDrawing = async drawingB64 => {
    const r = await api.reshikiOpen(drawingB64 || null);
    if (r.ok) { setActive(true); return; }
    if (r.error === 'notFound') {
      const i = await ask({ title: t('ReShiki nicht gefunden'),
        message: t('ReShiki ist kostenlos und quelloffen (reshiki.com). Installiere es oder wähle das Programm aus – danach hier einfach erneut klicken.'),
        buttons: [{ label: t('Programm wählen …'), role: 'default' }, { label: t('Abbrechen'), role: 'cancel' }] });
      if (i === 0 && await api.reshikiChoosePath()) startDrawing(drawingB64);
      return;
    }
    alertOK(t('ReShiki konnte nicht gestartet werden'), t('Bitte prüfe in den Einstellungen, welches Programm verwendet wird.'));
  };

  const editDrawing = async () => {
    const d = await api.drawingLoad(data);
    if (!d) { refreshSaved(); return; }
    startDrawing(d.base64);
  };

  const stop = quitApp => { api.reshikiStop(quitApp); setActive(false); refreshSaved(); };

  /** Wie der ChemDraw-Import: gesicherten Stand rendern, als Bild übernehmen, Zeichnung 7 Tage aufheben, Modus beenden. */
  const importNow = async () => {
    if (!activeRef.current || importing) return;
    setImporting(true);
    const r = await api.reshikiImport();
    setImporting(false);
    if (r.error) {
      if (r.error !== 'inactive') alertOK(t('Import fehlgeschlagen'), t('Konnte kein Bild aus ReShiki importieren.\nBitte stelle sicher, dass eine Zeichnung in ReShiki vorhanden ist und mit Strg+S gesichert wurde.'));
      return;
    }
    await api.drawingSave(r.drawing, r.png, 'reShiki');
    onChange(r.png);
    stop(true);
  };

  useEffect(() => {
    // Strg+S in ReShiki (ReShiki sichert Entwürfe getrennt – die Datei ändert sich nur beim Sichern), ReShiki beendet, Strg+D
    const offChanged = api.on('reshiki:changed', () => { if (activeRef.current) importNow(); });
    const offClosed = api.on('reshiki:closed', () => { if (activeRef.current) stop(false); });
    const onImport = () => { if (activeRef.current) importNow(); };
    window.addEventListener('import-drawing', onImport);
    return () => { offChanged(); offClosed(); window.removeEventListener('import-drawing', onImport); };
  });
  useEffect(() => () => { if (activeRef.current) api.reshikiStop(true); }, []);

  const imageMenu = e => openContextMenu(e, [
    { label: t('Bild kopieren'), icon: 'doc.on.doc', action: copyImage },
    { label: t('Bild aus Zwischenablage einfügen'), icon: 'clipboard', action: pasteFromClipboard },
    ...(canEdit ? [{ label: t('In {0} bearbeiten', 'ReShiki'), icon: 'pencil', action: editDrawing }] : []),
    'separator',
    { label: t('Bild entfernen'), icon: 'xmark', destructive: true, action: remove },
  ]);

  return html`<div>
    <div class="section-head">
      <span class="headline">${t('Reaktionsgleichung')}</span><span style="flex:1"></span>
      ${active && html`
        <button class="tint-button green" onClick=${importNow}><${Icon} name="square.and.arrow.down" /> ${t('Zeichnung importieren (Strg+D)')}</button>
        <button class="tint-button gray" onClick=${() => stop(true)}><${Icon} name="xmark.circle" /> ${t('Beenden')}</button>`}
      ${canEdit && html`<button class="tint-button orange" title=${editHelp} onClick=${editDrawing}><${Icon} name="pencil" /> ${t('In {0} bearbeiten', 'ReShiki')}</button>`}
      <button class="tint-button orange" disabled=${active} onClick=${() => startDrawing(null)}><${Icon} name="paintbrush" /> ${t('In {0} zeichnen', 'ReShiki')}</button>
      <button class="tint-button green" onClick=${chooseFile}><${Icon} name="square.and.arrow.down" /> ${t('Datei wählen …')}</button>
    </div>
    <div class=${'drop-zone' + (hovering ? ' hovering' : '') + (active ? ' drawing-active' : '')} tabIndex="0"
      onPaste=${e => { const f = [...e.clipboardData.files][0]; if (f) { e.preventDefault(); f.arrayBuffer().then(b => importFile(f.name, new Uint8Array(b))); } }}
      onDragEnter=${e => { e.preventDefault(); depth.current++; setHovering(true); }}
      onDragOver=${e => e.preventDefault()}
      onDragLeave=${() => { depth.current = Math.max(0, depth.current - 1); if (!depth.current) setHovering(false); }}
      onDrop=${onDrop}>
      ${data
        ? html`<img src=${`data:${sniffMime(data)};base64,${data}`} alt=${t('Reaktionsgleichung')} class=${canEdit ? 'editable' : ''}
            title=${canEdit ? editHelp : ''} onClick=${() => { if (canEdit) editDrawing(); }} onContextMenu=${imageMenu} />
            <button class="remove-image" title=${t('Bild entfernen')} onClick=${remove}><${Icon} name="xmark" /></button>
            <span class="image-copy-area">
              ${copied && html`<span class="copied-badge"><${Icon} name="checkmark" /> ${t('Kopiert')}</span>`}
              <button class="copy-image" title=${t('Bild in die Zwischenablage kopieren – in einem anderen Ansatz mit „Aus Zwischenablage einfügen“ einsetzen')} onClick=${copyImage}>
                <${Icon} name="doc.on.doc" /> ${t('Kopieren')}</button>
            </span>`
        : active
          ? html`<div class="placeholder orange"><span class="big"><${Icon} name="paintbrush" /></span>
              <span class="headline">${t('In ReShiki zeichnen & Strg+S drücken')}</span>
              <span>${t('ReShiki speichert und ChemJournal importiert das Bild automatisch')}</span>
              <span class="caption secondary">${t('Alternativ hier Strg+D oder den Button oben nutzen')}</span></div>`
          : html`<div class="placeholder"><span class="big"><${Icon} name="photo" /></span><span>${t('Bild oder PDF hier ablegen (oder einfügen mit Strg+V)')}</span>
              <button class="link-button" title=${t('Ein kopiertes Reaktionsbild (z. B. aus einem anderen Ansatz) oder eine Zeichnung einfügen')} onClick=${pasteFromClipboard}>
                <${Icon} name="clipboard" />${t('Aus Zwischenablage einfügen')}</button></div>`}
      ${active && data && html`<div class="drawing-banner"><${Icon} name="paintbrush" /><b>${t('ReShiki aktiv')}</b> – ${t('In ReShiki Strg+S drücken oder hier Strg+D zum Importieren')}</div>`}
    </div>
  </div>`;
}

// MARK: Aufreinigung & Analytik --------------------------------------------------------------------------

const A = () => CJ.Analysis;

function AnalysisSection({ entries, onChange }) {
  const add = method => onChange(list => {
    const entry = A().newEntry(method);
    const last = [...list].reverse().find(e => e.method === method);
    if (last) {
      for (const key of A().inherited(method)) if (last.values[key]) entry.values[key] = last.values[key];
      entry.sample = last.sample;
    }
    return list.concat([entry]);
  });
  const addMenu = e => openMenuAt(e.currentTarget, A().GROUPS.flatMap((grp, i) => [
    ...(i ? ['separator'] : []),
    { header: A().groupTitle(grp) },
    ...A().methodsIn(grp).map(m => ({ label: A().title(m), icon: A().symbol(m), action: () => add(m) })),
  ]));
  const update = (id, fn) => onChange(list => list.map(e => (e.id === id ? fn(e) : e)));
  const move = (id, offset) => onChange(list => {
    const i = list.findIndex(e => e.id === id), j = i + offset;
    if (i < 0 || j < 0 || j >= list.length) return list;
    const out = list.slice(); [out[i], out[j]] = [out[j], out[i]]; return out;
  });
  const duplicate = id => onChange(list => {
    const i = list.findIndex(e => e.id === id);
    if (i < 0) return list;
    const copy = { ...list[i], id: uuid(), createdAt: nowRef(), values: { ...list[i].values }, files: list[i].files.map(f => ({ ...f, id: uuid() })) };
    const out = list.slice(); out.splice(i + 1, 0, copy); return out;
  });

  return html`<div class="table-box analysis-box">
    <div class="section-head" style="margin:0">
      <span class="headline">${t('Aufreinigung & Analytik')}</span><span style="flex:1"></span>
      ${entries.length > 0 && html`<button class="link-button" title=${t('Weitere Messung oder Aufreinigung zu dieser Stufe hinzufügen')} onClick=${addMenu}>
        <${Icon} name="plus" />${t('Hinzufügen')}<${Icon} name="chevron.down" /></button>`}
    </div>
    ${entries.length === 0 && html`<div class="analysis-empty">
      <div class="callout secondary">${t('Messung oder Aufreinigungsschritt hinzufügen:')}</div>
      ${A().GROUPS.map(grp => html`<div class="analysis-group" key=${grp}>
        <span class="caption secondary group-title">${A().groupTitle(grp)}</span>
        <span class="badges">${A().methodsIn(grp).map(m => html`<button class=${'method-badge ' + A().group(m)} onClick=${() => add(m)}>
          <${Icon} name=${A().symbol(m)} />${A().title(m)}</button>`)}</span>
      </div>`)}
    </div>`}
    ${entries.map((entry, i) => html`<${AnalysisCard} key=${entry.id} entry=${entry}
      onUpdate=${fn => update(entry.id, fn)} onDelete=${() => onChange(list => list.filter(e => e.id !== entry.id))}
      onDuplicate=${() => duplicate(entry.id)} onMove=${off => move(entry.id, off)} canUp=${i > 0} canDown=${i < entries.length - 1} />`)}
  </div>`;
}

function AnalysisCard({ entry, onUpdate, onDelete, onDuplicate, onMove, canUp, canDown }) {
  const [dropTarget, setDropTarget] = useState(false);
  const [existing, setExisting] = useState({});
  const group = A().group(entry.method);
  const setValue = (key, v) => onUpdate(e => { const values = { ...e.values }; if (v) values[key] = v; else delete values[key]; return { ...e, values }; });
  const fields = A().fields(entry.method);
  const results = A().results(entry);
  const filesKey = entry.files.map(f => f.filePath).join('\n');
  useEffect(() => { api.filesExist(entry.files.map(f => f.filePath)).then(r => setExisting(r || {})); }, [filesKey]);

  const link = paths => onUpdate(e => {
    const files = e.files.slice();
    for (const p of paths) if (p && !files.some(f => f.filePath === p)) files.push({ id: uuid(), filePath: p, description: '' });
    return { ...e, files };
  });
  const choose = async () => link(await api.chooseAnalysisFiles());
  const onDrop = e => {
    e.preventDefault(); setDropTarget(false);
    link([...(e.dataTransfer.files || [])].map(f => api.pathForFile(f)).filter(Boolean));
  };
  const moreMenu = e => openMenuAt(e.currentTarget, [
    { label: t('Duplizieren'), icon: 'doc.on.doc', action: onDuplicate },
    ...(canUp ? [{ label: t('Nach oben'), action: () => onMove(-1) }] : []),
    ...(canDown ? [{ label: t('Nach unten'), action: () => onMove(1) }] : []),
    'separator',
    { label: t('Zusammenfassung kopieren'), icon: 'doc.text', action: () => navigator.clipboard.writeText(A().summary(entry)) },
  ]);

  return html`<div class=${'analysis-card ' + group + (dropTarget ? ' drop-target' : '')}
    onDragOver=${e => { if ([...e.dataTransfer.types].includes('Files')) { e.preventDefault(); setDropTarget(true); } }}
    onDragLeave=${() => setDropTarget(false)} onDrop=${onDrop}>
    <div class="analysis-head">
      <button class=${'disclosure' + (entry.isExpanded ? ' open' : '')} title=${entry.isExpanded ? t('Einklappen') : t('Aufklappen')}
        onClick=${() => onUpdate(e => ({ ...e, isExpanded: !e.isExpanded }))}><${Icon} name="chevron.right" /></button>
      <span class=${'method-icon ' + group}><${Icon} name=${A().symbol(entry.method)} /></span>
      <span class="heading">${A().heading(entry)}</span>
      <input class="plain-field sample" placeholder=${t('Probe')} value=${entry.sample} onInput=${e => onUpdate(x => ({ ...x, sample: e.target.value }))} />
      <span style="flex:1"></span>
      ${!entry.isExpanded && entry.files.length > 0 && html`<span class="caption secondary" title=${t('Verknüpfte Dateien')}><${Icon} name="paperclip" />${entry.files.length}</span>`}
      <button class="icon-button gray" title=${t('Weitere Aktionen')} onClick=${moreMenu}><${Icon} name="ellipsis.circle" /></button>
      <button class="icon-button red" title=${t('Eintrag entfernen (Strg+Z macht es rückgängig)')} onClick=${onDelete}><${Icon} name="trash" /></button>
    </div>
    ${entry.isExpanded
      ? html`<div class="analysis-fields">${fields.filter(f => f.kind !== 'multiline').map(f => html`<${FieldCell} key=${f.key} field=${f} value=${entry.values[f.key] || ''} onChange=${v => setValue(f.key, v)} />`)}</div>
        ${fields.filter(f => f.kind === 'multiline').map(f => html`<div class="analysis-multiline" key=${f.key}>
          <span class="caption secondary">${f.label}</span>
          <${AutoTextArea} value=${entry.values[f.key] || ''} onInput=${v => setValue(f.key, v)} />
        </div>`)}
        ${results.length > 0 && html`<div class="analysis-results">${results.map(r => html`<span class=${'result-chip ' + group}><${Icon} name="function" />${r.label}: ${r.value}</span>`)}</div>`}
        <div class="analysis-files">
          ${entry.files.map(f => html`<${AnalysisFileRow} key=${f.id} file=${f} exists=${existing[f.filePath] !== false}
            onDescription=${v => onUpdate(e => ({ ...e, files: e.files.map(x => (x.id === f.id ? { ...x, description: v } : x)) }))}
            onRemove=${() => onUpdate(e => ({ ...e, files: e.files.filter(x => x.id !== f.id) }))} />`)}
          <button class="link-button" title=${t('Spektrum, Rohdaten oder Ordner verknüpfen – oder Dateien auf die Karte ziehen')} onClick=${choose}>
            <${Icon} name="paperclip" />${entry.method === 'nmr' ? t('NMR-Daten verknüpfen') : t('Datei verknüpfen')}</button>
        </div>`
      : html`<div class="callout secondary analysis-summary">${A().summary(entry)}</div>`}
  </div>`;
}

/** Eingabefeld mit Beschriftung; Vorschläge (⌄) oder Mehrfachauswahl, Einheit dahinter. */
function FieldCell({ field, value, onChange }) {
  const [multiOpen, setMultiOpen] = useState(false);
  const accessory = field.kind === 'choice'
    ? html`<button class="icon-button gray" title=${t('Vorschläge – eigene Eingabe ist auch möglich')} onClick=${e => openMenuAt(e.currentTarget,
        field.options.map(o => ({ label: o, icon: o === value ? 'checkmark' : null, action: () => onChange(o) })))}><${Icon} name="chevron.down" /></button>`
    : field.kind === 'multiChoice'
      ? html`<button class="icon-button gray" title=${t('Einen oder mehrere auswählen – z. B. wenn eine Datei mehrere Spektren enthält')} onClick=${() => setMultiOpen(o => !o)}><${Icon} name="chevron.down" /></button>`
      : field.unit ? html`<span class="secondary unit">${field.unit}</span>` : null;
  return html`<div class="field-cell">
    <span class="caption secondary">${field.label}</span>
    <div class="field-line">
      <input class="field" value=${value} onInput=${e => onChange(e.target.value)} />
      <span class=${'accessory' + (field.unit && field.unit.length > 4 ? ' wide' : '')}>${accessory}</span>
    </div>
    ${multiOpen && html`<${MultiChoice} options=${field.options} value=${value} onChange=${onChange} onClose=${() => setMultiOpen(false)} />`}
  </div>`;
}

/** Mehrfachauswahl (z. B. NMR-Kerne): Häkchen; das Feld bleibt frei editierbar. Reihenfolge der Vorschläge, eigene hinten. */
function MultiChoice({ options, value, onChange, onClose }) {
  const ref = useRef(null);
  const selected = A().list(value);
  useEffect(() => {
    const close = e => { if (ref.current && !ref.current.contains(e.target)) onClose(); };
    setTimeout(() => window.addEventListener('mousedown', close), 0);
    return () => window.removeEventListener('mousedown', close);
  }, []);
  const set = (option, on) => {
    let current = selected.filter(x => x !== option);
    if (on) current = current.concat([option]);
    const known = options.filter(o => current.includes(o)), custom = current.filter(c => !options.includes(c));
    onChange(known.concat(custom).join(', '));
  };
  return html`<div class="multi-choice" ref=${ref}>
    <div class="caption secondary">${t('Mehrfachauswahl möglich')}</div>
    ${options.map(o => html`<label key=${o}><input type="checkbox" checked=${selected.includes(o)} onChange=${e => set(o, e.target.checked)} />${o}</label>`)}
  </div>`;
}

function AutoTextArea({ value, onInput }) {
  const ref = useRef(null);
  useLayoutEffect(() => { const el = ref.current; if (el) { el.style.height = 'auto'; el.style.height = `${Math.max(44, el.scrollHeight)}px`; } });
  return html`<textarea ref=${ref} class="textarea-field analysis-textarea" value=${value} onInput=${e => onInput(e.target.value)}></textarea>`;
}

/** Eine verknüpfte Datei: Name, Beschreibung, Öffnen, im Dateimanager zeigen, entfernen. */
function AnalysisFileRow({ file, exists, onDescription, onRemove }) {
  const baseName = p => p.split(/[\\/]/).pop();
  return html`<div class="file-row">
    <span class=${exists ? 'gray' : 'orange'} title=${exists ? file.filePath : t('Datei nicht gefunden: {0}', file.filePath)}>
      <${Icon} name=${exists ? 'doc.text' : 'exclamationmark.triangle.fill'} /></span>
    <span class="file-name" title=${file.filePath}>${baseName(file.filePath)}</span>
    <input class="field" placeholder=${t('Beschreibung …')} value=${file.description} onInput=${e => onDescription(CJ.applySmartFormatting(e.target.value))} />
    <button class="btn" disabled=${!exists} onClick=${async () => { const err = await api.openPath(file.filePath); if (err) alertOK(t('Datei nicht gefunden'), t('{0} konnte nicht geöffnet werden.', file.filePath)); }}>${t('Öffnen')}</button>
    <button class="icon-button gray" disabled=${!exists} title=${t('Im Dateimanager zeigen')} onClick=${() => api.showItem(file.filePath)}><${Icon} name="folder" /></button>
    <button class="icon-button gray" title=${t('Verknüpfung entfernen (die Datei bleibt erhalten)')} onClick=${onRemove}><${Icon} name="xmark.circle" /></button>
  </div>`;
}

export function duplicateStage(stage) {
  return { ...stage, id: uuid(), title: stage.title + t(' (Kopie)'), createdAt: nowRef() };
}
