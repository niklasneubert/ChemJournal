// Seitenleiste, Detailansichten, Verlauf und Einstellungen – entspricht ContentView.swift, ExperimentDetailView.swift,
// ProjectDetailView.swift, VersionHistoryView.swift und SettingsView.swift.
import { html, CJ, api, t, useState, useEffect, useRef, nowRef, refToDate, newStage, formatLong, formatAbbrevTime, formatNumeric, formatTime, formatBytes } from './lib.js';
import { Icon } from './icons.js';
import { Sheet, ask, askText, openContextMenu, openMenuAt } from './ui.js';
import { store } from './store.js';
import { StageView, duplicateStage } from './stage.js';
import { RichText } from './latex.js';

// MARK: Seitenleiste ---------------------------------------------------------------------------------------

export function Sidebar({ selection, setSelection, actions }) {
  const [query, setQuery] = useState('');
  const [width, setWidth] = useState(250);
  const [dropTarget, setDropTarget] = useState(null);
  // Filter: nur markierte Ansätze und/oder nur Ansätze mit diesem Tag
  const [filterMarked, setFilterMarked] = useState(false);
  const [filterTag, setFilterTag] = useState(null);
  const projects = store.projects;
  const tags = CJ.Tags.all(projects);
  const isFiltering = filterMarked || filterTag !== null;
  const clearFilter = () => { setFilterMarked(false); setFilterTag(null); };
  // Tag umbenannt oder gelöscht: Filter darauf aufheben
  useEffect(() => { if (filterTag !== null && !tags.some(x => CJ.Tags.same(x, filterTag))) setFilterTag(null); });
  useEffect(() => {
    const onFilter = e => setFilterTag(e.detail);
    window.addEventListener('filter-by-tag', onFilter);
    return () => window.removeEventListener('filter-by-tag', onFilter);
  }, []);

  // Suche (gleiche Logik wie JournalSearch auf dem Mac)
  const q = query.trim();
  let filtered = projects, hits = {};
  if (q) {
    const search = CJ.JournalSearch(q, projects, term => [...store.casEntries.values()]
      .filter(e => CJ.normalizeSearch(e.name).includes(term)).map(e => e.cas));
    filtered = projects.map(p => {
      const projectMatches = p.title.toLowerCase().includes(q.toLowerCase());
      const matching = [];
      for (const e of p.experiments) { const h = search.hits(e); if (h) { matching.push(e); hits[e.id] = h; } }
      if (!projectMatches && !matching.length) return null;
      return projectMatches ? p : { ...p, experiments: matching };
    }).filter(Boolean);
  }
  if (isFiltering) {
    const passes = e => (!filterMarked || e.isMarked) && (filterTag === null || CJ.Tags.hasTag(e, filterTag));
    filtered = filtered.map(p => ({ ...p, experiments: p.experiments.filter(passes) })).filter(p => p.experiments.length);
  }

  const filterMenu = e => openMenuAt(e.currentTarget, [
    { label: t('Nur markierte'), icon: filterMarked ? 'checkmark' : 'star', action: () => setFilterMarked(m => !m) },
    ...(tags.length ? ['separator', { header: t('Tag') },
      { label: t('Alle Tags'), icon: filterTag === null ? 'checkmark' : null, action: () => setFilterTag(null) },
      ...tags.map(tag => ({ label: tag, icon: filterTag !== null && CJ.Tags.same(tag, filterTag) ? 'checkmark' : null, action: () => setFilterTag(tag) }))] : []),
    ...(isFiltering ? ['separator', { label: t('Filter aufheben'), action: clearFilter }] : []),
  ]);

  const onResize = e => {
    e.preventDefault();
    const startX = e.clientX, startW = width;
    const move = ev => setWidth(Math.min(400, Math.max(150, startW + ev.clientX - startX)));
    const up = () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up); };
    window.addEventListener('mousemove', move); window.addEventListener('mouseup', up);
  };

  const dragStart = (e, eid) => { e.dataTransfer.setData('text/chemjournal-experiment', eid); e.dataTransfer.effectAllowed = 'move'; };
  const dropOnProject = (e, pid) => {
    e.preventDefault(); setDropTarget(null);
    const eid = e.dataTransfer.getData('text/chemjournal-experiment');
    if (eid) actions.moveExperiment(eid, pid);
  };
  const dropOnExperiment = (e, pid, targetEid) => {
    e.preventDefault(); e.stopPropagation(); setDropTarget(null);
    const eid = e.dataTransfer.getData('text/chemjournal-experiment');
    if (!eid || eid === targetEid) return;
    if (q || isFiltering) return;   // während Suche oder Filter zeigen die Positionen auf die gefilterte Liste
    actions.reorderExperiment(eid, pid, targetEid);
  };

  return html`<div class="sidebar" style=${{ width: `${width}px` }}>
    <div class="sidebar-toolbar">
      <button class="toolbar-button" title=${t('Neu')} onClick=${e => openMenuAt(e.currentTarget, [
        { label: t('Neues Projekt'), icon: 'folder.badge.plus', action: actions.addProject },
        { label: t('Neuer Ansatz'), icon: 'doc.badge.plus', action: actions.addExperiment },
        'separator',
        { label: t('Ansatz importieren (.chemjournal)'), icon: 'square.and.arrow.down', action: actions.importExperiment },
      ])}><${Icon} name="plus" /></button>
      <button class=${'toolbar-button' + (isFiltering ? ' active' : '')} title=${t('Ansätze nach Markierung oder Tag filtern')} onClick=${filterMenu}>
        <${Icon} name=${isFiltering ? 'line.3.horizontal.decrease.circle.fill' : 'line.3.horizontal.decrease.circle'} /></button>
    </div>
    <div class="search-field">
      <${Icon} name="magnifyingglass" />
      <input placeholder=${t('Suchen: Ansatz, Chemikalie, CAS …')} value=${query} onInput=${e => setQuery(e.target.value)}
        onKeyDown=${e => { if (e.key === 'Escape') setQuery(''); }} />
      ${query && html`<button class="search-clear" onClick=${() => setQuery('')}><${Icon} name="xmark.circle" /></button>`}
    </div>
    ${isFiltering && html`<div class="filter-banner">
      <span class="accent"><${Icon} name="line.3.horizontal.decrease.circle.fill" /></span>
      ${filterMarked && html`<span class="secondary"><${Icon} name="star.fill" /> ${t('Markiert')}</span>`}
      ${filterTag !== null && html`<${TagChip} name=${filterTag} compact=${true} />`}
      <span style="flex:1"></span>
      <button class="search-clear" title=${t('Filter aufheben')} onClick=${clearFilter}><${Icon} name="xmark.circle" /></button>
    </div>`}
    <div class="sidebar-list">
      ${isFiltering && !filtered.length && html`<div class="callout secondary" style="padding:8px 12px">${t('Keine Ansätze für diesen Filter')}</div>`}
      ${filtered.map(p => {
        const expanded = (projects.find(x => x.id === p.id) || p).isExpanded;
        const sel = selection && selection.kind === 'project' && selection.id === p.id;
        return html`<div key=${p.id}>
          <div class=${'project-row' + (sel ? ' selected' : '') + (dropTarget === p.id ? ' drop-target' : '')}
            onClick=${() => setSelection({ kind: 'project', id: p.id })}
            onContextMenu=${e => openContextMenu(e, [{ label: t('Projekt löschen'), icon: 'trash', destructive: true, action: () => actions.deleteProject(p.id) }])}
            onDragOver=${e => { e.preventDefault(); setDropTarget(p.id); }} onDragLeave=${() => setDropTarget(null)} onDrop=${e => dropOnProject(e, p.id)}>
            <button class=${'disclosure' + (expanded ? ' open' : '')} onClick=${e => { e.stopPropagation(); store.updateProject(p.id, x => ({ ...x, isExpanded: !x.isExpanded }), { undo: false }); }}><${Icon} name="chevron.right" /></button>
            <span class="label"><span class="folder"><${Icon} name="folder" /></span><span class="headline row-title">${p.title}</span></span>
          </div>
          ${(expanded || q) && p.experiments.map(e => {
            const esel = selection && selection.kind === 'experiment' && selection.id === e.id;
            const h = hits[e.id] || [];
            return html`<div key=${e.id} class=${'experiment-row' + (esel ? ' selected' : '') + (dropTarget === e.id ? ' drop-before' : '')}
              draggable="true" onDragStart=${ev => dragStart(ev, e.id)}
              onDragOver=${ev => { ev.preventDefault(); ev.stopPropagation(); setDropTarget(e.id); }} onDragLeave=${() => setDropTarget(null)}
              onDrop=${ev => dropOnExperiment(ev, p.id, e.id)}
              onClick=${() => setSelection({ kind: 'experiment', id: e.id })}
              onContextMenu=${ev => openContextMenu(ev, [
                { label: e.isMarked ? t('Markierung entfernen') : t('Markieren'), icon: 'star', action: () => store.updateExperiment(e.id, x => ({ ...x, isMarked: !x.isMarked, updatedAt: nowRef() })) },
                { header: t('Tags') },
                ...tags.map(tag => ({ label: tag, icon: CJ.Tags.hasTag(e, tag) ? 'checkmark' : null,
                  action: () => store.updateExperiment(e.id, x => ({ ...(CJ.Tags.hasTag(x, tag) ? CJ.Tags.removeTag(x, tag) : (CJ.Tags.addTag(x, tag) || x)), updatedAt: nowRef() })) })),
                { label: t('Neuer Tag …'), icon: 'tag', action: () => addNewTag(e.id, tags) },
                'separator',
                { label: t('Ansatz duplizieren'), icon: 'doc.on.doc', action: () => actions.duplicateExperiment(e.id) },
                { label: t('Als .chemjournal exportieren'), icon: 'square.and.arrow.up', action: () => actions.exportExperimentAsFile(e.id) },
                'separator',
                { label: t('Ansatz löschen'), icon: 'trash', destructive: true, action: () => actions.deleteExperiment(e.id) },
              ])}>
              <div class="content">
                <span class="headline title-line"><span class="line">${e.title || t('Unbenannter Ansatz')}</span>${e.isMarked && html`<span class="star" title=${t('Markiert')}><${Icon} name="star.fill" /></span>`}</span>
                <span class="subheadline secondary line">${e.summary || t('Keine Beschreibung')}</span>
                <span class="caption2 secondary">${formatLong(refToDate(e.createdAt))}</span>
                ${(e.tags || []).length > 0 && html`<span class="tag-line">${e.tags.slice(0, 3).map(tag => html`<${TagChip} key=${tag} name=${tag} compact=${true} />`)}
                  ${e.tags.length > 3 && html`<span class="caption2 secondary">+${e.tags.length - 3}</span>`}</span>`}
                ${h.slice(0, 3).map(label => html`<span class="caption2 hit line"><${Icon} name="magnifyingglass" />${label}</span>`)}
                ${h.length > 3 && html`<span class="caption2 secondary">${t('+ {0} weitere Treffer', h.length - 3)}</span>`}
              </div>
            </div>`;
          })}
        </div>`;
      })}
    </div>
    <div class="sidebar-resize" onMouseDown=${onResize}></div>
  </div>`;
}

// MARK: Tags (wie TagViews.swift) ---------------------------------------------------------------------------

/** Farbige Kapsel mit dem Tag-Namen (feste Farbe je Name), optional mit Entfernen-Knopf. */
export function TagChip({ name, compact = false, onRemove, onContextMenu }) {
  return html`<span class=${'tag-chip tag-' + CJ.Tags.color(name) + (compact ? ' compact' : '')} onContextMenu=${onContextMenu}>
    ${name}${onRemove && html`<button title=${t('Tag von diesem Ansatz entfernen')} onClick=${onRemove}><${Icon} name="xmark" /></button>`}</span>`;
}

/** Gleicher Name in anderer Schreibweise: die vorhandene übernehmen. */
const canonicalTag = (raw, tags) => { const c = CJ.Tags.clean(raw); return c ? tags.find(x => CJ.Tags.same(x, c)) || c : null; };

async function addNewTag(eid, tags) {
  const name = await askText({ title: t('Neuer Tag'), message: t('Name des Tags, z. B. „Photokatalyse“ oder „Scale-up“.'), placeholder: t('Name des Tags'), confirm: t('Hinzufügen') });
  const tag = name && canonicalTag(name, tags);
  if (tag) store.updateExperiment(eid, e => ({ ...(CJ.Tags.addTag(e, tag) || e), updatedAt: nowRef() }));
}

async function renameTag(tag) {
  const name = await askText({ title: t('Tag „{0}“ umbenennen', tag), message: t('Der neue Name gilt in allen Ansätzen mit diesem Tag.'), defaultValue: tag, confirm: t('Umbenennen') });
  if (name && CJ.Tags.clean(name)) store.setProjects(CJ.Tags.rename(store.projects, tag, name));
}

async function deleteTagEverywhere(tag) {
  const count = store.projects.flatMap(p => p.experiments).filter(e => CJ.Tags.hasTag(e, tag)).length;
  const i = await ask({ title: t('Tag „{0}“ überall löschen?', tag), message: t('Der Tag wird von {0} Ansätzen entfernt. Die Ansätze selbst bleiben erhalten.', count),
    buttons: [{ label: t('Löschen'), role: 'destructive' }, { label: t('Abbrechen'), role: 'cancel' }] });
  if (i === 0) store.setProjects(CJ.Tags.remove(store.projects, tag));
}

/** Tags im Kopf eines Ansatzes: anzeigen, hinzufügen, entfernen, überall umbenennen oder löschen. */
function TagBar({ experiment }) {
  const [adding, setAdding] = useState(false);
  const [text, setText] = useState('');
  const ref = useRef(null);
  const eid = experiment.id;
  const allTags = CJ.Tags.all(store.projects);
  const typed = text.trim();
  const suggestions = allTags.filter(tag => !CJ.Tags.hasTag(experiment, tag) && (!typed || tag.toLowerCase().includes(typed.toLowerCase())));
  const add = raw => {
    const tag = canonicalTag(raw, allTags);
    if (tag) store.updateExperiment(eid, e => ({ ...(CJ.Tags.addTag(e, tag) || e), updatedAt: nowRef() }));
    setText(''); setAdding(false);
  };
  const remove = tag => store.updateExperiment(eid, e => ({ ...CJ.Tags.removeTag(e, tag), updatedAt: nowRef() }));
  useEffect(() => {
    if (!adding) return undefined;
    const close = e => { if (ref.current && !ref.current.contains(e.target)) setAdding(false); };
    setTimeout(() => window.addEventListener('mousedown', close), 0);
    return () => window.removeEventListener('mousedown', close);
  }, [adding]);
  return html`<div class="tag-bar">
    ${(experiment.tags || []).map(tag => html`<${TagChip} key=${tag} name=${tag} onRemove=${() => remove(tag)} onContextMenu=${e => openContextMenu(e, [
      { label: t('Nur Ansätze mit diesem Tag zeigen'), icon: 'line.3.horizontal.decrease.circle', action: () => window.dispatchEvent(new CustomEvent('filter-by-tag', { detail: tag })) },
      'separator',
      { label: t('Umbenennen …'), icon: 'pencil', action: () => renameTag(tag) },
      { label: t('Von diesem Ansatz entfernen'), icon: 'xmark', action: () => remove(tag) },
      { label: t('Überall löschen …'), icon: 'trash', destructive: true, action: () => deleteTagEverywhere(tag) },
    ])} />`)}
    <span class="tag-add" ref=${ref}>
      <button class="link-button" title=${t('Eigenen Tag vergeben, um Ansätze einzuordnen')} onClick=${() => { setText(''); setAdding(a => !a); }}>
        <${Icon} name="plus" />${(experiment.tags || []).length ? t('Tag') : t('Tag hinzufügen')}</button>
      ${adding && html`<div class="tag-popover">
        <input class="field" placeholder=${t('Neuer oder vorhandener Tag')} value=${text} onInput=${e => setText(e.target.value)}
          onKeyDown=${e => { if (e.key === 'Enter') add(text); if (e.key === 'Escape') setAdding(false); }} ref=${el => el && !el.dataset.f && (el.dataset.f = 1, el.focus())} />
        ${suggestions.length > 0 && html`<div class="caption secondary">${t('Vorhandene Tags')}</div>
          <div class="tag-line">${suggestions.map(tag => html`<button class="plain" key=${tag} onClick=${() => add(tag)}><${TagChip} name=${tag} /></button>`)}</div>`}
        <div class="caption2 secondary">${t('Return übernimmt den Namen. Tags gelten für das ganze Journal.')}</div>
      </div>`}
    </span>
  </div>`;
}

// MARK: Ansatz ---------------------------------------------------------------------------------------------

export function DetailView({ project, experiment }) {
  const [showHistory, setShowHistory] = useState(false);
  const eid = experiment.id;
  const hasYields = experiment.stages.some(s => s.yieldProducts.length);
  useEffect(() => { api.setSnapWidths(hasYields ? [1024, 1260] : [1024]); }, [hasYields]);

  const setField = (field, value) => store.updateExperiment(eid, e => ({ ...e, [field]: value, updatedAt: nowRef() }));
  const setStages = fn => store.updateExperiment(eid, e => ({ ...e, stages: fn(e.stages) }));
  const neededWidth = hasYields ? 960 : 780;

  return html`<div class="scroll">
    <div class="detail-content" style=${{ minWidth: `${neededWidth}px` }}>
      <input class="plain-field exp-title" placeholder=${t('Titel des Ansatzes')} value=${experiment.title} onInput=${e => setField('title', e.target.value)} />
      <input class="plain-field exp-summary" placeholder=${t('Kurze Zusammenfassung')} value=${experiment.summary} onInput=${e => setField('summary', e.target.value)} />
      <div class="meta-row">
        <span class="item"><${Icon} name="calendar" />${formatLong(refToDate(experiment.createdAt))}</span>
        <button class="link-button" title=${t('Frühere Versionen dieses Ansatzes ansehen und wiederherstellen')} onClick=${() => setShowHistory(true)}>
          <${Icon} name="clock.arrow.circlepath" />${t('Verlauf')}</button>
        <button class=${'link-button mark-button' + (experiment.isMarked ? ' marked' : '')} title=${experiment.isMarked ? t('Markierung entfernen') : t('Ansatz markieren')}
          onClick=${() => store.updateExperiment(eid, e => ({ ...e, isMarked: !e.isMarked, updatedAt: nowRef() }))}>
          <${Icon} name=${experiment.isMarked ? 'star.fill' : 'star'} />${experiment.isMarked ? t('Markiert') : t('Markieren')}</button>
      </div>
      <${TagBar} experiment=${experiment} />
      <div class="divider"></div>
      <div>
        ${experiment.stages.map(stage => html`<${StageView} key=${stage.id} eid=${eid} stage=${stage}
          onDelete=${() => setStages(list => list.filter(s => s.id !== stage.id))}
          onDuplicate=${() => setStages(list => { const i = list.findIndex(s => s.id === stage.id); const out = list.slice(); out.splice(i + 1, 0, duplicateStage(stage)); return out; })} />`)}
        <button class="add-stage" onClick=${() => setStages(list => list.concat([newStage(t('Stufe {0}', list.length + 1))]))}>
          <${Icon} name="plus.circle.fill" />${t('Neue Stufe hinzufügen')}</button>
      </div>
    </div>
    ${showHistory && html`<${VersionHistory} experimentID=${eid} currentTitle=${experiment.title} onClose=${() => setShowHistory(false)} />`}
  </div>`;
}

export function ProjectDetail({ project, onAddExperiment }) {
  useEffect(() => { api.setSnapWidths([1024]); }, []);
  return html`<div class="project-detail">
    <span class="big-folder"><${Icon} name="folder.fill" /></span>
    <input class="plain-field" placeholder=${t('Projektname')} value=${project.title} onInput=${e => store.updateProject(project.id, p => ({ ...p, title: e.target.value }))} />
    <div class="title2 secondary">${t('{0} Ansätze in diesem Projekt', project.experiments.length)}</div>
    <button class="primary-big" onClick=${onAddExperiment}><${Icon} name="plus.circle.fill" />${t('Neuen Ansatz erstellen')}</button>
  </div>`;
}

// MARK: Versionsverlauf ------------------------------------------------------------------------------------

function VersionRow({ info, selected, onClick }) {
  return html`<div class=${'list-item' + (selected ? ' selected' : '')} onClick=${onClick}>
    <span class="mono" style="display:flex;gap:4px;align-items:center">${formatAbbrevTime(new Date(info.date))}
      ${info.pinned && html`<span class="orange caption" title=${t('Wird nie automatisch entfernt')}><${Icon} name="pin.fill" /></span>`}</span>
    <span class="caption secondary">${t(info.reason)}</span>
    <span class="caption tertiary">${info.stageCount === 1 ? t('1 Stufe · {0} Chemikalien', info.chemicalCount) : t('{0} Stufen · {1} Chemikalien', info.stageCount, info.chemicalCount)}</span>
  </div>`;
}

export function VersionPreview({ snapshot }) {
  const e = snapshot.experiment;
  const line = (name, cas, values) => {
    let s = name || '–';
    if (cas) s += ` (${cas})`;
    const v = values.filter(Boolean);
    if (v.length) s += ' · ' + v.join(' · ');
    return s;
  };
  return html`<div class="preview-pane">
    <div class="title2" style="font-weight:700">${e.title || t('Ohne Titel')}</div>
    ${e.summary && html`<div class="secondary">${e.summary}</div>`}
    ${snapshot.projectTitle && html`<div class="caption secondary" style="display:flex;gap:4px;align-items:center"><${Icon} name="folder" />${snapshot.projectTitle}</div>`}
    ${e.stages.map(s => html`<div class="preview-stage" key=${s.id}>
      <div class="headline">${s.title}</div>
      ${s.chemicals.map(c => html`<div>${line(c.name, c.cas, [c.equivalents ? `${c.equivalents} eq` : '', c.mass, c.volume, c.amount])}</div>`)}
      ${s.yieldProducts.map(y => html`<div class="secondary">${t('Produkt: ')}${line(y.name, y.cas, [y.mass, y.amount])}</div>`)}
      ${s.procedure && html`<${RichText} class="secondary" text=${s.procedure} />`}
      ${s.observation && html`<div class="secondary">${t('Beobachtung: ')}${s.observation}</div>`}
    </div>`)}
  </div>`;
}

function VersionHistory({ experimentID, currentTitle, onClose }) {
  const [versions, setVersions] = useState(null);
  const [selected, setSelected] = useState(null);
  const [snapshot, setSnapshot] = useState(null);
  useEffect(() => { (async () => { await store.saveNow(); const v = await api.versions(experimentID); setVersions(v); setSelected(v[0] || null); })(); }, []);
  useEffect(() => { let c = false; setSnapshot(null); if (selected) api.loadSnapshot(selected).then(s => { if (!c) setSnapshot(s); }); return () => { c = true; }; }, [selected]);

  const restore = async asCopy => {
    if (!snapshot) return;
    if (!asCopy) {
      const i = await ask({ title: t('Diesen Stand wiederherstellen?'), message: t('Der aktuelle Stand wird vorher selbst als Version gesichert und bleibt im Verlauf.'),
        buttons: [{ label: t('Wiederherstellen'), role: 'default' }, { label: t('Abbrechen'), role: 'cancel' }] });
      if (i !== 0) return;
    }
    const id = await restoreSnapshot(snapshot, asCopy);
    onClose();
    if (asCopy) window.dispatchEvent(new CustomEvent('select-experiment', { detail: id }));
  };

  return html`<${Sheet} onClose=${onClose} width=${820} height=${560} padded=${false}>
    <div style="padding:14px 20px"><div class="headline">${t('Verlauf')}</div><div class="subheadline secondary">${currentTitle}</div></div>
    ${versions === null ? html`<div class="unavailable"><span class="spinner"></span></div>`
      : versions.length === 0 ? html`<div class="unavailable" style="border-top:1px solid var(--separator);border-bottom:1px solid var(--separator)">
          <span class="big"><${Icon} name="clock.arrow.circlepath" /></span><span class="title">${t('Noch keine Versionen')}</span>
          <span>${t('ChemJournal sichert automatisch: beim ersten Speichern, danach höchstens alle 10 Minuten, wenn sich etwas geändert hat, und beim Beenden.')}</span></div>`
      : html`<div class="split-pane">
          <div class="list-pane">${versions.map(v => html`<${VersionRow} key=${v.file} info=${v} selected=${selected && selected.file === v.file} onClick=${() => setSelected(v)} />`)}</div>
          ${snapshot ? html`<${VersionPreview} snapshot=${snapshot} />` : html`<div class="unavailable"><span class="spinner"></span></div>`}
        </div>`}
    <div class="modal-actions" style="padding:12px 20px">
      <span class="caption secondary" style="flex:1">${t('Ältere Versionen werden ausgedünnt: 24 h alle, 30 Tage eine pro Tag, danach eine pro Woche.')}</span>
      <button class="btn" onClick=${onClose}>${t('Schließen')}</button>
      <button class="btn" disabled=${!snapshot} title=${t('Diese Version als zusätzlichen Ansatz einfügen – der aktuelle Stand bleibt unverändert')} onClick=${() => restore(true)}>${t('Als Kopie hinzufügen')}</button>
      <button class="btn primary" disabled=${!snapshot} onClick=${() => restore(false)}>${t('Wiederherstellen …')}</button>
    </div>
  <//>`;
}

/** Stellt eine Version wieder her (wie JournalStore.restore). Gibt die ID des wiederhergestellten Ansatzes zurück. */
export async function restoreSnapshot(snap, asCopy) {
  let experiment = snap.experiment;
  if (asCopy) {
    const stamp = formatAbbrevTime(new Date(snap.date));
    experiment = { ...experiment, id: crypto.randomUUID().toUpperCase(), title: experiment.title + t(' (Version vom {0})', stamp),
      stages: experiment.stages.map(s => ({ ...s, id: crypto.randomUUID().toUpperCase() })), updatedAt: nowRef() };
    insertExperiment(experiment, snap.projectID, snap.projectTitle);
    return experiment.id;
  }
  const found = store.findExperiment(experiment.id);
  if (found) {
    await api.snapshot(found.experiment, found.project, 'Vor dem Wiederherstellen', true);
    store.updateExperiment(experiment.id, () => ({ ...experiment, updatedAt: nowRef() }));
  } else {
    insertExperiment(experiment, snap.projectID, snap.projectTitle);
  }
  return experiment.id;
}

function insertExperiment(experiment, projectID, projectTitle) {
  const projects = store.projects;
  let target = projects.find(p => p.id === projectID) || (projectTitle && projects.find(p => p.title === projectTitle));
  if (target) {
    store.updateProject(target.id, p => ({ ...p, isExpanded: true, experiments: p.experiments.concat([experiment]) }));
  } else {
    store.setProjects(projects.concat([{ id: crypto.randomUUID().toUpperCase(), title: projectTitle || t('Wiederhergestellt'), isExpanded: true, experiments: [experiment] }]));
  }
}

// MARK: Einstellungen --------------------------------------------------------------------------------------

export function Settings({ onClose }) {
  const [tab, setTab] = useState('storage');
  const tabs = [['general', 'gearshape', t('Allgemein')], ['storage', 'externaldrive', t('Speicherort & Backups')], ['deleted', 'trash', t('Gelöschte Ansätze')], ['cas', 'flask', t('CAS-Datenbank')]];
  return html`<${Sheet} onClose=${onClose} width=${640} height=${540} padded=${false}>
    <div class="tabs">${tabs.map(([id, icon, label]) => html`<button class=${'tab' + (tab === id ? ' active' : '')} onClick=${() => setTab(id)}>
      <span class="ic"><${Icon} name=${icon} /></span>${label}</button>`)}</div>
    <div style="flex:1;min-height:0;display:flex;flex-direction:column">
      ${tab === 'general' && html`<${GeneralSettings} />`}
      ${tab === 'storage' && html`<${StorageSettings} />`}
      ${tab === 'deleted' && html`<${DeletedExperiments} />`}
      ${tab === 'cas' && html`<${CASDatabaseView} />`}
    </div>
    <div class="modal-actions" style="padding:10px 16px;border-top:1px solid var(--separator)"><button class="btn primary" onClick=${onClose}>${t('Fertig')}</button></div>
  <//>`;
}

function GeneralSettings() {
  const [language, setLanguage] = useState(api.language);
  const [stored, setStored] = useState(api.language);
  const [reshiki, setReshiki] = useState(null);
  useEffect(() => { api.getLanguage().then(l => { setLanguage(l); setStored(l); }); api.reshikiStatus().then(setReshiki); }, []);
  const choose = async l => { setLanguage(l); await api.setLanguage(l); setStored(l); };
  return html`<div class="modal-body" style="flex:1">
    <div class="form-section">
      <div class="form-row"><span class="label">${t('Sprache')}</span>
        <select class="field" style="width:200px" value=${language} onChange=${e => choose(e.target.value)}>
          <option value="de">Deutsch</option><option value="en">English</option>
        </select></div>
      <div class="caption secondary">${t('Standard ist Deutsch, unabhängig von der Sprache des Rechners. Die Smart-Extract-Texterkennung versteht immer Deutsch und Englisch.')}</div>
      ${stored !== api.language && html`<div class="form-row"><span>${t('Die neue Sprache gilt nach einem Neustart von ChemJournal.')}</span>
        <button class="btn primary" onClick=${() => api.relaunch()}>${t('Jetzt neu starten')}</button></div>`}
    </div>
    <div class="headline">${t('Reaktionsgleichung')}</div>
    <div class="form-section">
      <div class="form-row"><span class="label">${t('Zeichenprogramm')}</span><span>ReShiki</span></div>
      <div class="form-row"><span class="label">${t('Programm')}</span>
        <span style="display:flex;gap:8px;align-items:center">
          ${reshiki && reshiki.path ? html`<${PathButton} path=${reshiki.path} />` : html`<span class="orange">${t('nicht gefunden')}</span>`}
          <button class="btn" onClick=${async () => { await api.reshikiChoosePath(); setReshiki(await api.reshikiStatus()); }}>${t('Wählen …')}</button>
          ${reshiki && reshiki.configured && html`<button class="btn" title=${t('Wieder automatisch im Suchpfad und in ~/Applications suchen')}
            onClick=${async () => { await api.reshikiResetPath(); setReshiki(await api.reshikiStatus()); }}>${t('Automatisch')}</button>`}
        </span></div>
      <div class="caption secondary">${t('Reaktionsgleichungen zeichnest du mit ReShiki (kostenlos und quelloffen, reshiki.com): „In ReShiki zeichnen“, dann in ReShiki Strg+S – das Bild wird übernommen. Gespeicherte Zeichnungen lassen sich 7 Tage lang mit „In ReShiki bearbeiten“ wieder öffnen.')}</div>
    </div>
  </div>`;
}

function PathButton({ path }) {
  const home = path.replace(/^\/home\/[^/]+|^\/Users\/[^/]+/, '~');
  return html`<button class="path-link" title=${t('Im Dateimanager zeigen')} onClick=${() => api.showItem(path)}><bdi dir="ltr">${home}</bdi></button>`;
}

function StorageSettings() {
  const [backups, setBackups] = useState([]);
  const [message, setMessage] = useState(null);
  const [busy, setBusy] = useState(false);
  const [, tick] = useState(0);
  const info = store.storage;
  const reload = async () => setBackups(await api.backups());
  useEffect(() => { reload(); }, [info && info.paths.backupsDirectory]);

  const performSwitch = async (mode, folder, useExisting) => {
    setBusy(true);
    const r = await api.switchStorage(mode, folder, useExisting, store.projects);
    store.storage = r.storage;
    if (r.projects) { store.projects = r.projects; store.clearUndo(); }
    store.setCASEntries(await api.casList());
    setBusy(false);
    setMessage(t('Speicherort: {0}. Die bisherigen Dateien am alten Ort bleiben unverändert liegen.', t(r.storage.modes[mode])));
    tick(t => t + 1);
    store.notify();
    reload();
  };

  const requestSwitch = async (mode, folderOverride) => {
    let folder = folderOverride ?? info.syncFolder;
    if (mode === 'folder' && !folder) { folder = await api.chooseSyncFolder(); if (!folder) return; }
    if (mode === info.mode && folder === info.syncFolder) return;
    await store.saveNow();
    const check = await api.checkSwitch(mode, folder);
    if (check.kind === 'unavailable') { setMessage(t('Der Sync-Ordner ist nicht erreichbar.')); return; }
    if (check.kind === 'targetHasJournal') {
      const date = check.modified ? t(' (zuletzt geändert {0})', formatAbbrevTime(new Date(check.modified))) : '';
      const i = await ask({ title: t('Im Sync-Ordner liegt bereits ein Journal'),
        message: t('Am Ziel gibt es schon ein Journal mit {0} Ansätzen{1}, z. B. von einem anderen Rechner. Die jeweils andere Fassung wird in jedem Fall als Backup aufbewahrt.', check.experiments, date),
        buttons: [{ label: t('Vorhandenes Journal verwenden'), role: 'default' }, { label: t('Durch dieses Journal ersetzen') }, { label: t('Abbrechen'), role: 'cancel' }] });
      if (i === 0) await performSwitch(mode, folder, true);
      else if (i === 1) await performSwitch(mode, folder, false);
      return;
    }
    await performSwitch(mode, folder, false);
  };

  const restoreBackup = async b => {
    const i = await ask({ title: t('Journal auf diesen Stand zurücksetzen?'),
      message: t('Das ganze Journal wird durch das Backup vom {0} ersetzt. Der aktuelle Stand wird vorher als Backup gesichert.', formatAbbrevTime(new Date(b.date))),
      buttons: [{ label: t('Wiederherstellen'), role: 'default' }, { label: t('Abbrechen'), role: 'cancel' }] });
    if (i !== 0) return;
    const r = await store.restoreBackup(b.url);
    setMessage(!r ? t('Dieses Backup ist nicht lesbar und wurde nicht wiederhergestellt.')
      : r.safety ? t('Backup wiederhergestellt. Der vorherige Stand liegt unter {0}.', r.safety.split(/[\\/]/).pop()) : t('Backup wiederhergestellt.'));
    reload();
  };

  if (!info) return null;
  return html`<div class="modal-body" style="flex:1">
    <div class="form-section">
      <div class="form-row"><span class="label">${t('Speicherort')}</span>
        <select class="field" style="width:280px" value=${info.mode} disabled=${busy} onChange=${e => requestSwitch(e.target.value)}>
          ${Object.entries(info.modes).map(([k, v]) => html`<option value=${k}>${t(v)}</option>`)}
        </select></div>
      ${busy && html`<div style="display:flex;gap:6px;align-items:center"><span class="spinner"></span><span class="caption">${t('Daten werden umgezogen …')}</span></div>`}
      <div class="caption secondary">${info.mode === 'folder'
        ? t('Journal, Versionen, Backups und CAS-Datenbank liegen im Sync-Ordner und sind auf allen deinen Rechnern verfügbar (auch auf dem Mac, wenn der Ordner dort synchronisiert wird). Änderungen anderer Rechner werden automatisch übernommen, solange du hier nichts Ungespeichertes hast.')
        : t('Alles bleibt auf diesem Rechner. Mit „Sync-Ordner“ liegen die Daten zusätzlich in einem synchronisierten Ordner (Nextcloud, Dropbox, Netzlaufwerk …) und sind auf deinen anderen Rechnern verfügbar.')}</div>
      ${info.mode === 'folder' && html`<div class="form-row"><span class="label">${t('Sync-Ordner')}</span><span style="display:flex;gap:8px;align-items:center"><${PathButton} path=${info.syncFolder} />
        <button class="btn" onClick=${async () => { const f = await api.chooseSyncFolder(); if (f) requestSwitch('folder', f); }}>${t('Ändern …')}</button></span></div>`}
      ${store.lastExternalReload && html`<div class="caption secondary">${t('Zuletzt Änderungen von einem anderen Rechner übernommen: {0}', formatTime(store.lastExternalReload))}</div>`}
      <div class="form-row"><span class="label">${t('Journal')}</span><${PathButton} path=${info.paths.journalFile} /></div>
      <div class="form-row"><span class="label">${t('Versionen')}</span><${PathButton} path=${info.paths.versionsDirectory} /></div>
      <div class="form-row"><span class="label">${t('Backups')}</span><${PathButton} path=${info.paths.backupsDirectory} /></div>
    </div>
    <div class="headline">${t('Backups')}</div>
    <div class="form-section">
      <div class="form-row"><span class="caption secondary">${t('Automatisch: ein Backup pro Tag (bleibt 30 Tage) und Versionen je Ansatz.')}</span>
        <button class="btn" onClick=${async () => { const p = await api.backupNow(store.projects); store.dirty = false; setMessage(p ? t('Backup angelegt: {0}', p.split(/[\\/]/).pop()) : t('Backup konnte nicht angelegt werden (noch keine Daten gespeichert?).')); reload(); }}>${t('Jetzt sichern')}</button></div>
      ${message && html`<div class="caption secondary">${message}</div>`}
      ${backups.length === 0 ? html`<div class="secondary">${t('Noch keine Backups – das erste entsteht bei der ersten Änderung heute.')}</div>`
        : backups.slice(0, 12).map(b => html`<div class="form-row" key=${b.url}>
            <span style="display:flex;gap:8px;align-items:center"><span class="gray"><${Icon} name=${b.url.includes('manuell') ? 'hand.raised' : 'calendar'} /></span>
              <span class="mono">${formatAbbrevTime(new Date(b.date))}</span><span class="secondary">${formatBytes(b.size)}</span></span>
            <span style="display:flex;gap:12px"><button class="link-button" onClick=${() => api.showItem(b.url)}>${t('Im Dateimanager zeigen')}</button>
              <button class="link-button" onClick=${() => restoreBackup(b)}>${t('Wiederherstellen …')}</button></span></div>`)}
      ${backups.length > 12 && html`<div class="caption secondary">${t('+ {0} ältere', backups.length - 12)}</div>`}
    </div>
    <div class="caption secondary">${t('Beim Wiederherstellen wird der aktuelle Stand vorher selbst als Backup gesichert. Mit ⌘Z lässt es sich außerdem rückgängig machen.').replace('⌘Z', 'Strg+Z')}</div>
  </div>`;
}

function DeletedExperiments() {
  const [deleted, setDeleted] = useState([]);
  const [selected, setSelected] = useState(null);
  const [snapshot, setSnapshot] = useState(null);
  const reload = async () => {
    await store.saveNow();
    const ids = store.projects.flatMap(p => p.experiments.map(e => e.id));
    const list = await api.deletedExperiments(ids);
    setDeleted(list);
    setSelected(s => (s && list.find(x => x.file === s.file)) || list[0] || null);
  };
  useEffect(() => { reload(); }, []);
  useEffect(() => { let c = false; setSnapshot(null); if (selected) api.loadSnapshot(selected).then(s => { if (!c) setSnapshot(s); }); return () => { c = true; }; }, [selected]);

  const restore = async () => {
    if (!snapshot) return;
    const id = await restoreSnapshot(snapshot, false);
    window.dispatchEvent(new CustomEvent('select-experiment', { detail: id }));
    setSelected(null);
    setTimeout(reload, 50);
  };
  const purge = async () => {
    if (!selected) return;
    const i = await ask({ title: t('Verlauf dieses Ansatzes endgültig entfernen?'), message: t('Alle gespeicherten Versionen dieses Ansatzes werden gelöscht. Tägliche Backups des ganzen Journals bleiben davon unberührt.'),
      buttons: [{ label: t('Endgültig entfernen'), role: 'destructive' }, { label: t('Abbrechen'), role: 'cancel' }] });
    if (i !== 0) return;
    await api.purgeHistory(selected.experimentID);
    setSelected(null);
    reload();
  };

  return html`<div style="flex:1;display:flex;flex-direction:column;min-height:0">
    ${deleted.length === 0
      ? html`<div class="unavailable"><span class="big"><${Icon} name="trash.slash" /></span><span class="title">${t('Keine gelöschten Ansätze')}</span>
          <span>${t('Gelöschte Ansätze bleiben hier mit ihrem letzten Stand, bis du sie endgültig entfernst.')}</span></div>`
      : html`<div class="split-pane" style="border-top:none">
          <div class="list-pane" style="width:220px">${deleted.map(d => html`<div key=${d.file} class=${'list-item' + (selected && selected.file === d.file ? ' selected' : '')} onClick=${() => setSelected(d)}>
            <span class="row-title">${d.title || t('Ohne Titel')}</span>
            <span class="caption secondary">${[d.projectTitle, formatAbbrevTime(new Date(d.date))].filter(Boolean).join(' · ')}</span></div>`)}</div>
          ${snapshot ? html`<${VersionPreview} snapshot=${snapshot} />` : html`<div class="unavailable secondary">${t('Ansatz auswählen')}</div>`}
        </div>`}
    <div class="modal-actions" style="padding:12px">
      <button class="btn destructive" disabled=${!selected} onClick=${purge}>${t('Endgültig entfernen …')}</button>
      <span style="flex:1"></span>
      <button class="btn primary" disabled=${!snapshot} onClick=${restore}>${t('Wiederherstellen')}</button>
    </div>
  </div>`;
}

function CASDatabaseView() {
  const [query, setQuery] = useState('');
  const [selection, setSelection] = useState(new Set());
  const [, tick] = useState(0);
  useEffect(() => store.subscribe(() => tick(t => t + 1)), []);
  const all = [...store.casEntries.values()].sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt));
  const q = CJ.normalizeSearch(query);
  const entries = q ? all.filter(e => CJ.normalizeSearch(e.name).includes(q) || e.cas.includes(query.trim())) : all;
  const toggle = (cas, multi) => setSelection(s => { const n = new Set(multi ? s : []); if (n.has(cas) && multi) n.delete(cas); else n.add(cas); return n; });
  const removeSelected = async () => { for (const cas of selection) await api.casRemove(cas); setSelection(new Set()); };
  return html`<div class="modal-body" style="flex:1;gap:8px">
    <div class="caption secondary">${t('Jede eingegebene CAS-Nummer mit Molmasse und Dichte – aus PubChem oder von dir. Beim nächsten Eintippen der CAS-Nummer werden die Werte sofort eingetragen, auch offline. Eigene Werte haben Vorrang vor PubChem. Molmasse und Dichte lassen sich hier direkt ändern (Doppelklick oder Klick ins Feld, Return übernimmt).')}</div>
    <div class="search-field" style="margin:0"><${Icon} name="magnifyingglass" /><input placeholder=${t('CAS oder Name')} value=${query} onInput=${e => setQuery(e.target.value)} /></div>
    <div style="flex:1;overflow:auto;border:1px solid var(--separator);border-radius:6px">
      <table class="cas-table">
        <thead><tr><th>${t('CAS')}</th><th>${t('Name')}</th><th>M (g/mol)</th><th>d (g/cm³)</th><th>${t('Quelle')}</th><th>${t('Datum')}</th></tr></thead>
        <tbody>${entries.map(e => html`<tr key=${e.cas} class=${selection.has(e.cas) ? 'selected' : ''} onClick=${ev => toggle(e.cas, ev.ctrlKey || ev.metaKey || ev.shiftKey)}
            onContextMenu=${ev => openContextMenu(ev, [{ label: t('Entfernen'), icon: 'trash', destructive: true, action: () => api.casRemove(e.cas) }])}>
          <td class="mono">${e.cas}</td><td title=${e.name}>${e.name || '–'}</td>
          <td class="mono"><${CASValueCell} value=${e.molarMass} onCommit=${v => api.casEdit(e.cas, v, e.density)} /></td>
          <td class="mono"><${CASValueCell} value=${e.density} onCommit=${v => api.casEdit(e.cas, e.molarMass, v)} /></td>
          <td class=${e.source === 'eigene Eingabe' ? '' : 'secondary'}>${t(e.source)}</td><td class="mono">${formatNumeric(new Date(e.updatedAt))}</td></tr>`)}</tbody>
      </table>
    </div>
    <div class="modal-actions"><span class="caption secondary" style="flex:1">${t('{0} Einträge', all.length)}</span>
      <button class="btn" disabled=${!selection.size} onClick=${removeSelected}>${t('Ausgewählte entfernen')}</button></div>
  </div>`;
}

/** Bearbeitbare Zahl in der CAS-Tabelle. Übernimmt bei Return oder beim Verlassen des Feldes; gilt danach als eigene Eingabe. */
function CASValueCell({ value, onCommit }) {
  const [text, setText] = useState(value);
  const focused = useRef(false);
  useEffect(() => { if (!focused.current) setText(value); }, [value]);
  const commit = () => { if (text !== value) onCommit(text); };
  return html`<input class="cas-value" placeholder="–" value=${text} title=${t('Wert ändern – gilt danach als eigene Eingabe')}
    onClick=${e => e.stopPropagation()} onInput=${e => setText(e.target.value)}
    onFocus=${() => { focused.current = true; }} onBlur=${() => { focused.current = false; commit(); }}
    onKeyDown=${e => { if (e.key === 'Enter') e.target.blur(); }} />`;
}
