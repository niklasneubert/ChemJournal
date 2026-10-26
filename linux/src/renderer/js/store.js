// Gemeinsamer Datenbestand – entspricht JournalStore.swift (Oberflächenteil).
// - Speichert 0,8 s nach der letzten Änderung, beim Beenden sofort (mit Versionen).
// - Widerrufen/Wiederholen (Strg+Z / Strg+Umschalt+Z) für das ganze Journal: Tippen wird gebündelt,
//   Hinzufügen/Löschen ist immer ein eigener Schritt; höchstens 100 Schritte.
import { api, useState, useEffect } from './lib.js';

const UNDO_LIMIT = 100;
const UNDO_GROUPING = 1000;

export const store = {
  projects: [],
  loaded: false,
  dirty: false,
  loadMessage: null,
  storage: null,
  casEntries: new Map(),
  lastExternalReload: null,
  undoStack: [],
  redoStack: [],
  lastEditTime: 0,
  lastChangeWasStructural: false,
  saveTimer: null,
  listeners: new Set(),

  subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); },
  notify() { for (const fn of this.listeners) fn(); },

  async load() {
    const result = await api.load();
    this.storage = result.storage;
    this.applyLoadResult(result);
    this.loaded = true;
    this.setCASEntries(await api.casList());
    this.notify();
  },

  applyLoadResult(result) {
    if (result.kind === 'loaded') this.projects = result.projects;
    else if (result.kind === 'recovered') {
      this.projects = result.projects;
      this.loadMessage = window.CJ.t('Die Datendatei war beschädigt. Der letzte Stand aus dem Backup wurde geladen. Die beschädigte Datei liegt unter {0}.', result.preserved);
    } else if (result.kind === 'failed') {
      this.loadMessage = window.CJ.t('Die Datendatei konnte nicht gelesen werden und wurde unter {0} gesichert. ChemJournal startet mit einem leeren Journal.', result.preserved || '–');
    }
  },

  setCASEntries(list) {
    this.casEntries = new Map(list.map(e => [e.cas, e]));
    this.notify();
  },

  /** Neuer Stand des Journals. options.undo = false: kein Widerrufen-Schritt (z. B. Auf-/Zuklappen). */
  setProjects(next, options = {}) {
    if (!this.loaded || next === this.projects) return;
    if (options.undo !== false) this.recordUndo(this.projects, next);
    this.projects = next;
    this.dirty = true;
    this.scheduleSave();
    this.notify();
  },

  recordUndo(old, next) {
    const now = Date.now();
    const gap = now - this.lastEditTime;
    const structural = structure(old) !== structure(next);
    if (structural || gap > UNDO_GROUPING || (this.lastChangeWasStructural && gap > 300)) {
      this.undoStack.push(old);
      if (this.undoStack.length > UNDO_LIMIT) this.undoStack.shift();
    }
    this.lastEditTime = now;
    this.lastChangeWasStructural = structural;
    this.redoStack = [];
  },

  undo() {
    if (!this.undoStack.length) return false;
    this.redoStack.push(this.projects);
    this.restore(this.undoStack.pop());
    return true;
  },

  redo() {
    if (!this.redoStack.length) return false;
    this.undoStack.push(this.projects);
    this.restore(this.redoStack.pop());
    return true;
  },

  restore(state) {
    this.projects = state;
    this.lastEditTime = 0;
    this.dirty = true;
    this.scheduleSave();
    this.notify();
  },

  clearUndo() { this.undoStack = []; this.redoStack = []; this.lastEditTime = 0; },

  scheduleSave() {
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this.saveNow(), 800);
  },

  async saveNow() {
    clearTimeout(this.saveTimer);
    if (!this.loaded) return;
    const snapshot = this.projects;
    await api.save(snapshot, false);
    if (this.projects === snapshot) this.dirty = false;
  },

  /** Beim Beenden: synchron speichern, jede noch nicht gesicherte Änderung wird zur Version. */
  saveBeforeQuit() {
    clearTimeout(this.saveTimer);
    if (this.loaded) api.saveSync(this.projects, true);
    this.dirty = false;
  },

  /** Backup zurückspielen (Einstellungen). Der aktuelle Stand wird vorher gesichert; Widerrufen bleibt möglich.
   *  Gibt { safety } zurück oder null, wenn das Backup nicht lesbar ist. */
  async restoreBackup(url) {
    clearTimeout(this.saveTimer);
    const r = await api.restoreBackup(url, this.projects);
    if (!r) return null;
    this.lastEditTime = 0;   // eigener Widerrufen-Schritt
    this.setProjects(r.projects);
    await this.saveNow();
    return { safety: r.safety };
  },

  /** Änderungen eines anderen Rechners (Sync-Ordner) – nur ohne eigene ungespeicherte Änderungen. */
  applyExternal(result) {
    if (this.dirty || !result) return;
    if (result.kind === 'loaded' || result.kind === 'recovered') {
      this.projects = result.projects;
      this.clearUndo();
      this.lastExternalReload = new Date();
      this.notify();
    }
  },

  // MARK: Hilfen für Änderungen (erzeugen neue Objekte nur entlang des Pfads)

  findExperiment(eid) {
    for (const p of this.projects) { const e = p.experiments.find(x => x.id === eid); if (e) return { project: p, experiment: e }; }
    return null;
  },
  updateProject(pid, fn, options) {
    this.setProjects(this.projects.map(p => (p.id === pid ? fn(p) : p)), options);
  },
  updateExperiment(eid, fn) {
    this.setProjects(this.projects.map(p => (p.experiments.some(e => e.id === eid)
      ? { ...p, experiments: p.experiments.map(e => (e.id === eid ? fn(e) : e)) } : p)));
  },
  updateStage(eid, sid, fn) {
    this.updateExperiment(eid, e => ({ ...e, stages: e.stages.map(s => (s.id === sid ? fn(s) : s)) }));
  },
  stage(eid, sid) {
    const f = this.findExperiment(eid);
    return f ? f.experiment.stages.find(s => s.id === sid) : null;
  },
};

/** Anzahl der Projekte, Ansätze, Stufen, Zeilen, Analysen und Bilder – ändert sich nur beim Hinzufügen/Löschen. */
function structure(projects) {
  const s = [projects.length];
  for (const p of projects) {
    s.push(p.experiments.length);
    for (const e of p.experiments) {
      s.push(e.stages.length);
      for (const st of e.stages) s.push(st.chemicals.length, st.yieldProducts.length, st.analysisFiles.length, st.reactionImageData ? 1 : 0);
    }
  }
  return s.join(',');
}

/** Komponente neu zeichnen, wenn sich der Datenbestand ändert. */
export function useStore() {
  const [, setTick] = useState(0);
  useEffect(() => store.subscribe(() => setTick(t => t + 1)), []);
  return store;
}
