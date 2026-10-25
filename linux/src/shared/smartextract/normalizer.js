// Bereinigt Synthesevorschriften, die aus PDFs kopiert wurden – entspricht SynthesisTextNormalizer.swift.
//
// Repariert verklebte Wörter und Zahlen, Ersatzzeichen für Grad und Minus, Silbentrennung und an Klammern
// klebende Nummern. Formeln (CuSO4·5H2O, Pd(PPh3)4), Verbindungsnummern (3b) und Kürzel (B2pin2) bleiben.
// Die regulären Ausdrücke arbeiten wie NSRegularExpression auf UTF-16 (ohne u-Flag).
(function (g) {
  'use strict';
  const { SynthesisLexicon } = typeof module === 'object' && module.exports ? require('./lexicon.js') : g.CJ;

  const ligatures = { 'ﬀ': 'ff', 'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬃ': 'ffi', 'ﬄ': 'ffl', 'ﬅ': 'st', 'ﬆ': 'st' };

  const symbolFont = {
    0xF0B0: '°', 0xF06D: 'µ', 0xF0B4: '×', 0xF0B1: '±', 0xF0A2: '′', 0xF0D7: '·', 0xF02D: '-', 0xF0BB: '≈',
    0xF0AE: '→', 0xF0D2: '', 0xF0E2: '', 0xF0D3: '', 0xF0E3: '', 0xF0D4: '', 0xF0E4: '',
    0xF061: 'α', 0xF062: 'β', 0xF063: 'χ', 0xF064: 'δ', 0xF065: 'ε', 0xF066: 'φ', 0xF067: 'γ', 0xF068: 'η',
    0xF06C: 'λ', 0xF06E: 'ν', 0xF070: 'π', 0xF071: 'θ', 0xF072: 'ρ', 0xF073: 'σ', 0xF074: 'τ', 0xF077: 'ω',
    0xF044: 'Δ',
  };

  /** Ersetzt jeden Treffer; fn bekommt [ganzer Treffer, Gruppe 1, …] (nicht getroffene Gruppen = ""). */
  function rep(s, re, fn) {
    return s.replace(re, (...args) => {
      const groups = [];
      let i = 0;
      for (; i < args.length; i++) {
        if (typeof args[i] === 'number') break;
        groups.push(args[i] === undefined ? '' : args[i]);
      }
      return fn(groups);
    });
  }

  function cleanUnicode(input) {
    let s = input.normalize('NFC');
    if (/[\uF000-\uF0FF]/.test(s)) {
      s = Array.from(s).map(ch => {
        const cp = ch.codePointAt(0);
        return Object.prototype.hasOwnProperty.call(symbolFont, cp) ? symbolFont[cp] : ch;
      }).join('');
    }
    s = s.replace(/[®™©]/g, '');
    s = s.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    s = s.replace(/\u2028/g, '\n').replace(/\u2029/g, '\n\n');
    for (const [lig, plain] of Object.entries(ligatures)) s = s.split(lig).join(plain);
    s = s.replace(/\u00AD[ \t]*\n[ \t]*/g, '');
    s = s.replace(/[\u00AD\u200B\u200C\u200D\u2060\uFEFF]/g, '');
    s = s.replace(/[\u00A0\u2000-\u200A\u202F\u205F\u3000\t]/g, ' ');
    s = s.replace(/μ/g, 'µ');
    s = s.replace(/↵/g, 'α');
    s = s.replace(/([α-ω]), (?=[α-ω][,\-′'])/g, '$1,');
    s = s.replace(/‐/g, '-').replace(/‑/g, '-');
    return s;
  }

  const chemicalPrefixes = new Set([
    'n', 's', 't', 'i', 'o', 'm', 'p', 'd', 'l', 'r', 'e', 'z', 'tert', 'sec', 'iso', 'neo', 'cis', 'trans',
    'endo', 'exo', 'syn', 'anti', 'rac', 'meso', 'ortho', 'meta', 'para', 'bis', 'tris', 'tetrakis', 'di', 'tri',
  ]);

  function repairLineBreaks(input) {
    let s = input;
    s = rep(s, /([A-Za-zÄÖÜäöüß]+)-[ \t]*\n[ \t]*([a-zäöüß])/g, m => {
      const left = m[1], right = m[2];
      if (chemicalPrefixes.has(left.toLowerCase())) return `${left}-${right}`;
      return left + right;
    });
    s = rep(s, /^([ \t]*(?:\d+\.)+\d*[ \t]+[A-ZÄÖÜ][a-zäöüß]{2,}[^\n]*)\n(?!\n)/gm, m => {
      const line = m[1].replace(/^[ \t]+|[ \t]+$/g, '');
      const hasUnit = /\d\s*(?:mmol|µmol|mol|mg|g|kg|ml|mL|µl|µL|l|L|eq|equiv|Äq|°C)(?![A-Za-z])/.test(line);
      const isHeading = !hasUnit && Array.from(line).length < 150 && !line.endsWith('.');
      return m[1] + (isHeading ? '\n\n' : '\n');
    });
    s = s.replace(/-[ \t]*\n[ \t]*(?=[A-ZÄÖÜ0-9(\[])/g, '-');
    s = s.replace(/[ \t]*\n[ \t]*\n[\s]*/g, '\uE000');
    s = s.replace(/[ \t]*\n[ \t]*/g, ' ');
    s = s.replace(/\uE000/g, '\n\n');
    return s;
  }

  function normalizeTemperatures(input) {
    let s = input.replace(/→(?=\d+(?:[.,]\d+)?[ ]*→[ ]*[CFK](?![A-Za-zÄÖÜäöüß0-9]))/g, '-');
    s = s.replace(/(\d)[ ]*[°º˚◦∘•∙⁰→¶][ ]*([CFK])(?![A-Za-zÄÖÜäöüß0-9])/g, '$1 °$2');
    s = s.replace(/(\d)[ ]*[°¶][ ]*([CFK])(?=[a-zäöüß]{3,})/g, '$1 °$2 ');
    return s;
  }

  const DASHES = '[‒–—―−﹘﹣－]';
  const reRange = new RegExp(`(\\d)[ ]*${DASHES}[ ]*(?=\\d)`, 'g');
  const reSign = new RegExp(`${DASHES}[ ]*(?=\\d)`, 'g');
  const reNameDash = new RegExp(`(?<=[A-Za-zÄÖÜäöüß0-9)\\]])${DASHES}(?=[A-Za-zÄÖÜäöüß(\\[])`, 'g');

  function normalizeDashes(input) {
    let s = input;
    s = s.replace(reRange, '$1-');
    s = s.replace(reSign, '-');
    s = s.replace(reNameDash, '-');
    s = s.replace(/(?<=[A-Za-zÄÖÜäöüß])-(?=\d+(?:[.,]\d+)?[ ]?°[CFK])/g, ' -');
    return s;
  }

  function normalizeAdductDots(input) {
    let s = input.replace(/(?<=[A-Za-z0-9)\]])[ ]*[•∙⋅·][ ]*(?=[A-Za-z0-9(\[])/g, '·');
    s = s.replace(/·(\d+)[ ]+(?=H2O\b)/g, '·$1');
    return s;
  }

  function splitGluedSentences(input) {
    return input.replace(/(?<=[a-zäöüß]{3}|\))\.(?=[A-ZÄÖÜ][a-zäöüß])/g, '. ');
  }

  const participleRegex = /^(?:hinzu|zusammen|zu|ab|auf|aus|an|ein|nach|weg|vor|bei|mit|um|unter|über|durch)?ge[a-zäöüß]{3,}(?:t|en)$/;
  const inseparableVerbRegex = /^(?:ver|ent|zer|be|er)[a-zäöüß]{3,}t$|^[a-zäöüß]{3,}iert$/;

  function healInlineHyphenation(input) {
    return rep(input, /(?<![A-Za-zÄÖÜäöüß-])([A-Za-zÄÖÜäöüß][a-zäöüß]+)-([a-zäöüß]{2,})(?![A-Za-zÄÖÜäöüß-])/g, m => {
      const joined = (m[1] + m[2]).toLowerCase();
      if (chemicalPrefixes.has(m[1].toLowerCase())) return m[0];
      if (SynthesisLexicon.words.has(joined) || participleRegex.test(joined) || inseparableVerbRegex.test(joined)) return m[1] + m[2];
      return m[0];
    });
  }

  const formulaSuffixes = [
    'pin', 'dba', 'cod', 'acac', 'dppf', 'dppe', 'dppp', 'dppb', 'bpy', 'bipy', 'terpy', 'ppy', 'phen', 'dtbbpy',
    'tmeda', 'dmpe', 'salen', 'moc', 'boc', 'cbz', 'troc', 'alloc', 'dmso', 'tmhd', 'hfacac', 'nbd', 'dipp', 'mes',
  ];

  function splitLettersFromDigits(input) {
    return rep(input, /(?<![A-Za-zÄÖÜäöüß0-9])([A-ZÄÖÜa-zäöüß]?[a-zäöüß]{3,})(?=\d)/g, m => {
      const word = m[1].toLowerCase();
      if (formulaSuffixes.some(suf => word.endsWith(suf))) return m[0];
      return m[1] + ' ';
    });
  }

  const longUnits = [
    'mmol', 'µmol', 'umol', 'nmol', 'mol-%', 'mol%', 'mol', 'mg', 'µg', 'ug', 'kg', 'mL', 'ml', 'µL', 'µl', 'uL', 'ul',
    'mM', 'eq', 'Eq', 'equiv', 'Äq', 'äq', 'Äquiv', 'äquiv', 'min', 'bar', 'atm', 'mbar', 'Torr', 'wt%',
  ];
  const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const unitsAlt = longUnits.slice().sort((a, b) => b.length - a.length).map(escapeRe).join('|');
  const reLongUnits = new RegExp(`(?<![A-Za-z])(\\d+(?:[.,]\\d+)?)(?=(?:${unitsAlt})(?![A-Za-zÄÖÜäöüß0-9]))`, 'g');

  function splitDigitsFromLetters(input) {
    let s = input;
    s = s.replace(reLongUnits, '$1 ');
    s = s.replace(/(?<![A-Za-z0-9.,])(\d+[.,]\d+)(?=[gLlMhN](?![A-Za-zÄÖÜäöüß0-9]))/g, '$1 ');
    s = s.replace(/(?<![A-Za-z0-9.,])(\d+)(?=L(?![A-Za-zÄÖÜäöüß0-9]))/g, '$1 ');
    s = s.replace(/(?<![A-Za-z0-9.,])(\d+(?:[.,]\d+)?)[ ]?(mL|ml|mg|kg|mmol|µmol|µL|µl|g|L)(?=[A-Z][A-Za-z0-9(])/g, '$1 $2 ');
    s = rep(s, /(\d+(?:[.,]\d+)?)(mL|ml|mg|g|L|mmol)([a-zäöüß]{3,})/g, m =>
      SynthesisLexicon.words.has(m[3].toLowerCase()) ? `${m[1]} ${m[2]} ${m[3]}` : m[0]);
    s = s.replace(/(?<![A-Za-zÄÖÜäöüß0-9])(in|im|zu|um|am|an|mit|von|und|of|to|at|by)(?=\d)/g, '$1 ');
    s = s.replace(/(?<![A-Za-z0-9])(\d+(?:[.,]\d+)?)(?=[A-ZÄÖÜa-zäöüß][a-zäöüß]{2,})/g, '$1 ');
    return s;
  }

  const quantityContent = /\d\s*(?:mmol|µmol|umol|mol|mg|µg|kg|g|mL|ml|µL|µl|L|l|eq|Eq|equiv|Äq|äq|Äquiv|%|M)(?![A-Za-z0-9])/;

  function splitBracketsAndCommas(input) {
    let s = input;
    s = rep(s, /\(([^()]*)\)(?=[A-Za-zÄÖÜäöüß0-9])/g, m => quantityContent.test(m[1]) ? m[0] + ' ' : m[0]);
    s = rep(s, /(?<=[A-Za-zÄÖÜäöüß0-9])\(([^()]*)\)/g, m => quantityContent.test(m[1]) ? ' ' + m[0] : m[0]);
    s = s.replace(/(?<=[a-zµ%.)\]]),(?=[A-Za-zÄÖÜäöüß0-9(])/g, ', ');
    s = s.replace(/;(?=\S)/g, '; ');
    return s;
  }

  function splitGluedWords(input) {
    return input.replace(/[A-Za-zÄÖÜäöüß]{6,}/g, m => {
      const seg = SynthesisLexicon.segment(m);
      return seg == null ? m : seg;
    });
  }

  function tidyWhitespace(input) {
    let s = input.replace(/ {2,}/g, ' ');
    s = s.replace(/ *\n */g, '\n');
    s = s.replace(/\n{3,}/g, '\n\n');
    return s.trim();
  }

  function normalizeSynthesisText(input) {
    let s = cleanUnicode(input);
    s = repairLineBreaks(s);
    s = normalizeTemperatures(s);
    s = normalizeDashes(s);
    s = normalizeAdductDots(s);
    s = splitGluedSentences(s);
    s = healInlineHyphenation(s);
    for (let i = 0; i < 3; i++) {
      const before = s;
      s = splitDigitsFromLetters(splitLettersFromDigits(s));
      if (s === before) break;
    }
    s = splitBracketsAndCommas(s);
    s = splitGluedWords(s);
    s = splitDigitsFromLetters(splitLettersFromDigits(s));
    s = tidyWhitespace(s);
    return s;
  }

  const api = { normalizeSynthesisText };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
