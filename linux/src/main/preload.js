// Schnittstelle zwischen Oberfläche und Hintergrundprozess (nur diese Funktionen sind sichtbar).
'use strict';
const { contextBridge, ipcRenderer, webUtils } = require('electron');

const invoke = (channel, ...args) => ipcRenderer.invoke(channel, ...args);

contextBridge.exposeInMainWorld('chemjournal', {
  platform: process.platform,
  // Sprache dieses Starts (Hintergrundprozess übergibt sie als Startparameter)
  language: (process.argv.find(a => a.startsWith('--cj-lang=')) || '--cj-lang=de').slice('--cj-lang='.length) === 'en' ? 'en' : 'de',
  getLanguage: () => invoke('lang:get'),
  setLanguage: lang => invoke('lang:set', lang),
  relaunch: () => invoke('app:relaunch'),
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
  restoreBackup: (url, projects) => invoke('backups:restore', url, projects),
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
  casEdit: (cas, m, d) => invoke('cas:edit', cas, m, d),
  pubChemLookup: cas => invoke('cas:lookup', cas),
  // Dateien
  exportExperiment: (experiment, name) => invoke('file:exportExperiment', experiment, name),
  importExperiment: () => invoke('file:importExperiment'),
  chooseAnalysisFiles: () => invoke('file:chooseAnalysisFiles'),
  chooseImage: () => invoke('file:chooseImage'),
  readFile: p => invoke('file:read', p),
  filesExist: paths => invoke('file:exists', paths),
  /** Pfad einer hineingezogenen Datei (File.path gibt es in neueren Electron-Versionen nicht mehr). */
  pathForFile: file => { try { return webUtils.getPathForFile(file); } catch (e) { return null; } },
  // Reaktionsgleichung
  drawingFind: imageB64 => invoke('drawing:find', imageB64),
  drawingLoad: imageB64 => invoke('drawing:load', imageB64),
  drawingSave: (drawingB64, imageB64, app) => invoke('drawing:save', drawingB64, imageB64, app),
  reshikiStatus: () => invoke('reshiki:status'),
  reshikiChoosePath: () => invoke('reshiki:choosePath'),
  reshikiResetPath: () => invoke('reshiki:resetPath'),
  reshikiOpen: drawingB64 => invoke('reshiki:open', drawingB64),
  reshikiImport: () => invoke('reshiki:import'),
  reshikiStop: quitApp => invoke('reshiki:stop', quitApp),
  clipboardWriteImage: b64 => invoke('clipboard:writeImage', b64),
  clipboardReadImage: () => invoke('clipboard:readImage'),
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
    const allowed = ['menu', 'journal:external', 'casdb:changed', 'app:prepare-quit', 'storage:changed', 'open-file', 'reshiki:changed', 'reshiki:closed'];
    if (!allowed.includes(channel)) return () => {};
    const listener = (_e, ...args) => fn(...args);
    ipcRenderer.on(channel, listener);
    return () => ipcRenderer.removeListener(channel, listener);
  },
});
