// Molmasse und Dichte zu einer CAS-Nummer aus PubChem – entspricht Services/CASLookupService.swift.
//
// 1. CAS-Nummer prüfen (Format und Prüfziffer) – ungültige Eingaben lösen keine Anfrage aus.
// 2. compound/name/<CAS>/cids → PubChem-ID (zuverlässiger als der CAS-Querverweis).
// 3. property/MolecularWeight,Title → Molmasse.
// 4. pug_view … heading=Density → Dichteangaben als Freitext; parseDensity wählt einen Wert in g/cm³.
// An PubChem wird nur die CAS-Nummer gesendet.
(function (g) {
  'use strict';
  const { normalizeCAS } = typeof module === 'object' && module.exports ? require('./casnumber.js') : g.CJ;
  const { t } = typeof module === 'object' && module.exports ? require('./i18n.js') : g.CJ;

  const BASE = 'https://pubchem.ncbi.nlm.nih.gov/rest';

  class LookupError extends Error {
    constructor(kind, message) { super(message); this.kind = kind; }
  }
  const errors = {
    invalidCAS: () => new LookupError('invalidCAS', t('Ungültige CAS-Nummer (Prüfziffer stimmt nicht).')),
    notFound: () => new LookupError('notFound', t('In PubChem nicht gefunden.')),
    network: m => new LookupError('network', t('PubChem nicht erreichbar: {0}', m)),
  };

  const cache = new Map();
  const running = new Map();

  async function get(url, allowNotFound) {
    let res;
    try {
      res = await fetch(url, { signal: AbortSignal.timeout(10000) });
    } catch (e) {
      throw errors.network(e && e.name === 'TimeoutError' ? t('Zeitüberschreitung') : (e.message || String(e)));
    }
    if (res.status === 404 && allowNotFound) return null;
    if (!res.ok) throw errors.network(`HTTP ${res.status}`);
    return res.json();
  }

  async function fetchCompound(cas) {
    const cidJSON = await get(`${BASE}/pug/compound/name/${cas}/cids/JSON`, true);
    const cid = cidJSON && cidJSON.IdentifierList && cidJSON.IdentifierList.CID && cidJSON.IdentifierList.CID[0];
    if (!cid) throw errors.notFound();
    const propJSON = await get(`${BASE}/pug/compound/cid/${cid}/property/MolecularWeight,Title/JSON`, false);
    const first = propJSON && propJSON.PropertyTable && propJSON.PropertyTable.Properties && propJSON.PropertyTable.Properties[0];
    const mw = first ? Number(first.MolecularWeight) : NaN;
    if (!first || !(mw > 0)) throw errors.notFound();
    const densityJSON = await get(`${BASE}/pug_view/data/compound/${cid}/JSON?heading=Density`, true);
    const density = densityJSON ? parseDensity(collectStrings(densityJSON)) : null;
    return { title: first.Title || '', molarMass: mw, density };
  }

  /** Sucht Molmasse und Dichte. Wirft LookupError (kind: invalidCAS, notFound, network). */
  async function lookup(rawCAS) {
    const cas = normalizeCAS(rawCAS);
    if (!cas) throw errors.invalidCAS();
    if (cache.has(cas)) return cache.get(cas);
    if (running.has(cas)) return running.get(cas);
    const task = fetchCompound(cas);
    running.set(cas, task);
    try {
      const result = await task;
      cache.set(cas, result);
      return result;
    } finally {
      running.delete(cas);
    }
  }

  /** Alle "String"-Werte einer pug_view-Antwort (die Dichteangaben stehen darin als Freitext). */
  function collectStrings(obj) {
    const out = [];
    (function walk(o) {
      if (Array.isArray(o)) o.forEach(walk);
      else if (o && typeof o === 'object') {
        if (typeof o.String === 'string') out.push(o.String);
        Object.values(o).forEach(walk);
      }
    })(obj);
    return out;
  }

  // Dichte aus Freitext ---------------------------------------------------------------------------------

  function leadingNumber(s) {
    const m = /\d+(?:[.,]\d+)?/.exec(s);
    if (!m) return null;
    const text = m[0].replace(',', '.');
    const v = Number(text);
    if (!Number.isFinite(v)) return null;
    const parts = text.split('.');
    return { value: v, decimals: parts.length > 1 ? parts[1].length : 0 };
  }

  function firstValue(s) {
    const number = '(\\d+(?:[.,]\\d+)?)';
    const units = [
      ['\\s*(?:g/cu\\.? ?cm|g/cm3|g/cm³|g\\s*cm-3|g\\s*cm⁻³|g/ml|g/mL)', 1],
      ['\\s*(?:kg/m3|kg/m³|kg\\s*m-3)', 0.001],
      ['\\s*(?:kg/l|kg/L|kg/dm3|kg/dm³)', 1],
    ];
    for (const [unit, factor] of units) {
      const m = new RegExp(number + unit, 'i').exec(s);
      if (m) { const v = leadingNumber(m[0]); if (v) return { ...v, explicit: true, factor }; }
    }
    const rel = new RegExp('(?:water\\s*=\\s*1\\)?:?\\s*)' + number, 'i').exec(s);
    if (rel) {
      const tail = rel[0].split(/[:)]/).pop() || '';
      const v = leadingNumber(tail.trim());
      if (v) return { ...v, explicit: false, factor: 1 };
    }
    if (new RegExp('^\\s*' + number + '(?:\\s*$|\\s+(?:at|@)\\b|\\s*@|\\s+-?\\d+(?:\\.\\d+)?\\s*°)').test(s)) {
      const v = leadingNumber(s.trim());
      if (v) return { ...v, explicit: false, factor: 1 };
    }
    return null;
  }

  function temperatureCelsius(s) {
    const m = /(-?\d+(?:\.\d+)?)\s*°\s*([CF])/.exec(s);
    if (!m) return null;
    const part = m[0];
    const v = leadingNumber(part);
    if (!v) return null;
    const signed = part.startsWith('-') ? -v.value : v.value;
    return part.endsWith('F') ? ((signed - 32) * 5) / 9 : signed;
  }

  /** Wählt aus PubChems Freitext-Angaben eine Dichte in g/cm³ (bevorzugt ausdrückliche Einheit nahe Raumtemperatur). */
  function parseDensity(entries) {
    let best = null;
    for (const entry of entries) {
      const lower = entry.toLowerCase();
      if (['vapor', 'vapour', 'bulk', 'lb/', 'lb ', 'saturated', 'gas density', 'crystal'].some(w => lower.includes(w))) continue;
      const v = firstValue(entry);
      if (!v) continue;
      const density = v.value * v.factor;
      if (!(density > 0.1 && density < 25)) continue;
      let score = v.explicit ? 20 : 10;
      const t = temperatureCelsius(entry);
      if (t !== null) {
        if (t >= 18 && t <= 27) score += 5; else if (t >= 15 && t <= 30) score += 3; else score -= 5;
      }
      if (!best || score > best.score || (score === best.score && v.decimals > best.decimals)) best = { score, decimals: v.decimals, value: density };
    }
    return best ? Math.round(best.value * 10000) / 10000 : null;
  }

  const api = { PubChem: { lookup, parseDensity, collectStrings, LookupError } };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
