// Schnittstelle zwischen Oberfläche und Hintergrundprozess (nur diese Funktionen sind sichtbar).
'use strict';
const { contextBridge, ipcRenderer } = require('electron');

const invoke = (channel, ...args) => ipcRenderer.invoke(channel, ...args);

contextBridge.exposeInMainWorld('chemjournal', {
  platform: process.platform,
  // Journal
  load: () => invoke('journal:load'),
  save: (projects, force) => invoke('journal:save', projects, force),
  saveSync: (projects, force) => ipcRenderer.sendSync('journal:saveSync', projects, force),
  // Versionsverlauf & Backups
  versions: id => invoke('history:versions', id),
  loadSnapshot: info => invoke('history:loadSnapshot', info),
  deletedExperiments: existingIds => invoke('history:deleted', existingIds),
  snapshot: (experiment, project, reason, pinned) => invoke('history:snapshot', experiment, project, reason, pinned),
  purgeHistory: id => invoke('history:purge', id),
  backups: () => invoke('backups:list'),
  backupNow: projects => invoke('backups:now', projects),
  // Speicherort
  storageInfo: () => invoke('storage:info'),
  chooseSyncFolder: () => invoke('storage:chooseFolder'),
  checkSwitch: (mode, folder) => invoke('storage:check', mode, folder),
  switchStorage: (mode, folder, useExisting, projects) => invoke('storage:switch', mode, folder, useExisting, projects),
  // CAS-Datenbank & PubChem
  casList: () => invoke('cas:list'),
  casRecordUser: (cas, name, m, d) => invoke('cas:recordUser', cas, name, m, d),
  casRecordPubChem: (cas, result) => invoke('cas:recordPubChem', cas, result),
  casMarkChecked: cas => invoke('cas:markChecked', cas),
  casRemove: cas => invoke('cas:remove', cas),
  pubChemLookup: cas => invoke('cas:lookup', cas),
  // Dateien
  exportExperiment: (experiment, name) => invoke('file:exportExperiment', experiment, name),
  importExperiment: () => invoke('file:importExperiment'),
  chooseAnalysisFiles: () => invoke('file:chooseAnalysisFiles'),
  chooseImage: () => invoke('file:chooseImage'),
  readFile: p => invoke('file:read', p),
  openPath: p => invoke('shell:openPath', p),
  showItem: p => invoke('shell:showItem', p),
  openExternal: url => invoke('shell:openExternal', url),
  // PDF
  exportPDF: (html, footer, suggestedName) => invoke('pdf:export', html, footer, suggestedName),
  exportPDFs: jobs => invoke('pdf:exportSeparate', jobs),
  // Fenster
  setSnapWidths: widths => invoke('window:setSnapWidths', widths),
  setTheme: theme => invoke('theme:set', theme),
  getTheme: () => invoke('theme:get'),
  quitReady: () => ipcRenderer.send('app:quit-ready'),
  // Ereignisse aus dem Hintergrund (Menü, Änderungen anderer Rechner, CAS-Datenbank)
  on: (channel, fn) => {
    const allowed = ['menu', 'journal:external', 'casdb:changed', 'app:prepare-quit', 'storage:changed', 'open-file'];
    if (!allowed.includes(channel)) return () => {};
    const listener = (_e, ...args) => fn(...args);
    ipcRenderer.on(channel, listener);
    return () => ipcRenderer.removeListener(channel, listener);
  },
});
