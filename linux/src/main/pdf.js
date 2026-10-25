// PDF-Export – entspricht PDFManager (Services/PDFExport.swift).
// Druckt das HTML aus einem unsichtbaren Fenster auf A4 (automatischer Seitenumbruch, Tabellenköpfe wiederholen
// sich) und setzt unten „Name · Seite x von y“. MathJax kommt aus der App – funktioniert offline.
'use strict';
const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { BrowserWindow, app } = require('electron');
const { htmlEscaped } = require('../shared/smartformat');
const { uuid } = require('./model');

const MATHJAX = path.join(__dirname, '../renderer/vendor/mathjax-tex-svg-full.js');
const PT = 1 / 72;   // Punkt → Zoll
const MARGINS = { top: 42 * PT, bottom: 54 * PT, left: 48 * PT, right: 48 * PT };

let queue = Promise.resolve();

/** Erzeugt ein PDF (Buffer). Aufträge laufen nacheinander. */
function generatePDF(html, footer) {
  const job = queue.then(() => render(html, footer));
  queue = job.catch(() => {});
  return job;
}

async function render(html, footer) {
  const mathJax = `<script>window.MathJax = { tex: { inlineMath: [['$','$']], displayMath: [['$$','$$']], packages: {'[+]': ['mhchem']} },
    svg: { fontCache: 'global' },
    startup: { pageReady: () => MathJax.startup.defaultPageReady().then(() => { window.mathJaxDone = true; }, () => { window.mathJaxDone = true; }) } };</script>
    <script src="${pathToFileURL(MATHJAX).href}"></script>`;
  const file = path.join(app.getPath('temp'), `ChemJournal-${uuid()}.html`);
  // Funktion statt Text als Ersatz: sonst würde "$'" in den MathJax-Einstellungen als Sonderzeichen gelesen
  fs.writeFileSync(file, html.replace('<head>', () => '<head>' + mathJax));
  const win = new BrowserWindow({ show: false, width: 800, height: 1100, webPreferences: { sandbox: true, contextIsolation: true } });
  try {
    await win.loadFile(file);
    const deadline = Date.now() + 8000;
    while (Date.now() < deadline) {
      if (await win.webContents.executeJavaScript('window.mathJaxDone === true')) break;
      await new Promise(r => setTimeout(r, 100));
    }
    const footerTemplate = `<div style="width:100%;font-size:7.5pt;font-family:-apple-system,'Helvetica Neue',Helvetica,Arial,sans-serif;color:#737373;padding:0 48pt;display:flex;justify-content:space-between;-webkit-print-color-adjust:exact;">
      <span>${htmlEscaped(footer || '')}</span><span>Seite <span class="pageNumber"></span> von <span class="totalPages"></span></span></div>`;
    return await win.webContents.printToPDF({
      pageSize: 'A4', printBackground: true, margins: MARGINS,
      displayHeaderFooter: true, headerTemplate: '<span></span>', footerTemplate,
    });
  } finally {
    win.destroy();
    fs.rm(file, () => {});
  }
}

module.exports = { generatePDF };
