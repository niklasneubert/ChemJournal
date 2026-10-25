// CAS-Nummern prüfen – entspricht CASNumber in Services/CASLookupService.swift.
(function (g) {
  'use strict';

  /** Bringt die Eingabe in die Form "109-99-9" und prüft die Prüfziffer. null, wenn ungültig. */
  function normalizeCAS(raw) {
    if (raw == null) return null;
    const trimmed = String(raw).replace(/^[ \t]+|[ \t]+$/g, '')
      .replace(/–/g, '-').replace(/‑/g, '-').replace(/‐/g, '-').replace(/−/g, '-');
    if (!/^\d{2,7}-\d{2}-\d$/.test(trimmed)) return null;
    const digits = trimmed.replace(/\D/g, '').split('').map(Number);
    const check = digits[digits.length - 1];
    const body = digits.slice(0, -1).reverse();
    const sum = body.reduce((acc, d, i) => acc + (i + 1) * d, 0);
    return sum % 10 === check ? trimmed : null;
  }

  function isValidCAS(raw) { return normalizeCAS(raw) !== null; }

  const api = { normalizeCAS, isValidCAS };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
