// Entspricht Utilities/SmartFormatting.swift.
(function (g) {
  'use strict';

  const boldMap = { 0: '\u{1D7CE}', 1: '\u{1D7CF}', 2: '\u{1D7D0}', 3: '\u{1D7D1}', 4: '\u{1D7D2}', 5: '\u{1D7D3}', 6: '\u{1D7D4}', 7: '\u{1D7D5}', 8: '\u{1D7D6}', 9: '\u{1D7D7}' };
  const subMap = { 0: '₀', 1: '₁', 2: '₂', 3: '₃', 4: '₄', 5: '₅', 6: '₆', 7: '₇', 8: '₈', 9: '₉' };
  const supMap = { 0: '⁰', 1: '¹', 2: '²', 3: '³', 4: '⁴', 5: '⁵', 6: '⁶', 7: '⁷', 8: '⁸', 9: '⁹', '+': '⁺', '-': '⁻' };

  /** Wandelt "(12)" in fette Verbindungsnummern und "\ce{H2O}" in Unicode-Tief-/Hochstellung um. */
  function applySmartFormatting(text) {
    let result = text.replace(/\(([0-9]+)\)/g, (m, digits) => digits.split('').map(c => boldMap[c] || c).join(''));
    result = result.replace(/\\ce\{([^}]+)\}/g, (m, content) => {
      let out = '';
      let sup = false;
      for (const c of Array.from(content)) {
        if (c === '^') { sup = true; continue; }
        if (sup) {
          if (supMap[c] !== undefined) out += supMap[c];
          else { out += c; sup = false; }
        } else if (/\p{N}/u.test(c)) out += subMap[c] !== undefined ? subMap[c] : c;
        else out += c;
      }
      return out;
    });
    return result;
  }

  /** Entschärft Nutzertext für HTML. */
  function htmlEscaped(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  /** Dateiname ohne Zeichen, die Pfade brechen ("/" und ":"). */
  function safeFileName(s, fallback = 'Ansatz') {
    const cleaned = String(s).replace(/\//g, '-').replace(/:/g, '-').trim();
    return cleaned || fallback;
  }

  const api = { applySmartFormatting, htmlEscaped, safeFileName };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
