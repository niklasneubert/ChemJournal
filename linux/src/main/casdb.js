// Lokale CAS-Datenbank – entspricht Services/CASDatabase.swift.
// Jede einmal eingegebene CAS-Nummer mit Molmasse und Dichte, egal ob von dir oder aus PubChem. Funktioniert offline.
'use strict';
const fs = require('fs');
const { normalizeCAS } = require('../shared/casnumber');
const { format3, format4 } = require('../shared/numberformat');
const { normalizeSearch } = require('../shared/search');
const { writeAtomic } = require('./history');
const { isoNoMs } = require('./model');

const SOURCE_USER = 'eigene Eingabe';
const SOURCE_PUBCHEM = 'PubChem';

class CASDatabase {
  constructor(file, onChange) {
    this.file = file;
    this.onChange = onChange || (() => {});
    this.entries = file ? CASDatabase.read(file) : new Map();
  }

  static read(file) {
    const map = new Map();
    try {
      for (const e of JSON.parse(fs.readFileSync(file, 'utf8'))) {
        const prev = map.get(e.cas);
        if (!prev || new Date(e.updatedAt) > new Date(prev.updatedAt)) map.set(e.cas, e);
      }
    } catch (e) { /* noch keine Datei */ }
    return map;
  }

  list() { return [...this.entries.values()].sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt)); }

  entry(raw) {
    const cas = normalizeCAS(raw);
    return cas ? this.entries.get(cas) || null : null;
  }

  /** Werte, die du selbst eingetippt hast. Leere Felder überschreiben keine vorhandenen Werte. */
  recordUserValues(raw, name, molarMass, density) {
    const cas = normalizeCAS(raw);
    if (!cas) return;
    const m = String(molarMass || '').trim(), d = String(density || '').trim();
    if (!m && !d) return;
    const existing = this.entries.get(cas);
    if (existing && (!m || m === existing.molarMass) && (!d || d === existing.density)) return;
    const e = existing ? { ...existing } : { cas, name: '', molarMass: '', density: '', source: SOURCE_USER, updatedAt: '', pubChemChecked: false };
    if (m) e.molarMass = m;
    if (d) e.density = d;
    if (!e.name && name) e.name = name;
    e.source = SOURCE_USER;
    e.updatedAt = isoNoMs(new Date());
    this.store(e);
  }

  /** Ergebnis aus PubChem. Vorhandene eigene Werte bleiben; fehlende werden ergänzt. */
  recordPubChem(raw, result) {
    const cas = normalizeCAS(raw);
    if (!cas) return;
    const m = format3(result.molarMass), d = result.density == null ? '' : format4(result.density);
    const existing = this.entries.get(cas);
    let e;
    if (existing && existing.source === SOURCE_USER) {
      e = { ...existing };
      if (!e.molarMass) e.molarMass = m;
      if (!e.density) e.density = d;
      if (!e.name) e.name = result.title;
      e.pubChemChecked = true;
    } else {
      e = { cas, name: result.title, molarMass: m, density: d, source: SOURCE_PUBCHEM, updatedAt: '', pubChemChecked: true };
    }
    e.updatedAt = isoNoMs(new Date());
    this.store(e);
  }

  /** PubChem kannte den Stoff nicht – nicht bei jeder Eingabe erneut fragen. */
  markPubChemChecked(raw) {
    const cas = normalizeCAS(raw);
    const e = cas && this.entries.get(cas);
    if (!e) return;
    this.store({ ...e, pubChemChecked: true });
  }

  remove(cas) {
    this.entries.delete(cas);
    this.persist();
  }

  /** CAS-Nummern, deren gespeicherter Name zur Suche passt ("butyllithium" → 109-72-8). */
  casNumbersMatchingName(normalizedTerm) {
    if (Array.from(normalizedTerm).length < 3) return [];
    return [...this.entries.values()].filter(e => normalizeSearch(e.name).includes(normalizedTerm)).map(e => e.cas);
  }

  /** Wechselt den Speicherort und führt die Einträge beider Dateien zusammen (neuerer Eintrag gewinnt). */
  relocate(newFile) {
    for (const [cas, e] of CASDatabase.read(newFile)) {
      const mine = this.entries.get(cas);
      if (!mine || new Date(mine.updatedAt) < new Date(e.updatedAt)) this.entries.set(cas, e);
    }
    this.file = newFile;
    this.persist();
  }

  /** Änderungen von einem anderen Rechner übernehmen – neuerer Eintrag gewinnt. */
  reloadFromDisk() {
    if (!this.file) return;
    let changed = false;
    for (const [cas, e] of CASDatabase.read(this.file)) {
      const mine = this.entries.get(cas);
      if (!mine || new Date(mine.updatedAt) < new Date(e.updatedAt)) { this.entries.set(cas, e); changed = true; }
    }
    if (changed) this.persist();
  }

  store(e) {
    this.entries.set(e.cas, e);
    this.persist();
  }

  persist() {
    this.onChange();
    if (!this.file) return;
    const list = [...this.entries.values()].sort((a, b) => (a.cas < b.cas ? -1 : a.cas > b.cas ? 1 : 0))
      .map(e => ({ cas: e.cas, density: e.density, molarMass: e.molarMass, name: e.name, pubChemChecked: !!e.pubChemChecked, source: e.source, updatedAt: e.updatedAt }));
    try { writeAtomic(this.file, JSON.stringify(list, null, 2)); } catch (e) { console.error('CAS-Datenbank: Speichern fehlgeschlagen', e); }
  }
}

module.exports = { CASDatabase, SOURCE_USER, SOURCE_PUBCHEM };
