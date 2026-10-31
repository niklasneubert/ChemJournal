// Datenmodell im selben JSON-Format wie die Mac-App (Swift Codable):
// - Datumswerte: Sekunden seit dem 1.1.2001 (Swift "timeIntervalSinceReferenceDate"),
// - IDs: UUIDs in Großbuchstaben, Bilder: Base64-Text.
// So lassen sich ChemJournalData.json und .chemjournal-Dateien zwischen Mac und Linux austauschen.
'use strict';
const crypto = require('crypto');
const { Analysis } = require('../shared/analysis');
const { Tags } = require('../shared/tags');

const REFERENCE_EPOCH_MS = Date.UTC(2001, 0, 1);

const nowRef = () => (Date.now() - REFERENCE_EPOCH_MS) / 1000;
const refToDate = s => new Date(REFERENCE_EPOCH_MS + s * 1000);
const dateToRef = d => (d.getTime() - REFERENCE_EPOCH_MS) / 1000;
/** ISO-8601 ohne Millisekunden – so liest und schreibt Swift ".iso8601". */
const isoNoMs = d => d.toISOString().replace(/\.\d{3}Z$/, 'Z');
const uuid = () => crypto.randomUUID().toUpperCase();

const str = v => (typeof v === 'string' ? v : v == null ? '' : String(v));
const num = (v, fallback) => (typeof v === 'number' && Number.isFinite(v) ? v : fallback);

/** Ergänzt fehlende Felder (ältere oder fremde Dateien), damit die App und die Mac-Version sie lesen können. */
function normalizeChemical(c = {}) {
  return { id: str(c.id) || uuid(), name: str(c.name), equivalents: str(c.equivalents), cas: str(c.cas), molarMass: str(c.molarMass), density: str(c.density), amount: str(c.amount), volume: str(c.volume), mass: str(c.mass), purity: str(c.purity) };
}
function normalizeYield(y = {}) {
  const out = { id: str(y.id) || uuid(), name: str(y.name), cas: str(y.cas), molarMass: str(y.molarMass), density: str(y.density), amount: str(y.amount), volume: str(y.volume), mass: str(y.mass) };
  if (y.referenceChemicalID) out.referenceChemicalID = str(y.referenceChemicalID);
  return out;
}
function normalizeStage(s = {}) {
  // Aufreinigung & Analytik; ältere Dateien haben nur die Dateiliste `analysisFiles` → Einträge mit erratener Methode
  const analyses = Array.isArray(s.analyses)
    ? s.analyses.map(Analysis.normalizeEntry)
    : (s.analysisFiles || []).map(a => Analysis.migrated({ id: str(a.id) || uuid(), filePath: str(a.filePath), description: str(a.description) }));
  const out = {
    id: str(s.id) || uuid(), title: str(s.title), sourceURL: str(s.sourceURL), summary: str(s.summary), procedure: str(s.procedure),
    observation: str(s.observation), chemicals: (s.chemicals || []).map(normalizeChemical), yieldProducts: (s.yieldProducts || []).map(normalizeYield),
    analyses,
    // Flache Dateiliste zusätzlich, damit ältere Versionen die verknüpften Dateien weiter sehen (wie auf dem Mac)
    analysisFiles: analyses.flatMap(a => a.files),
    isExpanded: s.isExpanded !== false, createdAt: num(s.createdAt, nowRef()),
  };
  if (s.reactionImageData) out.reactionImageData = str(s.reactionImageData);
  return out;
}
function normalizeExperiment(e = {}) {
  const tags = [];
  for (const raw of Array.isArray(e.tags) ? e.tags : []) { const tag = Tags.clean(raw); if (tag && !tags.some(x => Tags.same(x, tag))) tags.push(tag); }
  return { id: str(e.id) || uuid(), title: str(e.title), summary: str(e.summary), stages: (e.stages || []).map(normalizeStage), createdAt: num(e.createdAt, nowRef()), updatedAt: num(e.updatedAt, nowRef()),
    isMarked: e.isMarked === true, tags };
}
function normalizeProject(p = {}) {
  return { id: str(p.id) || uuid(), title: str(p.title), isExpanded: p.isExpanded !== false, experiments: (p.experiments || []).map(normalizeExperiment) };
}
function normalizeProjects(list) {
  if (!Array.isArray(list)) throw new Error('Kein Journal (Liste von Projekten erwartet)');
  return list.map(normalizeProject);
}

// Versionsdateien speichern Datumswerte als ISO-Text (wie Swift mit dateEncodingStrategy .iso8601)
function experimentToISO(e) {
  const iso = v => isoNoMs(refToDate(v));
  return { ...e, createdAt: iso(e.createdAt), updatedAt: iso(e.updatedAt), stages: e.stages.map(s => ({ ...s, createdAt: iso(s.createdAt),
    analyses: (s.analyses || []).map(a => ({ ...a, createdAt: iso(a.createdAt) })) })) };
}
function experimentFromISO(e) {
  const toRef = v => (typeof v === 'string' ? dateToRef(new Date(v)) : v);
  return normalizeExperiment({ ...e, createdAt: toRef(e.createdAt), updatedAt: toRef(e.updatedAt), stages: (e.stages || []).map(s => ({ ...s, createdAt: toRef(s.createdAt),
    ...(Array.isArray(s.analyses) ? { analyses: s.analyses.map(a => ({ ...a, createdAt: toRef(a.createdAt) })) } : {}) })) });
}

/** JSON mit sortierten Schlüsseln (für Hash-Vergleiche). */
function canonicalJSON(v) {
  if (Array.isArray(v)) return '[' + v.map(canonicalJSON).join(',') + ']';
  if (v && typeof v === 'object') return '{' + Object.keys(v).sort().filter(k => v[k] !== undefined).map(k => JSON.stringify(k) + ':' + canonicalJSON(v[k])).join(',') + '}';
  return JSON.stringify(v);
}

function deepEqual(a, b) { return canonicalJSON(a) === canonicalJSON(b); }

module.exports = {
  nowRef, refToDate, dateToRef, isoNoMs, uuid, canonicalJSON, deepEqual,
  normalizeProjects, normalizeExperiment, normalizeStage, experimentToISO, experimentFromISO,
};
