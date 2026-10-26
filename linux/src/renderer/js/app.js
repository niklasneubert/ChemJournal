// Hauptansicht – entspricht ContentView.swift und den Menübefehlen aus MyApp.swift.
import { html, render, CJ, api, t, useState, useEffect, refToDate, nowRef, uuid, newExperiment, newProject } from './lib.js';
import { store, useStore } from './store.js';
import { AlertHost, ContextMenuHost, ask, alertOK } from './ui.js';
import { Sidebar, DetailView, ProjectDetail, Settings } from './views.js';

// Welche Textfelder seit dem Fokussieren bearbeitet wurden (für Strg+Z im Feld)
const typedSinceFocus = new WeakSet();
document.addEventListener('focusin', e => typedSinceFocus.delete(e.target));
document.addEventListener('input', e => { if (e.isTrusted) typedSinceFocus.add(e.target); });

/**
 * Strg+Z / Strg+Umschalt+Z: Wird gerade in einem Textfeld getippt, wirkt es dort;
 * sonst wird der letzte Schritt im Journal widerrufen – auch Löschen und Hinzufügen.
 */
function performUndo(redo) {
  const el = document.activeElement;
  const isText = el && (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT');
  if (isText && typedSinceFocus.has(el)) {
    const before = el.value;
    document.execCommand(redo ? 'redo' : 'undo');
    if (el.value !== before) return;
  }
  if (isText) el.blur();
  if (redo) store.redo(); else store.undo();
}

function App() {
  useStore();
  const [selection, setSelection] = useState(null);   // { kind: 'project'|'experiment', id }
  const [showSettings, setShowSettings] = useState(false);
  const [exporting, setExporting] = useState(false);
  const projects = store.projects;

  // MARK: Aktionen
  const selectedProjectIndex = () => {
    if (selection && selection.kind === 'project') { const i = projects.findIndex(p => p.id === selection.id); if (i >= 0) return i; }
    if (selection && selection.kind === 'experiment') { const i = projects.findIndex(p => p.experiments.some(e => e.id === selection.id)); if (i >= 0) return i; }
    return 0;
  };

  const actions = {
    addProject() {
      const p = newProject();
      store.setProjects(store.projects.concat([p]));
      setSelection({ kind: 'project', id: p.id });
      return p;
    },
    addExperiment() {
      if (!store.projects.length) actions.addProject();
      const exp = newExperiment();
      const target = store.projects[Math.min(selectedProjectIndex(), store.projects.length - 1)];
      store.updateProject(target.id, p => ({ ...p, isExpanded: true, experiments: p.experiments.concat([exp]) }));
      setSelection({ kind: 'experiment', id: exp.id });
    },
    async importExperiment() {
      const exp = await api.importExperiment();
      if (exp) actions.insertImported(exp);
    },
    insertImported(exp) {
      const imported = { ...exp, id: uuid(), title: exp.title + t(' (importiert)') };
      if (!store.projects.length) actions.addProject();
      const target = store.projects[Math.min(selectedProjectIndex(), store.projects.length - 1)];
      store.updateProject(target.id, p => ({ ...p, isExpanded: true, experiments: p.experiments.concat([imported]) }));
      setSelection({ kind: 'experiment', id: imported.id });
    },
    moveExperiment(eid, pid) {
      const from = store.projects.find(p => p.experiments.some(e => e.id === eid));
      const to = store.projects.find(p => p.id === pid);
      if (!from || !to || from.id === pid) return;
      const exp = from.experiments.find(e => e.id === eid);
      store.setProjects(store.projects.map(p => {
        if (p.id === from.id) return { ...p, experiments: p.experiments.filter(e => e.id !== eid) };
        if (p.id === pid) return { ...p, experiments: p.experiments.concat([exp]) };
        return p;
      }));
    },
    reorderExperiment(eid, pid, beforeId) {
      const found = store.findExperiment(eid);
      if (!found) return;
      const without = store.projects.map(p => ({ ...p, experiments: p.experiments.filter(e => e.id !== eid) }));
      store.setProjects(without.map(p => {
        if (p.id !== pid) return p;
        const list = p.experiments.slice();
        const i = list.findIndex(e => e.id === beforeId);
        list.splice(i < 0 ? list.length : i, 0, found.experiment);
        return { ...p, experiments: list };
      }));
    },
    async deleteProject(id) {
      const p = store.projects.find(x => x.id === id);
      if (!p) return;
      const i = await ask({ title: t('Projekt „{0}“ löschen?', p.title),
        message: t('Alle {0} Ansätze in diesem Projekt werden gelöscht. Sie bleiben im Versionsverlauf und lassen sich unter Einstellungen › Gelöschte Ansätze wiederherstellen.', p.experiments.length),
        buttons: [{ label: t('Löschen'), role: 'destructive' }, { label: t('Abbrechen'), role: 'cancel' }] });
      if (i !== 0) return;
      for (const e of p.experiments) await api.snapshot(e, p, 'Vor dem Löschen', true);
      if (selection && ((selection.kind === 'project' && selection.id === id) || (selection.kind === 'experiment' && p.experiments.some(e => e.id === selection.id)))) setSelection(null);
      store.setProjects(store.projects.filter(x => x.id !== id));
    },
    async deleteExperiment(id) {
      const found = store.findExperiment(id);
      if (!found) return;
      const i = await ask({ title: t('Ansatz „{0}“ löschen?', found.experiment.title),
        message: t('Der Ansatz bleibt im Versionsverlauf und lässt sich unter Einstellungen › Gelöschte Ansätze wiederherstellen.'),
        buttons: [{ label: t('Löschen'), role: 'destructive' }, { label: t('Abbrechen'), role: 'cancel' }] });
      if (i !== 0) return;
      await api.snapshot(found.experiment, found.project, 'Vor dem Löschen', true);
      if (selection && selection.kind === 'experiment' && selection.id === id) setSelection(null);
      store.updateProject(found.project.id, p => ({ ...p, experiments: p.experiments.filter(e => e.id !== id) }));
    },
    duplicateExperiment(id) {
      const found = store.findExperiment(id);
      if (!found) return;
      const e = found.experiment;
      const copy = { ...e, id: uuid(), title: e.title + t(' (Kopie)'), createdAt: nowRef(), updatedAt: nowRef(),
        stages: e.stages.map(s => ({ ...s, id: uuid(), createdAt: nowRef() })) };
      store.updateProject(found.project.id, p => ({ ...p, experiments: p.experiments.concat([copy]) }));
      setSelection({ kind: 'experiment', id: copy.id });
    },
    exportExperimentAsFile(id) {
      const found = store.findExperiment(id);
      if (found) api.exportExperiment(found.experiment, found.experiment.title);
    },
  };

  // MARK: PDF-Export
  const runExport = async (experiments, projectName, combined) => {
    setExporting(true);
    try {
      if (combined) {
        const htmlDoc = CJ.generatePDFHTML(experiments, projectName, refToDate);
        const footer = projectName || (experiments[0] && experiments[0].title) || '';
        const name = experiments.length === 1 ? `${CJ.safeFileName(experiments[0].title)}.pdf` : `${t('Laborjournal_Export')}.pdf`;
        const r = await api.exportPDF(htmlDoc, footer, name);
        if (!r.ok) alertOK(t('PDF-Export fehlgeschlagen'), t('Das PDF konnte nicht erstellt werden. Bitte versuche es erneut.'));
      } else {
        await api.exportPDFs(experiments.map(e => ({ html: CJ.generatePDFHTML([e], projectName, refToDate), footer: e.title, name: e.title })));
      }
    } finally {
      setExporting(false);
    }
  };

  const preparePDFExport = async () => {
    if (!selection) return;
    if (selection.kind === 'experiment') {
      const found = store.findExperiment(selection.id);
      if (found) runExport([found.experiment], found.project.title, true);
    } else {
      const p = store.projects.find(x => x.id === selection.id);
      if (!p || !p.experiments.length) return;
      const i = await ask({ title: t('Wie möchtest du die Ansätze exportieren?'), message: '',
        buttons: [{ label: t('Als ein gemeinsames PDF'), role: 'default' }, { label: t('Als getrennte Einzel-PDFs') }, { label: t('Abbrechen'), role: 'cancel' }] });
      if (i === 0) runExport(p.experiments, p.title, true);
      if (i === 1) runExport(p.experiments, p.title, false);
    }
  };

  // MARK: Menü & Ereignisse
  useEffect(() => {
    const off = [
      api.on('menu', name => {
        if (name === 'newExperiment') actions.addExperiment();
        else if (name === 'newProject') actions.addProject();
        else if (name === 'save') store.saveNow();
        else if (name === 'exportPDF') preparePDFExport();
        else if (name === 'importExperiment') actions.importExperiment();
        else if (name === 'settings') setShowSettings(true);
        else if (name === 'undo') performUndo(false);
        else if (name === 'redo') performUndo(true);
      }),
      api.on('journal:external', result => store.applyExternal(result)),
      api.on('casdb:changed', list => store.setCASEntries(list)),
      api.on('open-file', exp => actions.insertImported(exp)),
      api.on('app:prepare-quit', () => { store.saveBeforeQuit(); api.quitReady(); }),
    ];
    const onSelect = e => setSelection({ kind: 'experiment', id: e.detail });
    window.addEventListener('select-experiment', onSelect);
    return () => { off.forEach(f => f()); window.removeEventListener('select-experiment', onSelect); };
  });

  useEffect(() => { if (store.loadMessage) alertOK(t('Hinweis zu deinen Daten'), store.loadMessage).then(() => { store.loadMessage = null; }); }, [store.loaded]);
  useEffect(() => { if (!selection || selection.kind !== 'experiment') api.setSnapWidths([1024]); }, [selection]);

  // MARK: Darstellung
  let detail;
  if (selection && selection.kind === 'project') {
    const p = projects.find(x => x.id === selection.id);
    if (p) detail = html`<${ProjectDetail} project=${p} onAddExperiment=${actions.addExperiment} />`;
  } else if (selection && selection.kind === 'experiment') {
    const found = store.findExperiment(selection.id);
    if (found) detail = html`<${DetailView} key=${found.experiment.id} project=${found.project} experiment=${found.experiment} />`;
  }
  if (!detail) detail = html`<div class="empty-detail title2 secondary">${t('Wähle ein Projekt oder einen Ansatz aus, oder erstelle ein neues.')}</div>`;

  return html`<div class="split">
    <${Sidebar} selection=${selection} setSelection=${setSelection} actions=${actions} />
    <div class="detail">
      ${detail}
      ${exporting && html`<div class="overlay"><div class="box"><span class="spinner"></span>${t('PDF wird generiert...')}</div></div>`}
    </div>
    ${showSettings && html`<${Settings} onClose=${() => setShowSettings(false)} />`}
    <${AlertHost} />
    <${ContextMenuHost} />
  </div>`;
}

store.load().then(() => render(html`<${App} />`, document.getElementById('app')));
