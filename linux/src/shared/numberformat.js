// Zahlenformatierung für die Tabellen – entspricht Utilities/NumberFormatting.swift.
// Feste Nachkommastellen, aber sehr kleine Werte behalten ihre signifikanten Stellen:
// 115 µmol werden als "0.000115" mol angezeigt statt als "0.0001".
(function (g) {
  'use strict';

  // NumberFormatter rundet standardmäßig "half even" – Intl.NumberFormat kann das ebenfalls.
  const opts = { useGrouping: false, roundingMode: 'halfEven' };
  const fmt3 = new Intl.NumberFormat('en-US', { ...opts, maximumFractionDigits: 3, minimumFractionDigits: 0 });
  const fmt4 = new Intl.NumberFormat('en-US', { ...opts, maximumFractionDigits: 4, minimumFractionDigits: 0 });
  const sig3 = new Intl.NumberFormat('en-US', { ...opts, maximumSignificantDigits: 3, minimumSignificantDigits: 1 });
  const sig4 = new Intl.NumberFormat('en-US', { ...opts, maximumSignificantDigits: 4, minimumSignificantDigits: 1 });

  function clean(s) { return s === '-0' ? '0' : s; }

  /** Masse (g) und Volumen (ml): drei Nachkommastellen, unter 0.1 drei signifikante Stellen. */
  function format3(v) {
    if (!Number.isFinite(v)) return '';
    return clean((v !== 0 && Math.abs(v) < 0.1 ? sig3 : fmt3).format(v));
  }

  /** Stoffmenge (mol) und Äquivalente: vier Nachkommastellen, unter 0.01 vier signifikante Stellen. */
  function format4(v) {
    if (!Number.isFinite(v)) return '';
    return clean((v !== 0 && Math.abs(v) < 0.01 ? sig4 : fmt4).format(v));
  }

  /** Liest "6.55", "6,55" und ".5". Gibt null für alles andere zurück (auch "1e5" oder leere Strings). */
  function parseDecimal(s) {
    if (s == null) return null;
    const trimmed = String(s).replace(/^[ \t\u00A0\u2000-\u200A\u202F\u205F\u3000]+|[ \t\u00A0\u2000-\u200A\u202F\u205F\u3000]+$/g, '');
    if (!/^-?(?:\d+(?:[.,]\d*)?|[.,]\d+)$/.test(trimmed)) return null;
    const v = Number(trimmed.replace(',', '.'));
    return Number.isFinite(v) ? v : null;
  }

  const api = { format3, format4, parseDecimal };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
