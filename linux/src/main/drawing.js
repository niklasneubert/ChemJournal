// Reaktionsgleichung: Zeichnungen 7 Tage aufheben und ReShiki als Zeichenprogramm – entspricht
// Services/DrawingStore.swift und Services/ReShikiBridge.swift.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawn, execFile } = require('child_process');

const LIFETIME_MS = 7 * 24 * 60 * 60 * 1000;
const EXT = { chemDraw: 'cdxml', reShiki: 'rsk' };

/**
 * Hebt die Zeichnung zu einem importierten Reaktionsbild 7 Tage lang auf, benannt nach dem SHA-256 des Bildes.
 * So braucht das Journal kein neues Feld: Gehört das Bild noch zur Zeichnung, findet man sie über das Bild.
 */
class DrawingStore {
  constructor(directory) { this.directory = directory; }

  file(imageBytes, app) {
    const hash = crypto.createHash('sha256').update(imageBytes).digest('hex');
    return path.join(this.directory, `${hash}.${EXT[app]}`);
  }

  /** { file, expires (ms), app } oder null. */
  find(imageBytes, now = Date.now()) {
    let best = null;
    for (const app of Object.keys(EXT)) {
      const file = this.file(imageBytes, app);
      let saved;
      try { saved = fs.statSync(file).mtimeMs; } catch (e) { continue; }
      const expires = saved + LIFETIME_MS;
      if (expires > now && (!best || expires > best.expires)) best = { file, expires, app };
    }
    return best;
  }

  /** Speichert die Zeichnung zum Bild; die 7 Tage beginnen neu. Eine ältere Zeichnung aus dem anderen Programm fällt weg. */
  save(drawingBytes, imageBytes, app = 'reShiki') {
    fs.mkdirSync(this.directory, { recursive: true });
    const file = this.file(imageBytes, app);
    const tmp = `${file}.tmp-${process.pid}`;
    fs.writeFileSync(tmp, drawingBytes);
    fs.renameSync(tmp, file);
    for (const other of Object.keys(EXT)) if (other !== app) { try { fs.unlinkSync(this.file(imageBytes, other)); } catch (e) { /* keine */ } }
    return true;
  }

  /** Löscht Zeichnungen, die älter als 7 Tage sind. */
  purgeExpired(now = Date.now()) {
    let names = [];
    try { names = fs.readdirSync(this.directory); } catch (e) { return; }
    for (const n of names) {
      if (!Object.values(EXT).includes(path.extname(n).slice(1))) continue;
      const p = path.join(this.directory, n);
      try { if (fs.statSync(p).mtimeMs + LIFETIME_MS <= now) fs.unlinkSync(p); } catch (e) { /* egal */ }
    }
  }
}

/** `true`, wenn die ReShiki-Zeichnung (.rsk ist JSON) mehr als eine leere Seite enthält. */
function containsReShikiDrawing(bytes) {
  try {
    const json = JSON.parse(Buffer.from(bytes).toString('utf8'));
    return ['atoms', 'annotations', 'arrows', 'graphics'].some(k => Array.isArray(json[k]) && json[k].length > 0);
  } catch (e) { return false; }
}

/** Leere Zeichnung im Format von ReShiki 0.13 (neuere Versionen lesen ältere Dateien). */
const EMPTY_RSK = '{"atom_labels":{"carbons":"skeletal","hydrogens":true,"stereo":false},"version":29,'
  + '"atoms":[],"bonds":[],"annotations":[],"arrows":[],"graphics":[],"groups":[],"reactions":[]}';

/** Sucht das ReShiki-Programm: eigene Einstellung, dann PATH und übliche Orte (auch AppImages in ~/Applications). */
function findReShiki(configured) {
  const ok = p => { try { fs.accessSync(p, fs.constants.X_OK); return fs.statSync(p).isFile(); } catch (e) { return false; } };
  if (configured && ok(configured)) return configured;
  const names = ['reshiki', 'ReShiki'];
  for (const dir of String(process.env.PATH || '').split(path.delimiter).filter(Boolean)) {
    for (const n of names) if (ok(path.join(dir, n))) return path.join(dir, n);
  }
  const home = os.homedir();
  const candidates = [path.join(home, '.local/bin/reshiki'), '/opt/ReShiki/reshiki', '/opt/reshiki/reshiki', '/usr/local/bin/reshiki',
    '/Applications/ReShiki.app/Contents/MacOS/reshiki'];
  for (const dir of [path.join(home, 'Applications'), path.join(home, 'Downloads'), '/opt']) {
    try { for (const n of fs.readdirSync(dir)) if (/^reshiki.*\.appimage$/i.test(n)) candidates.push(path.join(dir, n)); } catch (e) { /* fehlt */ }
  }
  return candidates.find(ok) || null;
}

/**
 * Ablauf wie bei ChemDraw auf dem Mac: ChemJournal legt eine .rsk-Datei an (leer oder die gespeicherte Zeichnung) und
 * öffnet sie in ReShiki. Strg+S in ReShiki sichert die Datei; ChemJournal rendert sie über ReShikis Kommandozeile
 * (`reshiki --cli render`) zu einem PNG, übernimmt es und beendet den Modus. ReShiki sichert Entwürfe getrennt –
 * die Datei ändert sich also nur beim Sichern.
 */
class ReShikiBridge {
  /** @param {() => string|null} resolveExecutable  @param {(event: string) => void} emit */
  constructor(resolveExecutable, emit) {
    this.resolveExecutable = resolveExecutable;
    this.emit = emit;
    this.file = null;
    this.child = null;
    this.lastSeen = 0;
    this.timer = null;
  }

  get active() { return !!this.file; }

  /** { ok: true } | { error: 'notFound' | 'failed' } */
  open(drawingBytes) {
    const exe = this.resolveExecutable();
    if (!exe) return { error: 'notFound' };
    this.stop(false);
    const dir = path.join(os.tmpdir(), 'ChemJournal');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, `Reaktion_${crypto.randomUUID().slice(0, 8).toUpperCase()}.rsk`);
    try { fs.writeFileSync(file, drawingBytes || EMPTY_RSK); } catch (e) { return { error: 'failed' }; }
    this.file = file;
    this.lastSeen = fs.statSync(file).mtimeMs;
    let child;
    try { child = spawn(exe, [file], { detached: true, stdio: 'ignore' }); } catch (e) { this.file = null; return { error: 'failed' }; }
    child.on('error', () => {});
    const startedAt = Date.now();
    this.child = child;
    child.on('exit', () => {
      // Sofort beendet: ReShiki hat die Datei an ein schon laufendes Fenster übergeben – kein Ende des Modus
      if (this.child === child) this.child = null;
      if (this.file === file && Date.now() - startedAt > 2500) this.emit('reshiki:closed');
    });
    child.unref();
    this.timer = setInterval(() => this.poll(), 700);
    return { ok: true };
  }

  poll() {
    if (!this.file) return;
    let m;
    try { m = fs.statSync(this.file).mtimeMs; } catch (e) { return; }
    if (m > this.lastSeen) { this.lastSeen = m; this.emit('reshiki:changed'); }
  }

  /** Rendert den gesicherten Stand: { png, drawing } (Buffer) oder { error }. */
  render() {
    const exe = this.resolveExecutable();
    const file = this.file;
    if (!exe || !file) return Promise.resolve({ error: 'inactive' });
    let drawing;
    try { drawing = fs.readFileSync(file); } catch (e) { return Promise.resolve({ error: 'unreadable' }); }
    if (!containsReShikiDrawing(drawing)) return Promise.resolve({ error: 'empty' });
    const png = path.join(os.tmpdir(), `ReShiki_Export_${crypto.randomUUID().slice(0, 8)}.png`);
    // Vorschau-Größe: bis 2400 × 1600 Pixel (der Export mit 1200 dpi wäre viel zu groß)
    const args = ['--cli', 'render', file, '-o', png, '--width', '2400', '--height', '1600', '--force'];
    return new Promise(resolve => {
      execFile(exe, args, { timeout: 60000 }, err => {
        let out = null;
        try { if (!err) out = fs.readFileSync(png); } catch (e) { /* fehlt */ }
        try { fs.unlinkSync(png); } catch (e) { /* egal */ }
        resolve(out && out.length > 8 ? { png: out, drawing } : { error: 'render' });
      });
    });
  }

  /** Modus beenden. Die Datei bleibt liegen (ReShiki hat sie womöglich noch offen).
   *  quitApp: das von ChemJournal gestartete ReShiki-Fenster schließen (wie ChemDraw nach dem Import). */
  stop(quitApp) {
    clearInterval(this.timer);
    this.timer = null;
    const child = this.child;
    this.file = null;
    this.child = null;
    if (quitApp && child && child.exitCode === null) { try { process.kill(child.pid, 'SIGTERM'); } catch (e) { /* schon beendet */ } }
  }
}

module.exports = { DrawingStore, ReShikiBridge, findReShiki, containsReShikiDrawing, EMPTY_RSK, LIFETIME_MS };
