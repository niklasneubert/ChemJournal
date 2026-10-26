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

  // Mengenangaben vereinheitlichen -------------------------------------------

  const numberWords = {
    one: '1', two: '2', three: '3', four: '4', five: '5', six: '6', seven: '7', eight: '8', nine: '9', ten: '10',
    ein: '1', eine: '1', einem: '1', zwei: '2', drei: '3', vier: '4', 'fünf': '5', zehn: '10',
  };

  /** Schreibweisen in echten Vorschriften, die der Parser sonst missversteht. */
  function normalizeQuantityPhrases(input) {
    let s = input;
    // Molmasse und Dichte als Zusatz in der Mengenklammer: "(MW = 151.12 g/mol, 1.00 equiv, …, density 0.948 g/mL)"
    s = s.replace(/\b(?:MW|M\.W\.|Mw|molecular weight)\s*[=:]?\s*\d+(?:[.,]\d+)?\s*g\s*\/\s*mol\b\s*,?\s*/gi, '');
    s = s.replace(/,?\s*(?:\b(?:density|dichte|d)|ρ)\s*[=:]?\s*\d+(?:[.,]\d+)?\s*g\s*\/\s*(?:mL|ml|cm3|cm³)\b/gi, '');
    // Fußnotenbuchstabe vor dem ersten Wort einer Tabellenfußnote: "aReaction conditions: …", "bTitration by I2"
    s = s.replace(/(^|(?<=[.:;]\s))[a-f](?=[A-Z][a-z]{3,})/gm, '$1');
    // Nummerierte Teilschritte: "Reaction conditions: (1) 1 (1 mmol), 2 (1.2 mmol) … (2) After evaporation …"
    s = s.replace(/(^|(?<=[.:;]\s))\((?:\d{1,2}|i{1,3}|iv|vi{0,3})\)\s+(?=\S)/gm, '$1');
    // "20 mmol %" (Tippfehler für mol%)
    s = s.replace(/(\d)\s*mmol\s*%/g, '$1 mol%');
    // Zahlwörter vor Einheiten: "One equiv of …", "Two equiv …", "One mmol (1.4 equiv)"
    s = rep(s, /\b(one|two|three|four|five|six|seven|eight|nine|ten|ein|eine|einem|zwei|drei|vier|fünf|zehn)\s+(?=(?:equiv|equivalents?|eq|mmol|mol|äquivalente?|äq)(?![A-Za-z0-9_]))/gi,
      m => (numberWords[m[1].toLowerCase()] || m[1]) + ' ');
    // Semikolon in Klammern trennt nur Angaben, keinen Satz: "(5.6 mg, 0.1 mmol; 20 mol %)"
    let depth = 0;
    s = Array.from(s).map(c => {
      if (c === '(') depth += 1; else if (c === ')') depth = Math.max(0, depth - 1);
      return c === ';' && depth > 0 ? ',' : c;
    }).join('');
    // "Triphenylphosphine (PPh3) (0.02 mmol, …)", "BBr3 (1 M in DCM) (0.15 mmol)" → eine Klammer
    s = s.replace(/\(([^()]{1,60})\)\s*\((?=\s*\d)/g, '($1, ');
    return s;
  }

  function normalizeSynthesisText(input) {
    let s = cleanUnicode(input);
    s = repairLineBreaks(s);
    s = normalizeQuantityPhrases(s);
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
