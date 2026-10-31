// Markierungen und Tags – entspricht JournalTag (Models/JournalModels.swift) und TagColor (Views/TagViews.swift).
(function (g) {
  'use strict';
  const node = typeof module === 'object' && module.exports;

  const MAX_LENGTH = 40;
  const fold = s => String(s).normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();

  /** Leerraum am Rand weg, innen zusammengefasst, führendes "#" entfernt; null, wenn nichts übrig bleibt. */
  function clean(raw) {
    let t = String(raw || '').split(/\s+/).filter(Boolean).join(' ');
    t = t.replace(/^#+/, '').trim();
    if (!t) return null;
    return Array.from(t).slice(0, MAX_LENGTH).join('');
  }

  /** Gleicher Tag (Groß-/Kleinschreibung und Akzente egal). */
  const same = (a, b) => fold(a) === fold(b);
  const hasTag = (e, tag) => (e.tags || []).some(x => same(x, tag));

  /** Fügt den Tag hinzu (bereinigt, ohne Dublette). Gibt den neuen Ansatz zurück oder null, wenn nichts zu tun war. */
  function addTag(e, raw) {
    const tag = clean(raw);
    if (!tag || hasTag(e, tag)) return null;
    return { ...e, tags: (e.tags || []).concat([tag]) };
  }

  function removeTag(e, tag) { return { ...e, tags: (e.tags || []).filter(x => !same(x, tag)) }; }

  /** Alle Tags im Journal, alphabetisch, jeder nur einmal (in der Schreibweise des ersten Vorkommens). */
  function all(projects) {
    const seen = [];
    for (const p of projects) for (const e of p.experiments) for (const tag of e.tags || []) if (!seen.some(s => same(s, tag))) seen.push(tag);
    return seen.sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }));
  }

  /** Benennt einen Tag in allen Ansätzen um; gibt es den neuen Namen schon, werden beide zusammengelegt. */
  function rename(projects, old, raw) {
    const neu = clean(raw);
    if (!neu) return projects;
    return projects.map(p => ({ ...p, experiments: p.experiments.map(e => {
      if (!hasTag(e, old)) return e;
      const position = Math.max(0, e.tags.findIndex(x => same(x, old)));
      let tags = e.tags.filter(x => !same(x, old));
      if (tags.some(x => same(x, neu))) tags = tags.map(x => (same(x, neu) ? neu : x));
      else tags.splice(Math.min(position, tags.length), 0, neu);
      return { ...e, tags };
    }) }));
  }

  /** Entfernt einen Tag aus allen Ansätzen. */
  function remove(projects, tag) {
    return projects.map(p => ({ ...p, experiments: p.experiments.map(e => (hasTag(e, tag) ? removeTag(e, tag) : e)) }));
  }

  /** Feste Farbe pro Tag-Name – gleiche Reihenfolge und gleicher Hash wie auf dem Mac. */
  const PALETTE = ['blue', 'green', 'orange', 'purple', 'pink', 'teal', 'indigo', 'brown', 'mint', 'red', 'cyan'];
  function color(tag) {
    let sum = 5381;
    for (const ch of fold(tag)) sum = (Math.imul(sum, 33) + ch.codePointAt(0)) >>> 0;
    return PALETTE[sum % PALETTE.length];
  }

  const api = { Tags: { clean, same, hasTag, addTag, removeTag, all, rename, remove, color, MAX_LENGTH } };
  if (node) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
