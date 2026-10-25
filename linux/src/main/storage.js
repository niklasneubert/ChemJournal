// Speicherort, Laden und Speichern – entspricht AppPaths.swift und JournalPersistence (JournalStore.swift).
//
// - Lokal: Journal unter ~/Dokumente/ChemJournalData.json (wie auf dem Mac), Versionen, Backups und
//   CAS-Datenbank unter ~/.local/share/ChemJournal.
// - Sync-Ordner (statt iCloud Drive): alles zusammen in <gewählter Ordner>/ChemJournal, z. B. in Nextcloud,
//   Dropbox oder auf einem Netzlaufwerk. Änderungen anderer Rechner werden übernommen.
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { JournalHistory, writeAtomic } = require('./history');
const { normalizeProjects, isoNoMs } = require('./model');

const MODES = {
  local: 'Nur auf diesem Rechner',
  folder: 'Sync-Ordner (Nextcloud, Dropbox, …)',
};

function documentsDir(app) {
  try { return app.getPath('documents'); } catch (e) { return path.join(os.homedir(), 'Documents'); }
}

function localSupportDir() {
  const base = process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share');
  return path.join(base, 'ChemJournal');
}

/** Pfade für einen Speicherort. */
function pathsFor(app, mode, syncFolder) {
  let dataDirectory, supportDirectory;
  if (mode === 'folder' && syncFolder) {
    dataDirectory = supportDirectory = path.join(syncFolder, 'ChemJournal');
  } else {
    dataDirectory = documentsDir(app);
    supportDirectory = localSupportDir();
  }
  return {
    dataDirectory, supportDirectory,
    journalFile: path.join(dataDirectory, 'ChemJournalData.json'),
    versionsDirectory: path.join(supportDirectory, 'Versionen'),
    backupsDirectory: path.join(supportDirectory, 'Backups'),
    casDatabaseFile: path.join(supportDirectory, 'CAS-Datenbank.json'),
  };
}

function samePaths(a, b) { return a.journalFile === b.journalFile && a.supportDirectory === b.supportDirectory; }

function createDirectories(p) {
  for (const d of [p.dataDirectory, p.supportDirectory, p.versionsDirectory, p.backupsDirectory]) fs.mkdirSync(d, { recursive: true });
}

/** Liest und schreibt ChemJournalData.json; legt dabei Versionen und das tägliche Backup an. */
class JournalPersistence {
  constructor(paths) {
    this.paths = paths;
    this.saveURL = paths.journalFile;
    this.backupURL = path.join(path.dirname(paths.journalFile), 'ChemJournalData.bak.json');
    this.history = new JournalHistory(paths.versionsDirectory, paths.backupsDirectory);
    this.mainFileIsValid = false;
    this.knownModificationTime = null;
  }

  decode(file) {
    try { return normalizeProjects(JSON.parse(fs.readFileSync(file, 'utf8'))); } catch (e) { return null; }
  }

  mtime() {
    try { return fs.statSync(this.saveURL).mtimeMs; } catch (e) { return null; }
  }

  /** { kind: 'empty' | 'loaded' | 'recovered' | 'failed', projects?, preserved? } */
  load() {
    if (!fs.existsSync(this.saveURL)) {
      const p = this.decode(this.backupURL);
      return p ? { kind: 'loaded', projects: p } : { kind: 'empty' };
    }
    this.knownModificationTime = this.mtime();
    const p = this.decode(this.saveURL);
    if (p) { this.mainFileIsValid = true; this.history.seed(p); return { kind: 'loaded', projects: p }; }
    // Beschädigt: Original sichern, bevor irgendetwas überschrieben wird
    this.mainFileIsValid = false;
    const stamp = isoNoMs(new Date()).replace(/:/g, '-');
    const preserved = path.join(path.dirname(this.saveURL), `ChemJournalData.defekt-${stamp}.json`);
    let didPreserve = false;
    try { fs.copyFileSync(this.saveURL, preserved); didPreserve = true; } catch (e) { /* ignoriert */ }
    const backup = this.decode(this.backupURL);
    if (backup) { this.history.seed(backup); return { kind: 'recovered', projects: backup, preserved: path.basename(preserved) }; }
    return { kind: 'failed', preserved: didPreserve ? path.basename(preserved) : null };
  }

  save(projects, forceVersions = false) {
    const data = JSON.stringify(projects);
    fs.mkdirSync(path.dirname(this.saveURL), { recursive: true });
    if (this.mainFileIsValid && fs.existsSync(this.saveURL)) {
      // Tägliches Backup = Stand vor der ersten Änderung des Tages
      this.history.dailyBackup(this.saveURL);
      // Nur eine lesbare Datei wird zum Backup – sonst würde ein defekter Stand das gute Backup ersetzen
      try { fs.copyFileSync(this.saveURL, this.backupURL); } catch (e) { /* ignoriert */ }
    }
    try {
      writeAtomic(this.saveURL, data);
      this.mainFileIsValid = true;
      this.knownModificationTime = this.mtime();
    } catch (e) {
      console.error('ChemJournal: Speichern fehlgeschlagen', e);
      return false;
    }
    this.history.recordChanges(projects, new Date(), forceVersions);
    return true;
  }

  /** Hat ein anderer Rechner die Datei geändert? Dann neu laden; sonst null. */
  reloadIfChangedExternally() {
    const t = this.mtime();
    if (t === null || t <= (this.knownModificationTime || 0)) return null;
    this.history.invalidateCaches();
    return this.load();
  }
}

/** Kopiert Dateien, die am Ziel noch fehlen (rekursiv). Vorhandene werden nicht überschrieben. */
function mergeDirectory(source, target) {
  if (!fs.existsSync(source)) return;
  for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
    const from = path.join(source, entry.name), to = path.join(target, entry.name);
    if (entry.isDirectory()) { fs.mkdirSync(to, { recursive: true }); mergeDirectory(from, to); }
    else if (!fs.existsSync(to)) { fs.mkdirSync(path.dirname(to), { recursive: true }); fs.copyFileSync(from, to); }
  }
}

module.exports = { MODES, pathsFor, samePaths, createDirectories, JournalPersistence, mergeDirectory };
