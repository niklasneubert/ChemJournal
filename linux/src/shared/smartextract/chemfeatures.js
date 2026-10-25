// Merkmale eines Wortes für den Namensklassifikator (Training und App nutzen genau diese Funktion).
(function (g) {
  'use strict';
  const DIM = 1 << 17;

  function hash(s) {
    let h = 0x811c9dc5;
    for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193); }
    return (h >>> 0) % DIM;
  }

  function shape(word) {
    let out = '', last = '';
    for (const c of Array.from(word)) {
      const k = /\p{Lu}/u.test(c) ? 'A' : /\p{Ll}/u.test(c) ? 'a' : /\p{N}/u.test(c) ? '0' : c;
      if (k !== last) out += k;
      last = k;
    }
    return out;
  }

  /** Liste von Merkmalsindizes (Buchstaben-n-Gramme 2–5, Wortform, Länge, ganzes Wort). */
  function features(word) {
    const lower = word.toLowerCase();
    const padded = '^' + lower + '$';
    const cs = Array.from(padded);
    const f = new Set();
    for (let n = 2; n <= 5; n++) for (let i = 0; i + n <= cs.length; i++) f.add(hash('g' + cs.slice(i, i + n).join('')));
    f.add(hash('w:' + lower));
    f.add(hash('s:' + shape(word)));
    f.add(hash('l:' + Math.min(Array.from(word).length, 12)));
    if (/\p{N}/u.test(word)) f.add(hash('digit'));
    if (/.\p{Lu}/u.test(word)) f.add(hash('innerUpper'));
    if (/^\p{Lu}/u.test(word)) f.add(hash('initUpper'));
    return [...f];
  }

  const api = { features, DIM };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
