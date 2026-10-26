// Stufe eines Ansatzes – entspricht StageView.swift, ReactionImageView.swift, AnalysisFilesView.swift.
import { html, CJ, api, t, useState, useRef, uuid, nowRef, refToDate, formatLong, formatAbbrevTime } from './lib.js';
import { Icon } from './icons.js';
import { ask, openContextMenu, alertOK } from './ui.js';
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
      <${LaTeXEditor} title=${t('Vorgehen')} value=${stage.procedure} onChange=${v => set('procedure', v)} onContextMenu=${textMenu('procedure')} />
      <${LaTeXEditor} title=${t('Beobachtung')} value=${stage.observation} onChange=${v => set('observation', v)} onContextMenu=${textMenu('observation')} />
      <${YieldTable} eid=${eid} stage=${stage} />
      <${AnalysisFiles} files=${stage.analysisFiles} onChange=${fn => update(s => ({ ...s, analysisFiles: fn(s.analysisFiles) }))} />
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
  const depth = useRef(0);

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

  const pasteFromClipboard = async () => {
    try {
      const items = await navigator.clipboard.read();
      for (const item of items) {
        const type = item.types.find(t => t.startsWith('image/'));
        if (type) { const blob = await item.getType(type); await importFile('bild', new Uint8Array(await blob.arrayBuffer())); return; }
      }
      alertOK(t('Kein Bild in der Zwischenablage'), t('Kopiere die Zeichnung in deinem Strukturprogramm (z. B. ChemSketch, MarvinSketch oder Ketcher) und versuche es erneut.'));
    } catch (e) {
      alertOK(t('Kein Bild in der Zwischenablage'), t('Die Zwischenablage enthält kein Bild.'));
    }
  };

  const chooseFile = async () => {
    const f = await api.chooseImage();
    if (f) await importFile(f.name, Uint8Array.from(atob(f.base64), c => c.charCodeAt(0)));
  };

  const remove = () => onChange(null);

  return html`<div>
    <div class="section-head">
      <span class="headline">${t('Reaktionsgleichung')}</span><span style="flex:1"></span>
      <button class="tint-button green" onClick=${chooseFile}><${Icon} name="square.and.arrow.down" /> ${t('Datei wählen …')}</button>
      <button class="tint-button orange" onClick=${pasteFromClipboard}><${Icon} name="clipboard" /> ${t('Aus Zwischenablage einfügen')}</button>
    </div>
    <div class=${'drop-zone' + (hovering ? ' hovering' : '')} tabIndex="0"
      onPaste=${e => { const f = [...e.clipboardData.files][0]; if (f) { e.preventDefault(); f.arrayBuffer().then(b => importFile(f.name, new Uint8Array(b))); } }}
      onDragEnter=${e => { e.preventDefault(); depth.current++; setHovering(true); }}
      onDragOver=${e => e.preventDefault()}
      onDragLeave=${() => { depth.current = Math.max(0, depth.current - 1); if (!depth.current) setHovering(false); }}
      onDrop=${onDrop}>
      ${data
        ? html`<img src=${`data:${sniffMime(data)};base64,${data}`} alt=${t('Reaktionsgleichung')}
            onContextMenu=${e => openContextMenu(e, [{ label: t('Bild entfernen'), icon: 'xmark', destructive: true, action: remove }])} />
            <button class="remove-image" title=${t('Bild entfernen')} onClick=${remove}><${Icon} name="xmark" /></button>`
        : html`<div class="placeholder"><span class="big"><${Icon} name="photo" /></span><span>${t('Bild oder PDF hier ablegen (oder einfügen mit Strg+V)')}</span></div>`}
    </div>
  </div>`;
}

// MARK: Analyse & Daten ---------------------------------------------------------------------------------

function AnalysisFiles({ files, onChange }) {
  const add = async () => {
    const paths = await api.chooseAnalysisFiles();
    onChange(list => {
      const out = list.slice();
      for (const p of paths) if (!out.some(f => f.filePath === p)) out.push({ id: uuid(), filePath: p, description: '' });
      return out;
    });
  };
  const baseName = p => p.split(/[\\/]/).pop();
  return html`<div class="table-box files-box">
    <span class="headline">${t('Analyse & Daten')}</span>
    <div style="display:flex;flex-direction:column;gap:8px">
      ${files.map(f => html`<div class="file-row" key=${f.id}>
        <span class="gray"><${Icon} name="doc.text" /></span>
        <span class="file-name" title=${f.filePath}>${baseName(f.filePath)}</span>
        <input class="field" placeholder=${t('Beschreibung...')} value=${f.description}
          onInput=${e => { const v = CJ.applySmartFormatting(e.target.value); onChange(list => list.map(x => (x.id === f.id ? { ...x, description: v } : x))); }} />
        <button class="btn" onClick=${async () => { const err = await api.openPath(f.filePath); if (err) alertOK(t('Datei nicht gefunden'), t('{0} konnte nicht geöffnet werden.', f.filePath)); }}>${t('Öffnen')}</button>
        <button class="icon-button red" onClick=${() => onChange(list => list.filter(x => x.id !== f.id))}><${Icon} name="trash" /></button>
      </div>`)}
    </div>
    <button class="plain-add blue" style="padding:4px 0 0" onClick=${add}><${Icon} name="plus" /> ${t('Dateien verknüpfen')}</button>
  </div>`;
}

export function duplicateStage(stage) {
  return { ...stage, id: uuid(), title: stage.title + t(' (Kopie)'), createdAt: nowRef() };
}
