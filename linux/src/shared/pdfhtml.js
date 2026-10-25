// HTML für Formel-Vorschau und PDF-Export – entspricht HTMLGenerator (Services/PDFExport.swift) und
// LaTeXEditorView.previewHTML (Views/LaTeXEditorView.swift).
(function (g) {
  'use strict';
  const node = typeof module === 'object' && module.exports;
  const { htmlEscaped } = node ? require('./smartformat.js') : g.CJ;
  const { parseDecimal, format3 } = node ? require('./numberformat.js') : g.CJ;

  /** Nur Text mit $…$ oder \ce{…} braucht MathJax. */
  function containsFormulas(text) {
    return text.includes('$') || text.includes('\\ce{');
  }

  /** HTML maskieren, Zeilenumbrüche, nacktes \ce{…} in $…$ setzen. */
  function previewHTML(text) {
    let fmt = htmlEscaped(text).replace(/\n/g, '<br>');
    fmt = fmt.replace(/(?<!\$)\\ce\{([^}]+)\}/g, (m, inner) => `$\\ce{${inner}}$`);
    return fmt;
  }

  const rich = text => previewHTML(text);

  function looksLikeFormula(word) {
    const first = word[0];
    if (!first || !(/\p{Lu}/u.test(first) || first === '(' || first === '[')) return false;
    if (!/^(?:[A-Z][a-z]?|[0-9]+|[()\[\]·•])+$/.test(word)) return false;
    return /[A-Za-z)\]][0-9]/.test(word);
  }

  /** Ziffern nach einem Buchstaben oder einer Klammer tiefstellen; Faktoren nach „·“ (5H2O) bleiben normal. */
  function subscriptDigits(word) {
    let out = '', previous = null, inSub = false;
    for (const c of Array.from(word)) {
      const isNum = /\p{N}/u.test(c);
      const sub = isNum && (inSub || (previous !== null && (/\p{L}/u.test(previous) || previous === ')' || previous === ']')));
      if (sub && !inSub) out += '<sub>';
      if (!sub && inSub) out += '</sub>';
      inSub = sub;
      out += htmlEscaped(c);
      previous = c;
    }
    if (inSub) out += '</sub>';
    return out;
  }

  /** Name in einer Tabellenzeile: Text in Dokumentschrift; nur Summenformeln bekommen tiefgestellte Ziffern. */
  function nameHTML(name) {
    if (name.includes('$') || name.includes('\\ce{')) return rich(name);
    return name.split(' ').map(w => (looksLikeFormula(w) ? subscriptDigits(w) : htmlEscaped(w))).join(' ');
  }

  const keepTogetherRows = 18;
  const block = (label, content) => `<div class='block'><div class='label'>${label}</div><div class='text'>${content}</div></div>`;
  const th = (title, unit, left) => `<th${left ? " class='left'" : ''}>${title}${unit ? `<span class='unit'>${unit}</span>` : ''}</th>`;
  const num = s => `<td class='num'>${htmlEscaped(s)}</td>`;

  function stageHTML(stage) {
    const e = htmlEscaped;
    let h = "<section class='stage'>";
    h += `<h2>${rich(stage.title)}</h2>`;
    if (stage.sourceURL) h += `<div class='source'><span class='label-inline'>Literatur</span> ${e(stage.sourceURL)}</div>`;
    if (stage.summary) h += block('Zusammenfassung', rich(stage.summary));
    if (stage.reactionImageData) h += `<figure class='scheme'><img src='data:image/png;base64,${stage.reactionImageData}'></figure>`;
    if (stage.chemicals.length) {
      h += `<div class='block${stage.chemicals.length <= keepTogetherRows ? ' keep' : ''}'><div class='label'>Reagenzien</div><table class='chem'>`;
      h += "<colgroup><col style='width:27%'><col style='width:13%'><col style='width:7%'><col style='width:10%'><col style='width:9%'><col style='width:11%'><col style='width:11%'><col style='width:12%'></colgroup>";
      h += `<thead><tr>${th('Verbindung', null, true)}${th('CAS', null, true)}${th('eq')}${th('M', 'g/mol')}${th('d', 'g/cm³')}${th('n', 'mol')}${th('V', 'mL')}${th('m', 'g')}</tr></thead><tbody>`;
      for (const c of stage.chemicals) {
        h += `<tr><td class='name'>${nameHTML(c.name)}</td><td class='cas'>${e(c.cas)}</td>${num(c.equivalents)}${num(c.molarMass)}${num(c.density)}${num(c.amount)}${num(c.volume)}${num(c.mass)}</tr>`;
      }
      h += '</tbody></table></div>';
    }
    if (stage.procedure) h += block('Durchführung', rich(stage.procedure));
    if (stage.observation) h += block('Beobachtung', rich(stage.observation));
    if (stage.yieldProducts.length) {
      h += `<div class='block${stage.yieldProducts.length <= keepTogetherRows ? ' keep' : ''}'><div class='label'>Ausbeute</div><table class='yield'>`;
      h += "<colgroup><col style='width:30%'><col style='width:14%'><col style='width:12%'><col style='width:12%'><col style='width:14%'><col style='width:18%'></colgroup>";
      h += `<thead><tr>${th('Produkt', null, true)}${th('CAS', null, true)}${th('M', 'g/mol')}${th('m', 'g')}${th('m theor.', 'g')}${th('Ausbeute')}</tr></thead><tbody>`;
      for (const y of stage.yieldProducts) {
        const ref = y.referenceChemicalID ? stage.chemicals.find(c => c.id === y.referenceChemicalID) : null;
        const refN = ref ? parseDecimal(ref.amount) : null;
        let mTheor = '';
        const M = parseDecimal(y.molarMass);
        if (refN !== null && M !== null) mTheor = format3(refN * M);
        let yPct = '';
        const myN = parseDecimal(y.amount);
        if (refN !== null && refN > 0 && myN !== null && myN > 0) yPct = `${((myN / refN) * 100).toFixed(1)} %`;
        h += `<tr><td class='name'>${nameHTML(y.name)}</td><td class='cas'>${e(y.cas)}</td>${num(y.molarMass)}${num(y.mass)}${num(mTheor)}<td class='num strong'>${e(yPct)}</td></tr>`;
      }
      h += '</tbody></table></div>';
    }
    return h + '</section>';
  }

  const css = `@page { size: A4; }
* { box-sizing: border-box; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body { margin: 0; font-family: -apple-system, 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 9.5pt;
       line-height: 1.45; color: #1d1d1f; hyphens: auto; -webkit-hyphens: auto; }
.new-page { break-before: page; }
.doc-header { border-bottom: 1.5pt solid #1d1d1f; padding-bottom: 8pt; margin-bottom: 14pt; }
.eyebrow { font-size: 8.5pt; letter-spacing: .02em; color: #6e6e73; font-weight: 600; text-align: right; }
h1 { font-size: 18pt; line-height: 1.2; margin: 2pt 0 4pt; font-weight: 700; }
.meta { font-size: 8.5pt; color: #6e6e73; }
.dot { margin: 0 5pt; }
.lead { margin: 8pt 0 0; font-size: 10pt; color: #3a3a3c; }
.stage { margin-top: 16pt; }
.stage + .stage { border-top: .5pt solid #d2d2d7; padding-top: 12pt; }
h2 { font-size: 12.5pt; margin: 0 0 6pt; font-weight: 650; break-after: avoid; }
.source { font-size: 8.5pt; color: #3a3a3c; margin-bottom: 6pt; overflow-wrap: anywhere; }
.label-inline { font-weight: 600; color: #6e6e73; margin-right: 4pt; }
.block { margin-top: 10pt; }
.label { font-size: 7.5pt; letter-spacing: .1em; text-transform: uppercase; color: #6e6e73; font-weight: 600;
         margin-bottom: 3pt; break-after: avoid; }
.text { overflow-wrap: anywhere; }
figure.scheme { margin: 10pt 0; text-align: center; break-inside: avoid; }
figure.scheme img { max-width: 100%; max-height: 210pt; object-fit: contain; }
table { width: 100%; border-collapse: collapse; table-layout: fixed; font-size: 8.5pt; }
.keep, figure.scheme { break-inside: avoid; page-break-inside: avoid; }
thead { display: table-header-group; break-inside: avoid; }
tr, th { break-inside: avoid; page-break-inside: avoid; }
th { font-weight: 600; font-size: 7.5pt; color: #3a3a3c; text-align: right; vertical-align: bottom;
     padding: 4pt 5pt; border-bottom: 1pt solid #1d1d1f; background: #f5f5f7; }
th.left { text-align: left; }
th .unit { display: block; font-weight: 400; color: #86868b; }
td { padding: 4pt 5pt; border-bottom: .5pt solid #d2d2d7; vertical-align: top; overflow-wrap: anywhere; }
tbody tr:nth-child(even) td { background: #fafafa; }
td.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
td.strong { font-weight: 600; }
td.cas { font-variant-numeric: tabular-nums; color: #3a3a3c; white-space: nowrap; font-size: 8pt; }
td.name { font-weight: 500; }
sub { font-size: 70%; line-height: 0; vertical-align: -0.3em; }
mjx-container { max-width: 100%; }
mjx-container svg { max-width: 100%; height: auto; }`;

  /**
   * HTML für den PDF-Export.
   * @param {object[]} experiments
   * @param {string} projectName
   * @param {(refSeconds:number)=>Date} toDate Swift-Datum (Sekunden seit 2001) → Date
   */
  function generatePDFHTML(experiments, projectName, toDate) {
    const e = htmlEscaped;
    const dateFmt = new Intl.DateTimeFormat('de-DE', { dateStyle: 'long' });
    let body = '';
    experiments.forEach((exp, index) => {
      body += `<article class='experiment${index > 0 ? ' new-page' : ''}'>`;
      const meta = [dateFmt.format(toDate(exp.createdAt))];
      if (projectName) meta.unshift(e(projectName));
      meta.push(exp.stages.length === 1 ? '1 Stufe' : `${exp.stages.length} Stufen`);
      body += `
      <header class="doc-header">
        <div class="eyebrow">ChemJournal</div>
        <h1>${rich(exp.title || 'Ohne Titel')}</h1>
        <div class="meta">${meta.join("<span class='dot'>·</span>")}</div>
        ${exp.summary ? `<p class='lead'>${rich(exp.summary)}</p>` : ''}
      </header>`;
      for (const stage of exp.stages) body += stageHTML(stage);
      body += '</article>';
    });
    return `<!DOCTYPE html><html lang="de"><head><meta charset="utf-8">
<style>${css}</style></head><body>${body}</body></html>`;
  }

  const api = { containsFormulas, previewHTML, nameHTML, looksLikeFormula, subscriptDigits, generatePDFHTML };
  if (node) module.exports = api;
  else Object.assign((g.CJ = g.CJ || {}), api);
})(typeof globalThis !== 'undefined' ? globalThis : this);
