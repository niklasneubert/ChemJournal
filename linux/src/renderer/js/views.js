// Seitenleiste, Detailansichten, Verlauf und Einstellungen – entspricht ContentView.swift, ExperimentDetailView.swift,
// ProjectDetailView.swift, VersionHistoryView.swift und SettingsView.swift.
import { html, CJ, api, useState, useEffect, useRef, nowRef, refToDate, newStage, formatLong, formatAbbrevTime, formatNumeric, formatTime, formatBytes } from './lib.js';
import { Icon } from './icons.js';
import { Sheet, ask, openContextMenu, openMenuAt } from './ui.js';
import { store } from './store.js';
import { StageView, duplicateStage } from './stage.js';
import { RichText } from './latex.js';

// MARK: Seitenleiste ---------------------------------------------------------------------------------------

export function Sidebar({ selection, setSelection, actions }) {
  const [query, setQuery] = useState('');
  const [width, setWidth] = useState(250);
  const [dropTarget, setDropTarget] = useState(null);
  const projects = store.projects;

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
    if (q) return;   // während der Suche zeigen die Positionen auf die gefilterte Liste
    actions.reorderExperiment(eid, pid, targetEid);
  };

  return html`<div class="sidebar" style=${{ width: `${width}px` }}>
    <div class="sidebar-toolbar">
      <button class="toolbar-button" title="Neu" onClick=${e => openMenuAt(e.currentTarget, [
        { label: 'Neues Projekt', icon: 'folder.badge.plus', action: actions.addProject },
        { label: 'Neuer Ansatz', icon: 'doc.badge.plus', action: actions.addExperiment },
        'separator',
        { label: 'Ansatz importieren (.chemjournal)', icon: 'square.and.arrow.down', action: actions.importExperiment },
      ])}><${Icon} name="plus" /></button>
    </div>
    <div class="search-field">
      <${Icon} name="magnifyingglass" />
      <input placeholder="Suchen: Ansatz, Chemikalie, CAS …" value=${query} onInput=${e => setQuery(e.target.value)}
        onKeyDown=${e => { if (e.key === 'Escape') setQuery(''); }} />
      ${query && html`<button class="search-clear" onClick=${() => setQuery('')}><${Icon} name="xmark.circle" /></button>`}
    </div>
    <div class="sidebar-list">
      ${filtered.map(p => {
        const expanded = (projects.find(x => x.id === p.id) || p).isExpanded;
        const sel = selection && selection.kind === 'project' && selection.id === p.id;
        return html`<div key=${p.id}>
          <div class=${'project-row' + (sel ? ' selected' : '') + (dropTarget === p.id ? ' drop-target' : '')}
            onClick=${() => setSelection({ kind: 'project', id: p.id })}
            onContextMenu=${e => openContextMenu(e, [{ label: 'Projekt löschen', icon: 'trash', destructive: true, action: () => actions.deleteProject(p.id) }])}
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
                { label: 'Ansatz duplizieren', icon: 'doc.on.doc', action: () => actions.duplicateExperiment(e.id) },
                { label: 'Als .chemjournal exportieren', icon: 'square.and.arrow.up', action: () => actions.exportExperimentAsFile(e.id) },
                'separator',
                { label: 'Ansatz löschen', icon: 'trash', destructive: true, action: () => actions.deleteExperiment(e.id) },
              ])}>
              <div class="content">
                <span class="headline line">${e.title || 'Unbenannter Ansatz'}</span>
                <span class="subheadline secondary line">${e.summary || 'Keine Beschreibung'}</span>
                <span class="caption2 secondary">${formatLong(refToDate(e.createdAt))}</span>
                ${h.slice(0, 3).map(label => html`<span class="caption2 hit line"><${Icon} name="magnifyingglass" />${label}</span>`)}
                ${h.length > 3 && html`<span class="caption2 secondary">+ ${h.length - 3} weitere Treffer</span>`}
              </div>
            </div>`;
          })}
        </div>`;
      })}
    </div>
    <div class="sidebar-resize" onMouseDown=${onResize}></div>
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
      <input class="plain-field exp-title" placeholder="Titel des Ansatzes" value=${experiment.title} onInput=${e => setField('title', e.target.value)} />
      <input class="plain-field exp-summary" placeholder="Kurze Zusammenfassung" value=${experiment.summary} onInput=${e => setField('summary', e.target.value)} />
      <div class="meta-row">
        <span class="item"><${Icon} name="calendar" />${formatLong(refToDate(experiment.createdAt))}</span>
        <button class="link-button" title="Frühere Versionen dieses Ansatzes ansehen und wiederherstellen" onClick=${() => setShowHistory(true)}>
          <${Icon} name="clock.arrow.circlepath" />Verlauf</button>
      </div>
      <div class="divider"></div>
      <div>
        ${experiment.stages.map(stage => html`<${StageView} key=${stage.id} eid=${eid} stage=${stage}
          onDelete=${() => setStages(list => list.filter(s => s.id !== stage.id))}
          onDuplicate=${() => setStages(list => { const i = list.findIndex(s => s.id === stage.id); const out = list.slice(); out.splice(i + 1, 0, duplicateStage(stage)); return out; })} />`)}
        <button class="add-stage" onClick=${() => setStages(list => list.concat([newStage(`Stufe ${list.length + 1}`)]))}>
          <${Icon} name="plus.circle.fill" />Neue Stufe hinzufügen</button>
      </div>
    </div>
    ${showHistory && html`<${VersionHistory} experimentID=${eid} currentTitle=${experiment.title} onClose=${() => setShowHistory(false)} />`}
  </div>`;
}

export function ProjectDetail({ project, onAddExperiment }) {
  useEffect(() => { api.setSnapWidths([1024]); }, []);
  return html`<div class="project-detail">
    <span class="big-folder"><${Icon} name="folder.fill" /></span>
    <input class="plain-field" placeholder="Projektname" value=${project.title} onInput=${e => store.updateProject(project.id, p => ({ ...p, title: e.target.value }))} />
    <div class="title2 secondary">${project.experiments.length} Ansätze in diesem Projekt</div>
    <button class="primary-big" onClick=${onAddExperiment}><${Icon} name="plus.circle.fill" />Neuen Ansatz erstellen</button>
  </div>`;
}

// MARK: Versionsverlauf ------------------------------------------------------------------------------------

function VersionRow({ info, selected, onClick }) {
  return html`<div class=${'list-item' + (selected ? ' selected' : '')} onClick=${onClick}>
    <span class="mono" style="display:flex;gap:4px;align-items:center">${formatAbbrevTime(new Date(info.date))}
      ${info.pinned && html`<span class="orange caption" title="Wird nie automatisch entfernt"><${Icon} name="pin.fill" /></span>`}</span>
    <span class="caption secondary">${info.reason}</span>
    <span class="caption tertiary">${info.stageCount} ${info.stageCount === 1 ? 'Stufe' : 'Stufen'} · ${info.chemicalCount} Chemikalien</span>
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
    <div class="title2" style="font-weight:700">${e.title || 'Ohne Titel'}</div>
    ${e.summary && html`<div class="secondary">${e.summary}</div>`}
    ${snapshot.projectTitle && html`<div class="caption secondary" style="display:flex;gap:4px;align-items:center"><${Icon} name="folder" />${snapshot.projectTitle}</div>`}
    ${e.stages.map(s => html`<div class="preview-stage" key=${s.id}>
      <div class="headline">${s.title}</div>
      ${s.chemicals.map(c => html`<div>${line(c.name, c.cas, [c.equivalents ? `${c.equivalents} eq` : '', c.mass, c.volume, c.amount])}</div>`)}
      ${s.yieldProducts.map(y => html`<div class="secondary">Produkt: ${line(y.name, y.cas, [y.mass, y.amount])}</div>`)}
      ${s.procedure && html`<${RichText} class="secondary" text=${s.procedure} />`}
      ${s.observation && html`<div class="secondary">Beobachtung: ${s.observation}</div>`}
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
      const i = await ask({ title: 'Diesen Stand wiederherstellen?', message: 'Der aktuelle Stand wird vorher selbst als Version gesichert und bleibt im Verlauf.',
        buttons: [{ label: 'Wiederherstellen', role: 'default' }, { label: 'Abbrechen', role: 'cancel' }] });
      if (i !== 0) return;
    }
    const id = await restoreSnapshot(snapshot, asCopy);
    onClose();
    if (asCopy) window.dispatchEvent(new CustomEvent('select-experiment', { detail: id }));
  };

  return html`<${Sheet} onClose=${onClose} width=${820} height=${560} padded=${false}>
    <div style="padding:14px 20px"><div class="headline">Verlauf</div><div class="subheadline secondary">${currentTitle}</div></div>
    ${versions === null ? html`<div class="unavailable"><span class="spinner"></span></div>`
      : versions.length === 0 ? html`<div class="unavailable" style="border-top:1px solid var(--separator);border-bottom:1px solid var(--separator)">
          <span class="big"><${Icon} name="clock.arrow.circlepath" /></span><span class="title">Noch keine Versionen</span>
          <span>ChemJournal sichert automatisch: beim ersten Speichern, danach höchstens alle 10 Minuten, wenn sich etwas geändert hat, und beim Beenden.</span></div>`
      : html`<div class="split-pane">
          <div class="list-pane">${versions.map(v => html`<${VersionRow} key=${v.file} info=${v} selected=${selected && selected.file === v.file} onClick=${() => setSelected(v)} />`)}</div>
          ${snapshot ? html`<${VersionPreview} snapshot=${snapshot} />` : html`<div class="unavailable"><span class="spinner"></span></div>`}
        </div>`}
    <div class="modal-actions" style="padding:12px 20px">
      <span class="caption secondary" style="flex:1">Ältere Versionen werden ausgedünnt: 24 h alle, 30 Tage eine pro Tag, danach eine pro Woche.</span>
      <button class="btn" onClick=${onClose}>Schließen</button>
      <button class="btn" disabled=${!snapshot} title="Diese Version als zusätzlichen Ansatz einfügen – der aktuelle Stand bleibt unverändert" onClick=${() => restore(true)}>Als Kopie hinzufügen</button>
      <button class="btn primary" disabled=${!snapshot} onClick=${() => restore(false)}>Wiederherstellen …</button>
    </div>
  <//>`;
}

/** Stellt eine Version wieder her (wie JournalStore.restore). Gibt die ID des wiederhergestellten Ansatzes zurück. */
export async function restoreSnapshot(snap, asCopy) {
  let experiment = snap.experiment;
  if (asCopy) {
    const stamp = formatAbbrevTime(new Date(snap.date));
    experiment = { ...experiment, id: crypto.randomUUID().toUpperCase(), title: `${experiment.title} (Version vom ${stamp})`,
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
    store.setProjects(projects.concat([{ id: crypto.randomUUID().toUpperCase(), title: projectTitle || 'Wiederhergestellt', isExpanded: true, experiments: [experiment] }]));
  }
}

// MARK: Einstellungen --------------------------------------------------------------------------------------

export function Settings({ onClose }) {
  const [tab, setTab] = useState('storage');
  const tabs = [['storage', 'externaldrive', 'Speicherort & Backups'], ['deleted', 'trash', 'Gelöschte Ansätze'], ['cas', 'flask', 'CAS-Datenbank']];
  return html`<${Sheet} onClose=${onClose} width=${640} height=${540} padded=${false}>
    <div class="tabs">${tabs.map(([id, icon, label]) => html`<button class=${'tab' + (tab === id ? ' active' : '')} onClick=${() => setTab(id)}>
      <span class="ic"><${Icon} name=${icon} /></span>${label}</button>`)}</div>
    <div style="flex:1;min-height:0;display:flex;flex-direction:column">
      ${tab === 'storage' && html`<${StorageSettings} />`}
      ${tab === 'deleted' && html`<${DeletedExperiments} />`}
      ${tab === 'cas' && html`<${CASDatabaseView} />`}
    </div>
    <div class="modal-actions" style="padding:10px 16px;border-top:1px solid var(--separator)"><button class="btn primary" onClick=${onClose}>Fertig</button></div>
  <//>`;
}

function PathButton({ path }) {
  const home = path.replace(/^\/home\/[^/]+|^\/Users\/[^/]+/, '~');
  return html`<button class="path-link" title="Im Dateimanager zeigen" onClick=${() => api.showItem(path)}>${home}</button>`;
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
    setMessage(`Speicherort: ${r.storage.modes[mode]}. Die bisherigen Dateien am alten Ort bleiben unverändert liegen.`);
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
    if (check.kind === 'unavailable') { setMessage('Der Sync-Ordner ist nicht erreichbar.'); return; }
    if (check.kind === 'targetHasJournal') {
      const date = check.modified ? ` (zuletzt geändert ${formatAbbrevTime(new Date(check.modified))})` : '';
      const i = await ask({ title: 'Im Sync-Ordner liegt bereits ein Journal',
        message: `Am Ziel gibt es schon ein Journal mit ${check.experiments} Ansätzen${date}, z. B. von einem anderen Rechner. Die jeweils andere Fassung wird in jedem Fall als Backup aufbewahrt.`,
        buttons: [{ label: 'Vorhandenes Journal verwenden', role: 'default' }, { label: 'Durch dieses Journal ersetzen' }, { label: 'Abbrechen', role: 'cancel' }] });
      if (i === 0) await performSwitch(mode, folder, true);
      else if (i === 1) await performSwitch(mode, folder, false);
      return;
    }
    await performSwitch(mode, folder, false);
  };

  if (!info) return null;
  return html`<div class="modal-body" style="flex:1">
    <div class="form-section">
      <div class="form-row"><span class="label">Speicherort</span>
        <select class="field" style="width:280px" value=${info.mode} disabled=${busy} onChange=${e => requestSwitch(e.target.value)}>
          ${Object.entries(info.modes).map(([k, v]) => html`<option value=${k}>${v}</option>`)}
        </select></div>
      ${busy && html`<div style="display:flex;gap:6px;align-items:center"><span class="spinner"></span><span class="caption">Daten werden umgezogen …</span></div>`}
      <div class="caption secondary">${info.mode === 'folder'
        ? 'Journal, Versionen, Backups und CAS-Datenbank liegen im Sync-Ordner und sind auf allen deinen Rechnern verfügbar (auch auf dem Mac, wenn der Ordner dort synchronisiert wird). Änderungen anderer Rechner werden automatisch übernommen, solange du hier nichts Ungespeichertes hast.'
        : 'Alles bleibt auf diesem Rechner. Mit „Sync-Ordner“ liegen die Daten zusätzlich in einem synchronisierten Ordner (Nextcloud, Dropbox, Netzlaufwerk …) und sind auf deinen anderen Rechnern verfügbar.'}</div>
      ${info.mode === 'folder' && html`<div class="form-row"><span class="label">Sync-Ordner</span><span style="display:flex;gap:8px;align-items:center"><${PathButton} path=${info.syncFolder} />
        <button class="btn" onClick=${async () => { const f = await api.chooseSyncFolder(); if (f) requestSwitch('folder', f); }}>Ändern …</button></span></div>`}
      ${store.lastExternalReload && html`<div class="caption secondary">Zuletzt Änderungen von einem anderen Rechner übernommen: ${formatTime(store.lastExternalReload)}</div>`}
      <div class="form-row"><span class="label">Journal</span><${PathButton} path=${info.paths.journalFile} /></div>
      <div class="form-row"><span class="label">Versionen</span><${PathButton} path=${info.paths.versionsDirectory} /></div>
      <div class="form-row"><span class="label">Backups</span><${PathButton} path=${info.paths.backupsDirectory} /></div>
    </div>
    <div class="headline">Backups</div>
    <div class="form-section">
      <div class="form-row"><span class="caption secondary">Automatisch: ein Backup pro Tag (30 Tage, danach eines pro Monat für ein Jahr) und Versionen je Ansatz.</span>
        <button class="btn" onClick=${async () => { const p = await api.backupNow(store.projects); store.dirty = false; setMessage(p ? `Backup angelegt: ${p.split(/[\\/]/).pop()}` : 'Backup konnte nicht angelegt werden (noch keine Daten gespeichert?).'); reload(); }}>Jetzt sichern</button></div>
      ${message && html`<div class="caption secondary">${message}</div>`}
      ${backups.length === 0 ? html`<div class="secondary">Noch keine Backups – das erste entsteht bei der ersten Änderung heute.</div>`
        : backups.slice(0, 12).map(b => html`<div class="form-row" key=${b.url}>
            <span style="display:flex;gap:8px;align-items:center"><span class="gray"><${Icon} name=${b.url.includes('manuell') ? 'hand.raised' : 'calendar'} /></span>
              <span class="mono">${formatAbbrevTime(new Date(b.date))}</span><span class="secondary">${formatBytes(b.size)}</span></span>
            <button class="link-button" onClick=${() => api.showItem(b.url)}>Im Dateimanager zeigen</button></div>`)}
      ${backups.length > 12 && html`<div class="caption secondary">+ ${backups.length - 12} ältere</div>`}
    </div>
    <div class="caption secondary">Zum Zurückspielen eines Backups: ChemJournal beenden, die Backup-Datei als „ChemJournalData.json“ an den Ort des Journals kopieren und neu starten.</div>
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
    const i = await ask({ title: 'Verlauf dieses Ansatzes endgültig entfernen?', message: 'Alle gespeicherten Versionen dieses Ansatzes werden gelöscht. Tägliche Backups des ganzen Journals bleiben davon unberührt.',
      buttons: [{ label: 'Endgültig entfernen', role: 'destructive' }, { label: 'Abbrechen', role: 'cancel' }] });
    if (i !== 0) return;
    await api.purgeHistory(selected.experimentID);
    setSelected(null);
    reload();
  };

  return html`<div style="flex:1;display:flex;flex-direction:column;min-height:0">
    ${deleted.length === 0
      ? html`<div class="unavailable"><span class="big"><${Icon} name="trash.slash" /></span><span class="title">Keine gelöschten Ansätze</span>
          <span>Gelöschte Ansätze bleiben hier mit ihrem letzten Stand, bis du sie endgültig entfernst.</span></div>`
      : html`<div class="split-pane" style="border-top:none">
          <div class="list-pane" style="width:220px">${deleted.map(d => html`<div key=${d.file} class=${'list-item' + (selected && selected.file === d.file ? ' selected' : '')} onClick=${() => setSelected(d)}>
            <span class="row-title">${d.title || 'Ohne Titel'}</span>
            <span class="caption secondary">${[d.projectTitle, formatAbbrevTime(new Date(d.date))].filter(Boolean).join(' · ')}</span></div>`)}</div>
          ${snapshot ? html`<${VersionPreview} snapshot=${snapshot} />` : html`<div class="unavailable secondary">Ansatz auswählen</div>`}
        </div>`}
    <div class="modal-actions" style="padding:12px">
      <button class="btn destructive" disabled=${!selected} onClick=${purge}>Endgültig entfernen …</button>
      <span style="flex:1"></span>
      <button class="btn primary" disabled=${!snapshot} onClick=${restore}>Wiederherstellen</button>
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
    <div class="caption secondary">Jede eingegebene CAS-Nummer mit Molmasse und Dichte – aus PubChem oder von dir. Beim nächsten Eintippen der CAS-Nummer werden die Werte sofort eingetragen, auch offline. Eigene Werte haben Vorrang vor PubChem.</div>
    <div class="search-field" style="margin:0"><${Icon} name="magnifyingglass" /><input placeholder="CAS oder Name" value=${query} onInput=${e => setQuery(e.target.value)} /></div>
    <div style="flex:1;overflow:auto;border:1px solid var(--separator);border-radius:6px">
      <table class="cas-table">
        <thead><tr><th>CAS</th><th>Name</th><th>M (g/mol)</th><th>d (g/cm³)</th><th>Quelle</th><th>Datum</th></tr></thead>
        <tbody>${entries.map(e => html`<tr key=${e.cas} class=${selection.has(e.cas) ? 'selected' : ''} onClick=${ev => toggle(e.cas, ev.ctrlKey || ev.metaKey || ev.shiftKey)}
            onContextMenu=${ev => openContextMenu(ev, [{ label: 'Entfernen', icon: 'trash', destructive: true, action: () => api.casRemove(e.cas) }])}>
          <td class="mono">${e.cas}</td><td title=${e.name}>${e.name || '–'}</td><td class="mono">${e.molarMass || '–'}</td><td class="mono">${e.density || '–'}</td>
          <td class=${e.source === 'eigene Eingabe' ? '' : 'secondary'}>${e.source}</td><td class="mono">${formatNumeric(new Date(e.updatedAt))}</td></tr>`)}</tbody>
      </table>
    </div>
    <div class="modal-actions"><span class="caption secondary" style="flex:1">${all.length} Einträge</span>
      <button class="btn" disabled=${!selection.size} onClick=${removeSelected}>Ausgewählte entfernen</button></div>
  </div>`;
}
