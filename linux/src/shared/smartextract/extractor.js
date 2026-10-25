// Smart Extract – entspricht Services/SmartExtract/SmartExtractor.swift.
//
// Wandelt eine Synthesevorschrift in Zeilen der Ansatzgrößen-Tabelle um:
// 1. normalizeSynthesisText repariert PDF-Artefakte.
// 2. Tokenisierung nach den Unicode-Wortgrenzen (wie NLTagger auf dem Mac).
// 3. Ein deterministischer Parser liest Zahl + Einheit, ordnet Mengen den Namen zu und filtert Temperaturen,
//    Zeiten, Konzentrationen, Kolbengrößen und Aufarbeitungsschritte heraus.
//
// Auf dem Mac entscheidet zusätzlich ein Core-ML-Modell, welche Wörter Chemikaliennamen sind. Core ML gibt es
// unter Linux nicht; stattdessen markiert ein Namenslexikon aus denselben Trainingsdaten bekannte Namen
// (chemlexicon.js). Unbekannte Wörter beurteilt wie auf dem Mac die Heuristik.
(function (g) {
  'use strict';
  const node = typeof module === 'object' && module.exports;
  const { normalizeSynthesisText } = node ? require('./normalizer.js') : g.CJ;
  const { parseDecimal, format3, format4 } = node ? require('../numberformat.js') : g.CJ;
  const optionalRequire = (file, name) => {
    if (!node) return (g.CJ && g.CJ[name]) || null;
    try { return require(file)[name]; } catch (e) { return null; }
  };
  const chemLexicon = optionalRequire('./chemlexicon.js', 'ChemLexicon');
  const chemClassifier = optionalRequire('./chemclassifier.js', 'ChemClassifier');
  const chemFeatures = optionalRequire('./chemfeatures.js', 'features');

  /** Wahrscheinlichkeit, dass ein Wortteil ein Chemikalienname ist (Ersatz für das Core-ML-Modell). */
  function chemProbability(word) {
    if (!chemClassifier || !chemFeatures) return 0;
    let z = chemClassifier.bias;
    for (const f of chemFeatures(word)) z += chemClassifier.weights.get(f) || 0;
    return 1 / (1 + Math.exp(-z));
  }

  const isUpper = c => c !== undefined && /\p{Lu}/u.test(c);
  const isLetter = c => c !== undefined && /\p{L}/u.test(c);
  const isNumber = c => c !== undefined && /\p{N}/u.test(c);
  const isWS = c => /\s/u.test(c);
  const allWS = s => Array.from(s).every(isWS);
  const chars = s => Array.from(s);
  const countOf = (s, c) => { let n = 0; for (const x of s) if (x === c) n++; return n; };
  const trimSet = (s, set) => {
    const a = chars(s);
    let i = 0, j = a.length;
    while (i < j && set.includes(a[i])) i++;
    while (j > i && set.includes(a[j - 1])) j--;
    return a.slice(i, j).join('');
  };

  // MARK: - Tokenisierung

  const segmenter = new Intl.Segmenter('en', { granularity: 'word' });

  /** Wörter und Symbole (°, +, ×, …); Leerraum und Satzzeichen fallen weg – wie NLTagger mit omitPunctuation. */
  /**
   * @param {string} text
   * @param {'classifier'|'lexicon'|'none'|boolean} nameModel Wie Namen markiert werden (true = 'classifier').
   */
  function tokenize(text, nameModel) {
    const mode = nameModel === true ? 'classifier' : nameModel === false || nameModel == null ? 'none' : nameModel;
    const tokens = [];
    for (const seg of segmenter.segment(text)) {
      const t = seg.segment;
      if (/^\s+$/u.test(t)) continue;
      if (!seg.isWordLike && /^\p{P}+$/u.test(t)) continue;
      tokens.push({ text: t, start: seg.index, end: seg.index + t.length, tag: null });
    }
    if (mode === 'lexicon' && chemLexicon) {
      for (const tok of tokens) if (chemLexicon.has(tok.text.toLowerCase())) tok.tag = 'CHEMICAL';
    } else if (mode === 'classifier' && chemClassifier) {
      for (const tok of tokens) {
        if (/\p{L}/u.test(tok.text) && chemProbability(tok.text) >= chemClassifier.threshold) tok.tag = 'CHEMICAL';
      }
    }
    return tokens;
  }

  const joinerCharacters = "-()[]/·'’′″,+";

  /** Ein "Wort" sind Tokens, die nur durch Bindezeichen ohne Leerraum verbunden sind ("n-Butyllithium-Lösung", "Pd(PPh3)4"). */
  function groupIntoWords(tokens, text) {
    const words = [];
    let previousEnd = 0;
    for (const token of tokens) {
      const gap = text.slice(previousEnd, token.start);
      const joins = words.length > 0 && chars(gap).every(c => joinerCharacters.includes(c));
      if (joins) {
        const w = words[words.length - 1];
        w.tokens.push(token);
        w.end = token.end;
      } else {
        words.push({ tokens: [token], gapBefore: gap, gapStart: previousEnd, start: token.start, end: token.end });
      }
      previousEnd = token.end;
    }
    return words;
  }

  // MARK: - Einheiten

  const Q = (kind, factor) => ({ kind, factor });
  const unitTable = {
    mg: Q('mass', 1e-3), 'µg': Q('mass', 1e-6), ug: Q('mass', 1e-6), g: Q('mass', 1), kg: Q('mass', 1e3),
    mmol: Q('amount', 1e-3), 'µmol': Q('amount', 1e-6), umol: Q('amount', 1e-6), nmol: Q('amount', 1e-9), mol: Q('amount', 1),
    ml: Q('volume', 1), 'µl': Q('volume', 1e-3), ul: Q('volume', 1e-3), l: Q('volume', 1e3), cm3: Q('volume', 1),
    eq: Q('eq', 1), equiv: Q('eq', 1), equivs: Q('eq', 1), equivalent: Q('eq', 1), equivalents: Q('eq', 1),
    'äq': Q('eq', 1), 'äquiv': Q('eq', 1), 'äquivalente': Q('eq', 1),
  };

  const Units = {
    quantity(rawUnit, gapAfter) {
      const unit = trimSet(rawUnit, ['.']).toLowerCase();
      const gap = gapAfter.replace(/^ +/, '');
      if (unit === 'mol' && (gap.startsWith('%') || gap.startsWith('-%'))) return Q('eq', 0.01);
      if (unit === 'mol%' || unit === 'mol-%') return Q('eq', 0.01);
      return Object.prototype.hasOwnProperty.call(unitTable, unit) ? unitTable[unit] : null;
    },
    isConcentration(rawUnit) {
      return ['M', 'N', 'mM', 'µM'].includes(rawUnit) || ['mol/l', 'mol/dm3', 'mmol/l'].includes(rawUnit.toLowerCase());
    },
    ignored: new Set([
      'min', 'mins', 'minute', 'minuten', 'minutes', 'h', 'hr', 'hrs', 'std', 'stunde', 'stunden', 'hour', 'hours',
      's', 'sec', 'sekunden', 'seconds', 'd', 'tag', 'tage', 'day', 'days', 'bar', 'mbar', 'atm', 'torr', 'psi', 'pa',
      'kpa', 'hpa', 'nm', 'w', 'mw', 'rpm', 'upm', 'å', 'k', 'x', '×', 'mhz', 'ppm', 'wt', 'gew',
    ]),
    isIgnoredUnit(rawUnit) { return this.ignored.has(rawUnit.toLowerCase()); },
  };

  // MARK: - Wortlisten

  const Vocabulary = {
    stopwords: new Set([
      // Deutsch
      'vorgelegt', 'zugegeben', 'hinzugegeben', 'addiert', 'zugetropft', 'hinzugetropft', 'getropft', 'gelöst', 'gerührt',
      'nachgerührt', 'abgekühlt', 'gekühlt', 'erwärmt', 'erhitzt', 'versetzt', 'behandelt', 'suspendiert', 'verdünnt',
      'gegeben', 'eingewogen', 'kombiniert', 'vereinigt', 'zugefügt', 'hinzugefügt', 'überführt', 'refluxiert',
      'die', 'der', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einer', 'eines', 'einem', 'einen', 'in', 'im', 'zu', 'zum',
      'zur', 'von', 'vom', 'nach', 'mit', 'auf', 'bei', 'für', 'über', 'unter', 'aus', 'als', 'und', 'oder', 'sowie',
      'es', 'wurde', 'wurden', 'wird', 'werden', 'dazu', 'hierzu', 'zunächst', 'anschließend', 'danach', 'dann',
      'weiteren', 'weitere', 'langsam', 'tropfenweise', 'portionsweise', 'vorsichtig', 'sofort', 'erneut', 'zusätzlich',
      'minuten', 'stunden', 'min', 'h', 'lösung', 'lösungen', 'gemisch', 'reaktionsgemisch', 'mischung', 'phase',
      'suspension', 'trockenem', 'trockenen', 'trockenes', 'wasserfreiem', 'wasserfreien', 'absolutem', 'abs',
      'frisch', 'destilliertem', 'entgastem', 'kolben', 'rundkolben', 'raumtemperatur', 'rt', 'rückfluss', 'argon',
      'stickstoff', 'schutzgas', 'atmosphäre', 'dieser', 'diese', 'dieses', 'diesem', 'letztes', 'zuletzt', 'nun',
      'insgesamt', 'jeweils', 'ca', 'etwa', 'gesättigter', 'gesättigte', 'ges', 'wässriger', 'wässrige', 'konz',
      'konzentrierte', 'konzentrierter', 'verdünnte', 'verdünnter', 'brauner', 'weißer', 'gelber', 'feststoff',
      'öl', 'reaktion', 'zugabe', 'beginn', 'ende', 'rühren', 'kühlen', 'erwärmen',
      // Englisch
      'added', 'stirred', 'dissolved', 'cooled', 'warmed', 'heated', 'treated', 'diluted', 'suspended', 'charged',
      'introduced', 'sequentially', 'combined', 'placed', 'transferred', 'dropwise', 'portionwise', 'slowly',
      'the', 'a', 'an', 'to', 'of', 'in', 'into', 'on', 'at', 'by', 'for', 'with', 'from', 'and', 'or', 'then',
      'after', 'over', 'under', 'was', 'were', 'is', 'are', 'this', 'that', 'which', 'it', 'as', 'further',
      'additional', 'again', 'solution', 'solutions', 'mixture', 'reaction', 'flask', 'vial', 'tube', 'room',
      'temperature', 'reflux', 'dry', 'anhydrous', 'freshly', 'distilled', 'degassed', 'nitrogen', 'atmosphere',
      'minutes', 'hours', 'hour', 'minute', 'overnight', 'sat', 'saturated', 'aq', 'aqueous', 'conc',
      'concentrated', 'solid', 'oil', 'until', 'followed', 'successively', 'portion', 'portions', 'one',
      // Analytik und Labor-Kürzel
      'nmr', 'tlc', 'dc', 'hplc', 'gc', 'ms', 'ir', 'uv', 'led', 'aav', 'esi', 'hrms', 'rf', 'ph', 'smp', 'mp',
      '1h', '13c', '19f', '31p', 'dest', 'anhyd', 'crude', 'technical', 'grade', 'purity', 'reinheit', 'technisch', 'mineralöl', 'mineral', 'paraffin', 'suspension', 'wt', 'gew',
    ]),
    clauseOpeners: new Set([
      'which', 'then', 'followed', 'whereupon', 'before', 'prior', 'anschließend', 'danach', 'wobei', 'bevor', 'worauf',
      'woraufhin', 'nachdem',
    ]),
    reactionVerbs: new Set([
      'treated', 'added', 'addiert', 'zugegeben', 'versetzt', 'zugetropft', 'behandelt', 'hinzugegeben', 'hinzugefügt',
      'zugefügt',
    ]),
    workupWords: new Set([
      'extrahiert', 'extracted', 'gewaschen', 'washed', 'getrocknet', 'dried', 'filtriert', 'abfiltriert', 'filtered',
      'eingeengt', 'eingedampft', 'abrotiert', 'concentrated', 'evaporated', 'gequencht', 'quenched', 'gereinigt',
      'purified', 'chromatographiert', 'chromatographed', 'umkristallisiert', 'recrystallized', 'eluiert', 'eluted',
      'erhalten', 'obtained', 'afforded', 'furnished', 'yielded', 'isoliert', 'isolated', 'ergab', 'lieferte',
      'aufgearbeitet', 'dekantiert', 'decanted', 'beendet', 'ausbeute', 'yield', 'rohprodukt', 'rohproduktes',
      'erhielt', 'quench', 'quenching', 'poured', 'gegossen', 'silica', 'kieselgel', 'slurry', 'brine',
      'filtration', 'evaporation', 'extraction', 'eingedampft', 'rotiert',
    ]),
    abbreviations: new Set([
      'eq', 'equiv', 'äq', 'äquiv', 'abs', 'ca', 'approx', 'conc', 'konz', 'ges', 'sat', 'aq', 'wässr', 'bzw', 'vgl',
      'resp', 'ref', 'nr', 'no', 'fig', 'abb', 'tab', 'lit', 'et', 'al', 'e.g', 'i.e', 'z.b', 'u.a', 'techn', 'dest', 'anhyd',
      'frisch', 'ca', 'vs', 'wt',
    ]),
    labelNouns: new Set([
      'compound', 'verbindung', 'substrat', 'substrate', 'edukt', 'ester', 'amin', 'amine', 'alkohol', 'alcohol',
      'aldehyd', 'aldehyde', 'material', 'startmaterial', 'salt', 'salz', 'ketone', 'keton', 'bromide', 'bromid',
      'iodide', 'iodid', 'acid', 'säure', 'amide', 'amid', 'alkyne', 'alkin', 'alkene', 'olefin', 'intermediate',
      'zwischenprodukt', 'precursor', 'vorstufe', 'ligand', 'catalyst', 'katalysator', 'complex', 'komplex',
      'diol', 'epoxide', 'epoxid', 'azide', 'azid', 'triflate', 'triflat', 'sulfonamide', 'sulfonamid', 'enone', 'enon',
      'acetylene', 'alkyne', 'nitrile', 'nitril', 'sulfone', 'sulfon', 'phenylsulfone', 'carbonate', 'carbonat', 'tosylate',
      'mesylate', 'boronate', 'lactone', 'lacton', 'imine', 'imin', 'oxime', 'oxim', 'sulfide', 'thiol', 'phenol', 'aniline',
      'anilin', 'indole', 'indol', 'pyridine', 'pyridin', 'olefine', 'alcohols', 'esters', 'derivative', 'derivat', 'nitrone',
    ]),
    apparatus: [
      'kolben', 'flask', 'vial', 'tube', 'gefäß', 'reaktor', 'reactor', 'schlenk', 'ampulle', 'ampoule', 'autoklav',
      'autoclave', 'trichter', 'funnel', 'spritze', 'syringe', 'becherglas', 'beaker', 'atmosph', 'ballon', 'balloon',
    ],
    solutionSuffixes: ['-lösung', ' lösung', '-solution', ' solution', '-suspension', ' suspension'],
  };
  Vocabulary.labelIntroducers = new Set([...Vocabulary.labelNouns, 'von', 'of', 'nr', 'no']);

  // MARK: - Heuristik für Chemikaliennamen

  const ChemicalHeuristics = (() => {
    const knownNames = new Set([
      'wasser', 'water', 'iod', 'iodine', 'jod', 'brom', 'bromine', 'chlor', 'zink', 'zinc', 'kupfer', 'copper',
      'eisen', 'iron', 'ammoniak', 'ammonia', 'harnstoff', 'urea', 'chloroform', 'aceton', 'acetone', 'ether',
      'äther', 'diethylether', 'dioxan', 'dioxane', 'hexan', 'hexane', 'hexanes', 'heptan', 'heptane', 'pentan',
      'pentane', 'pentanes', 'toluol', 'toluene', 'benzol', 'benzene', 'xylol', 'xylene', 'acetonitril',
      'acetonitrile', 'essigester', 'ethylacetat', 'pyridin', 'pyridine', 'oxone', 'celite', 'selectfluor',
      'triphosgen', 'triphosgene', 'phosgen', 'phosgene', 'formalin', 'paraformaldehyd', 'hydrazin', 'hydrazine',
      'magnesium', 'lithium', 'natrium', 'kalium', 'sodium', 'potassium', 'palladium', 'platin', 'platinum',
      'nickel', 'raney', 'dess-martin', 'periodinan', 'periodinane', 'grubbs', 'wilkinson', 'lawesson', 'burgess',
      'mesyl', 'tosyl', 'trityl', 'benzyl', 'allyl', 'vinyl', 'phenyl', 'methyl', 'ethyl', 'propyl', 'butyl',
      'isopropanol', 'methanol', 'ethanol', 'butanol', 'propanol', 'glycerin', 'glycerol', 'dichlormethan',
      'dichloromethane', 'chlorbenzol', 'chlorobenzene', 'piperidin', 'piperidine', 'morpholin', 'morpholine',
      'imidazol', 'imidazole', 'triethylamin', 'triethylamine', 'anilin', 'aniline',
    ]);
    const suffixes = [
      'amin', 'amine', 'amid', 'amide', 'imid', 'imide', 'anol', 'enol', 'anon', 'anone', 'enon', 'enone', 'ol',
      'säure', 'acid', 'ester', 'ether', 'aldehyd', 'aldehyde', 'keton', 'ketone', 'nitril', 'nitrile',
      'chlorid', 'chloride', 'bromid', 'bromide', 'iodid', 'iodide', 'jodid', 'fluorid', 'fluoride', 'hydrid',
      'hydride', 'oxid', 'oxide', 'sulfid', 'sulfide', 'cyanid', 'cyanide', 'azid', 'azide', 'hydroxid', 'hydroxide',
      'carbonat', 'carbonate', 'sulfat', 'sulfate', 'sulfit', 'sulfite', 'nitrat', 'nitrate', 'nitrit', 'nitrite',
      'phosphat', 'phosphate', 'acetat', 'acetate', 'formiat', 'formate', 'triflat', 'triflate', 'tosylat',
      'tosylate', 'mesylat', 'mesylate', 'borat', 'borate', 'chromat', 'chromate', 'perchlorat', 'perchlorate',
      'hydrat', 'hydrate', 'ium', 'benzol', 'benzene', 'toluol', 'pyridin', 'pyridine', 'furan', 'thiophen',
      'thiophene', 'indol', 'indole', 'phenol', 'anilin', 'aniline', 'methan', 'ethan', 'propan', 'butan', 'pentan',
      'hexan', 'heptan', 'octan', 'decan', 'ane', 'oate', 'oic', 'ylat', 'ylate', 'silan', 'silane', 'stannan',
      'boran', 'borane', 'phosphin', 'phosphine', 'phosphan', 'oxim', 'oxime', 'hydrazon', 'hydrazone', 'lacton',
      'lactone', 'lactam', 'imin', 'imine', 'azol', 'azole', 'azin', 'azine', 'idin', 'idine', 'olin', 'oline',
      'yl', 'pulver', 'staub', 'späne', 'chips', 'periodinan', 'periodinane',
    ];
    const elementSymbols = new Set([
      'Pd', 'Pt', 'Zn', 'Mg', 'Cu', 'Fe', 'Na', 'Li', 'Ni', 'Rh', 'Ru', 'Ir', 'Au', 'Ag', 'Sn', 'Al', 'Se', 'Mn',
      'Cr', 'Hg', 'Pb', 'Cs', 'Sm', 'Ce', 'Si', 'Ti', 'Co', 'Os', 'Zr', 'Sc', 'Yb', 'In',
    ]);
    const cationPrefixes = [
      'natrium', 'kalium', 'lithium', 'cäsium', 'caesium', 'cesium', 'calcium', 'magnesium', 'ammonium', 'tetrabutylammonium',
      'silber', 'kupfer', 'eisen', 'zink', 'palladium', 'platin', 'nickel', 'cobalt', 'kobalt', 'mangan', 'chrom',
      'barium', 'aluminium', 'titan', 'zinn', 'quecksilber', 'blei', 'sodium', 'potassium', 'silver',
    ];
    const singleLetterElements = new Set(['C', 'H', 'N', 'O', 'S', 'P', 'I', 'K', 'B', 'F']);
    const continuationSuffixes = ['ate', 'ite', 'ide', 'ine', 'ane', 'ene', 'yne', 'one', 'ol', 'al', 'salt', 'complex', 'sieves', 'monohydrate', 'dihydrate', 'hydrochloride'];
    const continuationWords = new Set([
      'acid', 'acids', 'salt', 'ester', 'anhydride', 'chloride', 'bromide', 'iodide', 'fluoride', 'oxide', 'hydride',
      'hydroxide', 'hydrate', 'monohydrate', 'dihydrate', 'complex', 'sieves', 'alcohol', 'aldehyde', 'ketone', 'amide',
      'amine', 'ether', 'acetate', 'carbonate', 'sulfate', 'nitrate', 'phosphate', 'triflate', 'säure', 'salz',
    ]);
    const prefixWords = ['n', 's', 't', 'i', 'o', 'm', 'p', 'sec', 'tert', 'iso', 'cis', 'trans', 'rac', 'bis', 'tris', 'tetrakis', 'di', 'tri'];
    const separators = "-()[]/·,'’+";
    const len = s => chars(s).length;

    function looksLikeChemical(raw) {
      const word = trimSet(raw, ['.', ',', ';', ':']);
      if (!word) return false;
      const lower = word.toLowerCase();
      if (Vocabulary.stopwords.has(lower)) return false;
      const parts = [];
      let cur = '';
      for (const c of chars(word)) {
        if (separators.includes(c)) { if (cur) parts.push(cur); cur = ''; } else cur += c;
      }
      if (cur) parts.push(cur);
      if (parts.length > 1) {
        if (prefixWords.includes(parts[0].toLowerCase())) return true;
        if (chars(parts[0]).every(isNumber) && parts.slice(1).some(p => len(p) >= 3)) return true;
        if (parts.every(p => elementSymbols.has(p) || singleLetterElements.has(p)) && parts.some(p => elementSymbols.has(p))) return true;
        return parts.some(p => p && looksLikeSingleChemical(p));
      }
      return looksLikeSingleChemical(word);
    }

    function looksLikeSingleChemical(word) {
      const lower = word.toLowerCase();
      if (Vocabulary.stopwords.has(lower)) return false;
      if (knownNames.has(lower) || elementSymbols.has(word)) return true;
      const cs = chars(word);
      const letters = cs.filter(isLetter);
      const digits = cs.filter(isNumber);
      if (letters.length && digits.length && isLetter(cs[0])) return true;
      if (cs.slice(1).some(isUpper) && letters.length >= 2) return true;
      const l = len(lower);
      const stems = l >= 8 && lower.endsWith('s') ? [lower, chars(lower).slice(0, -1).join('')] : [lower];
      if (l >= 5 && stems.some(stem => suffixes.some(suf => stem.endsWith(suf)))) return true;
      if (l >= 6 && ['ene', 'yne', 'en', 'in'].some(suf => lower.endsWith(suf)) &&
          ['nitro', 'chlor', 'brom', 'fluor', 'iod', 'methyl', 'ethyl', 'phenyl', 'benz'].some(p => lower.startsWith(p))) return true;
      if (l >= 4 && lower.endsWith('yl')) return true;
      const prefix = cationPrefixes.find(p => lower.startsWith(p));
      if (prefix && l >= len(prefix) + 3) return true;
      return false;
    }

    function looksLikeContinuation(raw) {
      if (looksLikeChemical(raw)) return true;
      const lower = raw.toLowerCase();
      if (continuationWords.has(lower)) return true;
      if (Vocabulary.stopwords.has(lower)) return false;
      return len(lower) >= 4 && chars(lower).every(isLetter) && continuationSuffixes.some(suf => lower.endsWith(suf));
    }

    return { looksLikeChemical, looksLikeContinuation };
  })();

  // MARK: - Hilfsfunktionen

  const isCompoundLabel = s => /^[1-9]\d{0,2}[a-z]?$/.test(s);

  function splitGluedQuantity(s) {
    const m = /^\d+(?:[.,]\d+)?/.exec(s);
    if (!m) return null;
    const unit = s.slice(m[0].length);
    const value = parseDecimal(m[0]);
    if (chars(unit).length < 2 || value === null) return null;
    return [value, unit];
  }

  const rowHasAnyQuantity = r => !!(r.equivalents || r.amount || r.volume || r.mass);

  // MARK: - Parser

  class Parser {
    constructor(text, words) {
      this.text = text;
      this.words = words;
      this.rows = [];
      this.current = newPartial();
      this.nameOpen = false;
      this.pendingNameStart = null;
      this.nameClosedByStopword = false;
      this.sawInAfterName = false;
      this.solventAfterIn = false;
      this.lastFlushed = null;
      this.parenDepth = 0;
      this.lastRejectedWord = null;
    }

    wt(w) { return this.text.slice(w.start, w.end); }

    run() {
      for (const sentence of this.splitSentences()) {
        this.flush();
        this.parenDepth = 0;
        const firstRow = this.rows.length;
        for (const clause of this.splitClauses(sentence)) {
          if (this.isWorkupOrProduct(clause)) continue;
          this.parse(clause);
          this.flush();
        }
        if (!this.rows.slice(firstRow).some(rowHasAnyQuantity)) this.rows.splice(firstRow);
      }
      return this.rows;
    }

    // Sätze ------------------------------------------------------------------

    splitSentences() {
      const result = [];
      let start = 0;
      for (let i = 1; i < this.words.length; i++) {
        if (this.isSentenceBoundary(i)) { result.push({ start, end: i }); start = i; }
      }
      if (start < this.words.length) result.push({ start, end: this.words.length });
      return result;
    }

    isSentenceBoundary(i) {
      const words = this.words;
      const gap = words[i].gapBefore;
      if (gap.includes('\n') || gap.includes(';')) return true;
      const prevTokens = words[i - 1].tokens;
      const lastToken = prevTokens[prevTokens.length - 1].text;
      const firstChar = chars(this.wt(words[i]))[0];
      if (chars(lastToken).length > 1 && lastToken.endsWith('.') && chars(gap).some(isWS) && (isUpper(firstChar) || isNumber(firstChar))) {
        const stem = lastToken.slice(0, -1).toLowerCase();
        if (!Vocabulary.abbreviations.has(stem) && !stem.includes('.')) return true;
      }
      if (gap.includes(':') && isUpper(firstChar)) return true;
      const dot = gap.indexOf('.');
      if (dot < 0) return false;
      const after = gap[dot + 1];
      if (after !== undefined && !isWS(after)) return false;
      const previous = this.wt(words[i - 1]).toLowerCase();
      return !Vocabulary.abbreviations.has(previous);
    }

    splitClauses(sentence) {
      const result = [];
      let start = sentence.start;
      const lower = i => (i < sentence.end ? this.wt(this.words[i]).toLowerCase() : '');
      for (let i = sentence.start; i < sentence.end; i++) {
        if (!(i > start)) continue;
        const comma = this.words[i].gapBefore.includes(',');
        const w = lower(i), next = lower(i + 1);
        const boundary = (comma && Vocabulary.clauseOpeners.has(w))
          || (['and', 'und'].includes(w) && ['then', 'anschließend', 'danach', 'dann'].includes(next))
          || (comma && ['and', 'und'].includes(w) && ['the', 'die', 'der', 'das', 'to', 'zu'].includes(next));
        if (boundary) { result.push({ start, end: i }); start = i; }
      }
      result.push({ start, end: sentence.end });
      return result;
    }

    isWorkupOrProduct(clause) {
      const lowers = [];
      for (let i = clause.start; i < clause.end; i++) lowers.push(this.wt(this.words[i]).toLowerCase());
      if (lowers.some(w => Vocabulary.workupWords.has(w))) return true;
      for (let k = 0; k + 1 < lowers.length; k++) {
        if (lowers[k] === 'crude' && ['product', 'residue', 'mixture', 'material', 'oil', 'solid', 'aldehyde', 'ketone', 'alcohol', 'diol'].includes(lowers[k + 1])) return true;
      }
      const saturated = lowers.some(w => ['saturated', 'sat', 'gesättigter', 'gesättigte', 'gesättigtem', 'ges'].includes(w));
      if (saturated && lowers.some(w => ['aqueous', 'aq', 'wässriger', 'wässrige', 'nh4cl', 'nahco3', 'nacl', 'na2s2o3'].some(p => w.startsWith(p)) || w.endsWith('-lösung'))) return true;
      if (lowers.some(w => ['diluted', 'verdünnt'].includes(w)) && !lowers.some(w => Vocabulary.reactionVerbs.has(w))) return true;
      return false;
    }

    // Wortweise Verarbeitung -------------------------------------------------

    parse(sentence) {
      let i = sentence.start;
      const skip = { carrier: false };
      while (i < sentence.end) {
        const word = this.words[i];
        const wordText = this.wt(word);
        const lower = wordText.toLowerCase();

        if (word.gapBefore.includes(',') || word.gapBefore.includes('(') || word.gapBefore.includes(')')) {
          this.nameOpen = false;
          skip.carrier = false;
        }
        const span = this.text.slice(word.gapStart, word.end);
        this.parenDepth = Math.max(0, this.parenDepth + countOf(span, '(') - countOf(span, ')'));
        if (skip.carrier) { i += 1; continue; }
        const rejectedBefore = this.lastRejectedWord;
        this.lastRejectedWord = null;

        // Zahl (+ Einheit)
        const value = word.tokens.length === 1 ? parseDecimal(wordText) : null;
        if (value !== null) {
          if (word.gapBefore.includes('(') && this.current.nameRange === null && !hasQuantity(this.current) &&
              rejectedBefore && i > sentence.start && rejectedBefore.start === this.words[i - 1].start && rejectedBefore.end === this.words[i - 1].end) {
            this.addNameWord(rejectedBefore);
          }
          i = this.handleNumber(value, i, sentence, skip);
          continue;
        }
        // Zahl und Einheit in einem Token ("298.0mg")
        if (word.tokens.length === 1) {
          const glued = splitGluedQuantity(wordText);
          const quantity = glued ? Units.quantity(glued[1], '') : null;
          if (glued && quantity) {
            this.setQuantity(quantity.kind, glued[0] * quantity.factor);
            i += 1;
            continue;
          }
        }

        // Stoppwörter schließen den aktuellen Namen
        if (word.tokens.length === 1 && Vocabulary.stopwords.has(lower)) {
          this.nameOpen = false;
          this.pendingNameStart = null;
          if (lower === 'in' && this.parenDepth > 0 && this.current.nameRange !== null) skip.carrier = true;
          if (lower === 'in' && this.parenDepth === 0 && this.current.nameRange !== null && !hasQuantity(this.current)) this.sawInAfterName = true;
          if (this.parenDepth === 0) {
            if (this.current.nameRange !== null && !hasQuantity(this.current)) this.nameClosedByStopword = true;
            if (this.current.nameRange !== null && hasQuantity(this.current)) this.flush();
          }
          i += 1;
          continue;
        }

        if (isCompoundLabel(wordText)) {
          if (this.acceptCompoundLabel(i, sentence)) this.addLabelWord(word, i, sentence);
          else { this.nameOpen = false; this.lastRejectedWord = word; }
          i += 1;
          continue;
        }

        // Kurzname in Klammern direkt nach dem Namen: "ethyl acetate (EtOAc, 2.0 mL)"
        if (word.gapBefore.includes('(') && this.current.nameRange !== null && !hasQuantity(this.current) &&
            i + 1 < sentence.end && this.words[i + 1].gapBefore.includes(',')) {
          i += 1;
          continue;
        }

        if (this.isChemicalName(word, wordText)) {
          this.addNameWord(word);
        } else {
          this.nameOpen = false;
          this.pendingNameStart = null;
          this.lastRejectedWord = word;
        }
        i += 1;
      }
    }

    handleNumber(value, i, sentence, skip) {
      const words = this.words;
      const numberWord = words[i];
      // Portionsgröße: "in Portionen zu jeweils ca. 0.5 g"
      const before = [];
      for (let k = Math.max(sentence.start, i - 3); k < i; k++) before.push(trimSet(this.wt(words[k]).toLowerCase(), ['.']));
      if (before.some(b => ['jeweils', 'je', 'each', 'portionen', 'portions', 'portion'].includes(b))) {
        if (i + 1 < sentence.end && Units.quantity(this.wt(words[i + 1]), '') !== null) return i + 2;
        return i + 1;
      }
      // "a solution of n-BuLi in hexane (1.44 mL, 3.6 mmol)"
      if (this.parenDepth > 0 && this.solventAfterIn && !hasQuantity(this.current) && this.lastFlushed && !hasQuantity(this.lastFlushed) &&
          this.rows.length && !rowHasAnyQuantity(this.rows[this.rows.length - 1]) && this.parenGroupHasAmount(i, sentence)) {
        this.rows.pop();
        this.current = this.lastFlushed;
        this.solventAfterIn = false;
      }
      const next = i + 1 < sentence.end ? words[i + 1] : null;
      const nextText = next ? this.wt(next) : '';
      const gapToNext = next ? next.gapBefore : '';
      const gapAfterNext = i + 2 < sentence.end ? words[i + 2].gapBefore
        : chars(this.text.slice(next ? next.end : this.text.length)).slice(0, 3).join('');

      if (gapToNext.startsWith('%')) {
        this.pendingNameStart = numberWord.start;
        return i + 1;
      }
      if (nextText.startsWith('°')) return i + 2;

      const unitAdjacent = next !== null && allWS(gapToNext);
      if (unitAdjacent) {
        const quantity = Units.quantity(nextText, gapAfterNext);
        if (quantity) {
          if (quantity.kind === 'volume' && this.isApparatus(i + 1, sentence)) return i + 2;
          this.setQuantity(quantity.kind, value * quantity.factor);
          return i + 2;
        }
        if (Units.isConcentration(nextText)) {
          if (i + 2 < sentence.end && this.wt(words[i + 2]).toLowerCase() === 'in') skip.carrier = true;
          return i + 2;
        }
        if (Units.isIgnoredUnit(nextText)) return i + 2;
      }

      // Ganze Zahl ohne Einheit: Verbindungsnummer
      const raw = this.wt(numberWord);
      if (isCompoundLabel(raw) && this.acceptCompoundLabel(i, sentence)) {
        this.addLabelWord(numberWord, i, sentence);
      } else {
        this.nameOpen = false;
        if (isCompoundLabel(raw)) this.lastRejectedWord = numberWord;
      }
      return i + 1;
    }

    parenGroupHasAmount(i, sentence) {
      for (let j = i; j < sentence.end; j++) {
        if (j > i && this.words[j].gapBefore.includes(')')) break;
        const w = this.wt(this.words[j]);
        if (Units.isConcentration(w)) return true;
        const q = Units.quantity(w, '');
        if (q && q.kind === 'amount') return true;
      }
      return false;
    }

    isApparatus(unitIndex, sentence) {
      for (let j = unitIndex + 1; j < Math.min(unitIndex + 3, sentence.end); j++) {
        const w = this.wt(this.words[j]).toLowerCase();
        if (Vocabulary.apparatus.some(a => w.includes(a))) return true;
      }
      return false;
    }

    acceptCompoundLabel(i, sentence) {
      if (hasQuantity(this.current) && this.current.nameRange === null) return true;
      if (this.nameOpen && allWS(this.words[i].gapBefore)) return true;
      if (i > sentence.start) {
        const previous = this.wt(this.words[i - 1]).toLowerCase();
        if (Vocabulary.labelIntroducers.has(previous)) return true;
      }
      return false;
    }

    // Namen ------------------------------------------------------------------

    addLabelWord(word, i, sentence) {
      if (!this.nameOpen && i > sentence.start && allWS(word.gapBefore)) {
        const previous = this.words[i - 1];
        const prevText = this.wt(previous).toLowerCase();
        if (Vocabulary.labelNouns.has(prevText)) {
          let start = previous.start;
          if (i - 1 > sentence.start && allWS(previous.gapBefore)) {
            const before = this.words[i - 2];
            const beforeText = this.wt(before).toLowerCase();
            if (!Vocabulary.stopwords.has(beforeText) && parseDecimal(beforeText) === null && chars(beforeText).every(isLetter)) start = before.start;
          }
          this.pendingNameStart = start;
        }
      }
      this.addNameWord(word);
    }

    isChemicalName(word, wordText) {
      const lower = wordText.toLowerCase();
      if (Vocabulary.apparatus.some(a => lower.includes(a))) return false;
      if (/^\d+(?:[.,]\d+)?-?(?:ml|l|µl|ul|g|mg|mmol|mol|eq)$/.test(lower)) return false;
      if (/^(?:aav|gp|av|sop|gsp)-?\d/.test(lower)) return false;
      if (Units.quantity(lower, '') !== null || Units.isIgnoredUnit(lower)) return false;
      const tags = word.tokens.map(t => t.tag).filter(t => t !== null);
      if (tags.includes('CHEMICAL')) return true;
      if (tags.length && tags.every(t => ['MASS', 'AMOUNT', 'VOLUME', 'EQ'].includes(t))) return false;
      return this.nameOpen ? ChemicalHeuristics.looksLikeContinuation(wordText) : ChemicalHeuristics.looksLikeChemical(wordText);
    }

    addNameWord(word) {
      const afterIn = this.sawInAfterName && this.current.nameRange !== null && !this.nameOpen;
      const pendingStart = this.pendingNameStart;
      if (this.current.nameRange !== null && !this.nameOpen) this.flush();
      this.pendingNameStart = pendingStart;
      this.solventAfterIn = afterIn;
      this.sawInAfterName = false;
      if (this.current.nameRange !== null && this.nameOpen) {
        this.current.nameRange = [this.current.nameRange[0], word.end];
      } else {
        const start = this.pendingNameStart !== null ? this.pendingNameStart : word.start;
        this.current.nameRange = [start, word.end];
      }
      this.pendingNameStart = null;
      this.nameOpen = true;
      this.nameClosedByStopword = false;
    }

    setQuantity(kind, value) {
      if (this.current[kind] !== null || (this.nameClosedByStopword && !hasQuantity(this.current))) this.flush();
      this.current[kind] = value;
      this.nameOpen = false;
      this.pendingNameStart = null;
    }

    // Zeile abschließen ------------------------------------------------------

    flush() {
      const flushedRow = this.current;
      try {
        let name = flushedRow.nameRange ? this.balancedName(flushedRow.nameRange) : '';
        let wasSolution = false;
        for (const suffix of Vocabulary.solutionSuffixes) {
          if (name.toLowerCase().endsWith(suffix)) {
            name = name.slice(0, name.length - suffix.length).replace(/^[ \t]+|[ \t]+$/g, '');
            wasSolution = true;
            break;
          }
        }
        name = trimSet(name, [' ', '.', ',', ';', ':']);
        while (name.startsWith('-')) name = name.slice(1);
        if (Vocabulary.stopwords.has(name.toLowerCase())) name = '';

        if (!name && !hasQuantity(flushedRow)) return;
        const quantityCount = ['mass', 'amount', 'volume', 'eq'].filter(k => flushedRow[k] !== null).length;
        if (!name && quantityCount < 2) return;
        if (!hasQuantity(flushedRow) && wasSolution) return;

        const row = newChemical();
        row.name = name;
        if (flushedRow.eq !== null) row.equivalents = format4(flushedRow.eq);
        if (flushedRow.amount !== null) row.amount = format4(flushedRow.amount);
        if (flushedRow.volume !== null) row.volume = format3(flushedRow.volume);
        if (flushedRow.mass !== null) row.mass = format3(flushedRow.mass);
        this.rows.push(row);
      } finally {
        this.lastFlushed = flushedRow;
        this.current = newPartial();
        this.nameOpen = false;
        this.pendingNameStart = null;
        this.nameClosedByStopword = false;
      }
    }

    /** Name aus dem Originaltext; abgeschnittene Klammern werden ergänzt: "S)-BINOL" → "(S)-BINOL". */
    balancedName(range) {
      const text = this.text;
      let lower = range[0], upper = range[1];
      const count = c => countOf(text.slice(lower, upper), c);
      while (count(')') > count('(') && lower > 0 && text[lower - 1] === '(') lower -= 1;
      while (count('(') > count(')') && upper < text.length && text[upper] === ')') upper += 1;
      let name = text.slice(lower, upper);
      while (name.endsWith(')') && countOf(name, ')') > countOf(name, '(')) name = name.slice(0, -1);
      while (name.startsWith('(') && countOf(name, '(') > countOf(name, ')')) name = name.slice(1);
      return name;
    }
  }

  function newPartial() { return { nameRange: null, mass: null, amount: null, volume: null, eq: null }; }
  function hasQuantity(p) { return p.mass !== null || p.amount !== null || p.volume !== null || p.eq !== null; }

  function newChemical() {
    return { id: uuid(), name: '', equivalents: '', cas: '', molarMass: '', density: '', amount: '', volume: '', mass: '' };
  }

  function uuid() {
    const c = g.crypto || (node ? require('crypto') : null);
    return c.randomUUID().toUpperCase();
  }

  /**
   * Extrahiert die Tabellenzeilen.
   * @param {string} rawText
   * @param {{nameModel?: 'classifier'|'lexicon'|'none'}} [options] Standard: 'classifier' (wie das Modell auf dem Mac)
   */
  function extract(rawText, options = {}) {
    const text = normalizeSynthesisText(rawText);
    if (!text) return [];
    const words = groupIntoWords(tokenize(text, options.nameModel || 'classifier'), text);
    return new Parser(text, words).run();
  }

  const api = { SmartExtractor: { extract, tokenize, chemProbability, groupIntoWords, isCompoundLabel, splitGluedQuantity, ChemicalHeuristics, Units, Vocabulary } };
  if (node) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
