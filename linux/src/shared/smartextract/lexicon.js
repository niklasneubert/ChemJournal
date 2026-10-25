// Wortschatz typischer Synthesevorschriften – entspricht Services/SmartExtract/SynthesisLexicon.swift.
//
// Wird für zwei Dinge genutzt:
// 1. Zerlegen von Wörtern, die beim PDF-Kopieren zusammengeklebt sind ("Lösungwurdeauf" → "Lösung wurde auf").
// 2. Heilen von Silbentrennungen ("zuge-tropft" → "zugetropft").
(function (g) {
  'use strict';

  const functionWords = new Set([
    // Deutsch
    'der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einer', 'eines', 'einem', 'einen',
    'und', 'oder', 'sowie', 'mit', 'von', 'vom', 'zu', 'zum', 'zur', 'in', 'im', 'auf', 'an', 'am', 'bei', 'beim',
    'nach', 'für', 'über', 'unter', 'aus', 'bis', 'durch', 'gegen', 'ohne', 'um', 'als', 'wie', 'wurde', 'wurden',
    'wird', 'werden', 'ist', 'sind', 'war', 'waren', 'hat', 'haben', 'es', 'sich', 'so', 'dann', 'noch', 'weitere',
    'weiteren', 'weiterer', 'anschließend', 'danach', 'dabei', 'dazu', 'hierzu', 'zunächst', 'nun', 'erneut',
    'zusätzlich', 'langsam', 'unter', 'sowie', 'dieser', 'diese', 'dieses', 'diesem', 'diesen',
    // Englisch
    'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'into', 'on', 'at', 'by', 'for', 'with', 'from', 'was',
    'were', 'is', 'are', 'then', 'after', 'over', 'under', 'this', 'that', 'which', 'it', 'as', 'further',
    'additional', 'slowly', 'again', 'until',
  ]);

  const contentWords = new Set([
    // Deutsch: Verben und Partizipien
    'vorgelegt', 'zugegeben', 'hinzugegeben', 'zugefügt', 'hinzugefügt', 'addiert', 'zugetropft', 'hinzugetropft',
    'getropft', 'gelöst', 'aufgelöst', 'erhalten', 'gerührt', 'nachgerührt', 'abgekühlt', 'gekühlt', 'erwärmt',
    'erhitzt', 'gekocht', 'refluxiert', 'filtriert', 'abfiltriert', 'gewaschen', 'getrocknet', 'extrahiert',
    'eingeengt', 'entfernt', 'versetzt', 'behandelt', 'suspendiert', 'verdünnt', 'neutralisiert', 'angesäuert',
    'gequencht', 'aufgearbeitet', 'gereinigt', 'umkristallisiert', 'destilliert', 'abdestilliert', 'isoliert',
    'eingewogen', 'gegeben', 'gegossen', 'überführt', 'kombiniert', 'vereinigt', 'getrennt', 'gelagert',
    'belassen', 'gehalten', 'gebracht', 'erreicht', 'gestartet', 'beendet', 'verfolgt', 'kontrolliert',
    'entgast', 'evakuiert', 'begast', 'gespült', 'geschüttelt', 'ausgefallen', 'gefällt', 'zersetzt',
    'tropfenweise', 'portionsweise', 'rühren', 'lösen', 'geben', 'wurde', 'wurden', 'gerührten',
    // Deutsch: Nomen und Adjektive aus Vorschriften
    'lösung', 'lösungen', 'gemisch', 'reaktionsgemisch', 'mischung', 'phase', 'phasen', 'rückstand', 'suspension',
    'minute', 'minuten', 'stunde', 'stunden', 'tag', 'tage', 'tagen', 'sekunden', 'nacht', 'temperatur',
    'raumtemperatur', 'rückfluss', 'argon', 'stickstoff', 'atmosphäre', 'schutzgas', 'kolben', 'rundkolben',
    'reaktion', 'zugabe', 'ausbeute', 'produkt', 'feststoff', 'öl', 'farbe', 'trockenem', 'trockenen', 'absolutem',
    'wasserfreiem', 'wasserfreien', 'absolutem', 'trockenen', 'frisch', 'abs', 'dest', 'organische', 'organischen', 'wässrige', 'wässrigen', 'gesättigte',
    'gesättigter', 'langsam', 'vorsichtig', 'sofort', 'insgesamt', 'weitere', 'weiteren', 'folgenden',
    'anschließend', 'abschließend', 'zusammen', 'genau', 'zeitraum', 'jeweils', 'portionen', 'spritze',
    // Englisch: Verben
    'added', 'dissolved', 'stirred', 'cooled', 'warmed', 'heated', 'refluxed', 'filtered', 'washed', 'dried',
    'extracted', 'concentrated', 'evaporated', 'removed', 'treated', 'diluted', 'quenched', 'neutralized',
    'acidified', 'purified', 'recrystallized', 'distilled', 'isolated', 'obtained', 'afforded', 'gave',
    'combined', 'separated', 'transferred', 'charged', 'placed', 'kept', 'maintained', 'allowed', 'stirring',
    'dropwise', 'portionwise', 'sequentially', 'introduced', 'suspended', 'degassed', 'evacuated', 'backfilled',
    // Englisch: Nomen und Adjektive
    'solution', 'solutions', 'mixture', 'phase', 'residue', 'suspension', 'minute', 'minutes', 'hour', 'hours',
    'day', 'days', 'night', 'overnight', 'temperature', 'room', 'reflux', 'argon', 'nitrogen', 'atmosphere',
    'flask', 'reaction', 'addition', 'yield', 'product', 'solid', 'oil', 'dry', 'anhydrous', 'organic',
    'aqueous', 'saturated', 'slowly', 'carefully', 'immediately', 'together',
  ]);

  const neverSplit = new Set([
    'inden', 'indem', 'indan', 'undecan', 'undecanol', 'undecen', 'andere', 'anderen', 'anderer', 'indol',
    'indium', 'anilin', 'aniline', 'another', 'within', 'without', 'thereafter', 'therefore', 'however',
    'afterwards', 'overnight', 'together', 'whereupon', 'herein', 'daraufhin', 'nachdem', 'sodass', 'wodurch',
    'worauf', 'wobei', 'womit', 'dabei', 'zudem', 'außerdem', 'hierbei', 'insgesamt', 'daran', 'darin',
    'zwischen', 'während', 'bevor', 'nachher', 'vorher', 'ausbeute', 'aufarbeitung', 'anschließend',
    'abschließend', 'zunächst', 'zusammen', 'sowohl', 'beiden', 'diesem', 'dieses', 'dieser',
  ]);

  const words = new Set([...functionWords, ...contentWords, ...neverSplit]);

  const participle = /^(?:hinzu|zusammen|zu|ab|auf|aus|an|ein|nach|weg|vor|bei|mit|um)?ge[a-zäöüß]{3,}(?:t|en)$|^[a-zäöüß]{3,}iert$/;
  const isParticiple = w => participle.test(w);
  const isUpper = c => /\p{Lu}/u.test(c);
  const germanEndings = new Set(['es', 'er', 'em', 'en', 'an', 'am', 'im', 'in', 'ab']);
  const compoundTails = ['gehalt', 'gemisch', 'gewicht', 'gefäß', 'gerät', 'gebiet', 'geruch', 'gestell'];

  /** Zerlegt ein verklebtes Wort in bekannte Wörter. Gibt null zurück, wenn das Wort ganz bleiben soll. */
  function segment(token) {
    const lower = token.toLowerCase();
    if (words.has(lower) || neverSplit.has(lower)) return null;
    const chars = Array.from(token);
    const lowerChars = Array.from(lower);
    const n = chars.length;
    if (n < 6 || lowerChars.length !== n) return null;

    const best = new Array(n + 1).fill(null);
    best[0] = { parts: 0, unknown: 0, cuts: [0], hasFunction: false };
    for (let end = 2; end <= n; end++) {
      for (let start = end - 2; start >= 0; start--) {
        const prev = best[start];
        if (!prev) continue;
        const piece = lowerChars.slice(start, end).join('');
        let isKnown = words.has(piece);
        let isFunction = functionWords.has(piece);
        if (Array.from(piece).length < 2) { isKnown = false; isFunction = false; }
        let unknownOK = false;
        if (!isKnown) {
          const len = Array.from(piece).length;
          const startsUpperInside = start > 0 && isUpper(chars[start]) && len >= 3;
          const participleAtStart = start === 0 && len >= 6 && isParticiple(piece);
          unknownOK = startsUpperInside || participleAtStart;
        }
        if (!(isKnown || unknownOK)) continue;
        const candidate = {
          parts: prev.parts + 1,
          unknown: prev.unknown + (isKnown ? 0 : 1),
          cuts: prev.cuts.concat([end]),
          hasFunction: prev.hasFunction || isFunction,
        };
        if (candidate.unknown > 1) continue;
        const current = best[end];
        if (current) {
          if (candidate.unknown < current.unknown || (candidate.unknown === current.unknown && candidate.parts < current.parts)) best[end] = candidate;
        } else {
          best[end] = candidate;
        }
      }
    }
    const path = best[n];
    if (path && path.parts >= 2 && path.hasFunction &&
        !germanEndings.has(lowerChars.slice(path.cuts[path.cuts.length - 2], n).join(''))) {
      const pieces = [];
      for (let i = 0; i < path.cuts.length - 1; i++) pieces.push(chars.slice(path.cuts[i], path.cuts[i + 1]).join(''));
      return pieces.join(' ');
    }
    return splitUnknownPrefix(chars, lowerChars);
  }

  function splitUnknownPrefix(chars, lower) {
    const n = chars.length;
    if (n < 8) return null;
    for (let k = 3; k <= n - 5; k++) {
      const rest = knownSegmentation(lower.slice(k));
      if (!rest || Array.from(rest[0]).length < 3 || germanEndings.has(rest[rest.length - 1])) continue;
      const hasFunction = rest.some(w => functionWords.has(w));
      const hasVerb = rest.some(w => Array.from(w).length >= 5 && !compoundTails.some(t => w.endsWith(t)) &&
        (isParticiple(w) || (w.endsWith('ed') && contentWords.has(w))));
      const okRest = hasVerb && (rest.length === 1 || hasFunction);
      if (!okRest) continue;
      const pieces = [chars.slice(0, k).join('')];
      let pos = k;
      for (const word of rest) {
        const len = Array.from(word).length;
        pieces.push(chars.slice(pos, pos + len).join(''));
        pos += len;
      }
      return pieces.join(' ');
    }
    return null;
  }

  function knownSegmentation(chars) {
    const n = chars.length;
    const best = new Array(n + 1).fill(null);
    best[0] = [];
    for (let end = 2; end <= Math.max(2, n); end++) {
      if (end > n) break;
      for (let start = end - 2; start >= 0; start--) {
        const prev = best[start];
        if (!prev) continue;
        const piece = chars.slice(start, end).join('');
        if (!words.has(piece)) continue;
        if (best[end] === null || prev.length + 1 < best[end].length) best[end] = prev.concat([piece]);
      }
    }
    return best[n];
  }

  const api = { SynthesisLexicon: { functionWords, contentWords, neverSplit, words, segment } };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
