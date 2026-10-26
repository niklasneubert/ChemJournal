// ChemJournal für Linux – Hintergrundprozess: Fenster, Menüs, Dateien, Speichern, PubChem, PDF.
'use strict';
const fs = require('fs');
const path = require('path');
const { app, BrowserWindow, Menu, ipcMain, dialog, shell, nativeTheme, screen } = require('electron');
const { MODES, pathsFor, samePaths, createDirectories, JournalPersistence, mergeDirectory } = require('./storage');
const { CASDatabase } = require('./casdb');
const { generatePDF } = require('./pdf');
const { PubChem } = require('../shared/pubchem');
const { safeFileName } = require('../shared/smartformat');
const { normalizeExperiment, normalizeProjects, isoNoMs } = require('./model');
const { writeAtomic } = require('./history');
const i18n = require('../shared/i18n');
const { t } = i18n;

app.setName('ChemJournal');

// Testmodus: alle Daten in einem eigenen Ordner (z. B. CHEMJOURNAL_HOME=/tmp/cj-test npm start),
// damit beim Ausprobieren nie das echte Journal angefasst wird.
if (process.env.CHEMJOURNAL_HOME) {
  const home = process.env.CHEMJOURNAL_HOME;
  app.setPath('userData', path.join(home, 'einstellungen'));
  app.setPath('documents', path.join(home, 'Dokumente'));
  process.env.XDG_DATA_HOME = path.join(home, 'daten');
}
if (process.platform === 'linux') app.setAppUserModelId?.('de.chemjournal.app');

// MARK: Einstellungen ---------------------------------------------------------------------------------

const settingsFile = () => path.join(app.getPath('userData'), 'einstellungen.json');
let settings = { storageMode: 'local', syncFolder: null, theme: 'system', windowBounds: null, language: 'de' };

function loadSettings() {
  try { settings = { ...settings, ...JSON.parse(fs.readFileSync(settingsFile(), 'utf8')) }; } catch (e) { /* Standard */ }
  if (settings.storageMode === 'folder' && (!settings.syncFolder || !fs.existsSync(settings.syncFolder))) {
    // Sync-Ordner nicht erreichbar → lokal weiterarbeiten statt Daten zu verlieren
    settings.storageMode = 'local';
  }
  if (settings.language !== 'en') settings.language = 'de';
  i18n.setLanguage(settings.language);
}
function saveSettings() {
  try { writeAtomic(settingsFile(), JSON.stringify(settings, null, 2)); } catch (e) { console.error(e); }
}

// MARK: Speicher ---------------------------------------------------------------------------------------

let paths, persistence, casdb;
let mainWindow = null;
let watchTimer = null;

function setupStorage() {
  paths = pathsFor(app, settings.storageMode, settings.syncFolder);
  persistence = new JournalPersistence(paths);
  casdb = new CASDatabase(paths.casDatabaseFile, () => send('casdb:changed', casdb.list()));
}

function send(channel, ...args) {
  if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send(channel, ...args);
}

function storageInfo() {
  return {
    mode: settings.storageMode, modes: MODES, syncFolder: settings.syncFolder, paths,
  };
}

function startWatching() {
  clearInterval(watchTimer);
  watchTimer = null;
  if (settings.storageMode !== 'folder') return;
  watchTimer = setInterval(checkExternal, 5000);
}

/** Änderungen eines anderen Rechners übernehmen (alle 5 s und beim Aktivieren des Fensters). */
function checkExternal() {
  if (settings.storageMode !== 'folder' || !persistence) return;
  const result = persistence.reloadIfChangedExternally();
  if (result) {
    send('journal:external', result);
    casdb.reloadFromDisk();
  }
}

// MARK: IPC --------------------------------------------------------------------------------------------

function registerIPC() {
  ipcMain.handle('journal:load', () => ({ ...persistence.load(), storage: storageInfo() }));
  ipcMain.handle('journal:save', (_e, projects, force) => persistence.save(normalizeProjects(projects), !!force));
  ipcMain.on('journal:saveSync', (e, projects, force) => {
    try { e.returnValue = persistence.save(normalizeProjects(projects), !!force); } catch (err) { e.returnValue = false; }
  });

  ipcMain.handle('history:versions', (_e, id) => persistence.history.versions(id));
  ipcMain.handle('history:loadSnapshot', (_e, info) => persistence.history.loadSnapshot(info));
  ipcMain.handle('history:deleted', (_e, ids) => persistence.history.deletedExperiments(new Set(ids)));
  ipcMain.handle('history:snapshot', (_e, experiment, project, reason, pinned) =>
    persistence.history.snapshot(normalizeExperiment(experiment), project ? { id: project.id, title: project.title } : null, reason, pinned));
  ipcMain.handle('history:purge', (_e, id) => persistence.history.removeHistory(id));
  ipcMain.handle('backups:list', () => persistence.history.backups());
  ipcMain.handle('backups:now', (_e, projects) => {
    persistence.save(normalizeProjects(projects));
    return persistence.history.manualBackup(persistence.saveURL);
  });

  /** Backup zurückspielen: liest es (nur aus dem Backup-Ordner), speichert vorher den aktuellen Stand samt Versionen
   *  und legt ihn zusätzlich als Backup ab. Die Oberfläche übernimmt dann den Inhalt (mit Widerrufen). */
  ipcMain.handle('backups:restore', (_e, url, projects) => {
    if (path.dirname(path.resolve(url)) !== path.resolve(paths.backupsDirectory)) return null;
    let restored;
    try { restored = normalizeProjects(JSON.parse(fs.readFileSync(url, 'utf8'))); } catch (e) { return null; }
    persistence.save(normalizeProjects(projects), true);
    const safety = persistence.history.safetyBackup(persistence.saveURL);
    return { projects: restored, safety };
  });

  ipcMain.handle('storage:info', () => storageInfo());
  ipcMain.handle('storage:chooseFolder', async () => {
    const r = await dialog.showOpenDialog(mainWindow, {
      title: t('Sync-Ordner wählen'), buttonLabel: t('Ordner wählen'),
      message: t('Wähle einen Ordner, der mit deinen anderen Rechnern synchronisiert wird (z. B. Nextcloud oder Dropbox).'),
      properties: ['openDirectory', 'createDirectory'],
    });
    return r.canceled ? null : r.filePaths[0];
  });
  ipcMain.handle('storage:check', (_e, mode, folder) => {
    if (mode === 'folder' && (!folder || !fs.existsSync(folder))) return { kind: 'unavailable' };
    const target = pathsFor(app, mode, folder);
    if (samePaths(target, paths)) return { kind: 'ready' };
    const probe = new JournalPersistence(target).load();
    if (probe.kind === 'loaded' || probe.kind === 'recovered') {
      let modified = null;
      try { modified = fs.statSync(target.journalFile).mtime.toISOString(); } catch (e) { /* egal */ }
      return { kind: 'targetHasJournal', experiments: probe.projects.reduce((a, p) => a + p.experiments.length, 0), modified };
    }
    return { kind: 'ready' };
  });
  ipcMain.handle('storage:switch', (_e, mode, folder, useExisting, projects) => {
    const target = pathsFor(app, mode, folder);
    const current = normalizeProjects(projects);
    if (samePaths(target, paths)) { settings.storageMode = mode; settings.syncFolder = folder; saveSettings(); return { projects: null, storage: storageInfo() }; }
    persistence.save(current, true);
    createDirectories(target);
    mergeDirectory(paths.versionsDirectory, target.versionsDirectory);
    mergeDirectory(paths.backupsDirectory, target.backupsDirectory);
    casdb.relocate(target.casDatabaseFile);
    const next = new JournalPersistence(target);
    const stamp = isoNoMs(new Date()).replace(/:/g, '-');
    let result = null;
    const probe = next.load();
    if (useExisting && probe.kind === 'loaded') {
      try { fs.copyFileSync(paths.journalFile, path.join(target.backupsDirectory, `ChemJournal-vor-Umzug-${stamp}.json`)); } catch (e) { /* egal */ }
      result = probe.projects;
    } else {
      if (fs.existsSync(target.journalFile)) {
        try { fs.copyFileSync(target.journalFile, path.join(target.backupsDirectory, `ChemJournal-ersetzt-${stamp}.json`)); } catch (e) { /* egal */ }
      }
      next.save(current);
    }
    persistence = next;
    paths = target;
    settings.storageMode = mode;
    settings.syncFolder = mode === 'folder' ? folder : settings.syncFolder;
    saveSettings();
    startWatching();
    return { projects: result, storage: storageInfo() };
  });

  ipcMain.handle('cas:list', () => casdb.list());
  ipcMain.handle('cas:recordUser', (_e, cas, name, m, d) => casdb.recordUserValues(cas, name, m, d));
  ipcMain.handle('cas:recordPubChem', (_e, cas, result) => casdb.recordPubChem(cas, result));
  ipcMain.handle('cas:markChecked', (_e, cas) => casdb.markPubChemChecked(cas));
  ipcMain.handle('cas:remove', (_e, cas) => casdb.remove(cas));
  ipcMain.handle('cas:lookup', async (_e, cas) => {
    try { return { ok: true, result: await PubChem.lookup(cas) }; } catch (err) { return { ok: false, kind: err.kind || 'network', message: err.message }; }
  });

  ipcMain.handle('file:exportExperiment', async (_e, experiment, name) => {
    const r = await dialog.showSaveDialog(mainWindow, {
      defaultPath: path.join(app.getPath('documents'), `${safeFileName(name)}.chemjournal`),
      filters: [{ name: t('ChemJournal-Ansatz'), extensions: ['chemjournal'] }],
    });
    if (r.canceled || !r.filePath) return false;
    fs.writeFileSync(r.filePath, JSON.stringify(normalizeExperiment(experiment)));
    return true;
  });
  ipcMain.handle('file:importExperiment', async () => {
    const r = await dialog.showOpenDialog(mainWindow, {
      title: t('Ansatz importieren'), message: t('Wähle eine .chemjournal-Datei zum Importieren'),
      filters: [{ name: t('ChemJournal-Ansatz'), extensions: ['chemjournal'] }], properties: ['openFile'],
    });
    if (r.canceled || !r.filePaths[0]) return null;
    return readExperimentFile(r.filePaths[0]);
  });
  ipcMain.handle('file:chooseAnalysisFiles', async () => {
    const r = await dialog.showOpenDialog(mainWindow, { title: t('Dateien verknüpfen'), properties: ['openFile', 'multiSelections'] });
    return r.canceled ? [] : r.filePaths;
  });
  ipcMain.handle('file:chooseImage', async () => {
    const r = await dialog.showOpenDialog(mainWindow, {
      title: t('Bild oder PDF wählen'), properties: ['openFile'],
      filters: [{ name: t('Bilder und PDF'), extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'pdf'] }],
    });
    if (r.canceled || !r.filePaths[0]) return null;
    return readFileForRenderer(r.filePaths[0]);
  });
  ipcMain.handle('file:read', (_e, p) => readFileForRenderer(p));
  ipcMain.handle('shell:openPath', (_e, p) => shell.openPath(p));
  ipcMain.handle('shell:showItem', (_e, p) => { if (fs.existsSync(p)) shell.showItemInFolder(p); else shell.openPath(path.dirname(p)); });
  ipcMain.handle('shell:openExternal', (_e, url) => {
    if (/^https?:\/\//i.test(url)) return shell.openExternal(url);
    return false;
  });

  ipcMain.handle('pdf:export', async (_e, html, footer, suggestedName) => {
    let data;
    try { data = await generatePDF(html, footer); } catch (err) { console.error(err); return { ok: false }; }
    const r = await dialog.showSaveDialog(mainWindow, {
      defaultPath: path.join(app.getPath('documents'), suggestedName), filters: [{ name: 'PDF', extensions: ['pdf'] }],
    });
    if (!r.canceled && r.filePath) fs.writeFileSync(r.filePath, data);
    return { ok: true };
  });
  ipcMain.handle('pdf:exportSeparate', async (_e, jobs) => {
    const r = await dialog.showOpenDialog(mainWindow, {
      title: t('Ordner wählen'), message: t('Wähle den Ordner für den Export der einzelnen PDFs'), properties: ['openDirectory', 'createDirectory'],
    });
    if (r.canceled || !r.filePaths[0]) return { ok: true, canceled: true };
    for (const job of jobs) {
      try { fs.writeFileSync(path.join(r.filePaths[0], `${safeFileName(job.name)}.pdf`), await generatePDF(job.html, job.footer)); } catch (err) { console.error(err); }
    }
    return { ok: true };
  });

  ipcMain.handle('window:setSnapWidths', (_e, widths) => { snapWidths = widths.filter(w => w >= 500); });
  ipcMain.handle('theme:get', () => settings.theme);
  ipcMain.handle('theme:set', (_e, theme) => { settings.theme = theme; applyTheme(); saveSettings(); buildMenu(); });
  ipcMain.handle('lang:get', () => settings.language);
  ipcMain.handle('lang:set', (_e, lang) => { settings.language = lang === 'en' ? 'en' : 'de'; saveSettings(); return settings.language; });
  // Neustart: Fenster schließen (die Oberfläche speichert vorher alles), danach startet ChemJournal neu
  ipcMain.handle('app:relaunch', () => { app.relaunch(); if (mainWindow) mainWindow.close(); });
  ipcMain.on('app:quit-ready', () => { quitReady = true; if (mainWindow) mainWindow.close(); });
}

function readFileForRenderer(p) {
  try {
    const data = fs.readFileSync(p);
    const ext = path.extname(p).toLowerCase();
    return { name: path.basename(p), ext, base64: data.toString('base64') };
  } catch (e) { return null; }
}

function readExperimentFile(p) {
  try { return normalizeExperiment(JSON.parse(fs.readFileSync(p, 'utf8'))); } catch (e) { return null; }
}

// MARK: Fenster ----------------------------------------------------------------------------------------

let snapWidths = [1024];
let quitReady = false;

function applyTheme() {
  nativeTheme.themeSource = settings.theme === 'light' ? 'light' : settings.theme === 'dark' ? 'dark' : 'system';
}

function createWindow() {
  const b = settings.windowBounds;
  mainWindow = new BrowserWindow({
    width: b ? b.width : 1024, height: b ? b.height : 653, x: b ? b.x : undefined, y: b ? b.y : undefined,
    minWidth: 480, minHeight: 320, title: 'ChemJournal', show: false,
    icon: path.join(__dirname, '../../build/icon.png'),
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#1e1e1e' : '#f5f5f7',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true, spellcheck: true,
      additionalArguments: [`--cj-lang=${settings.language}`] },
  });
  mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'));
  mainWindow.once('ready-to-show', () => mainWindow.show());

  // Links (DOI, URLs) im Browser öffnen, nie im App-Fenster
  mainWindow.webContents.setWindowOpenHandler(({ url }) => { if (/^https?:/i.test(url)) shell.openExternal(url); return { action: 'deny' }; });
  mainWindow.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('file:')) { e.preventDefault(); if (/^https?:/i.test(url)) shell.openExternal(url); } });

  // Beim Ziehen an der optimalen Breite einrasten (wie WindowSnapManager auf dem Mac)
  mainWindow.on('will-resize', (e, newBounds) => {
    for (const target of snapWidths) {
      if (Math.abs(newBounds.width - target) <= 20 && newBounds.width !== target) {
        e.preventDefault();
        mainWindow.setBounds({ ...newBounds, width: target });
        return;
      }
    }
  });
  mainWindow.on('focus', checkExternal);

  // Vor dem Schließen: Oberfläche speichert alles (inkl. Versionen), dann wirklich schließen
  mainWindow.on('close', e => {
    settings.windowBounds = mainWindow.getBounds();
    saveSettings();
    if (!quitReady) {
      e.preventDefault();
      send('app:prepare-quit');
      setTimeout(() => { quitReady = true; if (mainWindow && !mainWindow.isDestroyed()) mainWindow.close(); }, 3000);
    }
  });
  mainWindow.on('closed', () => { mainWindow = null; });
}

function snapToPerfectWidth() {
  if (!mainWindow) return;
  const width = snapWidths[0] || 1024;
  const bounds = mainWindow.getBounds();
  const area = screen.getDisplayMatching(bounds).workArea;
  const w = Math.min(width, area.width - 20);
  let x = bounds.x;
  if (x + w > area.x + area.width) x = Math.max(area.x, area.x + area.width - w);
  mainWindow.setBounds({ ...bounds, x, width: w }, true);
}

// MARK: Menü -------------------------------------------------------------------------------------------

function buildMenu() {
  const cmd = name => () => send('menu', name);
  const template = [
    {
      label: t('Ablage'),
      submenu: [
        { label: t('Neuer Ansatz'), accelerator: 'CmdOrCtrl+N', click: cmd('newExperiment') },
        { label: t('Neues Projekt'), accelerator: 'CmdOrCtrl+Shift+N', click: cmd('newProject') },
        { type: 'separator' },
        { label: t('Laborjournal speichern'), accelerator: 'CmdOrCtrl+S', click: cmd('save') },
        { type: 'separator' },
        { label: t('Als PDF exportieren …'), accelerator: 'CmdOrCtrl+P', click: cmd('exportPDF') },
        { label: t('Ansatz importieren (.chemjournal) …'), accelerator: 'CmdOrCtrl+Shift+I', click: cmd('importExperiment') },
        { type: 'separator' },
        { label: t('Einstellungen …'), accelerator: 'CmdOrCtrl+,', click: cmd('settings') },
        { type: 'separator' },
        { label: i18n.getLanguage() === 'en' ? 'Quit' : 'Beenden', accelerator: 'CmdOrCtrl+Q', role: 'quit' },
      ],
    },
    {
      label: t('Bearbeiten'),
      submenu: [
        { label: t('Widerrufen'), accelerator: 'CmdOrCtrl+Z', click: cmd('undo') },
        { label: t('Wiederholen'), accelerator: 'CmdOrCtrl+Shift+Z', click: cmd('redo') },
        { type: 'separator' },
        { label: t('Ausschneiden'), role: 'cut' },
        { label: t('Kopieren'), role: 'copy' },
        { label: t('Einsetzen'), role: 'paste' },
        { label: t('Alles auswählen'), role: 'selectAll' },
      ],
    },
    {
      label: t('Darstellung'),
      submenu: [
        {
          label: t('Erscheinungsbild'),
          submenu: [['system', 'System'], ['light', 'Hell'], ['dark', 'Dunkel']].map(([value, label]) => ({
            label: t(label), type: 'radio', checked: settings.theme === value,
            click: () => { settings.theme = value; applyTheme(); saveSettings(); send('menu', 'themeChanged'); },
          })),
        },
        { type: 'separator' },
        { label: t('Auf optimale Breite einrasten'), accelerator: 'CmdOrCtrl+Alt+0', click: snapToPerfectWidth },
        { type: 'separator' },
        { label: t('Vollbild'), role: 'togglefullscreen' },
        { label: t('Entwicklerwerkzeuge'), accelerator: 'CmdOrCtrl+Alt+I', role: 'toggleDevTools', visible: !app.isPackaged },
      ],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// MARK: Start ------------------------------------------------------------------------------------------

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', (_e, argv) => {
    if (mainWindow) { if (mainWindow.isMinimized()) mainWindow.restore(); mainWindow.focus(); }
    const file = argv.find(a => a.endsWith('.chemjournal'));
    if (file) { const exp = readExperimentFile(file); if (exp) send('open-file', exp); }
  });

  app.whenReady().then(() => {
    loadSettings();
    applyTheme();
    setupStorage();
    registerIPC();
    buildMenu();
    createWindow();
    startWatching();
    // Nur für automatische Tests: Skript, das das Fenster steuert und Bildschirmfotos macht
    if (process.env.CHEMJOURNAL_HOME && process.env.CHEMJOURNAL_TESTSCRIPT) {
      mainWindow.webContents.once('did-finish-load', () => require(process.env.CHEMJOURNAL_TESTSCRIPT)(mainWindow, { app, ipcMain }));
    }
    // Doppelklick auf eine .chemjournal-Datei
    const file = process.argv.find(a => a.endsWith('.chemjournal'));
    if (file) mainWindow.webContents.once('did-finish-load', () => { const exp = readExperimentFile(file); if (exp) send('open-file', exp); });
  });

  app.on('window-all-closed', () => app.quit());
}
