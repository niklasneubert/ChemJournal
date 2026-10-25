// Versionsverlauf pro Ansatz und tägliche Backups – entspricht Services/JournalHistory.swift.
//
//   Versionen/<Ansatz-UUID>/index.json
//   Versionen/<Ansatz-UUID>/2026-10-23T14-05-00.000Z.json
//   Backups/ChemJournal-2026-10-23.json
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { canonicalJSON, isoNoMs, experimentToISO, experimentFromISO, deepEqual } = require('./model');

const DAY = 86400 * 1000;

class JournalHistory {
  constructor(versionsDirectory, backupsDirectory, minimumInterval = 600) {
    this.versionsDirectory = versionsDirectory;
    this.backupsDirectory = backupsDirectory;
    this.minimumInterval = minimumInterval * 1000;
    this.lastSeen = new Map();
    this.indexCache = new Map();
  }

  /** Stand nach dem Laden der Datei merken – Grundlage für die erste Version nach dem Start. */
  seed(projects) {
    this.lastSeen = new Map();
    for (const p of projects) for (const e of p.experiments) if (!this.lastSeen.has(e.id)) this.lastSeen.set(e.id, e);
  }

  /**
   * Nach jedem Speichern. Eine Version ist der Stand, der vor einer neuen Bearbeitung bestand: Ist seit der letzten
   * Version mindestens minimumInterval vergangen, wird der zuletzt gespeicherte Stand gesichert.
   * force: beim Beenden/Umzug – den aktuellen Stand jedes geänderten Ansatzes sofort sichern.
   */
  recordChanges(projects, now = new Date(), force = false) {
    for (const project of projects) {
      for (const experiment of project.experiments) {
        const previous = this.lastSeen.get(experiment.id);
        if (previous && !force && deepEqual(previous, experiment)) continue;
        this.lastSeen.set(experiment.id, experiment);
        const index = this.loadIndex(experiment.id);
        if (index.length === 0 || force) {
          const hash = JournalHistory.hash(experiment);
          if (index[0] && index[0].hash === hash) continue;
          this.write(experiment, hash, project, index.length === 0 ? 'Erste Sicherung' : 'Beim Beenden', false, now);
          continue;
        }
        const newest = index[0];
        if (now - new Date(newest.date) < this.minimumInterval || !previous) continue;
        const hash = JournalHistory.hash(previous);
        if (hash !== newest.hash) this.write(previous, hash, project, 'Automatisch', false, now);
      }
    }
  }

  /** Sofort sichern, z. B. vor dem Löschen oder vor dem Wiederherstellen. */
  snapshot(experiment, project, reason, pinned, now = new Date()) {
    const hash = JournalHistory.hash(experiment);
    const index = this.loadIndex(experiment.id);
    if (index[0] && index[0].hash === hash) {
      if (pinned && !index[0].pinned) {
        index[0] = { ...index[0], pinned: true, reason };
        this.saveIndex(index, experiment.id);
      }
      return;
    }
    this.write(experiment, hash, project, reason, pinned, now);
  }

  write(experiment, hash, project, reason, pinned, now) {
    const dir = this.directory(experiment.id);
    fs.mkdirSync(dir, { recursive: true });
    const file = JournalHistory.fileName(now);
    const snapshot = { date: isoNoMs(now), reason, experiment: experimentToISO(experiment) };
    if (project) { snapshot.projectID = project.id; snapshot.projectTitle = project.title; }
    try {
      writeAtomic(path.join(dir, file), JSON.stringify(snapshot));
    } catch (e) {
      console.error('Versionsverlauf: Schreiben fehlgeschlagen', e);
      return;
    }
    const info = {
      file, experimentID: experiment.id, date: isoNoMs(now), reason, title: experiment.title,
      stageCount: experiment.stages.length, chemicalCount: experiment.stages.reduce((a, s) => a + s.chemicals.length, 0), hash, pinned,
    };
    if (project) info.projectTitle = project.title;
    let index = this.loadIndex(experiment.id).filter(i => i.file !== file);
    index.unshift(info);
    index = this.prune(index, now, dir);
    this.saveIndex(index, experiment.id);
  }

  /** Ausdünnen: 24 h alle, 30 Tage eine pro Tag, danach eine pro Woche; angeheftete bleiben; höchstens 300. */
  prune(index, now, dir) {
    let keep = [];
    const seenDays = new Set(), seenWeeks = new Set();
    for (const info of index) {
      const d = new Date(info.date);
      const age = now - d;
      if (info.pinned || age < DAY) { keep.push(info); continue; }
      if (age <= 30 * DAY) {
        const k = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
        if (!seenDays.has(k)) { seenDays.add(k); keep.push(info); }
      } else {
        const k = isoWeekKey(d);
        if (!seenWeeks.has(k)) { seenWeeks.add(k); keep.push(info); }
      }
    }
    if (keep.length > 300) {
      const unpinned = keep.filter(i => !i.pinned);
      const drop = new Set(unpinned.slice(unpinned.length - (keep.length - 300)).map(i => i.file));
      keep = keep.filter(i => !drop.has(i.file));
    }
    const kept = new Set(keep.map(i => i.file));
    for (const info of index) if (!kept.has(info.file)) { try { fs.unlinkSync(path.join(dir, info.file)); } catch (e) { /* schon weg */ } }
    return keep;
  }

  versions(experimentID) { return this.loadIndex(experimentID); }

  loadSnapshot(info) {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(this.directory(info.experimentID), info.file), 'utf8'));
      return { ...data, experiment: experimentFromISO(data.experiment) };
    } catch (e) {
      return null;
    }
  }

  /** Neueste Version jedes Ansatzes, den es im Journal nicht mehr gibt. */
  deletedExperiments(existing) {
    let dirs = [];
    try { dirs = fs.readdirSync(this.versionsDirectory); } catch (e) { return []; }
    return dirs.filter(d => /^[0-9A-F-]{36}$/i.test(d) && !existing.has(d))
      .map(d => this.loadIndex(d)[0]).filter(Boolean)
      .sort((a, b) => new Date(b.date) - new Date(a.date));
  }

  removeHistory(experimentID) {
    fs.rmSync(this.directory(experimentID), { recursive: true, force: true });
    this.indexCache.delete(experimentID);
  }

  // Backups -----------------------------------------------------------------

  /** Kopiert die Journal-Datei einmal pro Tag nach Backups/. */
  dailyBackup(journalFile, now = new Date()) {
    const target = path.join(this.backupsDirectory, `ChemJournal-${dayString(now)}.json`);
    if (fs.existsSync(target)) return null;
    return this.backup(journalFile, target, now);
  }

  manualBackup(journalFile, now = new Date()) {
    const stamp = isoNoMs(now).replace(/:/g, '-');
    return this.backup(journalFile, path.join(this.backupsDirectory, `ChemJournal-manuell-${stamp}.json`), now);
  }

  backup(journalFile, target, now) {
    if (!fs.existsSync(journalFile)) return null;
    fs.mkdirSync(this.backupsDirectory, { recursive: true });
    try { fs.copyFileSync(journalFile, target, fs.constants.COPYFILE_EXCL); } catch (e) { return null; }
    this.pruneBackups(now);
    return target;
  }

  backups() {
    let names = [];
    try { names = fs.readdirSync(this.backupsDirectory); } catch (e) { return []; }
    return names.filter(n => n.endsWith('.json')).map(n => {
      const p = path.join(this.backupsDirectory, n);
      const st = fs.statSync(p);
      return { url: p, date: st.mtime.toISOString(), size: st.size };
    }).sort((a, b) => new Date(b.date) - new Date(a.date));
  }

  /** Tägliche Backups: letzte 30 Tage + je eines pro Monat für 12 Monate. Manuelle bleiben. */
  pruneBackups(now) {
    const daily = this.backups().filter(b => /^ChemJournal-\d{4}-\d{2}-\d{2}\.json$/.test(path.basename(b.url)));
    const keptMonths = new Set();
    daily.forEach((b, i) => {
      if (i < 30) return;
      const age = now - new Date(b.date);
      const month = path.basename(b.url).slice('ChemJournal-'.length, 'ChemJournal-'.length + 7);
      if (age < 366 * DAY && !keptMonths.has(month)) { keptMonths.add(month); return; }
      try { fs.unlinkSync(b.url); } catch (e) { /* egal */ }
    });
  }

  // intern -------------------------------------------------------------------

  directory(id) { return path.join(this.versionsDirectory, id); }

  loadIndex(id) {
    if (this.indexCache.has(id)) return this.indexCache.get(id);
    let list = [];
    try { list = JSON.parse(fs.readFileSync(path.join(this.directory(id), 'index.json'), 'utf8')); } catch (e) { list = []; }
    list.sort((a, b) => new Date(b.date) - new Date(a.date));
    this.indexCache.set(id, list);
    return list;
  }

  saveIndex(index, id) {
    this.indexCache.set(id, index);
    try { writeAtomic(path.join(this.directory(id), 'index.json'), JSON.stringify(index, null, 2)); } catch (e) { console.error(e); }
  }

  invalidateCaches() { this.indexCache.clear(); }

  static hash(experiment) {
    return crypto.createHash('sha256').update(canonicalJSON(experimentToISO(experiment))).digest().subarray(0, 12).toString('hex');
  }

  static fileName(date) { return date.toISOString().replace(/:/g, '-') + '.json'; }
}

function dayString(d) {
  const p = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function isoWeekKey(d) {
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return `${t.getUTCFullYear()}-W${Math.ceil(((t - yearStart) / DAY + 1) / 7)}`;
}

/** Schreibt erst in eine Temp-Datei und benennt dann um – ein Absturz hinterlässt nie eine halbe Datei. */
function writeAtomic(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmp, data);
  fs.renameSync(tmp, file);
}

module.exports = { JournalHistory, writeAtomic, dayString };
