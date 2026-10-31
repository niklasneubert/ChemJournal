// Anzeigeeinheiten für n, V und m und Reinheit – entspricht Utilities/QuantityUnits.swift und der Reinheit in
// Models/JournalModels.swift. Gespeichert wird immer in mol, ml und g (Dateiformat und alle Rechnungen bleiben
// gleich); die gewählte Einheit ändert nur, wie die Zahl angezeigt und eingegeben wird.
(function (g) {
  'use strict';
  const node = typeof module === 'object' && module.exports;
  const { format3, format4, parseDecimal } = node ? require('./numberformat.js') : g.CJ;

  /** Einheiten zur Auswahl, die Basiseinheit zuerst. factor: Wert in der Basiseinheit = Wert × factor. */
  const UNITS = {
    amount: [['mol', 1], ['mmol', 1e-3], ['µmol', 1e-6]],
    volume: [['ml', 1], ['l', 1e3], ['µl', 1e-3]],
    mass: [['g', 1], ['kg', 1e3], ['mg', 1e-3], ['µg', 1e-6]],
  };

  function units(kind) { return UNITS[kind].map(([symbol, factor]) => ({ symbol, factor })); }
  function baseUnit(kind) { return units(kind)[0]; }
  /** Einheit zum gespeicherten Kürzel; Unbekanntes fällt auf die Basiseinheit zurück. */
  function unit(kind, symbol) { return units(kind).find(u => u.symbol === symbol) || baseUnit(kind); }
  const isBase = u => u.factor === 1;

  /** Zahl in einer Einheit mit derselben Genauigkeit wie in der Tabelle (n: 4 Stellen, V und m: 3 Stellen). */
  function format(v, kind) { return kind === 'amount' ? format4(v) : format3(v); }

  /** Bis zu 6 signifikante Stellen, ohne Exponent ("12.34 mg" → "0.01234"). */
  function formatBase(v) {
    if (v === 0) return '0';
    const p = Number(v.toPrecision(6));
    let s = String(p);
    if (/e/i.test(s)) {
      const digits = Math.min(20, Math.max(0, 5 - Math.floor(Math.log10(Math.abs(p)))));
      s = p.toFixed(digits).replace(/(\.\d*?)0+$/, '$1').replace(/\.$/, '');
    }
    return s;
  }

  /** Gespeicherten Wert (Basiseinheit) in der Anzeigeeinheit darstellen. Nicht lesbare Eingaben bleiben, wie sie sind. */
  function display(base, u, kind) {
    if (isBase(u)) return base;
    const v = parseDecimal(base);
    return v === null ? base : format(v / u.factor, kind);
  }

  /** Eingabe in der Anzeigeeinheit in die Basiseinheit umrechnen. Leeres oder nicht Lesbares wird unverändert gespeichert. */
  function toBase(text, u) {
    if (isBase(u)) return text;
    const v = parseDecimal(text);
    return v === null ? text : formatBase(v * u.factor);
  }

  // MARK: Reinheit

  /** Reinheit als Anteil (0 < p ≤ 1); leer oder ungültig = 1. */
  function purityFraction(chem) {
    const p = parseDecimal(String(chem.purity || '').replace(/%/g, '').trim());
    return p !== null && p > 0 && p <= 100 ? p / 100 : 1;
  }

  /** Abzuwiegende Masse (g) für n mol reinen Stoff: m = n · M / Reinheit. null ohne Molmasse. */
  function massToWeigh(chem, n) {
    const M = parseDecimal(chem.molarMass);
    return M !== null && M > 0 ? (n * M) / purityFraction(chem) : null;
  }

  /** Stoffmenge (mol) reinen Stoffes in m g Reagenz: n = m · Reinheit / M. null ohne Molmasse. */
  function pureAmount(chem, m) {
    const M = parseDecimal(chem.molarMass);
    return M !== null && M > 0 ? (m * purityFraction(chem)) / M : null;
  }

  const api = { Units: { units, baseUnit, unit, isBase, format, formatBase, display, toBase }, purityFraction, massToWeigh, pureAmount };
  if (node) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
