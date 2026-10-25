// Suche über das ganze Journal – entspricht Services/JournalSearch.swift.
//
// Jedes Wort der Suche muss im Ansatz vorkommen (UND). Ein Wort trifft Titel, Beschreibung und Texte der Stufen,
// Chemikalien- und Produktnamen ("n-BuLi" ≈ "nBuLi", "CH₂Cl₂" ≈ "CH2Cl2"), Synonyme ("n-BuLi" findet
// "n-Butyllithium") und CAS-Nummern – direkt, über die Synonymliste, die lokale CAS-Datenbank und das Journal
// selbst (heißt eine Zeile "n-BuLi" und hat CAS 109-72-8, findet "n-BuLi" alle Zeilen mit dieser CAS).
(function (g) {
  'use strict';
  const { normalizeCAS } = typeof module === 'object' && module.exports ? require('./casnumber.js') : g.CJ;

  const digitFold = {};
  '₀₁₂₃₄₅₆₇₈₉'.split('').forEach((c, i) => { digitFold[c] = String(i); });
  '⁰¹²³⁴⁵⁶⁷⁸⁹'.split('').forEach((c, i) => { digitFold[c] = String(i); });
  for (let i = 0; i < 10; i++) digitFold[String.fromCodePoint(0x1D7CE + i)] = String(i);
  const dropChars = "-–·.,()[]{}'’′/_";

  /** Suchtext vergleichbar machen: klein, ohne Akzente, ohne Leer-/Bindestriche/Punkte; Tief-/Fettziffern als Ziffern. */
  function normalizeSearch(s) {
    const folded = String(s).normalize('NFD').replace(/\p{M}/gu, '').normalize('NFC').toLowerCase()
      .replace(/[！-～]/g, c => String.fromCharCode(c.charCodeAt(0) - 0xFEE0));
    let out = '';
    for (const c of Array.from(folded)) {
      if (digitFold[c] !== undefined) { out += digitFold[c]; continue; }
      if (/\s/u.test(c) || dropChars.includes(c)) continue;
      out += c;
    }
    return out;
  }

  /** Häufige Abkürzungen und Namen derselben Chemikalie (deutsch/englisch) mit CAS-Nummer. */
  const synonymGroups = [
    { cas: "109-72-8", names: ["n-BuLi", "BuLi", "n-Butyllithium", "Butyllithium", "n-butyllithium"] },
    { cas: "598-30-1", names: ["s-BuLi", "sec-BuLi", "sec-Butyllithium"] },
    { cas: "594-19-4", names: ["t-BuLi", "tert-BuLi", "tert-Butyllithium"] },
    { cas: "917-54-4", names: ["MeLi", "Methyllithium"] },
    { cas: "4111-54-0", names: ["LDA", "Lithiumdiisopropylamid", "lithium diisopropylamide"] },
    { cas: "4039-32-1", names: ["LiHMDS", "LHMDS", "Lithiumhexamethyldisilazid", "lithium bis(trimethylsilyl)amide"] },
    { cas: "1070-89-9", names: ["NaHMDS", "Natriumhexamethyldisilazid", "sodium bis(trimethylsilyl)amide"] },
    { cas: "40949-94-8", names: ["KHMDS", "Kaliumhexamethyldisilazid", "potassium bis(trimethylsilyl)amide"] },
    { cas: "75-16-1", names: ["MeMgBr", "Methylmagnesiumbromid", "methylmagnesium bromide"] },
    { cas: "109-99-9", names: ["THF", "Tetrahydrofuran"] },
    { cas: "75-09-2", names: ["DCM", "CH2Cl2", "Dichlormethan", "Methylenchlorid", "dichloromethane"] },
    { cas: "67-66-3", names: ["CHCl3", "Chloroform", "Trichlormethan"] },
    { cas: "68-12-2", names: ["DMF", "Dimethylformamid", "N,N-Dimethylformamid", "dimethylformamide"] },
    { cas: "67-68-5", names: ["DMSO", "Dimethylsulfoxid", "dimethyl sulfoxide"] },
    { cas: "75-05-8", names: ["MeCN", "CH3CN", "Acetonitril", "acetonitrile"] },
    { cas: "141-78-6", names: ["EtOAc", "AcOEt", "Ethylacetat", "Essigester", "Essigsäureethylester", "ethyl acetate"] },
    { cas: "60-29-7", names: ["Et2O", "Diethylether", "diethyl ether"] },
    { cas: "67-56-1", names: ["MeOH", "Methanol"] },
    { cas: "64-17-5", names: ["EtOH", "Ethanol"] },
    { cas: "67-63-0", names: ["iPrOH", "Isopropanol", "2-Propanol"] },
    { cas: "108-88-3", names: ["Toluol", "toluene", "PhMe"] },
    { cas: "110-54-3", names: ["Hexan", "n-Hexan", "hexane"] },
    { cas: "109-66-0", names: ["Pentan", "n-Pentan", "pentane"] },
    { cas: "67-64-1", names: ["Aceton", "acetone"] },
    { cas: "7732-18-5", names: ["H2O", "Wasser", "water"] },
    { cas: "121-44-8", names: ["Et3N", "NEt3", "TEA", "Triethylamin", "triethylamine"] },
    { cas: "7087-68-5", names: ["DIPEA", "DIEA", "Hünig-Base", "Diisopropylethylamin", "N,N-diisopropylethylamine"] },
    { cas: "108-18-9", names: ["Diisopropylamin", "iPr2NH", "DIPA", "diisopropylamine"] },
    { cas: "110-86-1", names: ["Pyridin", "pyridine"] },
    { cas: "1122-58-3", names: ["DMAP", "4-Dimethylaminopyridin"] },
    { cas: "6674-22-2", names: ["DBU"] },
    { cas: "584-08-7", names: ["K2CO3", "Kaliumcarbonat", "potassium carbonate"] },
    { cas: "534-17-8", names: ["Cs2CO3", "Cäsiumcarbonat", "cesium carbonate"] },
    { cas: "7646-69-7", names: ["NaH", "Natriumhydrid", "sodium hydride"] },
    { cas: "16940-66-2", names: ["NaBH4", "Natriumborhydrid", "sodium borohydride"] },
    { cas: "16853-85-3", names: ["LiAlH4", "LAH", "Lithiumaluminiumhydrid", "lithium aluminum hydride"] },
    { cas: "1191-15-7", names: ["DIBAL-H", "DIBAL", "DIBAH", "Diisobutylaluminiumhydrid"] },
    { cas: "76-05-1", names: ["TFA", "Trifluoressigsäure", "trifluoroacetic acid"] },
    { cas: "7647-01-0", names: ["HCl", "Salzsäure", "hydrochloric acid"] },
    { cas: "7664-93-9", names: ["H2SO4", "Schwefelsäure", "sulfuric acid"] },
    { cas: "64-19-7", names: ["AcOH", "Essigsäure", "acetic acid"] },
    { cas: "14221-01-3", names: ["Pd(PPh3)4", "Tetrakis(triphenylphosphin)palladium"] },
    { cas: "3375-31-3", names: ["Pd(OAc)2", "Palladium(II)-acetat", "palladium acetate"] },
    { cas: "603-35-0", names: ["PPh3", "Triphenylphosphin", "triphenylphosphine"] },
    { cas: "128-08-5", names: ["NBS", "N-Bromsuccinimid", "N-bromosuccinimide"] },
    { cas: "937-14-4", names: ["mCPBA", "m-CPBA", "meta-Chlorperbenzoesäure"] },
    { cas: "24424-99-5", names: ["Boc2O", "Di-tert-butyldicarbonat", "Boc-Anhydrid"] },
    { cas: "18162-48-6", names: ["TBSCl", "TBDMSCl", "tert-Butyldimethylsilylchlorid"] },
    { cas: "75-77-4", names: ["TMSCl", "Trimethylsilylchlorid", "chlorotrimethylsilane"] },
    { cas: "7226-23-5", names: ["DMPU"] },
    { cas: "680-31-9", names: ["HMPA", "Hexamethylphosphorsäuretriamid"] },
    { cas: "110-18-9", names: ["TMEDA", "Tetramethylethylendiamin"] },
    { cas: "7681-65-4", names: ["CuI", "Kupfer(I)-iodid", "copper(I) iodide"] },
    { cas: "7726-95-6", names: ["Br2", "Brom", "bromine"] },
    { cas: "7553-56-2", names: ["I2", "Iod", "Jod", "iodine"] },
    { cas: "1310-73-2", names: ["NaOH", "Natriumhydroxid", "Natronlauge", "sodium hydroxide"] },
    { cas: "1310-58-3", names: ["KOH", "Kaliumhydroxid", "Kalilauge", "potassium hydroxide"] },
    { cas: "865-47-4", names: ["KOtBu", "tBuOK", "Kalium-tert-butanolat", "potassium tert-butoxide"] },
    { cas: "10294-33-4", names: ["BBr3", "Bortribromid", "boron tribromide"] },
    { cas: "10025-87-3", names: ["POCl3", "Phosphorylchlorid", "phosphoryl chloride"] },
    { cas: "7719-09-7", names: ["SOCl2", "Thionylchlorid", "thionyl chloride"] },
    { cas: "79-37-8", names: ["(COCl)2", "Oxalylchlorid", "oxalyl chloride"] }
  ];
  const synonymIndex = new Map();
  for (const grp of synonymGroups) for (const n of grp.names) synonymIndex.set(normalizeSearch(n), grp);

  /** Lange Namen: enthalten; kurze (≤ 3 Zeichen): als eigenes Wort ("THF" in "THF-Lösung", "Br2" nicht in "CuBr2"). */
  function nameMatches(rowName, names) {
    const whole = normalizeSearch(rowName);
    if (!whole) return false;
    let words = null;
    for (const n of names) {
      if (!n) continue;
      if (Array.from(n).length > 3) { if (whole.includes(n)) return true; }
      else {
        if (whole === n) return true;
        if (!words) words = new Set(String(rowName).split(/[^\p{L}\p{N}₀-₉]+/u).filter(Boolean).map(normalizeSearch));
        if (words.has(n)) return true;
      }
    }
    return false;
  }

  /**
   * @param {string} query
   * @param {object[]} projects
   * @param {(normalizedTerm: string) => string[]} [casNumbersForName] CAS-Nummern aus der lokalen CAS-Datenbank
   */
  function JournalSearch(query, projects, casNumbersForName) {
    const words = String(query).split(/\s+/).filter(Boolean);
    const rows = [];
    for (const p of projects) for (const e of p.experiments) for (const s of e.stages) {
      for (const c of s.chemicals) rows.push([c.name, normalizeCAS(c.cas) || '']);
      for (const y of s.yieldProducts) rows.push([y.name, normalizeCAS(y.cas) || '']);
    }
    const terms = words.map(word => {
      const norm = normalizeSearch(word);
      const names = new Set([norm]);
      const cas = new Set();
      const direct = normalizeCAS(word);
      if (direct) cas.add(direct);
      const grp = synonymIndex.get(norm);
      if (grp) { cas.add(grp.cas); grp.names.forEach(n => names.add(normalizeSearch(n))); }
      if (casNumbersForName && Array.from(norm).length >= 3) casNumbersForName(norm).forEach(c => cas.add(c));
      if (Array.from(norm).length >= 2) {
        for (const [name, c] of rows) if (c && nameMatches(name, names)) cas.add(c);
      }
      return { raw: word.toLowerCase(), normalized: norm, names, cas };
    });

    function textMatches(term, e) {
      const q = term.raw;
      if (e.title.toLowerCase().includes(q) || e.summary.toLowerCase().includes(q)) return true;
      return e.stages.some(s => [s.title, s.summary, s.procedure, s.observation, s.sourceURL].some(t => (t || '').toLowerCase().includes(q)));
    }

    /** null, wenn der Ansatz nicht passt; sonst die Treffer in Tabellenzeilen (kann leer sein). */
    function hits(experiment) {
      if (!terms.length) return [];
      const result = [];
      for (const term of terms) {
        let matched = textMatches(term, experiment);
        for (const stage of experiment.stages) {
          const list = stage.chemicals.map(c => [c.name, c.cas, false]).concat(stage.yieldProducts.map(y => [y.name, y.cas, true]));
          for (const [name, rawCAS, isProduct] of list) {
            const c = normalizeCAS(rawCAS);
            const byName = nameMatches(name, term.names);
            const byCAS = c ? term.cas.has(c) : false;
            if (!byName && !byCAS) continue;
            matched = true;
            const display = name ? name : (c || rawCAS);
            const casPart = c && name ? ` (${c})` : '';
            const label = `${display}${casPart}${isProduct ? ' – Produkt' : ''} · ${stage.title}`;
            if (!result.includes(label)) result.push(label);
          }
        }
        if (!matched) return null;
      }
      return result;
    }

    return { isEmpty: terms.length === 0, hits };
  }

  const api = { normalizeSearch, synonymGroups, nameMatches, JournalSearch };
  if (typeof module === 'object' && module.exports) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
